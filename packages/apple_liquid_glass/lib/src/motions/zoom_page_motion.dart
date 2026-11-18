import 'dart:math' as math;
import 'dart:ui';

import 'package:apple_liquid_glass/src/motions/navigation_motion.dart';
import 'package:apple_liquid_glass/src/motions/sheet_tuning.dart';
import 'package:flutter/foundation.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// The measured motion of UIKit's zoom transition into a pushed page
/// (`preferredTransition = .zoom` on a view controller pushed onto a
/// navigation controller).
///
/// Read from screen recordings of an iPhone 16 Pro on iOS 27.0.1 (four
/// pushes from a 160 x 100 card, a pop by the back button, drags down,
/// sideways and from the edge). The zooming container's center and width
/// ride one spring and its height another on the way in; a back-button pop
/// returns all of them on UIKit's `zoomOut` spring, a drag's dismissal on
/// [ZoomPageTuning.dismissSpring] and [ZoomPageTuning.dismissHeightSpring].
/// The page's content is drawn
/// at its own size scaled by the container's width, from the container's
/// top; the source's look crossfades into it; the page underneath dims
/// and the container casts a shadow on it.
@internal
@immutable
class ZoomPageTuning {
  /// Creates a tuning from explicit values.
  const ZoomPageTuning({
    this.openSpring = const Spring.response(0.317),
    this.openHeightSpring = const Spring.response(0.406, dampingRatio: 0.925),
    this.closeSpring = _zoomOutSpring,
    this.dismissSpring = const Spring.response(0.45, dampingRatio: 0.81),
    this.dismissHeightSpring = const Spring.response(0.33, dampingRatio: 0.98),
    this.returnSpring = const Spring.response(0.278, dampingRatio: 0.927),
    this.openFadeSpring = const Spring.response(0.156),
    this.openFadeDelay = 0.01,
    this.closeFadeSpring = const Spring.response(0.191),
    this.openDimmingSpring = _zoomInSpring,
    this.closeDimmingSpring = _zoomOutSpring,
    this.dimmingOpacity = 0.15,
    this.shadowOpacity = 0.36,
    this.shadowSigma = 30,
    this.shadowOffset = 4,
    this.dragSlop = 13.5,
    this.dragAngle = math.pi / 6,
    this.downWidthRate = 0.00078,
    this.downHeightRate = 0.00154,
    this.downGain = 0.61,
    this.sidewaysWidthRate = 0.00156,
    this.sidewaysHeightRate = 0.00168,
    this.sidewaysGain = 0.95,
    this.dismissDistance = 132.5,
    this.dismissVelocity = 1050,
  });

  /// The spring the container's center and width travel on toward the
  /// page (fitted to four device pushes with [openHeightSpring]: 0.98
  /// points rms over the container's edges).
  final Spring openSpring;

  /// The spring the container's height grows on toward the page.
  final Spring openHeightSpring;

  /// The spring the whole container travels on back into the source when
  /// the page is popped without a finger: UIKit's
  /// `_UIZoomTransitionSpec.zoomOut` (a pop by the back button fits it to
  /// 0.54 points rms).
  final Spring closeSpring;

  /// The spring the container's center and width travel on back into the
  /// source after a drag dismissed the page (two device drags: center
  /// 0.47 / 0.82, width 0.43 / 0.80).
  final Spring dismissSpring;

  /// The spring the container's height shrinks on after a drag dismissed
  /// the page (two device drags: 0.33 / 0.98).
  final Spring dismissHeightSpring;

  /// The spring a page released short of a dismissal returns to full
  /// screen on (device fit 0.40 points rms).
  final Spring returnSpring;

  /// The spring the source's look crossfades into the page's content on
  /// (device fit 0.156 s, critically damped, after [openFadeDelay]).
  final Spring openFadeSpring;

  /// Seconds the crossfade waits after the container starts to grow.
  final double openFadeDelay;

  /// The spring the page's content crossfades back into the source's look
  /// on (device fit 0.191 s, critically damped).
  final Spring closeFadeSpring;

  /// The spring the dimming rises on: UIKit's `zoomIn` spring.
  final Spring openDimmingSpring;

  /// The spring the dimming falls on: UIKit's `zoomOut` spring.
  final Spring closeDimmingSpring;

  /// The opacity of the black dimming over the page underneath (a 50
  /// percent grey reads 128 -> 109 on the device, whatever the drag).
  final double dimmingOpacity;

  /// The opacity of the container's black shadow (the grey page darkens
  /// from 109 to 89 at the container's edge).
  final double shadowOpacity;

