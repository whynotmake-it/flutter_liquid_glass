import 'package:flutter/foundation.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// The measured tuning of an iOS 27 sheet (UISheetPresentationController).
@internal
abstract final class SheetTuning {
  /// The spring a sheet presents, dismisses and moves between detents on (a
  /// flicked-away sheet leaves on [flickDismissSpring]). UIKit runs a
  /// CASpringAnimation of stiffness 333.3 and damping 36.5, mass 1:
  /// response 0.344 s, critically damped.
  /// The simulator's frames fit it to 0.06 points.
  static const spring = Spring.response(0.3441);

  /// The medium detent as a fraction of the maximum (435.68 of 778 on a
  /// 402 x 874 screen, read from UIKit's resolution context).
  static const double mediumFraction = 0.56;

  /// The display corner radius assumed for a floating sheet when the
  /// platform reports none: the iPhone 16 Pro's, where the floating
  /// sheet's bottom corners (62 - 8 = 54 unscaled points) were measured.
  static const double fallbackDisplayRadius = 62;

  /// How far momentum carries a released drag, in seconds of the
  /// release velocity: the sheet settles on the detent nearest to its
  /// height plus the velocity times this. Bracketed by flicks on the
  /// simulator: 680 pt/s up from 544 pt stayed at medium, 680 pt/s down
  /// from 738 pt went to medium (0.143 either way).
  static const double projection = 0.143;

  /// How much faster than the finger the sheet leaves the release: the
  /// settle spring starts at this many times the finger's velocity
  /// (fitted to seven flicks: 2.0 - 2.6, the slowest ones nearest 2).
  static const double releaseVelocityGain = 2;

  /// The release speed, in points per second down, that dismisses a
  /// sheet dragged below its smallest detent however short the drag: a
  /// 680 pt/s flick returned, 900 and 1213 pt/s flicks dismissed.
  static const double dismissVelocity = 1000;

  /// The spring a sheet flicked away leaves on; a sheet released still
  /// leaves on [spring]. Fitted to three flick dismissals (0.12 - 0.5 pt
  /// rms, response 0.349 - 0.354, damping 0.79).
  static const flickDismissSpring = Spring.response(0.352, dampingRatio: 0.79);

  /// The fraction of the finger's velocity a flicked-away sheet leaves
  /// with (0.53 and 0.65 fitted).
  static const double flickDismissVelocityGain = 0.6;

  /// The scale a floating sheet swells by under a touch. The swell holds
  /// while the touch drags the sheet (device: the area scale stays
  /// 0.96837, the floating 0.9602 times this, through every drag of a
  /// floating sheet) and goes when the drag's settle starts; a sheet
  /// docked at the touch does not swell.
  static const double pressScale = 1.00854;

  /// The spring the swell follows, on touch and on release (0.0001 rms in
  /// scale on a held touch).
  static const pressSpring = Spring.response(0.2835, dampingRatio: 0.70);

  /// Seconds between a touch and the start of the swell.
  static const double pressDelay = 0.028;

  /// How much a drag stretches a sheet that floated when the drag began,
  /// per point the finger travelled since: the ratio of the sheet's
  /// vertical to its horizontal scale is `1 + stretchPerPoint * travel`
  /// plus [stretchLagGain] of the lag, up or down alike. The height grows
  /// and the width shrinks by the square root of that ratio each, so the
  /// area holds, about the sheet's bottom edge. Fitted to three device
  /// drags held still (100 and 320 points down, 140 up: 8.80 - 9.00e-5
  /// per point). A sheet docked when the drag began does not stretch.
  static const double stretchPerPoint = 8.9e-5;

  /// The spring of the lag: a point that follows the finger's travel and
  /// its velocity, so it falls behind only while the finger speeds up and
  /// runs ahead while the finger slows down. A drag that starts or speeds
  /// up stretches the sheet further for a moment, one that stops lets it
  /// dip.
  static const stretchLagSpring = Spring.response(0.8, dampingRatio: 0.5);

  /// How much the lag, in points, adds to the stretch ratio. With
  /// [stretchLagSpring] and [stretchPerPoint] it replays the 18 device
  /// drags and flicks of a floating sheet to 0.0011 - 0.0066 rms in the
  /// ratio (0.0016 - 0.0123 without the lag; a 1300 pt/s flick reaches
  /// 1.043 at 168 points of travel, three times the held stretch).
  static const double stretchLagGain = 2.4e-4;

  /// The spring the stretch returns on when the drag ends: it holds from
  /// the lift and leaves with the settle (0.0005 - 0.0008 rms in the
  /// ratio over three releases held still).
  static const stretchSpring = Spring.response(0.355, dampingRatio: 0.62);

  /// Seconds between the lift of a tap on the grabber and the start of the
  /// detent change it causes (0.045 and 0.065 measured).
  static const double grabberTapDelay = 0.05;

  /// Seconds between the lift of a dragging finger and the start of the
  /// settle; the sheet holds still meanwhile (the median of nine
  /// releases, 0.003 - 0.047).
  static const double releaseDelay = 0.025;

  /// The limit, in unscaled points, that a sheet which cannot be dismissed
  /// approaches while it is pulled down: the drag below the smallest detent
  /// is rubber-banded (coefficient 0.55) with this dimension. A simulator
  /// capture of a 200 point sheet pulled 134 points fits 200 to 0.3 points
  /// rms; UIKit takes a quarter of the sheet's height capped at 200 (read
  /// from UIKit, notes private), so every phone reaches the cap.
  static const double refusedPullExtent = 200;

  /// The most a floating sheet stretches above its largest detent, in
  /// unscaled points: a drag up past it is rubber-banded (coefficient
  /// 0.55) with a dimension of the room left to the maximum height,
  /// capped at this. A docked sheet has no room and does not move.
  /// Simulator capture: a medium-only sheet fits 100 (0.2 points rms over
  /// 240 points of travel), a 700 point detent with 78 points of room
  /// fits 78 (0.5 points rms).
  /// Held iPhone 16 Pro drags confirm both dimensions within 1.5 points.
  static const double stretchLimit = 100;

  /// How far below the large detent, in unscaled points, a dragged sheet
  /// finishes docking: during a drag the docking progress runs from the
  /// largest floating detent to the large detent less this (768 of 778 on
  /// a 402 x 874 screen in every simulator row). A settle docks over the
  /// whole way to the large detent.
  static const double dragDockShortfall = 10;

  /// The docking progress at which a dragged sheet changes its background:
  /// past it the opaque fill animates in on [spring] and the glass goes
  /// once the fill is opaque; below it the glass returns and the fill
  /// animates out. The sheet takes the background of the detent nearest
  /// to it (read from UIKit, notes private); the simulator flips the
  /// background between 600.0 and 602.7 points both ways, where the drag's
  /// docking progress crosses one half.
  /// The iPhone 16 Pro turns at 602.67 points (progress 0.5025).
  static const double backgroundSwitch = 0.5;

  /// The share of [refusedPullExtent] that a refused pull must exceed when
  /// the finger lifts for the sheet to report a dismiss attempt: UIKit
  /// tests the pull beyond the edge against a quarter of its rubber-band
  /// extent once the drag has ended, then calls
  /// `presentationControllerDidAttemptToDismiss` (read from UIKit, notes
  /// private).
  static const double dismissAttemptShare = 0.25;
}
