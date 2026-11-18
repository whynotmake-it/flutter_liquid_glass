import 'package:apple_liquid_glass/src/motions/flex_interaction.dart';
import 'package:apple_liquid_glass/src/motions/flex_spec.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// The tuning of a selection lens, as measured on a UIKit control.
///
/// [segmented] and [tabBar] are fitted to frame-by-frame recordings of
/// UISegmentedControl and UITabBar on iOS 27; the two controls share the
/// travel and lift springs and differ in when they react, how far the lens
/// lifts and how strongly it deforms.
@internal
class LensTuning {
  /// Creates a tuning from explicit values.
  const LensTuning({
    required this.selectsOnPointerDown,
    required this.liftWidth,
    required this.liftHeight,
    required this.hangTime,
    required this.hangTimePerPixel,
    required this.hangFromTouch,
    required this.presentationSpring,
    required this.followSpring,
    required this.rubberBand,
    required this.pressDelay,
    this.pressHang = 0.25,
    this.releaseDelay = 0.03,
    this.travelSpring = const Spring.response(0.401, dampingRatio: 0.856),
    this.liftSpring = const Spring.response(0.25),
    this.startDelay = 0.02,
    this.flagLead = 0.025,
    this.hangReferenceDistance = 70,
    this.chromeFlexes = false,
    this.chromeLag = 0.02,
    this.chromeReleaseLag = 0.02,
    this.chromeLandingLag = 0.02,
    this.reducedMotionTravelSpring,
  });

  /// Whether a touch selects on contact (tab bar) or on release
  /// (segmented control).
  final bool selectsOnPointerDown;

  /// How many pixels the lens widens while lifted.
  final double liftWidth;

  /// How many pixels the lens grows taller while lifted.
  final double liftHeight;

  /// The spring that carries the lens between slots after a tap:
  /// 0.401/0.856 fitted to test/fixtures/ios27{,-device}/lens;
  /// lens_test.dart and lens_scrub_test.dart replay it.
  final Spring travelSpring;

  /// The spring that lifts and lands the lens and resizes it between
  /// slots of different widths.
  final Spring liftSpring;

  /// Seconds between a tap's selection and the start of the motion,
  /// counted from the touch's own time stamp.
  ///
  /// The tab bar's 0.045 is the median of 79 device taps (iPhone 16 Pro,
  /// `ios27-device/lens/tabbar*`, lift start fitted to the lift progress,
  /// 39 - 57 ms): UIKit delivers the touch 10 - 25 ms after its stamp,
  /// then sets up the lift on the main thread (the next display frame
  /// comes 26 - 39 ms after the one before instead of 8.3), and the lens
  /// moves from the frame after that. A touch on the selected tab shows
  /// the same setup before its [pressDelay].
  ///
  /// The segmented control's 0.04 is the median of 35 device taps on
  /// another segment, counted from the release that selects
  /// (`ios27-device/lens/segmented-*`, 31.5 - 56 ms): the same delivery and
  /// setup after the release (the next display frame comes 19.5 - 36 ms
  /// after the one before).
  final double startDelay;

  /// Seconds by which the deformation switches to its lifted response
  /// before the visible lift starts and before the visible landing.
  final double flagLead;

  /// Seconds a tapped lens stays lifted, counted from the start of the
  /// lift.
  final double hangTime;

  /// Whether [hangTime] counts from the touch that selected rather than
  /// from the start of the lift; the segmented control lands a fixed time
  /// after the release whatever the input latency.
  final bool hangFromTouch;

  /// Additional hang time per pixel of travel beyond
  /// [hangReferenceDistance].
  final double hangTimePerPixel;

  /// The travel distance at which [hangTime] applies unchanged.
  final double hangReferenceDistance;

