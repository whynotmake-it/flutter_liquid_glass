import 'dart:ui' show Rect;

/// [rect] reflected about the middle of a [width] wide box: where a
/// left-to-right layout's rect lies in a right-to-left one.
Rect mirroredIn(Rect rect, double width) =>
    Rect.fromLTRB(width - rect.right, rect.top, width - rect.left, rect.bottom);
