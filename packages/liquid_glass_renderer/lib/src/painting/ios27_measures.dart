import 'dart:math' as math;

import 'package:meta/meta.dart';

/// The shorter sides, in points, where iOS 27 tells a control's glass from a
/// panel's: glass up to `control` wears a control's material, haze and
/// shadow, glass from `panel` a panel's, and between the two each part grows
/// linearly ([ios27PanelProgress]).
@internal
const ios27SizeRamp = (control: 64.0, panel: 160.0);

/// How far glass whose shorter side is [shortSide] points has grown from a
/// control's toward a panel's ([ios27SizeRamp]): 0 up to a control, 1 from a
/// panel.
@internal
double ios27PanelProgress(double shortSide) {
  final (:control, :panel) = ios27SizeRamp;
  return ((shortSide - control) / (panel - control)).clamp(0.0, 1.0);
}

/// The Settings Liquid Glass slider's middle tick: iOS 27 glass follows the
/// slider at one rate up to it and at another past it
/// ([splitAtMiddleTick]).
@internal
const double sliderMiddleTick = 0.5;

/// How far the slider position [amount] runs up to [sliderMiddleTick], and
/// how far past it.
@internal
({double upTo, double past}) splitAtMiddleTick(double amount) => (
  upTo: math.min(amount, sliderMiddleTick),
  past: math.max(amount - sliderMiddleTick, 0),
);

/// The sigma, in logical pixels, a unit of iOS 27's blur radius comes to over
/// its pyramid of smaller copies.
@internal
const double ios27BlurUnit = 1.94;
