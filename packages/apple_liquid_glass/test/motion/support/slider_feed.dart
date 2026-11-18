import 'package:apple_liquid_glass/src/motions/slider_motion.dart';

import 'trace.dart';

/// How long after its stamp a touch of a device recording reaches the
/// slider: every valueChanged of the device recordings reflects a touch
/// 12 - 17 ms old and none 5 - 10 ms old (the probe stamps synthesized
/// touches before UIKit delivers them).
const double deviceDeliveryLag = 0.0125;

/// The touches at which a recorded pan began after waiting (true) and the
/// moves it held before (false).
///
/// A pan that begins at once counts the travel past
/// [SliderMotion.panSlop]; one whose start waited on another gesture
/// (something outside the slider held it in a few recordings) counts from
/// the touch where it began. A drag's first valueChanged tells which: the
/// travel it counts from, against one of the last touches delivered, is
/// the slop or the position of that touch.
Map<TraceTouch, bool> waitedBegins(
  Trace trace,
  double width,
  double value,
  double lag,
) {
  final waits = <TraceTouch, bool>{};
  final touches = trace.touches;
  for (var i = 0; i < touches.length; i++) {
    final down = touches[i];
    if (down.phase != 0) continue;
    var end = i + 1;
    while (end < touches.length && touches[end].phase != 3) {
      end++;
    }
    final up = end < touches.length ? touches[end].t : double.infinity;
    var v0 = value;
    for (final st in trace.states) {
      final t = (st['t']! as num).toDouble();
      final v = st['v'] as num?;
      if (t < down.t && v != null) v0 = v.toDouble();
    }
    final first = trace.events.where((e) {
      final t = (e['t']! as num).toDouble();
      final v = (e['v']! as num).toDouble();
      return e['e'] == 'valueChanged' && t > down.t && t < up && v > 0 && v < 1;
    }).firstOrNull;
    if (first == null) continue;
    final t = (first['t']! as num).toDouble();
    final v = (first['v']! as num).toDouble();
    final seen = [
      for (var j = i + 1; j < end; j++)
        if (touches[j].t + lag <= t) touches[j],
    ];
    for (final last in seen.reversed.take(3)) {
      final from = last.x - down.x - (v - v0) * width;
      if ((from.abs() - SliderMotion.panSlop).abs() < 0.05) break;
      final begin = seen
          .where((touch) => (touch.x - down.x - from).abs() < 0.05)
          .firstOrNull;
      if (begin == null) continue;
      for (final touch in seen.takeWhile((touch) => touch != begin)) {
        waits[touch] = false;
      }
      waits[begin] = true;
      break;
    }
  }
  return waits;
}

/// Feeds a recorded touch into [m], the track's left end at [left]; a
/// pan that waited ([waits]) skips the moves it held and begins where it
/// began.
void Function(TraceTouch) feedSlider(
  SliderMotion m,
  double left, [
  Map<TraceTouch, bool> waits = const {},
]) {
  return (TraceTouch touch) {
    final x = touch.x - left;
    switch (touch.phase) {
      case 0:
        m.pointerDown(touch.t, x);
      case 3:
        m.pointerUp(touch.t, x);
      case _:
        final wait = waits[touch];
        if (wait == false) return;
        m.pointerMove(touch.t, x, begin: wait ?? false);
    }
  };
}
