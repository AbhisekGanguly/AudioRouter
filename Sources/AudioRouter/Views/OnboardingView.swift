import AppKit
import SwiftUI

/// Welcome window shown on first launch (and reopenable from the menu's
/// help button). Menu-bar-only apps have no main window, so this is hosted
/// in a manually managed NSWindow.
@MainActor
final class OnboardingController {
    static let shared = OnboardingController()
    static let hasSeenKey = "hasCompletedOnboarding"

    private var window: NSWindow?

    func showIfFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: Self.hasSeenKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.hasSeenKey)
        show()
    }

    func show() {
        if window == nil {
            let view = OnboardingView { [weak self] in
                self?.window?.close()
            }
            let hosting = NSHostingController(rootView: view)
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
            newWindow.titlebarAppearsTransparent = true
            newWindow.titleVisibility = .hidden
            newWindow.isReleasedWhenClosed = false
            newWindow.isMovableByWindowBackground = true
            newWindow.center()
            window = newWindow
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct OnboardingView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 6) {
                Text("Welcome to AudioRouter")
                    .font(.title.bold())
                Text("Send each app's audio to a different speaker,\nheadphones, or AirPlay device — at the same time.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                step(
                    symbol: "hifispeaker.2.fill",
                    color: .blue,
                    title: "Route each app anywhere",
                    text: "Click the speaker icon in the menu bar and pick an output next to any app. Rules are remembered and re-apply automatically — even after a restart."
                )
                step(
                    symbol: "lock.shield.fill",
                    color: .green,
                    title: "Approve the one-time permission",
                    text: "The first time you route an app, macOS asks for System Audio Recording permission. AudioRouter needs it to capture an app's sound and redirect it — nothing is recorded or stored."
                )
                step(
                    symbol: "slider.horizontal.3",
                    color: .orange,
                    title: "Per-app volume",
                    text: "Every routed app gets its own volume slider, independent of the system volume."
                )
                step(
                    symbol: "exclamationmark.triangle.fill",
                    color: .yellow,
                    title: "One heads-up about Spotify Connect",
                    text: "If you pick a speaker inside Spotify itself, the audio streams straight to it and skips your Mac — AudioRouter can't route that. Choose AirPlay devices from AudioRouter instead."
                )
            }
            .padding(.horizontal, 4)

            Button("Get Started") {
                onDone()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 470)
    }

    private func step(symbol: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
