import AppKit
import CoreAudio
import Foundation
import os.log

/// Top-level orchestrator: owns the monitors and the rule store, and keeps
/// one active ProcessTapController per satisfiable rule (app running AND
/// target device connected). Routes are held while the app is running, not
/// only while it plays, so playback starts on the right device immediately.
@MainActor
final class AudioRouterEngine: ObservableObject {
    let processMonitor = AudioProcessMonitor()
    let deviceMonitor = AudioDeviceMonitor()

    @Published private(set) var rules: [String: RoutingRule] = [:]
    @Published private(set) var activeRouteBundleIDs: Set<String> = []
    @Published var lastError: String?

    private let store = RuleStore()
    private var activeRoutes: [String: ProcessTapController] = [:]
    private static let log = Logger(subsystem: "com.abhisekganguly.AudioRouter", category: "AudioRouterEngine")

    func start() {
        OrphanedTapCleanup.run()
        rules = store.rules
        processMonitor.onChange = { [weak self] in self?.applyRules() }
        deviceMonitor.onChange = { [weak self] in self?.applyRules() }
        processMonitor.start()
        deviceMonitor.start()
        applyRules()
    }

    /// Tears down every route (unmuting all apps). Called on quit.
    func shutdown() {
        store.flush()
        for controller in activeRoutes.values {
            controller.invalidate()
        }
        activeRoutes.removeAll()
        activeRouteBundleIDs = []
    }

    /// UI entry point: assign a device to an app (nil = back to system default).
    func setRule(for app: AudioApp, device: AudioDevice?) {
        if let device {
            store.set(
                RoutingRule(
                    bundleID: app.bundleID,
                    deviceUID: device.uid,
                    deviceName: device.name,
                    appName: app.name,
                    volume: store.rule(for: app.bundleID)?.volume ?? 1.0
                )
            )
        } else {
            store.removeRule(for: app.bundleID)
        }
        rules = store.rules
        lastError = nil
        applyRules()
    }

    /// Live volume change: applied to the running route immediately, persisted
    /// (debounced) to the rule. Never rebuilds the route.
    func setVolume(for bundleID: String, volume: Float) {
        activeRoutes[bundleID]?.volume = volume
        store.updateVolume(bundleID: bundleID, volume: volume)
        rules = store.rules
    }

    func removeRule(bundleID: String) {
        store.removeRule(for: bundleID)
        rules = store.rules
        applyRules()
    }

    /// Reconciles active routes against (rules × running apps × connected devices).
    func applyRules() {
        let apps = Dictionary(uniqueKeysWithValues: processMonitor.apps.map { ($0.bundleID, $0) })

        // Desired state: rule exists, app has audio processes, device connected.
        var desired: [String: (rule: RoutingRule, objects: Set<AudioObjectID>)] = [:]
        for (bundleID, rule) in store.rules {
            guard let app = apps[bundleID], !app.processObjectIDs.isEmpty else { continue }
            guard deviceMonitor.device(withUID: rule.deviceUID) != nil else { continue }
            desired[bundleID] = (rule, app.processObjectIDs)
        }

        // Tear down routes that no longer match (rule removed, app quit,
        // device gone, target changed, or the app's process set changed —
        // e.g. Chrome spawned a new audio helper — which needs a fresh tap).
        for (bundleID, controller) in activeRoutes {
            let wanted = desired[bundleID]
            if wanted == nil
                || wanted!.rule.deviceUID != controller.deviceUID
                || wanted!.objects != controller.processObjectIDs {
                controller.invalidate()
                activeRoutes.removeValue(forKey: bundleID)
            }
        }

        // Bring up missing routes.
        for (bundleID, wanted) in desired where activeRoutes[bundleID] == nil {
            let controller = ProcessTapController(
                bundleID: bundleID,
                deviceUID: wanted.rule.deviceUID,
                processObjectIDs: wanted.objects
            )
            controller.volume = wanted.rule.volume
            do {
                try controller.activate()
                activeRoutes[bundleID] = controller
            } catch {
                Self.log.error("Failed to activate route for \(bundleID, privacy: .public): \(error, privacy: .public)")
                lastError = "Couldn't route \(wanted.rule.appName): \(error.localizedDescription)"
            }
        }

        activeRouteBundleIDs = Set(activeRoutes.keys)
    }
}
