import CoreAudio
import Foundation
import os.log

/// Watches the system device list and publishes output-capable devices.
/// Hotplug notifications are debounced because Bluetooth connects fire
/// several redundant notifications while the HAL is still settling.
@MainActor
final class AudioDeviceMonitor: ObservableObject {
    @Published private(set) var devices: [AudioDevice] = []
    /// UID of the current system default output — where un-routed audio goes.
    @Published private(set) var defaultDeviceUID: String?

    var onChange: (() -> Void)?

    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var refreshWorkItem: DispatchWorkItem?
    private static let log = Logger(subsystem: "com.abhisekganguly.AudioRouter", category: "AudioDeviceMonitor")

    func start() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        listenerBlock = block
        var address = AudioObjectID.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(.system, &address, .main, block)
        var defaultAddress = AudioObjectID.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(.system, &defaultAddress, .main, block)
        refresh()
    }

    private func scheduleRefresh() {
        refreshWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        refreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
    }

    func refresh() {
        guard let deviceObjects = try? AudioObjectID.readDeviceList() else { return }

        var newDevices: [AudioDevice] = []
        for object in deviceObjects {
            guard object.isOutputCapable else { continue }
            let transport = object.readTransportType()
            // Hide aggregates: ours are plumbing, others' are rarely intended targets.
            guard !transport.isAggregateTransport else { continue }
            let uid = object.readDeviceUID()
            guard !uid.isEmpty else { continue }
            newDevices.append(
                AudioDevice(
                    objectID: object,
                    uid: uid,
                    name: object.readDeviceName(),
                    transportType: transport
                )
            )
        }
        newDevices.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if newDevices != devices {
            devices = newDevices
            onChange?()
        }

        let newDefaultUID = (try? AudioObjectID.readDefaultOutputDevice())
            .flatMap { $0.isValid ? $0.readDeviceUID() : nil }
        if newDefaultUID != defaultDeviceUID {
            defaultDeviceUID = newDefaultUID
        }
    }

    func device(withUID uid: String) -> AudioDevice? {
        devices.first { $0.uid == uid }
    }

    var defaultDevice: AudioDevice? {
        defaultDeviceUID.flatMap { device(withUID: $0) }
    }
}
