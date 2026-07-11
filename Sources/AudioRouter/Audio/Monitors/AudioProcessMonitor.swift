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
    private var pollTimer: DispatchSourceTimer?
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

        // kAudioProcessPropertyIsRunningOutput's change notification is not
        // reliable in practice — play/pause transitions can go unnoticed for
        // minutes. Poll as a hard ceiling on staleness. A DispatchSourceTimer
        // (not Timer) keeps firing while a menu/popover is open, since
        // Timer's default run loop mode stalls during event tracking.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1.0)
        timer.setEventHandler { [weak self] in self?.refresh() }
        timer.resume()
        pollTimer = timer
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

        let runningAppsByBundleID = Dictionary(
            runningApps.compactMap { app -> (String, NSRunningApplication)? in
                guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return nil }
                return (id, app)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var grouped: [String: (app: NSRunningApplication, objects: Set<AudioObjectID>, playing: Bool)] = [:]
        var seenObjects: Set<AudioObjectID> = []

        for object in processObjects {
            guard let pid = try? object.readProcessPID(), pid > 0 else { continue }
            guard let owner = resolveOwningApp(
                object: object,
                pid: pid,
                runningAppsByBundleID: runningAppsByBundleID,
                regularAppsByPID: regularAppsByPID,
                allApps: runningApps
            ) else { continue }
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
                // Every entry here has ≥1 process object by construction, so
                // this is always playing or paused; .inactive models an app
                // with zero process objects, which never gets a row at all.
                playbackState: entry.playing ? .playing : .paused
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if newApps != apps {
            apps = newApps
            onChange?()
        }
    }

    /// Maps a Core Audio process object to the user-visible app that owns it.
    /// Tries Core Audio's own reported bundle ID first (authoritative when
    /// present — this is what lets apps like Spotify, whose process tree
    /// shape doesn't match Chrome's parent/helper convention, attribute
    /// correctly), then falls back to walking the BSD process tree.
    private func resolveOwningApp(
        object: AudioObjectID,
        pid: pid_t,
        runningAppsByBundleID: [String: NSRunningApplication],
        regularAppsByPID: [pid_t: NSRunningApplication],
        allApps: [NSRunningApplication]
    ) -> NSRunningApplication? {
        let reportedBundleID = object.readProcessBundleID()
        if !reportedBundleID.isEmpty, let owner = runningAppsByBundleID[reportedBundleID] {
            return owner
        }

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
