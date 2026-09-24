# Cans

A menu bar controller for Sony **WH-1000XM4** and **WH-1000XM5** headphones on macOS. Everything Sony Sound Connect does that makes sense on a Mac, one click from the menu bar, no phone needed.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-support-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/yash.raj)

## What it controls

| | WH-1000XM4 | WH-1000XM5 |
|---|---|---|
| Noise cancelling / Ambient / Off, ambient level, Focus on Voice | ✓ | ✓ |
| Battery, EQ presets, Clear Bass + 5-band custom EQ, saved Mac presets | ✓ | ✓ |
| Codec and DSEE status | ✓ | – |
| Now playing from any app (Spotify, Music, browsers…), play/pause/skip | ✓ | ✓ |
| Speak-to-Chat (on/off, sensitivity, timeout, voice focus) | ✓ | – |
| NC Optimizer with air-pressure readout | ✓ | – |
| DSEE Extreme, sound quality vs. stable connection | ✓ | – |
| Touch panel, custom button, pause when taken off, auto power off | ✓ | – |
| Multipoint, voice guidance, power off | ✓ | – |

The XM4 controls use Sony's MDR v1 protocol. Every command was verified on a real WH-1000XM4 (firmware 3.0.1). XM5 support covers what the original XM5 Control app implemented over MDR v2.

Also included: a global **⌥⌘A** shortcut to toggle NC and Ambient, keys 1/2/3 for Off/NC/Ambient while the popover is open, launch at login, and automatic reconnection.

Phone-only Sound Connect features are intentionally out of scope: adaptive sound control, 360 Reality Audio setup, and the activity log. Volume stays with your Mac's volume keys: the headphones ignore volume writes while nothing is playing, so a second volume control would only work sometimes.

Cans follows the system appearance (light and dark). The headphone illustration reacts to the listening mode, and it has a couple of easter eggs.

## Footprint

About 8–18 MB of memory, 0% CPU when idle, and about 0.2% while the animated popover is open (all motion runs in Core Animation). A 4.7 MB universal app (1.3 MB download) with no third-party dependencies, no network access, no accounts and no analytics.

**How Now Playing works.** macOS doesn't pass track info to the headphones, and since macOS 15.4 its system Now Playing (what Control Center shows) only answers Apple-signed processes. So while the popover is open, Cans runs a tiny bundled helper library inside Apple's `/usr/bin/perl` (the approach of the open-source mediaremote-adapter project) to read it and to send play/pause/skip. It stops when the popover closes. For this reason Cans isn't sandboxed; it's distributed outside the App Store.

## Install

1. Download `Cans.zip` from the [latest release](../../releases/latest) and unzip it.
2. Move **Cans.app** to **/Applications**.
3. The build is ad-hoc signed, not notarized, so on first launch right-click **Cans.app** → **Open**. If macOS still refuses, go to **System Settings → Privacy & Security** and click **Open Anyway**.
4. Allow Bluetooth access when asked.

Verify the download with `shasum -a 256 -c Cans.zip.sha256`.

Only one app can hold Sony's control channel at a time. If Cans says **Busy**, close Sound Connect on your phone; Cans retries on its own.

## Build

```sh
brew install xcodegen
xcodegen                    # generates Cans.xcodeproj from project.yml
open Cans.xcodeproj         # or: scripts/release.sh → release/Cans.zip
```

Requires Xcode 16+ and macOS 14+. Pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml`, which tests, builds, and publishes the zip to GitHub Releases.

### End-to-end tests (real headphones)

`scripts/e2e.sh` runs the full release gate against a paired, powered-on WH-1000XM4: a hardware suite that changes each setting, re-reads everything from the headphones, checks they hold it, and restores it, plus a UI suite that drives the real app. Quit Cans and close Sound Connect on your phone first, since only one app can own the control channel. `CANS_E2E_MULTIPOINT=1` also toggles multipoint, which may restart the headphones.

To keep macOS from asking for Bluetooth permission after every rebuild, sign debug builds with a stable local identity: create a code-signing certificate in Keychain Access and put `CODE_SIGN_IDENTITY = <its name>` in the gitignored `Configuration/Local.xcconfig`.

## Credits

Cans started as a fork of [XM5 Control](https://github.com/Maadlou/xm5-control-macos) by Maadlou (MIT). The protocol work draws on [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge) and [mos9527/SonyHeadphonesClient](https://github.com/mos9527/SonyHeadphonesClient). The headphone illustration is original artwork made for Cans; see [CREDITS.md](CREDITS.md).

Cans is not affiliated with or endorsed by Sony. Sony, WH-1000XM4 and WH-1000XM5 are trademarks of Sony Group Corporation, used here only to identify compatible products.

## Support

Cans is free and open source. If it saves you reaching for your phone, you can [buy me a coffee](https://buymeacoffee.com/yash.raj).

## License

MIT. See [LICENSE](LICENSE); the original copyright notice is kept.
