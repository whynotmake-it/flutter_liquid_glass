import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/widgets/input_target.dart';
import 'package:kinesis/src/widgets/pointer_line.dart';
import 'package:kinesis/src/widgets/scope.dart';

/// Takes the touches that land where no input host of a control lies yet,
/// anywhere on the screen, while it is [armed].
///
/// Flutter: a global route on the `PointerRouter`. A menu takes a touch
/// made between the tap that opens it and its opening this way.
///
/// While armed it takes every new touch of the primary button, one at a
/// time, and runs it through its interactions exactly as an `InputRegion`
/// runs a touch that landed in it: every event stamped on the clock of the
/// nearest [MotionClockScope] at its own time stamp, the timed reactions on
/// that clock, and the haptic its `feedback` picks for each event the
/// interactions raise. Positions are global, and the touch's region is the
/// whole view. The capture stays out of the gesture arena: what lies under
/// the finger hears the touch as well, and a claim takes nothing from it.
///
/// ```dart
/// late final _capture = InputCapture(
///   context: context,
///   interactions: [_earlyTouch],
/// );
/// ```
///
/// The owner arms it for as long as such touches are its own and disposes
/// it with itself.
final class InputCapture {
  /// Creates a disarmed capture that runs touches through [interactions],
  /// plays haptics and reads its clock at [context].
  InputCapture({
    required BuildContext context,
    required List<Interaction> interactions,
    this._feedback,
  }) : _context = context,
       _clock = MotionClockScope.of(context) {
    _target = _CaptureTarget(this, interactions);
    _line = _CaptureLine(_target);
  }

  final BuildContext _context;
  final MotionHaptic? Function(InteractionEvent event)? _feedback;
  MotionClock _clock;
  late final _CaptureTarget _target;
  late final _CaptureLine _line;
  bool _armed = false;
  bool _routed = false;

  /// Whether the capture takes new touches.
  bool get armed => _armed;

  /// Starts taking new touches; arming an armed capture does nothing.
  void arm() {
    if (_armed) return;
    _armed = true;
    // A touch it still follows keeps the clock it started on.
    if (!_line.touched && _context.mounted) {
      _clock = MotionClockScope.of(_context);
    }
    _route();
  }

  /// Stops taking new touches; one it follows runs to its up or cancel.
  void disarm() {
    _armed = false;
    if (!_line.touched) _unroute();
  }

  /// Ends the touch it follows, which its interactions hear cancelled, and
  /// lets go of the screen's touches.
  void dispose() {
    _armed = false;
    _target.dispose();
    _line.dispose();
    _unroute();
  }

  void _route() {
    if (_routed) return;
    _routed = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_heard);
  }

  void _unroute() {
    if (!_routed) return;
    _routed = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_heard);
  }

  void _heard(PointerEvent event) {
    if (!_context.mounted) return;
    switch (event) {
      case PointerDownEvent(:final buttons):
        if (!_armed || _line.touched || buttons != kPrimaryButton) return;
      case PointerMoveEvent() || PointerUpEvent() || PointerCancelEvent():
        if (!_line.follows(event.pointer)) return;
      default:
        return;
    }
    final view = View.of(_context);
    _line.captured(event, view.physicalSize / view.devicePixelRatio);
    if (!_armed && !_line.touched) _unroute();
  }
}

final class _CaptureTarget extends InputTarget {
  _CaptureTarget(this.capture, super.interactions);

  final InputCapture capture;

  @override
  BuildContext get context => capture._context;

  @override
  bool get mounted => capture._context.mounted;

  @override
  MotionClock get clock => capture._clock;

  @override
  PointerLine<InputTarget> get line => capture._line;

  @override
  bool get enabled => true;

  // A capture has no states of its own: its owner shows what its touch does.
  @override
  void publish() {}

  @override
  MotionHaptic? feedback(InteractionEvent event) =>
      capture._feedback?.call(event);
}

final class _CaptureLine extends PointerLine<InputTarget> {
  _CaptureLine(this.base);

  @override
  final InputTarget base;

  @override
  RenderBox? get box => null;
}
