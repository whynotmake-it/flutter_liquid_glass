import 'dart:ui';

import 'package:apple_liquid_glass/src/motions/glass_press.dart';

import 'onset.dart';
import 'trace.dart';

/// One touch fed to a glass button replay: its stamp, its UITouch phase
/// (0 down, 3 up, others moves) and where it is in the button.
typedef GlassTouch = ({double t, int phase, Offset at});

/// The lift of a button of [size] pressed at its center at time 0 and
/// released at [up], [dt] seconds after the touch.
double _scale(Size size, double dt, {double? up}) {
  final center = size.center(Offset.zero);
  final m = GlassPress(size: size);
  m.pointerDown(0, center);
  if (up != null) {
    m.advance(up);
    m.pointerUp(up, center);
  }
  m.advance(dt);
  return m.scale;
}

/// Seconds from the touch-down at [down] to the time the model's
/// touch-down must be stamped for its lift to meet the first frame of
/// [rows] that lifted: zero when the device lifts as the model fed the
/// stamp does.
double glassPressLag(List<TraceFrame> rows, Size size, double down) {
  final first = rows.firstWhere((f) => f.t > down && f.sx > 1.0005);
  return first.t - timeToReach((dt) => _scale(size, dt), first.sx) - down;
}

/// Seconds from the release at [up] to the time the model's release must
/// be stamped for its return to meet the first frame of [rows] that
/// dropped from the plateau.
double glassReleaseLag(List<TraceFrame> rows, Size size, double up) {
  final plateau = rows.lastWhere((f) => f.t < up - 0.005).sx;
  final drop = rows.firstWhere(
    (f) => f.t > up - 0.03 && f.sx < plateau - 0.002,
  );
  const held = 1.0;
  final dt = timeToReach((dt) => _scale(size, held + dt, up: held), drop.sx);
  return drop.t - dt - up;
}

/// The lift, model minus recording, of both scales at every frame of
/// [rows] from the first that lifted until [until], with the model of a
/// button of [size] fed [touches].
///
/// A frame at which the recording rests on its target is left out: UIKit
/// snaps a spring that has nearly settled, morph only once what remains
/// is invisible (`MotionRest`, NEAR).
List<({double t, bool pressed, double error})> glassErrors(
  List<TraceFrame> rows,
  Size size,
  List<GlassTouch> touches,
  double until,
) {
  final m = GlassPress(size: size);
  m.advance(touches.first.t - 1);
  final from = rows.firstWhere((f) => f.t > touches.first.t && f.sx > 1.0005);
  final errors = <({double t, bool pressed, double error})>[];
  var next = 0;
  for (final f in rows) {
    if (f.t < from.t || f.t > until) continue;
    while (next < touches.length && touches[next].t <= f.t) {
      final touch = touches[next++];
      switch (touch.phase) {
        case 0:
          m.pointerDown(touch.t, touch.at);
        case 3:
          m.pointerUp(touch.t, touch.at);
        case _:
          m.pointerMove(touch.t, touch.at);
      }
    }
    m.advance(f.t);
    final pressed = m.isPressed;
    final target = pressed ? m.liftedScale : 1.0;
    if ((f.sx - target).abs() < 5e-5 && (f.sy - target).abs() < 5e-5) {
      continue;
    }
    errors.add((t: f.t, pressed: pressed, error: m.scaleX - f.sx));
    errors.add((t: f.t, pressed: pressed, error: m.scaleY - f.sy));
  }
  return errors;
}
