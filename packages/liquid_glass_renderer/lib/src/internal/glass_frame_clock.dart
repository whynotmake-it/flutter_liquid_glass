import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// A frame counter that works in any binding.
///
/// [frame] advances once per frame (a persistent frame callback, which runs
/// after the frame's scene is built). [epoch] advances with it and also when a
/// scene has been built since the last look, so two scenes built in one frame
/// never share what was derived from the layer tree.
@internal
class GlassFrameClock {
  GlassFrameClock._();

  static int _frame = 0;
  static int _epoch = 0;
  static SchedulerBinding? _installedOn;

  /// Frames drawn since the first read.
  static int get frame {
    _ensureInstalled();
    return _frame;
  }

  /// Changes whenever a layer tree may have changed since it was last read.
  static int get epoch {
    _ensureInstalled();
    return _epoch;
  }

  /// A scene was built: whatever was derived from the layer tree is stale.
  static void sceneBuilt() => _epoch++;

  static void _ensureInstalled() {
    final SchedulerBinding binding;
    try {
      binding = SchedulerBinding.instance;
    } on Object {
      return;
    }
    if (identical(binding, _installedOn)) return;
    _installedOn = binding;
    binding.addPersistentFrameCallback((_) {
      _frame++;
      _epoch++;
    });
  }
}
