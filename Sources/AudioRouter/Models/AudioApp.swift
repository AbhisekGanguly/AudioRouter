import AppKit
import CoreAudio

/// A user-visible application that has one or more Core Audio process objects.
/// Helper processes (e.g. Chrome's audio service) are grouped under the owning app.
struct AudioApp: Identifiable, Equatable {
    let bundleID: String
    let name: String
    let icon: NSImage?
    /// All Core Audio process objects attributed to this app (helpers included).
    let processObjectIDs: Set<AudioObjectID>
    let isPlaying: Bool

    var id: String { bundleID }

    static func == (lhs: AudioApp, rhs: AudioApp) -> Bool {
        lhs.bundleID == rhs.bundleID
            && lhs.processObjectIDs == rhs.processObjectIDs
            && lhs.isPlaying == rhs.isPlaying
    }
}
