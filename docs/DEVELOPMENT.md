# Developing Cans

## Build

```sh
brew install xcodegen
xcodegen                    # generates Cans.xcodeproj from project.yml
open Cans.xcodeproj         # or: scripts/release.sh → release/Cans.zip
```

Requires Xcode 16+ and macOS 14+. Pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml`, which tests, builds, and publishes the zip to GitHub Releases.

To keep macOS from asking for Bluetooth permission after every rebuild, sign debug builds with a stable local identity: create a code-signing certificate in Keychain Access and put `CODE_SIGN_IDENTITY = <its name>` in the gitignored `Configuration/Local.xcconfig`.

## Protocol

The XM4 controls use Sony's MDR v1 protocol and the XM5 uses MDR v2, both over Bluetooth RFCOMM. Every XM4 command was verified on a real WH-1000XM4 (firmware 3.0.1). XM5 support covers what the original XM5 Control app implemented over MDR v2.

Commands are reply-serialized: one request is in flight at a time, and the next one goes out after the reply (or a 1 s timeout). The sequence number comes from the headphones' ACK frame, not a local toggle. If three requests in a row go unanswered, the panel's lamp shows "No reply" until the headphones send anything again.

## How Now Playing works

macOS doesn't pass track info to the headphones, and since macOS 15.4 its system Now Playing (what Control Center shows) only answers Apple-signed processes. So while the popover is open, Cans runs a tiny bundled helper library (`NowPlayingHelper/`) inside Apple's `/usr/bin/perl`, the approach of the open-source mediaremote-adapter project, to read it and to send play/pause/skip. It stops when the popover closes. For this reason Cans isn't sandboxed; it's distributed outside the App Store.

## End-to-end tests (real headphones)

`scripts/e2e.sh` runs the full release gate against a paired, powered-on WH-1000XM4:

- a hardware suite that changes each setting, re-reads everything from the headphones, checks they hold it, and restores it;
- a UI suite that drives the real app.

Quit Cans and close Sound Connect on your phone first, since only one app can own the control channel. `CANS_E2E_MULTIPOINT=1` also toggles multipoint, which may restart the headphones.

## README media

Debug builds take capture flags:

| Flag | Effect |
|---|---|
| `--ui-test-host` | Shows the panel in a window. |
| `--demo-tour` | Walks through the controls on the connected headphones, then restores NC with EQ off. It skips the Headphones page, which shows the Bluetooth address. |
| `--demo-name=WH-1000XM4` | Replaces a personal device name. |
| `--demo-track="Title\|Artist\|App"` | Shows a stand-in track instead of what's really playing. |
| `--appearance=dark\|light` | Forces an appearance. |

The GIFs and images in `docs/media` are real recordings of the panel driven by `--demo-tour`, shown at their native Retina pixel size.
