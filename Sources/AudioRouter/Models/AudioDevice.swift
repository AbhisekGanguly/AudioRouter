import CoreAudio

/// An output-capable Core Audio device (built-in, USB, Bluetooth, AirPlay, ...).
struct AudioDevice: Identifiable, Equatable, Hashable {
    let objectID: AudioObjectID
    /// Stable across reboots/reconnects — this is what rules persist.
    let uid: String
    let name: String
    let transportType: UInt32

    var id: String { uid }
    var transportName: String { transportType.transportTypeName }
}