  /// The Gaussian sigma of the container's shadow in points (the
  /// darkening falls to a third 20 points out and to nothing by 60).
  final double shadowSigma;

  /// How far below the container its shadow sits, in points.
  final double shadowOffset;

  /// The finger travel, in points, the page ignores before it follows
  /// (fitted 12.5 sideways, 14.4 down).
  final double dragSlop;

  /// How far, in radians, a drag may lean off straight down or straight
  /// toward the trailing edge and still move the page: a drag 31 degrees
  /// off down does not, and neither do drags up or toward the leading
  /// edge.
  final double dragAngle;

  /// The share of its width the page loses per point of downward travel
  /// past the slop (four device drags, 2.4 points rms together with the
  /// other `down` values).
  final double downWidthRate;

  /// The share of its height the page loses per point of downward travel
  /// past the slop.
  final double downHeightRate;

  /// The share of downward finger travel the page's center follows (the
  /// page also shrinks about the point under the finger).
  final double downGain;

  /// The share of its width the page loses per point of sideways travel
  /// past the slop (the content shrinks like the height: a label read off
  /// a held drag scales 0.56 at 285 points).
  final double sidewaysWidthRate;

  /// The share of its height the page loses per point of sideways travel
  /// past the slop (4.5 points rms over a drag out and back).
  final double sidewaysHeightRate;

  /// The share of sideways finger travel the page's center follows.
  final double sidewaysGain;

  /// The finger travel past which a released page zooms back into its
  /// source: device drags held still at 70, 110 and 125 points return, at
  /// 140, 150 and 300 they dismiss.
  final double dismissDistance;

  /// The release speed along the drag, in points per second, past which
  /// a page zooms back into its source whatever its travel: a 70 point
  /// flick leaving at about 900 points per second returned, a 100 point
  /// one at about 1200 dismissed.
  final double dismissVelocity;

  /// The measured tuning.
  static const standard = ZoomPageTuning();
}

/// The zoom of a pushed page out of its source and back, in the page's
/// coordinates.
///
/// The container is four quantities in points - its center, width and
/// height - each a spring of its own. [open] puts it on the source and
/// [start] sends it to the page; [leave] sends it back into the source,
/// carrying each one's velocity, so a reversal is continuous. While a
/// finger drags the page ([dragStart], [dragUpdate]) the container is a
/// pure function of the finger's travel ([dragFrame]); [dragEnd] either
/// returns the page or reports a dismissal, after which the shell pops the
/// page and [leave] starts from where the finger left the page, at rest.
///
/// It rests within [MotionRest.length] for the frame and
/// [MotionRest.opacity] for the crossfade and the dimming (NEAR).
final class ZoomPageMotion extends PageMotion with Sourced {
  /// Creates a motion for a page filling [page], in global coordinates.
  ZoomPageMotion({
    @internal this.tuning = ZoomPageTuning.standard,
    Rect page = Rect.zero,
  }) : _origin = page.topLeft,
       _size = page.size;

  /// The measured behavior this motion reproduces.
  @internal
  final ZoomPageTuning tuning;

  /// The radius of the display's corners, which the container's corners
  /// turn into.
  double displayRadius = SheetTuning.fallbackDisplayRadius;

  late final _cx = own(
    MotionValue<double>(0, spring: tuning.openSpring),
    rest: _length,
  );
  late final _cy = own(
    MotionValue<double>(0, spring: tuning.openSpring),
    rest: _length,
  );
  late final _w = own(
    MotionValue<double>(0, spring: tuning.openSpring),
    rest: _length,
  );
  late final _h = own(
    MotionValue<double>(0, spring: tuning.openHeightSpring),
    rest: _length,
  );
  late final _fade = own(
    MotionValue<double>(1, spring: tuning.openFadeSpring),
    rest: _opacity,
  );
  late final _dim = own(
    MotionValue<double>(1, spring: tuning.openDimmingSpring),
    rest: _opacity,
  );
  final Offset _origin;
  Size _size;
  bool _shown = false;
  bool _started = false;
  Rect _source = Rect.zero;
  double _sourceRadius = 0;
  Offset? _dragFrom;
  Offset _dragDelta = Offset.zero;
  bool _dragMoved = false;

  static double _length() => MotionRest.length;
  static double _opacity() => MotionRest.opacity;

  Rect get _page => Offset.zero & _size;

  /// Whether a finger drags the page.
  bool get isDragging => _dragFrom != null;

  /// The source frame the motion zooms out of and back into.
  Rect get source => _source;

  @override
  bool get isShown => _shown;

  /// Whether a finger may take the page now.
  bool get takesDrag => _shown && presence == PresenceStatus.shown;

