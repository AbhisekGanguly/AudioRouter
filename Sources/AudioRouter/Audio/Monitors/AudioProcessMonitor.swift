import AppKit
import CoreAudio
import Foundation
import os.log

/// Watches Core Audio's process object list and publishes the set of
/// user-visible apps that currently have audio processes, grouping helper
/// processes (e.g. Chrome's audio service) under the owning application.
@MainActor
final class AudioProcessMonitor: ObservableObject {
    @Published private(set) var apps: [AudioApp] = []

    var onChange: (() -> Void)?

    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var outputListenerObjects: Set<AudioObjectID> = []
    private var outputListenerBlock: AudioObjectPropertyListenerBlock?
    private var refreshWorkItem: DispatchWorkItem?
    private static let log = Logger(subsystem: "com.abhisekganguly.AudioRouter", category: "AudioProcessMonitor")

    func start() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        listenerBlock = block
        var address = AudioObjectID.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectAddPropertyListenerBlock(.system, &address, .main, block)

        outputListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.scheduleRefresh() }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceAppsChanged),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceAppsChanged),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )

        refresh()
    }

    @objc private func workspaceAppsChanged() {
        scheduleRefresh()
    }

    /// Debounced: process launches/quits fire bursts of notifications.
    private func scheduleRefresh() {
        refreshWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        refreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
    }

    func refresh() {
        guard let processObjects = try? AudioObjectID.readProcessList() else { return }

        let runningApps = NSWorkspace.shared.runningApplications
        let regularAppsByPID = Dictionary(
            uniqueKeysWithValues: runningApps
                .filter { $0.activationPolicy == .regular }
                .map { ($0.processIdentifier, $0) }
        )

        var grouped: [String: (app: NSRunningApplication, objects: Set<AudioObjectID>, playing: Bool)] = [:]
        var seenObjects: Set<AudioObjectID> = []

        for object in processObjects {
            guard let pid = try? object.readProcessPID(), pid > 0 else { continue }
            guard let owner = resolveOwningApp(pid: pid, regularAppsByPID: regularAppsByPID, allApps: runningApps) else { continue }
            guard let ownerBundleID = owner.bundleIdentifier else { continue }
            // Never offer to route ourselves.
            guard ownerBundleID != Bundle.main.bundleIdentifier else { continue }

            seenObjects.insert(object)
            let playing = object.readProcessIsRunningOutput()
            if var entry = grouped[ownerBundleID] {
                entry.objects.insert(object)
                entry.playing = entry.playing || playing
                grouped[ownerBundleID] = entry
            } else {
                grouped[ownerBundleID] = (owner, [object], playing)
            }
        }

        updateOutputListeners(for: seenObjects)

        let newApps = grouped.map { bundleID, entry in
            AudioApp(
                bundleID: bundleID,
                name: entry.app.localizedName ?? bundleID,
                icon: entry.app.icon,
                processObjectIDs: entry.objects,
                isPlaying: entry.playing
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if newApps != apps {
            apps = newApps
            onChange?()
        }
    }

    /// Maps an audio process PID to the user-visible app that owns it by
    /// walking up the BSD process tree until a `.regular` app is found.
    private func resolveOwningApp(
        pid: pid_t,
        regularAppsByPID: [pid_t: NSRunningApplication],
        allApps: [NSRunningApplication]
    ) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<12 {
            if let app = regularAppsByPID[current] { return app }
            guard let parent = ProcessTree.parentPID(of: current), parent != current, parent > 1 else { break }
            current = parent
        }
        // Fallback: helper bundle IDs are typically prefixed with the owner's
        // bundle ID (com.google.Chrome.helper → com.google.Chrome).
        if let helper = NSRunningApplication(processIdentifier: pid),
           let helperBundleID = helper.bundleIdentifier {
            return allApps.first {
                guard $0.activationPolicy == .regular, let ownerID = $0.bundleIdentifier else { return false }
                return helperBundleID == ownerID || helperBundleID.hasPrefix(ownerID + ".")
            }
        }
        return nil
    }

    /// Keeps a kAudioProcessPropertyIsRunningOutput listener on every known
    /// process object so play/pause flips update the UI (and rule activation).
    private func updateOutputListeners(for objects: Set<AudioObjectID>) {
        guard let block = outputListenerBlock else { return }
        var address = AudioObjectID.address(kAudioProcessPropertyIsRunningOutput)

        for stale in outputListenerObjects.subtracting(objects) {
            AudioObjectRemovePropertyListenerBlock(stale, &address, .main, block)
        }
        for fresh in objects.subtracting(outputListenerObjects) {
            AudioObjectAddPropertyListenerBlock(fresh, &address, .main, block)
        }
        outputListenerObjects = objects
    }
}
