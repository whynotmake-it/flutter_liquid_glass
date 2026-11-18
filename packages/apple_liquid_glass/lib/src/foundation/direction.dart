import 'package:flutter/widgets.dart';

/// What a glass widget reads of the reading direction around it.
extension GlassDirection on BuildContext {
  /// Whether the text direction around this context runs right to left.
  bool get isRightToLeft => Directionality.of(this) == TextDirection.rtl;
}
