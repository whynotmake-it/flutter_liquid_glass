import 'dart:typed_data';

import 'package:apple_liquid_glass/src/motions/menu_outline_math.dart';
import 'package:meta/meta.dart';

/// The fusion worker where there are no isolates to run it on: it never
/// runs, and every fusion is computed where it is needed.
@internal
abstract final class FusionWorker {
  /// Whether this platform can run the worker.
  static const bool supported = false;

  /// Does nothing.
  static void request(Float64List inputs, {Object? owner}) {}

  /// Always null.
  static OutlineParts? take(Float64List inputs, double tolerance) => null;

  /// Always false.
  @visibleForTesting
  static bool get debugHasReady => false;

  /// Does nothing.
  static void reset({Object? owner}) {}
}
