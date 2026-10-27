import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// A frame counter that works in any binding.
///
/// [frame] advances once per frame (a persistent frame callback, which runs
/// after the frame's scene is built).
@internal
class GlassFrameClock {
  GlassFrameClock._();

  static int _frame = 0;
  static SchedulerBinding? _installedOn;

  /// Frames drawn since the first read.
  static int get frame {
    _ensureInstalled();
    return _frame;
  }

  static void _ensureInstalled() {
    final SchedulerBinding binding;
    try {
      binding = SchedulerBinding.instance;
    } on Object {
      return;
    }
    if (identical(binding, _installedOn)) return;
    _installedOn = binding;
    binding.addPersistentFrameCallback((_) => _frame++);
  }
}
