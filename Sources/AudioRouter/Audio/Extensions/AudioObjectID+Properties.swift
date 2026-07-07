import CoreAudio
import Foundation

enum CoreAudioError: LocalizedError {
    case osStatus(OSStatus, String)

    var errorDescription: String? {
        switch self {
        case .osStatus(let status, let context):
            return "\(context) failed (OSStatus \(status))"
        }
    }
}

func checkOSStatus(_ status: OSStatus, _ context: String) throws {
    guard status == noErr else { throw CoreAudioError.osStatus(status, context) }
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)

    var isValid: Bool { self != Self.unknown }

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    func hasProperty(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> Bool {
        var address = Self.address(selector, scope: scope)
        return AudioObjectHasProperty(self, &address)
    }

    /// Reads a fixed-size scalar property (UInt32, pid_t, etc.).
    func read<T>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        defaultValue: T
    ) throws -> T {
        var address = Self.address(selector, scope: scope)
        var size = UInt32(MemoryLayout<T>.size)
        var value = defaultValue
        try checkOSStatus(
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, &value),
            "AudioObjectGetPropertyData(\(selector.fourCharString))"
        )
        return value
    }

    /// Reads a CFString property (device UID, bundle ID, names).
    func readString(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) throws -> String {
        var address = Self.address(selector, scope: scope)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString? = nil
        try withUnsafeMutablePointer(to: &value) { ptr in
            try checkOSStatus(
                AudioObjectGetPropertyData(self, &address, 0, nil, &size, ptr),
                "AudioObjectGetPropertyData(\(selector.fourCharString))"
            )
        }
        return (value as String?) ?? ""
    }

    /// Reads a variable-length array of AudioObjectIDs (device list, process list, stream list).
    func readObjectList(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) throws -> [AudioObjectID] {
        var address = Self.address(selector, scope: scope)
        var size: UInt32 = 0
        try checkOSStatus(
            AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size),
            "AudioObjectGetPropertyDataSize(\(selector.fourCharString))"
        )
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var list = [AudioObjectID](repeating: .unknown, count: count)
        try checkOSStatus(
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, &list),
            "AudioObjectGetPropertyData(\(selector.fourCharString))"
        )
        return list
    }
}

extension AudioObjectPropertySelector {
    var fourCharString: String {
        let chars: [Character] = [
            Character(UnicodeScalar((self >> 24) & 0xFF) ?? " "),
            Character(UnicodeScalar((self >> 16) & 0xFF) ?? " "),
            Character(UnicodeScalar((self >> 8) & 0xFF) ?? " "),
            Character(UnicodeScalar(self & 0xFF) ?? " "),
        ]
        return String(chars)
    }
}
