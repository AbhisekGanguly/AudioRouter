import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var engine: AudioRouterEngine
    @ObservedObject var processMonitor: AudioProcessMonitor
    @ObservedObject var deviceMonitor: AudioDeviceMonitor
    @StateObject private var launchAtLogin = LaunchAtLogin()

    init(engine: AudioRouterEngine) {
        self.engine = engine
        self.processMonitor = engine.processMonitor
        self.deviceMonitor = engine.deviceMonitor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if processMonitor.apps.isEmpty {
                Text("No apps are using audio right now.\nStart playing something and it will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(processMonitor.apps) { app in
                            AppRow(
                                app: app,
                                devices: deviceMonitor.devices,
                                rule: engine.rules[app.bundleID],
                                isRouted: engine.activeRouteBundleIDs.contains(app.bundleID),
                                fallbackDeviceName: deviceMonitor.defaultDevice?.name,
                                onSelect: { device in
                                    engine.setRule(for: app, device: device)
                                },
                                onVolumeChange: { volume in
                                    engine.setVolume(for: app.bundleID, volume: volume)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 320)
            }

            savedRulesSection

            if let error = engine.lastError {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(10)
            }

            Divider()
            footer
        }
        .frame(width: 340)
    }

    private var header: some View {
        HStack {
            Image(systemName: "hifispeaker.2.fill")
            Text("AudioRouter")
                .font(.headline)
            Spacer()
        }
        .padding(12)
    }

    /// Rules for apps that aren't currently running, so they can be reviewed/removed.
    private var savedRulesSection: some View {
        let runningIDs = Set(processMonitor.apps.map(\.bundleID))
        let dormant = engine.rules.values
            .filter { !runningIDs.contains($0.bundleID) }
            .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }

        return Group {
            if !dormant.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved rules (app not running)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(dormant, id: \.bundleID) { rule in
                        HStack {
                            Text("\(rule.appName) → \(rule.deviceName)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                engine.removeRule(bundleID: rule.bundleID)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove rule")
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )
            .toggleStyle(.checkbox)
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Text("\(engine.activeRouteBundleIDs.count) active route\(engine.activeRouteBundleIDs.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    OnboardingController.shared.show()
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Show welcome guide")
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(10)
        .onAppear { launchAtLogin.refresh() }
    }
}
