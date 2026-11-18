import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Where a press counts: the area a region takes a finger in, and how far
/// beyond its body the finger may stray and still count as inside.
///
/// UIKit: a control's hit area and `UIControl`'s touch-inside test.
@immutable
final class PressReach {
  /// Creates a reach that takes a finger in the body grown to at least
  /// [minimumHit] and holds it within [slop] of the body.
  const PressReach({this.minimumHit, this.slop = 0});

  /// The body alone: it takes and holds a finger only inside itself.
  static const PressReach box = PressReach();

  /// The smallest area that takes a finger, centred on the body, or null
  /// for the body.
  final Size? minimumHit;

  /// How far outside the body, in logical pixels, a finger still counts as
  /// inside.
  final double slop;

  /// The area a press on [body] starts in: [body] grown about its centre to
  /// at least [minimumHit].
  Rect takes(Rect body) {
    final minimum = minimumHit;
    if (minimum == null) return body;
    return Rect.fromCenter(
      center: body.center,
      width: math.max(body.width, minimum.width),
      height: math.max(body.height, minimum.height),
    );
  }

  /// Whether a finger at [position] counts as inside [body]: in the area
  /// [takes] gives, or within [slop] of [body]. Edges count as
  /// `CGRectContainsPoint` counts them: the right and bottom ones are out.
  bool holds(Rect body, Offset position) =>
      takes(body).contains(position) || body.inflate(slop).contains(position);

  @override
  bool operator ==(Object other) =>
      other is PressReach &&
      other.minimumHit == minimumHit &&
      other.slop == slop;

  @override
  int get hashCode => Object.hash(minimumHit, slop);
}
