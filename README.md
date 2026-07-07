# AudioRouter

A macOS menu bar app that routes different apps' audio to different output devices simultaneously — e.g. Spotify to a home speaker while Chrome plays through your headphones.

Built on Apple's Core Audio **process tap** API (macOS 14.4+): each app→device rule creates a tap on that app's audio processes, wraps it in a private aggregate device whose real sub-device is the destination, and copies the tapped audio into the destination's output buffers in an IOProc. The tap uses `.mutedWhenTapped`, so the app's original output is silenced only while the route is active.

## Requirements

- macOS 14.4 or later (built/tested on 15.x, Apple Silicon)
- Xcode command line tools (Swift 5.10+)

## Build & run

```sh
./scripts/build-app.sh
open build/AudioRouter.app
```

The script builds with SwiftPM, assembles `build/AudioRouter.app`, and ad-hoc signs it. For distribution, sign with a real identity:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-app.sh
```

## Usage

1. Click the speaker icon in the menu bar. Apps that are using audio appear in the list (a green wave icon = currently playing).
2. Pick an output device from the dropdown next to an app. macOS will ask for **System Audio Recording** permission the first time — this is required for the tap API.
3. The rule is saved (keyed by bundle ID, in `~/Library/Application Support/AudioRouter/rules.json`) and re-applies automatically whenever that app runs again.
4. Pick "System Default" to remove a rule. Rules for apps that aren't running are listed at the bottom and can be removed there.
5. Routed apps get their own **volume slider** (independent of system volume), remembered per app.

A welcome guide opens on first launch and can be reopened any time via the **?** button in the menu footer.

## Behavior notes

- Routes are held while the app is **running** (not only while playing), so playback starts on the right device instantly. While a route is active, macOS shows an audio-capture indicator in the menu bar — expected.
- If the target device disconnects, the app falls back to normal system output; the route re-activates when the device returns.
- Audio picked via an app's *own* network output picker (e.g. Spotify Connect) never touches the Mac's audio system and can't be routed here. Use AirPlay via macOS instead — AirPlay devices show up as normal output devices.
- On every launch the app destroys any aggregate devices a previous crash may have leaked (a leaked tap can otherwise leave an app muted).

## Startup & distribution

See [NEXT_STEPS.md](NEXT_STEPS.md) for launch-at-login, signing, notarization, and release packaging.

## Troubleshooting

- **No permission prompt / silent routing:** ad-hoc signed builds may not register properly with TCC. Reset with `tccutil reset SystemAudioCaptureRequests com.abhisekganguly.AudioRouter`, or rebuild with a real signing identity (sign into Xcode with your Apple ID → Settings → Accounts → Manage Certificates → Apple Development).
- **Check permission state:** System Settings → Privacy & Security → Screen & System Audio Recording (or "System Audio Recording Only" on newer macOS).
- **Logs:** `log stream --predicate 'subsystem == "com.abhisekganguly.AudioRouter"' --level info`
