import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter_test/flutter_test.dart';

/// The widgets of [type] that show: no hidden [MotionVisibility] lies above
/// them. A lens's lifted glass stays built at rest and shows only while the
/// lens is lifted.
Finder findShown(Type type) => find.byElementPredicate((element) {
  if (element.widget.runtimeType != type) return false;
  var shown = true;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is MotionVisibility && !widget.visible.value) shown = false;
    return shown;
  });
  return shown;
}, description: 'shown $type');