  @override
  bool get holds => _dragFrom != null || (_shown && !_started);

  @override
  PresenceStatus get presence {
    final settled = isSettled;
    if (_shown) return settled ? PresenceStatus.shown : PresenceStatus.opening;
    return settled ? PresenceStatus.hidden : PresenceStatus.leaving;
  }

  @override
  double get progress => reach;

  @override
  void sourceMoved(double t, SourceGeometry? geometry) {
    if (geometry == null) return;
    advance(t);
    _source = geometry.rect.shift(-_origin);
    _sourceRadius = geometry.radius.topLeft.x;
    if (_dragFrom != null) return;
    if (!_started) {
      _set(t, _source);
    } else if (!_shown) {
      _retarget(t, _source);
    }
  }

  /// The page takes [size] from time [t]: a page shown heads to it.
  void resize(double t, Size size) {
    if (size == _size) return;
    advance(t);
    _size = size;
    if (_dragFrom == null && _shown && _started) _retarget(t, _page);
  }

  /// Puts the container on the source at time [t], to zoom out of it once
  /// [start] runs.
  @override
  void open(double t) {
    advance(t);
    _shown = true;
    _started = false;
    _set(t, _source);
    _fade.snap(t, 0);
    _dim.snap(t, 0);
  }

  /// Zooms out of the source into the page from time [t].
  @override
  void start(double t) {
    advance(t);
    _started = true;
    _zoomTo(t, _page, tuning.openSpring, height: tuning.openHeightSpring);
    _dim.retarget(t, 1, spring: tuning.openDimmingSpring);
    _fade.retarget(
      t,
      1,
      spring: tuning.openFadeSpring,
      delay: tuning.openFadeDelay,
    );
  }

  @override
  void showInPlace(double t) {
    advance(t);
    _started = true;
    _set(t, _page);
    _fade.snap(t, 1);
    _dim.snap(t, 1);
  }

  /// Zooms back into the source from time [t]. After a drag the container
  /// starts from where the finger left the page, at rest (a 100 point
  /// flick on the device leaves without carrying the finger's speed), and
  /// rides [ZoomPageTuning.dismissSpring] and
  /// [ZoomPageTuning.dismissHeightSpring]; otherwise
  /// [ZoomPageTuning.closeSpring].
  @override
  bool leave(double t, DismissTrigger trigger) {
    advance(t);
    final from = _dragFrom;
    if (from != null) {
      _set(t, dragFrame(_page, from, _dragDelta));
      _dragFrom = null;
    }
    _shown = false;
    _started = true;
    if (from == null) {
      _zoomTo(t, _source, tuning.closeSpring);
    } else {
      _zoomTo(
        t,
        _source,
        tuning.dismissSpring,
        height: tuning.dismissHeightSpring,
      );
    }
    _fade.retarget(t, 0, spring: tuning.closeFadeSpring);
    _dim.retarget(t, 0, spring: tuning.closeDimmingSpring);
    return true;
  }

  void _retarget(double t, Rect to) {
    if (_cx.target != to.center.dx) _cx.retarget(t, to.center.dx);
    if (_cy.target != to.center.dy) _cy.retarget(t, to.center.dy);
    if (_w.target != to.width) _w.retarget(t, to.width);
    if (_h.target != to.height) _h.retarget(t, to.height);
  }

  /// A finger touched the page at [position] at time [t].
  void dragStart(double t, Offset position) {
    advance(t);
    _dragFrom = position;
    _dragDelta = Offset.zero;
    _dragMoved = false;
    changed();
  }

  /// The dragging finger is at [position] at time [t].
  void dragUpdate(double t, Offset position) {
    advance(t);
    final from = _dragFrom;
    if (from == null) return;
    _dragDelta = position - from;
    if (_pastSlop(_dragDelta)) _dragMoved = true;
    _set(t, dragFrame(_page, from, _dragDelta));
  }

  /// The finger left the page at time [t] moving at [velocity] points per
  /// second; returns whether the page zooms back into its source (the
  /// shell then pops the page and [leave] runs) or returns to full screen.
  bool dragEnd(double t, Offset velocity) {
    advance(t);
    if (_dragFrom == null) return false;
    final d = _dragDelta.distance;
    final along = d == 0
        ? 0.0
        : (velocity.dx * _dragDelta.dx + velocity.dy * _dragDelta.dy) / d;
    final exit = ProjectionExit(
      threshold: tuning.dismissDistance,
      flickVelocity: tuning.dismissVelocity,
    );
    if (_dragMoved && exit.passes(d, along)) return true;
    stay(t);
    return false;
  }

