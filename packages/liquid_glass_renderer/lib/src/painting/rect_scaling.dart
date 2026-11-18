import 'dart:ui';

/// A rect in logical pixels taken to another grid.
///
/// The libraries of this package use it; the umbrella library hides it, so an
/// app that imports the renderer gets no new member on [Rect].
extension RectScaling on Rect {
  /// This rect with every edge multiplied by [factor], for a logical rect in
  /// device pixels.
  Rect scaled(double factor) => Rect.fromLTRB(
    left * factor,
    top * factor,
    right * factor,
    bottom * factor,
  );
}
