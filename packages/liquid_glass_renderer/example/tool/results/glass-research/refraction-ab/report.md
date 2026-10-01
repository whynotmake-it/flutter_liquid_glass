# Refraction: Apple UIGlassEffect vs ours in the A/B app

Setup: `lib/glint_ab_main.dart` (#182). A 300×64 pt capsule at the same spot:
native `UIGlassEffect` (`.regular` / `.clear`) vs our `ios27Toolbar` /
`ios27Clear` presets (height 20, amount 60; toolbar has `refractionFitsShape`,
so height 16 / amount 32 at this size; clear doesn't). iOS 27 iPhone 17 Pro
simulator at the system default tint. The **iPhone was unavailable** (devicectl
"unavailable" from 18:30), so the device half is still open.

Method: a 120 pt black→white sawtooth behind the glass encodes source position.
The glass tone is calibrated on the undisplaced interior (clear: gain 0.95,
offset 32, which is Apple's clear face), then each pixel is inverted to its
source, and the median displacement along the outward normal is taken per inset
band. The decoder is
`ramp_decode.py`. Visual crops: `simulator-crops.jpg`.

## Clear glass (reliable)

Displacement toward the interior (pt), by inset (pt):

| inset | 1–2 | 2–3 | 3–4 | 4–6 | 6–8 | 8–10 | 10–13 | 13–16 | 16–20 |
|---|---|---|---|---|---|---|---|---|---|
| top, Apple | 35.5 | 27.1 | 21.7 | 15.8 | 10.3 | 6.8 | 4.0 | 1.8 | 0.1 |
| top, ours | 53.6 | 42.0 | 32.4 | 20.3 | 14.6 | 9.9 | 5.7 | 2.3 | 0.4 |
| end, Apple | 25.5 | 21.2 | 17.7 | 13.9 | 10.0 | 6.7 | 3.8 | 1.6 | 0.3 |
| end, ours | 37.1 | 30.8 | 25.8 | 19.7 | 14.0 | 9.6 | 5.5 | 2.2 | 0.3 |

- Ours is **×1.44 at every inset** (1.26–1.55), with the same band width (both end
  by 16–20 pt) and the same quarter-circle shape.
- A quarter circle of height 20 and amount **≈ 42.5** reproduces Apple within
  0.5 pt from 3.5 to 14.5 pt.
- No lens effect: displacement is ≈ 0 deeper than 20 pt in both.
  `backdropShrink` / `backdropScale` play no part at this size.

**Why the fit disagrees.** The clear amount (60) was fitted on a single 92 pt
capsule (halfMinor 46, so 60 = 1.30 × halfMinor). Here halfMinor is 32 and
Apple uses 42.5 = 1.33 × halfMinor. So Apple scales the clear lens with the
shape too, just more gently than regular glass (amount ≤ halfMinor). One
capsule size couldn't reveal the scaling.

**Proposed fix (not applied):** clear glass fits its amount to the shape at
`≈ 1.3 × halfMinor` (60 at 92 pt, 42 at 64 pt). Keep height 20. Before
committing, confirm at a third size (the #175 `material_card_clear` /
`material_circle_clear` references or an A/B size sweep), including whether the
amount is capped at 60 for large shapes.

## Regular glass (inconclusive)

Both glasses blur the ramp, so the affine tone calibration is unreliable.
Apple read 23 pt at 4–6 pt on the top wall but ≈ 0 at the ends, which isn't
physically consistent. Ours at the same place read 7.4 (top) and 7.5 (end).
Needs a sharper probe (for example, a ramp only mid-tooth pixels far from the
blur, or a device with the slider at Clear) before concluding. By construction
our toolbar uses 16 / 32 here, matching the notes' regular-glass limit.

## Device vs simulator

Not measured yet: the phone was unavailable. The same harness runs on the
device with `--dart-define=GLINT_AB_CYCLE=true`; screenshots go through
`devicectl`.
