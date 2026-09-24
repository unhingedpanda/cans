---
version: 1
slug: "sources-menubarview-swift"
primary_target: "Sources/MenuBarView.swift"
related_targets: []
---

Scope: the Cans menu-bar popover (dashboard + insert rack settings). Mode: Operate.
Audience/job: Sony XM4/XM5 owners at their Mac; glance, click, done. Frequent: mode switch, ambient level, volume, battery. Rare: the insert rack settings.
Constraints: native SwiftUI, no dependencies, dark console panel, ~344pt wide popover, every control VoiceOver-adjustable.

## Direction contract

THESIS: The headphones are one live channel on a mixing desk. Refuses the category default: a stack of rounded cards with SF Symbol tiles and system toggles (Control Center clone).

OWN-WORLD: Charcoal anodized panel (#17181A), recessed grooves (#0E0F10), off-white scribble-strip tape (#ECE9E1) with ink legends, condensed caps legends. Amber (#F2A33A) is the only "on" lamp colour; signal green (#46D07A) by law means only "control link live"; red only for low battery. Backlit push-buttons, vertical faders with square caps in grooves, and segmented LED ladders are the whole component family. Raises: one level ramp everywhere (every level reads as the same segmented ladder, from Star Atlas); state is a mark as well as a hue (the lit legend changes text and shape, from Cutting Bench); one colour by law (from Arcade CRT).

STORY: The user sees the channel's state in one glance (strip, link lamp, battery ladder, codec), punches an input button, rides a fader, and leaves. Deeper settings live in the insert rack, one click behind.

FIRST VIEWPORT: Top: scribble strip carrying the device name, link lamp and the INSERTS button. Meter bridge: battery ladder with %, codec and DSEE badges. Input selector: three backlit push-buttons OFF / NC / AMB across the width. Fader bank as the dominant region: AMB (with VOICE latch), VOL, then CB + five EQ bands, all as vertical faders with scribble labels, plus an EQ preset selector. Below: scene recall (FOCUS / OFFICE / AWARE) and transport with now-playing on a strip.

FORM: Channel Strip (analog console channel strip), position 3 on the ordered list; seed key 5e415ab7. Signature interaction: detented faders — drag snaps to device steps with trackpad haptic ticks, value shown live on the fader's own scribble. Motion grammar: lamps fade up in 120ms ease-out, the ladder fills segment by segment; instant under Reduce Motion.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