  /// Returns the page to full screen from time [t]: the finger let go
  /// short of a dismissal, or the dismissal it asked for was refused.
  void stay(double t) {
    advance(t);
    _dragFrom = null;
    _zoomTo(t, _page, tuning.returnSpring);
  }

  void _zoomTo(double t, Rect to, Spring spring, {Spring? height}) {
    _cx.retarget(t, to.center.dx, spring: spring);
    _cy.retarget(t, to.center.dy, spring: spring);
    _w.retarget(t, to.width, spring: spring);
    _h.retarget(t, to.height, spring: height ?? spring);
  }

  bool _pastSlop(Offset delta) => delta.distance > tuning.dragSlop;

  /// Whether the page follows a finger that has travelled [delta] since
  /// the touch: null while the travel is within [ZoomPageTuning.dragSlop],
  /// then whether it heads down or toward the trailing edge ([rtl] mirrors
  /// it) within [ZoomPageTuning.dragAngle].
  bool? allowsDrag(Offset delta, {bool rtl = false}) {
    if (!_pastSlop(delta)) return null;
    final along = rtl ? -delta.dx : delta.dx;
    final limit = math.cos(tuning.dragAngle) * delta.distance;
    return delta.dy >= limit || along >= limit;
  }

  /// The page dragged by a finger that touched it at [from] and has
  /// travelled [delta]: past [ZoomPageTuning.dragSlop] it shrinks
  /// about the point under the finger - its height faster than its width
  /// on a drag down, both alike on a drag sideways - and its center
  /// follows the finger by the gains; between the two directions the
  /// rates blend by the square of the direction's components.
  Rect dragFrame(Rect page, Offset from, Offset delta) {
    final d = delta.distance;
    final e = math.max<double>(0, d - tuning.dragSlop);
    if (e == 0) return page;
    final down = delta.dy * delta.dy / (d * d);
    final side = 1 - down;
    final sw = math.max<double>(
      0,
      1 - (tuning.downWidthRate * down + tuning.sidewaysWidthRate * side) * e,
    );
    final sh = math.max<double>(
      0,
      1 - (tuning.downHeightRate * down + tuning.sidewaysHeightRate * side) * e,
    );
    final cx =
        from.dx +
        tuning.sidewaysGain * delta.dx +
        (page.center.dx - from.dx) * sw;
    final cy =
        from.dy + tuning.downGain * delta.dy + (page.center.dy - from.dy) * sh;
    return Rect.fromCenter(
      center: Offset(cx, cy),
      width: page.width * sw,
      height: page.height * sh,
    );
  }

  void _set(double t, Rect r) {
    _cx.snap(t, r.center.dx);
    _cy.snap(t, r.center.dy);
    _w.snap(t, r.width);
    _h.snap(t, r.height);
  }

  /// The container's frame.
  Rect get rect => Rect.fromCenter(
    center: Offset(_cx.valueAt(now), _cy.valueAt(now)),
    width: math.max(0, _w.valueAt(now)),
    height: math.max(0, _h.valueAt(now)),
  );

  /// How far the container's frame has come from the source toward the
  /// page: the mean of its width's and its height's share, 0
  /// at the source and 1 at the page.
  double get reach {
    final r = rect;
    final page = _page;
    double share(double v, double a, double b) =>
        (b - a).abs() < 1e-6 ? 1 : ((v - a) / (b - a)).clamp(0.0, 1.0);
    return (share(r.width, _source.width, page.width) +
            share(r.height, _source.height, page.height)) /
        2;
  }

  /// The container's corner radius, from the source's to [displayRadius]
  /// by [reach] (device: 0.6 points off along four pushes).
  double get radius => lerpDouble(_sourceRadius, displayRadius, reach)!;

  /// The uniform scale the page's content is drawn at in the container:
  /// the container's width over the page's.
  double get contentScale => _size.width <= 0 ? 1 : rect.width / _size.width;

  /// The uniform scale the source's look is drawn at in the container:
  /// the container's width over the source's.
  double get lookScale => _source.width <= 0 ? 1 : rect.width / _source.width;

  /// The opacity of the page's content; the source's look
  /// shows at one minus it.
  double get fade => _fade.valueAt(now).clamp(0.0, 1.0);

  /// The fraction of the dimming and of the shadow.
  double get dimming => _dim.valueAt(now).clamp(0.0, 1.0);
}

/// UIKit's zoom-in spring (`_UIZoomTransitionSpec`): the dimming rises on
/// it.
const _zoomInSpring = Spring.response(0.34);

/// UIKit's zoom-out spring (`_UIZoomTransitionSpec`).
const _zoomOutSpring = Spring.response(0.34, dampingRatio: 0.92);
