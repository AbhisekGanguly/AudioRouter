import SwiftUI

/// One row: app icon + name + playing indicator, a device picker, and —
/// when the app has a rule — a per-app volume slider.
struct AppRow: View {
    let app: AudioApp
    let devices: [AudioDevice]
    let rule: RoutingRule?
    let isRouted: Bool
    /// Name of the system default output — where audio actually plays
    /// while the rule's device is disconnected.
    let fallbackDeviceName: String?
    let onSelect: (AudioDevice?) -> Void
    let onVolumeChange: (Float) -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "app.fill")
                        .frame(width: 24, height: 24)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(app.name)
                            .font(.callout)
                            .lineLimit(1)
                        if app.isPlaying {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .help("Playing audio")
                        }
                    }
                    if let rule, isRouted {
                        Text("→ \(rule.deviceName)")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    } else if let rule {
                        Text("→ \(fallbackDeviceName ?? "System Default") — \(rule.deviceName) disconnected")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help("\(rule.deviceName) is disconnected, so \(app.name) is playing on \(fallbackDeviceName ?? "the system default output"). The route resumes when it reconnects.")
                    }
                }

                Spacer()

                DevicePicker(
                    devices: devices,
                    selectedUID: rule?.deviceUID,
                    onSelect: onSelect
                )
            }

            if rule != nil {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(value: volumeBinding, in: 0...1)
                        .controlSize(.small)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 32)
                .help(isRouted ? "Volume for \(app.name)" : "Applies when the route is active")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { Double(rule?.volume ?? 1.0) },
            set: { onVolumeChange(Float($0)) }
        )
    }
}
