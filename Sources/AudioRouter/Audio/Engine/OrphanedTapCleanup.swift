import CoreAudio
import Foundation
import os.log

/// Destroys aggregate devices left behind by a crash or force-quit.
/// A leaked `.mutedWhenTapped` tap can leave the routed app silently muted
/// until its aggregate is destroyed, so this runs before any new taps are made.
enum OrphanedTapCleanup {
    private static let log = Logger(subsystem: "com.abhisekganguly.AudioRouter", category: "OrphanedTapCleanup")

    static func run() {
        guard let devices = try? AudioObjectID.readDeviceList() else { return }
        for device in devices {
            guard device.readTransportType().isAggregateTransport else { continue }
            let uid = device.readDeviceUID()
            guard uid.hasPrefix(ProcessTapController.aggregateUIDPrefix) else { continue }
            let status = AudioHardwareDestroyAggregateDevice(device)
            if status == noErr {
                log.info("Destroyed orphaned aggregate \(uid, privacy: .public)")
            } else {
                log.error("Failed to destroy orphaned aggregate \(uid, privacy: .public): \(status)")
            }
        }
    }
}
