# AudioRouter — Next Steps

Where the app stands, how to run it at startup, and how to ship it to other people.

## Current status

- ✅ Working per-app audio routing (verified: routes apply, permission prompt fires even with ad-hoc signing)
- ✅ Persistent rules that auto-reapply (`~/Library/Application Support/AudioRouter/rules.json`)
- ✅ Installed at `/Applications/AudioRouter.app`
- ✅ In-app "Launch at login" toggle (bottom of the menu popover)
- ✅ App icon (`Support/AppIcon.svg` → `.icns` via `scripts/make-icon.sh`)
- ✅ Per-app volume sliders (gain applied in the IO callback, persisted per rule)
- ✅ First-run onboarding window (reopenable via the ? button in the menu footer)

## Run at Mac startup

Open the menu bar popover and check **Launch at login** at the bottom. That's it — it registers the app with macOS via `SMAppService`, and you can see/manage it under **System Settings → General → Login Items & Extensions** too.

Two things to know:

- The login item points at `/Applications/AudioRouter.app`. Always run the installed copy, not `build/AudioRouter.app` (the build folder gets wiped on every rebuild).
- After you rebuild and reinstall, the ad-hoc signature changes, so macOS may show the System Audio Recording permission prompt once more. Approve it once and you're set. (This stops happening once you sign with a real certificate — see below.)

To update the installed copy after code changes:

```sh
./scripts/build-app.sh
killall AudioRouter; rm -rf /Applications/AudioRouter.app
cp -R build/AudioRouter.app /Applications/
open /Applications/AudioRouter.app
```

## Distributing to other people

Right now the app is **ad-hoc signed**: it works on this Mac, but on anyone else's Mac, Gatekeeper will refuse to open it (or force them through scary right-click → Open hoops, and on recent macOS even that is blocked for unsigned downloads). To distribute properly you need three things: a **Developer ID signature**, **notarization**, and a **download format**. There is no Mac App Store option — the system-audio-capture API this app depends on isn't accepted there, and the app runs unsandboxed.

### Step 1 — Join the Apple Developer Program

- Enroll at [developer.apple.com/programs](https://developer.apple.com/programs/) ($99/year) with your Apple ID.
- In Xcode: **Settings → Accounts → add your Apple ID → Manage Certificates → “+” → Developer ID Application**. This puts a `Developer ID Application: Your Name (TEAMID)` certificate in your keychain.

### Step 2 — Build signed with hardened runtime

The build script already applies `--options runtime` (hardened runtime, required for notarization) when the identity supports it:

```sh
SIGN_IDENTITY="Developer ID Application: Abhisek Ganguly (TEAMID)" ./scripts/build-app.sh
```

Verify: `codesign -dv --verbose=2 build/AudioRouter.app` should show your Team ID and `runtime` in the flags.

### Step 3 — Notarize and staple

One-time setup (uses an [app-specific password](https://support.apple.com/en-us/102654) from appleid.apple.com):

```sh
xcrun notarytool store-credentials AudioRouter \
  --apple-id abhisek@gangulyconsulting.com \
  --team-id TEAMID \
  --password <app-specific-password>
```

Then for each release:

```sh
ditto -c -k --keepParent build/AudioRouter.app build/AudioRouter.zip
xcrun notarytool submit build/AudioRouter.zip --keychain-profile AudioRouter --wait
xcrun stapler staple build/AudioRouter.app
```

`--wait` blocks until Apple's automated scan finishes (usually a few minutes). Stapling attaches the notarization ticket so the app opens instantly even offline.

### Step 4 — Package and publish

- **Zip** (simplest): re-zip the *stapled* app with `ditto -c -k --keepParent build/AudioRouter.app AudioRouter-0.1.0.zip` and attach it to a **GitHub Release**.
- **DMG** (nicer): `brew install create-dmg`, then `create-dmg AudioRouter.dmg build/AudioRouter.app` (sign + notarize the DMG too).
- Bump `CFBundleShortVersionString` / `CFBundleVersion` in `Support/Info.plist` for each release.

Users just download, drag to Applications, and approve the System Audio Recording prompt on first route.

### Later, if it grows

- **Auto-updates:** add [Sparkle](https://sparkle-project.org/) so users don't re-download manually.
- **Homebrew:** publish a cask (`brew install --cask audiorouter`) once there's a stable GitHub release URL.
- **A real app icon** (currently the app has none — menu bar only, but the Finder/dock representations look bare).

## Roadmap ideas (roughly in value order)

1. **Format-aware buffer copy** — the IOProc currently does a straight per-buffer copy; stereo-to-stereo is fine, but multichannel interfaces or odd sample formats would need real channel mapping.
2. **Bluetooth→Bluetooth drift tuning** — drift compensation is always on; when source and destination share a clock domain it can cause a faint periodic crackle. Detect and disable it for that case.
3. **Pause routing while app is silent** — routes currently hold while an app runs, which keeps AirPlay speakers "occupied" by silence. Could release the tap after N minutes of silence, at the cost of a brief blip when playback resumes.
4. **Route health check** — detect a stalled IOProc (no callbacks for N seconds while the app claims to be playing) and rebuild the route automatically.
