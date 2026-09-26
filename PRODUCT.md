# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

Native macOS menu bar app (SwiftUI + AppKit status item), macOS 14+. Follows Apple's Human Interface Guidelines; no web views.

## Users

Mac users who own Sony WH-1000XM4 or WH-1000XM5 headphones and wear them at their desk. Today, changing noise cancelling, EQ or any deeper setting means picking up the phone and opening Sony Sound Connect. They want those controls one click away in the menu bar, without their phone.

## Product Purpose

Cans is a menu bar controller for Sony 1000X headphones. It talks to the headphones directly over Sony's Bluetooth control channel (MDR v1 for XM4, MDR v2 for XM5). It covers everything Sound Connect offers on the Mac-relevant side: noise control, ambient level, Focus on Voice, EQ, speak-to-chat, NC optimizer, DSEE Extreme, sound quality mode, multipoint, touch panel, wearing detection, auto power off, custom button, voice guidance, playback, volume, battery and codec.

Success means never reaching for the phone to change a headphone setting while at the Mac.

## Positioning

Native, instant, and tiny: no account, no location tracking, no marketing surfaces; the only network call is a daily update check (Sparkle, can be turned off). Sound Connect is slow to connect, cluttered, and phone-only. Cans runs from the menu bar in a few MB of RAM and applies changes the moment you click.

## Operating Context

- Used in short glances from the menu bar while working: toggle NC and Ambient, nudge the ambient level, check battery, switch EQ.
- Deeper settings are rare, set-and-forget changes.
- A global shortcut (⌥⌘A) toggles NC and Ambient without opening the app.
- Only one process can own the Sony control channel at a time. When a phone or another app holds it, Cans must say so plainly and retry.

## Capabilities and Constraints

- Every XM4 command has been checked on real hardware (firmware 3.0.1). Phone-only features are out of scope: adaptive sound control, 360 Reality Audio setup, the activity log.
- Multipoint is a verified setting (D2, MULTIPOINT_SETTING), but toggling it may restart the headphones, so the UI must warn first.
- Distribution: public, as an ad-hoc signed zip, until a Developer ID exists. No notarization yet, so first launch needs right-click → Open.
- Fork of Maadlou/xm5-control-macos, MIT licensed. The original copyright notice must be kept.
- Performance budget: no third-party dependencies unless they earn their place, a minimal idle CPU wake schedule, and a small memory footprint.

## Brand Commitments

- Name: **Cans** (slang for headphones). Casual, confident, audiophile-literate.
- Voice: plain and short. Name the state ("Noise cancelling", "Control link busy — close Sound Connect on your phone"), never marketing.
- Not affiliated with Sony; Sony trademarks appear only to name compatible models.

## Evidence on Hand

- Protocol verification transcripts from live XM4 probing (this session).
- `Resources/Assets.xcassets/HeadphonesXM4.imageset/xm4.svg`, `HeadphonesXM5.imageset/xm5.svg` — original headphone illustrations made for Cans (no Sony photos or marks).
- No testimonials, user counts, or benchmarks exist; do not fabricate any.

## Product Principles

1. **One glance, one click.** The things people change daily sit on the first surface; everything else is one level down.
2. **The headphones are the source of truth.** Show what the device reports, and reflect changes made elsewhere (phone, buttons).
3. **Honest about the link.** Connection state and failures are explicit and recoverable.
4. **Weightless.** A menu bar utility should cost nothing when idle.

## Accessibility & Inclusion

Full VoiceOver labels and values on every control, keyboard operability, a Reduce Motion alternative for every transition, and state that never relies on colour alone.
