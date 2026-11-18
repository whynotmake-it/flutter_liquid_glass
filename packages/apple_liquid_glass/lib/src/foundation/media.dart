import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// What a glass overlay reads of the screen's insets.
extension GlassMediaQueryData on MediaQueryData {
  /// The bottom inset an overlay keeps clear: the larger of the safe area's
  /// and the keyboard's.
  double get bottomAboveKeyboard => math.max(padding.bottom, viewInsets.bottom);

  /// The safe area with its bottom grown to [bottomAboveKeyboard].
  EdgeInsets get paddingAboveKeyboard =>
      padding.copyWith(bottom: bottomAboveKeyboard);
}
