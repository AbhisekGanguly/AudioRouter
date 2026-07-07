# Homebrew cask for AudioRouter. The live copy of this file belongs in the
# tap repo (AbhisekGanguly/homebrew-tap → Casks/audiorouter.rb); this one is
# the source of truth kept alongside the app. After each release, update
# `version` and `sha256` (scripts/release.sh prints both) in the tap.
cask "audiorouter" do
  version "0.1.0"
  sha256 "b9198d0dfb459426d2f82f25a74e2cf152ed81b617cce61f87312a7bd0680227"

  url "https://github.com/AbhisekGanguly/AudioRouter/releases/download/v#{version}/AudioRouter-#{version}.zip"
  name "AudioRouter"
  desc "Route each app's audio to a different output device"
  homepage "https://github.com/AbhisekGanguly/AudioRouter"

  depends_on macos: ">= :sonoma"

  app "AudioRouter.app"

  zap trash: [
    "~/Library/Application Support/AudioRouter",
    "~/Library/Preferences/com.abhisekganguly.AudioRouter.plist",
  ]

  caveats <<~EOS
    AudioRouter is open source but not notarized. If you installed without
    HOMEBREW_CASK_OPTS=--no-quarantine, macOS will block the first launch:
    approve it under System Settings > Privacy & Security > "Open Anyway".

    On first route, macOS asks for System Audio Recording permission —
    required to capture an app's audio and redirect it.
  EOS
end
