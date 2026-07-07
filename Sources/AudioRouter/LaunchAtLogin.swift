import Foundation
import ServiceManagement
import os.log

/// Wraps SMAppService so the menu can offer a "Launch at login" checkbox.
/// Best registered while running from /Applications — the login item records
/// the app's current path.
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled: Bool = SMAppService.mainApp.status == .enabled

    private static let log = Logger(subsystem: "com.abhisekganguly.AudioRouter", category: "LaunchAtLogin")

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Self.log.error("Launch-at-login change failed: \(error, privacy: .public)")
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Re-reads status in case it was changed in System Settings.
    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
