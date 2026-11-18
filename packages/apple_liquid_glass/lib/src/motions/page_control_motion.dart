import 'dart:ui';

import 'package:apple_liquid_glass/src/motions/ui_frame_rate.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// The measured geometry and motion of iOS 27's UIPageControl.
@internal
abstract final class PageControlTuning {
  /// The box of one page's indicator.
  static const double indicatorSize = 9.67;

  /// The diameter of a drawn dot.
  static const double dotSize = 7.67;

  /// The gap between two indicators.
  static const double spacing = 8;

  /// The width of the current indicator while it shows a progress.
  static const double progressIndicatorWidth = 27.33;

  /// The padding between the dots and the platter's ends.
  static const double padding = 14;

  /// The height of the control and its platter.
  static const double height = 25.67;

  /// The spring an indicator's width changes on when the current page of
  /// a control showing progress changes (fitted to the simulator's
  /// frames, 0.08 point rms).
  static const widthSpring = Spring.response(0.398, dampingRatio: 0.927);

  /// The spring the finished progress fades out on (0.002 rms).
  static const fadeSpring = Spring.response(0.381, dampingRatio: 0.963);

  /// Seconds a touch rests on the control before its platter shows (and
  /// the dots take the platter's colors) under
  /// `GlassPageControlBackground.automatic`: 0.19 - 0.2 s on an iPhone 16
  /// Pro at 120 Hz (the 60 Hz simulator read 0.2).
  static const double platterDelay = 0.193;

  /// The spring the platter fades in on (critically damped 0.100 s on the
  /// device, 0.001 rms; 0.106 / 0.973 on the simulator's coarser frames).
  static const platterInSpring = Spring.response(0.100);

  /// The spring the platter fades out on (0.001 rms).
  static const platterOutSpring = Spring.response(0.100);

  /// Seconds between the lift of the touch and the platter's fade out
  /// (0.03 - 0.035 s on the device; 0.02 on the simulator).
  static const double platterOutDelay = 0.032;

  /// How far a touch travels before it scrubs instead of tapping.
  static const double scrubSlop = 10;

  /// How far past the midpoint between two dots a scrubbing finger goes
  /// before the page changes, either way (1 - 2 points measured, a frame
  /// of latency included).
  static const double scrubHysteresis = 1.5;

  /// The distance between two dot centers.
  static const double pitch = indicatorSize + spacing;
}

/// The motion of an iOS 27 page control's indicators.
///
/// Without a progress every dot is [PageControlTuning.indicatorSize] wide and a
/// page change is instant, as UIKit's is. With a progress the current indicator
/// is a capsule [PageControlTuning.progressIndicatorWidth] wide whose fill
/// shows the progress; when the page changes, the old capsule shrinks to a dot
/// and the new one grows on [PageControlTuning.widthSpring] while the old fill
/// fades out on [PageControlTuning.fadeSpring]. Times are seconds.
///
/// The platter and the old fill rest within [MotionRest.opacity] and the
/// widths within [MotionRest.length]: invisible, NEAR. A resting finger
/// holds nothing: its moves and lift arrive as stamped commands. Each pick
/// goes to [onEvent] as the command that makes it runs.
final class PageControlMotion extends Motion {
  /// Creates a motion of [count] pages showing [page].
  PageControlMotion({
    required int count,
    required int page,
    this.showsProgress = false,
    this.onEvent,
  }) : _page = count > 0 ? page.clamp(0, count - 1) : 0 {
    _widths = [
      for (var i = 0; i < count; i++)
        own(
          MotionValue<double>(
            _restWidth(i == _page, showsProgress),
            spring: PageControlTuning.widthSpring,
          ),
          rest: _length,
        ),
    ];
  }

  @override
  double get minFrameRate => uikitMinFrameRate;

  static double _restWidth(bool current, bool progress) => current && progress
      ? PageControlTuning.progressIndicatorWidth
      : PageControlTuning.indicatorSize;

  static double _length() => MotionRest.length;
  static double _opacity() => MotionRest.opacity;

  /// Whether the current indicator shows a progress.
  bool showsProgress;

  /// Hears each page a touch picks.
  final void Function(PageControlEvent event)? onEvent;

  int _page;
  late final List<MotionValue<double>> _widths;
  late final _platter = own(
    MotionValue<double>(0, spring: PageControlTuning.platterInSpring),
    rest: _opacity,
  );
  late final _fade = own(
    MotionValue<double>(0, spring: PageControlTuning.fadeSpring),
    rest: _opacity,
  );
  int _fading = -1;
  double? _downX;
  bool _scrubbing = false;
  bool _stepped = false;
  static const _platterSlot = #platter;

  /// The opacity of the platter under a touch, 0 to 1.
  double get platter => _platter.valueAt(now).clamp(0.0, 1.0);

  /// The number of pages.
  int get count => _widths.length;

  /// The current page.
  int get page => _page;

  /// A finger touched the control at [x], measured from the start of the
  /// dots.
  void pointerDown(double t, double x) {
    advance(t);
    if (count == 0) return;
    _downX = x;
    _scrubbing = false;
    _stepped = false;
    at(
      t + PageControlTuning.platterDelay,
      (s) => _platter.retarget(s, 1, spring: PageControlTuning.platterInSpring),
      slot: _platterSlot,
    );
  }