  /// The spring that carries the deformation toward its target.
  ///
  /// The targets are UIKit's flex movement law for a loupe of the lens's
  /// size ([FlexSpec.loupeForSize] of the resting lens, or of the
  /// fully lifted one while it is lifted). Read from UIKit, notes private;
  /// fed UIKit's own filtered motion, the law reproduces the targets UIKit
  /// recorded on an iPhone 16 Pro (`ios27-device/lens`): scale x to
  /// 0.0053 / 0.0003 rms on the segmented control resting / lifted and
  /// 0.0028 / 0.00003 on the tab bar.
  final Spring presentationSpring;

  /// The spring that makes a dragged lens follow the finger.
  final Spring followSpring;

  /// The rubber band past the first and last slots as (limit, stiffness): a
  /// lens dragged past an end slot travels at most limit pixels beyond it, in
  /// the form of kinesis's `RubberBand`. Inside the slots the lens follows the
  /// finger's travel since the touch one to one, in the control's own
  /// coordinates; a flexing control ([chromeFlexes]) scales and shifts the lens
  /// with it on top of that.
  final (double, double) rubberBand;

  /// Seconds between a touch on the selected item and the start of its
  /// lift, counted from the touch's own time stamp.
  ///
  /// The segmented control's 0.047 is the median of 8 device presses on
  /// the selected segment (lift start fitted to the lift progress, 33 -
  /// 80 ms: delivery, then UIKit setting the lift up on the main thread,
  /// the next display frame 21 - 65 ms after the one before). The tab
  /// bar's 0.05 is measured on its device taps on the selected tab.
  final double pressDelay;

  /// The shortest time, in seconds from the touch, a pressed selected
  /// lens stays lifted.
  final double pressHang;

  /// Seconds between the release of a held lens and the start of its
  /// travel to the chosen slot and of its landing, counted from the
  /// release's own time stamp.
  ///
  /// The segmented control's 0.024 minimizes the release travel rms of its
  /// four device drags together (0.130 pt; 0.030 left 0.496): a release
  /// sets nothing up, so the travel follows UIKit's delivery and begin
  /// frame, as the glass button's return does 26 ms after the release.
  final double releaseDelay;

  /// Whether the whole control flexes under a finger: UIKit's dynamic flex
  /// of the control's size ([FlexInteraction], spec
  /// [FlexSpec.forSize]), fed the finger's travel since the touch.
  ///
  /// The control grows by the spec's lift points along its long side, its
  /// short side in proportion; a dragging finger stretches it along the
  /// drag, narrows it across by as much and shifts it after the finger,
  /// four times as far per point the finger travels beyond the control's
  /// edge. The flex follows the finger on the spec's tracking spring and
  /// returns on its scale spring. Read from UIKit, notes private.
  ///
  /// The floating UITabBar flexes so (62 pt tall: 14.14 pt of growth, a
  /// stretch threshold of 8793, springs 0.314/0.625 and 0.36/0.6). On an
  /// iPhone 16 Pro (iOS 27.0.1, `ios27-device/lens/tabbar*`) a still
  /// finger holds the bar 14.06 - 14.14 pt wider (five holds), every still
  /// hold of the six scrubs (16 holds, 30 - 330 pt from the touch and up
  /// to 55 pt past the bar's end, bars of three and five tabs) sits within
  /// 0.04 pt of the law in width and 1e-4 in the scale across, and the
  /// scrubs replay at their stamps to 0.08 - 0.2 pt rms in width (a fixed
  /// growth of 14.6 left 0.49 - 2.06). The lens shows the bar's shift, so
  /// it follows the finger one to one.
  final bool chromeFlexes;

  /// Seconds between a touch and the start of the control's flex
  /// ([chromeFlexes]), counted from the touch's own time stamp.
  ///
  /// The tab bar's 0.0465 is the median of 34 device touches (iPhone 16
  /// Pro, `ios27-device/lens/tabbar{2,3,4,5}-taps` and `-tap-selected`: 29
  /// taps and 5 holds, the flex's steps on its tracking spring to and on
  /// its scale spring from the growth fitted to the bar's swell, 41.5 -
  /// 56.75 ms): the bar swells on the frame its lens starts (each touch 1.5
  /// ms before to 4 ms after its lens's lift start), after UIKit's delivery
  /// and its main-thread setup of the lift ([startDelay]).
  final double chromeLag;

