import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/selection.dart';
import 'package:kinesis/src/motion/value.dart';

/// Listening to any [Listenable] as a render object does.
extension RenderListening on Listenable {
  /// Listens as a render object does: a motion value or a derived value
  /// (`MotionValue`, `MotionSelection`) is heard also in the frame's resolve
  /// phase, after layout and before paint, so what draws it shows this
  /// frame's presentation; any other listenable as usual.
  ///
  /// For a render object that paints from a listenable it is given, such as
  /// a layer that follows a motion: the listener may mark paint, composited
  /// layers and layout. When it runs after layout, what it marks for layout
  /// is laid out again in the same frame. Stop it with
  /// [removeRenderListener].
  void addRenderListener(VoidCallback listener) => switch (this) {
    final MotionValue<Object?> value => value.addRenderListener(listener),
    final MotionSelection<Object?> value => value.addRenderListener(listener),
    _ => addListener(listener),
  };

  /// Stops a listener added with [addRenderListener].
  void removeRenderListener(VoidCallback listener) => switch (this) {
    final MotionValue<Object?> value => value.removeRenderListener(listener),
    final MotionSelection<Object?> value => value.removeRenderListener(
      listener,
    ),
    _ => removeListener(listener),
  };
}
