# iOS 27 bottom bar and toolbar references

Reference captures and measurements for the example's bottom bar and toolbar
(`example/lib/bottom_bar/`): the iOS 27 system tab bar and toolbar vs the
playground, on an iPhone 17 Pro iOS 27 simulator. The matching pipeline does
not read them; [`bottom_bar_match_test.dart`](../../../../test/bottom_bar_match_test.dart)
captures our side at the same size. "Ours" below is the playground as of
2026-09-30 (old review PR #182 at `226d856`), before the later bar edits.

Captured 2026-09-30 on a fresh simulator `BottomBarRef-iPhone17Pro-iOS27`
(iPhone 17 Pro, iOS 27.0, 402×874 pt @3x, light appearance unless noted).

- **Apple:** a SwiftUI reference app with `TabView` (Home, New, Radio, Library plus
  `Tab(role: .search)`) and `.tabViewBottomAccessory` (mini player). Each tab is a
  `NavigationStack` with glass toolbar buttons: leading `chevron.left`, trailing
  group `square.and.arrow.up` + `ellipsis`.
- **Ours:** playground `#182` head `226d856`, debug build, controls scene, on the
  same simulator.
- **Drags:** `agent-device gesture pan` over 3 s, with screenshots taken mid-gesture.
- **Jelly:** `simctl io recordVideo` of 250/500/1000 ms pans.
- **Images:** [`images/`](images/) (JPEG); loupe dynamics over time in
  [`loupe-dynamics/`](loupe-dynamics/).

All values are in pt. Screen-space y is measured from the top.

**Caveat:** iOS placed Search inside the tab bar as a fifth item, not as the
separate circle ours has. So Apple's bar has 5 slots, while ours has 4 slots plus a
62 pt circle.

## 6. Position and size (rest)

| | Apple | Ours |
|---|---|---|
| tab bar x | 20.3 – 381.7 (w 361.4, 5 slots of 72.3) | 16 – 310 (w 294, 4 slots of 71.5) + search circle 324 – 386 |
| tab bar y | 791.0 – 853.3, **h 62** | 758 – 820, h 62 |
| bottom edge → screen bottom | **20.5** | **54** (sits ~33.5 higher) |
| side margin | 20.3 | 16 |
| accessory | h ≈ 48 (735.5 – 783.3), w 356 (x 23–379), gap to bar **8** | h ≈ 46–48, gap 10 |
| selected platter (rest) | x 20.3–102 (w 81.7), y 793–851 (h 58), lum 231–235 on white | inset 4 (h 54) |
| tab icon heights | Home 24.0, New 21.0, Radio 20.7, Library 26.7, Search 22.3; icon rows ≈ 802–828 | — |
| label | cap-to-descender ≈ 10.3 (y 832–842), ≈ 10 pt semibold | 10 pt w600 |

Apple's bar is centred on 822.2 pt. Its bottom is 20.5 pt above the screen bottom,
which sits on the home-indicator safe area.

## 4. Press swell and stretch

- **Press:** the bar grows from 361.3×62.0 to **376.3×64.7**. Scale ≈ **1.042**
  horizontally and 1.044 vertically, about the centre (left edge 20.3 → 13.0).
  Ours uses `pressScale` 0.05 (1.05).
- **Dragging along the bar:** the bar stays at the pressed size (w ≈ 376–377).
- **Overdrag horizontally** past the ends: the bar stretches about **10–12 pt**
  toward the finger (left edge 13 → 0.7; right edge 389 → 399.7). The opposite edge
  stays put. The loupe does *not* follow past the end tab.
- **Overdrag vertically** (finger 45 pt below or 90 pt above the bar): **no vertical
  stretch**. The top and bottom move by ≤ 3 pt (top 789 → 788.3, bottom ≤ 854.3), and
  the width barely changes (+3 pt).
- **Ours:** overdrag up by 90 stretches the capsule upward and the loupe rises about
  30 pt above the bar top (`ours-overdrag-ruled.jpg`). Horizontal overdrag lets the
  loupe overhang the bar end by about 14 pt on the left, and about 22 pt on the right
  (where it merges into the search circle).

## 3. Drag clamp

Apple clamps the loupe to the bar. Past either end it sits on the end tab
(`apple-overdrag.jpg`: loupe centred on Home / Search while the finger is
beyond), and dragging off the bar vertically keeps it on the bar. Ours lets it
leave the bar in both axes (see above).

## 1. Loupe size, refraction, dispersion

| | Apple | Ours |
|---|---|---|
| loupe size (pressed/held) | **≈ 97 × 72** (press: x 20–117, y 786–858; drag: x 107–205) | ≈ 92–98 × **85** (y 747.5–832.5) |
| relative to slot | 1.34 × slot width; extends **≈ 5.5** beyond the bar top and bottom | extends ≈ 11 beyond the bar top and bottom |
| icon inside loupe | same size as at rest (house ≈ 28 wide) | magnified (tint compensation) |
| refraction over grid | interior shows the bar content **1:1**; grid lines stay straight; refraction and **dispersion only in thin rim bands ≈ 3–4 pt** at top and bottom | strong: big oval bands at top and bottom, grid pulled far inward, interior shrunk and washed |
| dispersion | rainbow fringes on the rim bands and where blue glyphs cross the rim | louder colour fringes over a wider band |

Crops: `apple-loupe-press-5x.jpg`, `apple-loupe-drag-5x.jpg`,
`apple-loupe-grid-5x.jpg`, `ours-loupe-grid-5x.jpg`,
`loupe-size-ruled-ours-vs-apple.jpg`.

## 5. Jelly during fast drags

Pans of 270 pt: 250 ms (≈ 1100 pt/s average), 500 ms (≈ 540), 1000 ms (≈ 270).

| | at rest | 250 ms | 500 ms | 1000 ms |
|---|---|---|---|---|
| Apple loupe w × h | 98 × 73 (aspect 1.34) | **91–97 × 44–48 (aspect 1.9–2.15)** | 84–91 × 49–57 (1.5–1.9) | ≈ 87 × 55 (1.58) |
| Ours loupe w × h | ≈ 95 × 85 (1.1) | ≈ 94–98 × ≥ 75, dipping 7–12 below the bar (≈ 1.25 or less) | similar | — |

Apple **stretches along the motion**: its width holds at about 1.0× and its height
drops to about 0.6×. Ours doesn't; it stays about as tall as wide and hangs below
the bar (`apple-jelly-fast-drag-frames.jpg`, `ours-jelly-fast-drag-ruled.jpg`).
The frame times in the Apple sheet are 30 fps indices; red ticks are every 10 pt.

## 2. Selected tab tint

Median rgb of the selected icon's saturated pixels (sRGB 8-bit):

| content | Apple, light appearance | Apple, dark appearance | Ours (light) |
|---|---|---|---|
| white / light | (0, 130, 248), platter lum 231 | (85, 230, 255), glass lum 185 | (0, 121, 255) on grid |
| black / dark | **(0, 93, 199)**: darker, platter lum 97; the bar stays light glass | (6, 151, 255), glass lum 32 | (0, 76, 255) on night |
| busy photo | (76, 142, 177), p90 (78, 143, 198) | median (0, 69, 112), p90 (57, 202, 255) | (0, 62, 255) on photos |

In these captures Apple's tint **follows the glass tone**: lighter glass gives a
lighter tint and darker glass a darker one, in both appearances. It gets lighter
on light content in dark appearance (cyan-ish 85, 230, 255) and darker on black
content in light appearance. It doesn't get lighter on dark content here. Apple's
adaptive light/dark flip of the whole bar didn't trigger over static black
content in light appearance, so "gains contrast on dark" may come from that flip
in a real scrolling app. Ours goes to a saturated deep blue (B = 255) on dark and
busy content, where Apple stays less saturated.

## 7. Top toolbar

| | Apple | Ours |
|---|---|---|
| leading button | 45.3 incl. rim (≈ 44 glass), x 15.3–60.7, y 61.3–106.7 | 48 circle, x 16–64 |
| trailing group | 102 × 45.3 (two buttons in one capsule), right margin 15.3 | 96 × 48 capsule + extra circles |
| row centre y | **84.3** | **97.8** (~13.5 lower) |
| chevron.left glyph | **10.7 × 18.3**, stroke ≈ 2.1 (medium) | 8.7 × 15.7 |
| square.and.arrow.up | **19.0 × 24.0** | 16.0 × 20.3 |
| ellipsis | 3 dots of **4.0**, pitch **7.8** (total 19.7) | dots 3.3–3.7, pitch 6.8 |

Crops: `toolbar-apple-vs-ours-5x.jpg`, full screens
`full-screens-light-apple-vs-ours.jpg` / `full-screens-busy-apple-vs-ours.jpg`.

## Raw frames

`apple-light-rest.jpg`, `apple-coast-rest.jpg`, `apple-darkmode-dark-rest.jpg`,
`apple-light-press.jpg`, `ours-grid-rest.jpg`, `ours-photos-rest.jpg`,
`ours-grid-press.jpg` (full resolution 1206×2622, JPEG q92).

The reference app (a single SwiftUI file built with `swiftc`) stayed on the
capture Mac and is not in the repository.
