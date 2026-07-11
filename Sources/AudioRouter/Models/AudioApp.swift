import AppKit
import CoreAudio

/// Whether an app is currently making sound, has an open audio session but
/// isn't outputting right now, or has no Core Audio session at all.
enum PlaybackState: Equatable {
    case playing
    case paused
    case inactive
}

/// A user-visible application that has one or more Core Audio process objects.
/// Helper processes (e.g. Chrome's audio service) are grouped under the owning app.
struct AudioApp: Identifiable, Equatable {
    let bundleID: String
    let name: String
    let icon: NSImage?
    /// All Core Audio process objects attributed to this app (helpers included).
    let processObjectIDs: Set<AudioObjectID>
    let playbackState: PlaybackState

    var id: String { bundleID }

    static func == (lhs: AudioApp, rhs: AudioApp) -> Bool {
        lhs.bundleID == rhs.bundleID
            && lhs.processObjectIDs == rhs.processObjectIDs
            && lhs.playbackState == rhs.playbackState
    }
}
