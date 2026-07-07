import CoreAudio
import Foundation

/// Helpers for Core Audio *device* objects.
extension AudioObjectID {
    static func readDeviceList() throws -> [AudioObjectID] {
        try AudioObjectID.system.readObjectList(kAudioHardwarePropertyDevices)
    }

    static func readDefaultOutputDevice() throws -> AudioObjectID {
        try AudioObjectID.system.read(kAudioHardwarePropertyDefaultOutputDevice, defaultValue: AudioObjectID.unknown)
    }

    func readDeviceUID() -> String {
        (try? readString(kAudioDevicePropertyDeviceUID)) ?? ""
    }

    func readDeviceName() -> String {
        (try? readString(kAudioObjectPropertyName)) ?? ""
    }

    func readTransportType() -> UInt32 {
        (try? read(kAudioDevicePropertyTransportType, defaultValue: UInt32(0))) ?? 0
    }

    var isOutputCapable: Bool {
        let streams = (try? readObjectList(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)) ?? []
        return !streams.isEmpty
    }
}

extension UInt32 {
    /// Human-readable transport type for device rows in the UI.
    var transportTypeName: String {
        switch self {
        case kAudioDeviceTransportTypeBuiltIn: return "Built-in"
        case kAudioDeviceTransportTypeAirPlay: return "AirPlay"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth"
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeHDMI: return "HDMI"
        case kAudioDeviceTransportTypeDisplayPort: return "DisplayPort"
        case kAudioDeviceTransportTypeThunderbolt: return "Thunderbolt"
        case kAudioDeviceTransportTypeAggregate: return "Aggregate"
        case kAudioDeviceTransportTypeVirtual: return "Virtual"
        default: return "Other"
        }
    }

    var isAggregateTransport: Bool { self == kAudioDeviceTransportTypeAggregate }
}
