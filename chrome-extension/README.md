# AudioRouter Tabs — Chrome extension

Per-**tab** audio control for Chrome, companion to the AudioRouter Mac app: route each tab to a different output device and give every tab its own volume (up to 200%), simultaneously — e.g. two YouTube tabs playing to two different speakers.

## How it works

Chrome mixes all tabs' audio inside one internal process before macOS ever sees it, so the Mac app's per-app routing can't tell tabs apart — that has to happen inside Chrome. This extension captures a tab's audio (`chrome.tabCapture`), runs it through a gain node (volume) and an `AudioContext` pointed at your chosen output device (`setSinkId`), all inside an extension-owned page. Capturing silences the tab's normal output, so audio comes out exactly once, on the device you picked. Closing the tab or clicking ✕ restores normal playback.

No content scripts, no access to page contents, no `<all_urls>` permission — it only touches tab *audio*, and only for tabs you explicitly route.

## Install (Developer Mode)

1. Open `chrome://extensions`
2. Enable **Developer mode** (top right)
3. Click **Load unpacked** and select this `chrome-extension/` folder
4. Optional but recommended: click the extension's **Settings** and grant device access once, so device *names* appear in the picker (Chrome only reveals speaker names via a one-time media permission; nothing is recorded)

## Use

1. Open the tab you want to control and click the AudioRouter Tabs icon
2. Pick an output device and/or set the tab's volume — routing starts immediately (the toolbar icon shows an **ON** badge for routed tabs)
3. Other tabs currently playing audio are listed too — click one to jump to it, then reopen the popup to control it (Chrome requires the extension to be invoked on a tab before it can capture it)

## Known limitations

- **Remove any whole-Chrome rule in the Mac app first.** An app-level "Chrome → device" rule in AudioRouter captures *all* Chrome audio — including this extension's routed playback — and overrides per-tab choices.
- Tabs show Chrome's capture indicator while routed (expected — that's the tabCapture API).
- `chrome://` pages and the Chrome Web Store can't be captured (Chrome policy).
- Capture adds a few milliseconds of latency; imperceptible for music, and normally fine for video.
