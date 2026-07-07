import AppKit
import SwiftUI

@main
struct AudioRouterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(engine: appDelegate.engine)
        } label: {
            Image(systemName: "hifispeaker.2.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = AudioRouterEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine.start()
        OnboardingController.shared.showIfFirstLaunch()
    }

    /// Destroy all taps on quit so no app is left muted.
    func applicationWillTerminate(_ notification: Notification) {
        engine.shutdown()
    }
}
