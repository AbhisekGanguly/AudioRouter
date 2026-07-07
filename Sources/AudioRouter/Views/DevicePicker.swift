import SwiftUI

/// Output device dropdown for one app. "System Default" clears the rule.
struct DevicePicker: View {
    let devices: [AudioDevice]
    let selectedUID: String?
    let onSelect: (AudioDevice?) -> Void

    var body: some View {
        Menu {
            Button {
                onSelect(nil)
            } label: {
                if selectedUID == nil {
                    Label("System Default", systemImage: "checkmark")
                } else {
                    Text("System Default")
                }
            }
            Divider()
            ForEach(devices) { device in
                Button {
                    onSelect(device)
                } label: {
                    if device.uid == selectedUID {
                        Label("\(device.name) (\(device.transportName))", systemImage: "checkmark")
                    } else {
                        Text("\(device.name) (\(device.transportName))")
                    }
                }
            }
        } label: {
            Text(selectedLabel)
                .font(.caption)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var selectedLabel: String {
        guard let selectedUID else { return "Default" }
        return devices.first { $0.uid == selectedUID }?.name ?? "Unavailable"
    }
}