  /// Seconds between the release of a touch and the return of the
  /// control's flex, counted from the release's own time stamp, when the
  /// release does not land a held lens ([chromeLandingLag]); the flex
  /// never returns before it starts.
  ///
  /// The tab bar's 0.0185 is the median of the 29 taps (12.75 - 32.75 ms):
  /// a release that leaves the lens to its hang sets nothing up, so the
  /// bar follows UIKit's delivery and begin frame, as the segmented
  /// control's travel does ([releaseDelay]). A touch shorter than the two
  /// lags apart does not swell the bar (unmeasured).
  final double chromeReleaseLag;

  /// Seconds between a release that lands a held lens and the return of
  /// the control's flex, counted from the release's own time stamp.
  ///
  /// The tab bar's 0.035 is the median of 11 device releases of a lens
  /// held 0.3 - 5 s (iPhone 16 Pro, `ios27-device/lens/tabbar*`: five
  /// holds and six scrubs, 25.25 - 41.5 ms, the return on the flex's scale
  /// spring fitted to the bar's swell): such a release sets the lens's
  /// landing up on the main thread (the display link's next frame comes
  /// 19 - 33 ms after the one before instead of 8.3), and the bar returns
  /// on the frame the lens starts landing (one of the 11 a frame later),
  /// as it swells on the frame the lens lifts ([chromeLag]). A release
  /// during a tap's hang ([hangTime], [pressHang]) sets nothing up
  /// ([chromeReleaseLag]).
  final double chromeLandingLag;

  /// The spring that carries the lens between slots, and after a dragging
  /// finger, for Reduce Motion; null when the selection does not travel
  /// then.
  ///
  /// UITabBar keeps moving its selection under Reduce Motion on dampingRatio
  /// 0.9, response 0.2 for taps and scrubs alike (its own springs are 0.85
  /// over 0.4 for a tap, which [travelSpring] fits, and 0.85 over 0.2 while
  /// scrubbing). UISegmentedControl disables its sliding selection: each
  /// segment shows its own, so the selection appears on the new segment
  /// and a press on the selected one neither lifts nor drags it. Read
  /// from UIKit, notes private; whether the segment's selection fades in
  /// is not recorded yet (it appears at once here).
  final Spring? reducedMotionTravelSpring;

  /// The lens of a UISegmentedControl.
  static const segmented = LensTuning(
    selectsOnPointerDown: false,
    liftWidth: 24,
    liftHeight: 16,
    hangTime: 0.25,
    hangTimePerPixel: 0,
    hangFromTouch: true,
    presentationSpring: Spring.response(0.442, dampingRatio: 0.582),
    followSpring: Spring.response(0.225),
    rubberBand: (12, 0.55),
    pressDelay: 0.047,
    releaseDelay: 0.024,
    startDelay: 0.04,
  );

  /// The lens of a floating UITabBar.
  static const tabBar = LensTuning(
    selectsOnPointerDown: true,
    liftWidth: 16,
    liftHeight: 16,
    hangTime: 0.215,
    hangTimePerPixel: 0.000274,
    hangFromTouch: false,
    presentationSpring: Spring.response(0.5, dampingRatio: 0.73),
    followSpring: Spring.response(0.271, dampingRatio: 0.803),
    rubberBand: (4.55, 0.95),
    pressDelay: 0.05,
    startDelay: 0.045,
    chromeFlexes: true,
    chromeLag: 0.0465,
    chromeReleaseLag: 0.0185,
    chromeLandingLag: 0.035,
    reducedMotionTravelSpring: Spring.response(0.2, dampingRatio: 0.9),
  );
}
