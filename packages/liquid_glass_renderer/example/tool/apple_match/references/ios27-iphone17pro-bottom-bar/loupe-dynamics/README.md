# Apple tab bar loupe dynamics (iOS 27 simulator, iPhone 17 Pro)

Recording: `simctl io recordVideo`. The container timestamps are compressed ×11.9, so the
CSV uses rescaled real time (about 20 ms per frame, ~50 fps). Light appearance over black
content: the loupe is bright wherever it extends beyond the bar.

Measured per frame: how far the loupe extends below the bar bottom (steady press = 5.37 pt)
and height = 72 + 2 × (extension − 5.37), where 72 pt is the ruled steady loupe height. Also
the width at 1.5 pt below the bar, and the bright extent at the bar-centre row (bar ends at
rest: 24.0 / 378.0).

Gestures:
- fast flick, 207 pt in 180 ms (t ≈ 1.8 s)
- slow drag, 207 pt in 3 s (t ≈ 4.9–7.9 s)
- 1.5 s press on Search, the right end tab (t ≈ 11 s)
- 1.5 s press on Home, the left end tab (t ≈ 15 s)

## Headline

| event | steady h | peak h | overshoot | rise to peak | settle (±0.7 pt of steady) |
|---|---|---|---|---|---|
| press → drag start (middle tabs) | 72 | 81.4 | **+13 %** | ~0.17 s | ~0.45 s after peak; one small undershoot (−1.2 pt, −1.7 %) |
| press at end tab Home | 72 | 84.0 | **+17 %** | ~0.24 s | ~0.6 s after peak, monotonic |
| press at end tab Search | 72 | 76.0 | +5.6 % | ~0.2 s | ~0.4 s |
| fast 180 ms flick | loupe only partly forms (~0.18 s visible), then fades on release | | | | |

- **Oscillation:** a single overshoot, then a small undershoot about 0.37 s later. That gives
  a period of about 0.74 s (≈ 1.35 Hz). The peak-to-undershoot ratio is about 7.8 per half
  cycle, so the damping ratio is **ζ ≈ 0.55** (under-damped, but only one visible
  undershoot). The end-tab press shows no undershoot, so ζ is close to 0.7–1 there.
- **Horizontal extent:** at the bar-centre row, the bright extent reaches **x = 12.7–17.0**
  on the left and **386.0–388.3** on the right. The rest bar spans 24.0–378.0, so it pushes
  about 7–11 pt past each end: the pressed bar swell (≈ 1.042 → ≈ 7.4 pt per side) plus
  the loupe overhanging by roughly 2–4 pt at the end tabs. Mid-bar presses reach the same
  outer extent, so most of that is the swell.
- **Refraction at the rim:** not measured numerically in this window. From the grid press
  crop (`../images/apple-loupe-grid-5x.jpg`), refraction and dispersion are
  confined to thin bands of about 3–4 pt at the loupe's top and bottom rims, and the
  interior is 1:1.

Files: `apple-loupe-timeline.csv` (all 901 frames) and `key-*.jpg` (the bar region at
3 px/pt, crop starting at y = 760 pt).
