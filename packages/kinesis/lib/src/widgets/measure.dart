import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/widgets/resolve.dart';
import 'package:kinesis/src/widgets/scope.dart';

/// Tells [onSize] the size layout gave [child], in the frame that laid it
/// out, before paint: a motion that sizes itself from its content, such as
/// a menu card from its rows or a sheet from its fitted content, commands
/// from it in that frame and draws the new size at once.
///
/// [onSize] hears the frame's time, on the clock of the motions around it
/// (`MotionClockScope`), and the new size after the first layout and after
/// each layout that changes the size. It runs in the frame's resolve phase:
/// it may command motions and mark layout, which is laid out again in that
/// frame, and must not rebuild.
class MotionMeasure extends SingleChildRenderObjectWidget {
  /// Reports the size of [child] to [onSize].
  const MotionMeasure({required this.onSize, super.child, super.key});

  /// Hears the frame's time and the size of [child].
  final void Function(double t, Size size) onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasure(onSize, MotionClockScope.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderMeasure).onSize = onSize;
  }
}

class _RenderMeasure extends RenderProxyBox with MotionResolveHost {
  _RenderMeasure(this.onSize, this._clock);

  void Function(double t, Size size) onSize;
  final MotionClock _clock;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (size != _reported) scheduleResolve();
  }

  @override
  void resolve() {
    if (size == _reported) return;
    _reported = size;
    onSize(_clock.now, size);
  }
}