  /// The finger moved to [x].
  void pointerMove(double t, double x) {
    advance(t);
    final from = _downX;
    if (from == null || count == 0) return;
    if (!_scrubbing && (x - from).abs() <= PageControlTuning.scrubSlop) {
      return;
    }
    _scrubbing = true;
    const pitch = PageControlTuning.pitch;
    const h = PageControlTuning.scrubHysteresis;
    final ahead = x - center(_page);
    var next = _page;
    if (ahead > pitch / 2 + h) {
      next = _page + ((ahead - pitch / 2 - h) / pitch).floor() + 1;
    } else if (ahead < -pitch / 2 - h) {
      next = _page - ((-ahead - pitch / 2 - h) / pitch).floor() - 1;
    }
    next = next.clamp(0, count - 1);
    if (next != _page) {
      _stepped = true;
      setPage(t, next);
      onEvent?.call(PageControlPicked(next, scrubbed: true));
    }
  }

  /// The finger lifted at [x]; a tap on the trailing half of a control
  /// [width] wide (dots and padding) steps forward, on the leading half
  /// back, unless the touch scrubbed.
  void pointerUp(double t, double x, {required double width}) {
    advance(t);
    final from = _downX;
    _downX = null;
    _hidePlatter(t);
    if (count == 0 || from == null || _scrubbing || _stepped) {
      _scrubbing = false;
      return;
    }
    final mid = width / 2 - PageControlTuning.padding;
    final next = (_page + (x > mid ? 1 : -1)).clamp(0, count - 1);
    if (next != _page) {
      setPage(t, next);
      onEvent?.call(PageControlPicked(next, scrubbed: false));
    }
  }

  /// The touch was cancelled.
  void pointerCancel(double t) {
    advance(t);
    _downX = null;
    _scrubbing = false;
    _hidePlatter(t);
  }

  void _hidePlatter(double t) {
    at(
      t + PageControlTuning.platterOutDelay,
      (s) =>
          _platter.retarget(s, 0, spring: PageControlTuning.platterOutSpring),
      slot: _platterSlot,
    );
  }

  /// Shows [page] from time [t]; animated only while showing progress.
  void setPage(double t, int page) {
    advance(t);
    if (count == 0) return;
    final next = page.clamp(0, count - 1);
    if (next == _page) return;
    final previous = _page;
    _page = next;
    if (!showsProgress) {
      for (var i = 0; i < count; i++) {
        _widths[i].snap(t, PageControlTuning.indicatorSize);
      }
      return;
    }
    _widths[previous].retarget(t, PageControlTuning.indicatorSize);
    _widths[next].retarget(t, PageControlTuning.progressIndicatorWidth);
    _fade.snap(t, 1);
    _fade.retarget(t, 0);
    _fading = previous;
  }

  /// The width of indicator [index].
  double width(int index) =>
      index >= 0 && index < count ? _widths[index].valueAt(now) : 0;

  /// The opacity of the fill of indicator [index]: 1 on the current page,
  /// fading on the page just left, 0 elsewhere.
  double fillOpacity(int index) {
    if (index == _page) return 1;
    if (index == _fading) return _fade.valueAt(now).clamp(0.0, 1.0);
    return 0;
  }

  /// The width of all indicators and the gaps between them.
  double get contentWidth {
    if (count == 0) return 0;
    var w = PageControlTuning.spacing * (count - 1);
    for (var i = 0; i < count; i++) {
      w += width(i);
    }
    return w;
  }

  /// The size of the control: the dots between the platter's paddings,
  /// [PageControlTuning.height] tall.
  Size get size => Size(
    contentWidth + 2 * PageControlTuning.padding,
    PageControlTuning.height,
  );

  /// Each page's indicator box in the control's box, a dot tall and as
  /// wide as the indicator less the dot's inset, vertically centered;
  /// mirrored when [rtl].
  List<Rect> indicatorRects({required bool rtl}) {
    const dot = PageControlTuning.dotSize;
    const inset = (PageControlTuning.indicatorSize - dot) / 2;
    final box = size;
    var x = 0.0;
    final rects = <Rect>[];
    for (var i = 0; i < count; i++) {
      final w = width(i);
      var cx = PageControlTuning.padding + x + w / 2;
      x += w + PageControlTuning.spacing;
      if (rtl) cx = box.width - cx;
      rects.add(
        Rect.fromCenter(
          center: Offset(cx, box.height / 2),
          width: w - 2 * inset,
          height: dot,
        ),
      );
    }
    return rects;
  }

  /// The position along the dots, from their start, of a touch at [x] in
  /// the control's box; [rtl] counts from the right edge.
  double contentX(double x, {required bool rtl}) =>
      (rtl ? size.width - x : x) - PageControlTuning.padding;

  /// The center of indicator [index] from the start of the dots.
  double center(int index) {
    if (index < 0 || index >= count) return 0;
    var x = 0.0;
    for (var i = 0; i < index; i++) {
      x += width(i) + PageControlTuning.spacing;
    }
    return x + width(index) / 2;
  }
}

/// What a [PageControlMotion] tells its host.
sealed class PageControlEvent {
  const PageControlEvent();
}

/// A touch picked [page]: a tap on either half, or a scrubbing finger
/// ([scrubbed]) that moved the control to another page.
final class PageControlPicked extends PageControlEvent {
  /// Creates the event.
  const PageControlPicked(this.page, {required this.scrubbed});

  /// The page picked.
  final int page;

  /// Whether a scrubbing finger picked it.
  final bool scrubbed;
}
