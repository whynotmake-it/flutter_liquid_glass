import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// The edge of a popover that points at its source.
enum PopoverArrowDirection {
  /// The popover sits above its source; the arrow points down.
  down,

  /// The popover sits below its source; the arrow points up.
  up,

  /// The popover sits to the right of its source; the arrow points left.
  left,

  /// The popover sits to the left of its source; the arrow points right.
  right,
}

/// Where a popover sits relative to its source, as UIKit places an action
/// sheet presented from a source view on iOS 27.
@immutable
class PopoverPlacement {
  /// Creates a placement.
  const PopoverPlacement({
    required this.content,
    required this.arrowDirection,
    required this.arrowCenter,
  });

  /// The popover's content box, without the arrow.
  final Rect content;

  /// The content edge the arrow sits on.
  final PopoverArrowDirection arrowDirection;

  /// The arrow's center along [arrowDirection], in the same coordinates as
  /// [content].
  final double arrowCenter;

  /// The tip of the arrow: the point the popover grows out of and shrinks
  /// back into.
  Offset get anchor => switch (arrowDirection) {
    PopoverArrowDirection.down => Offset(
      arrowCenter,
      content.bottom + PopoverTuning.arrowLength,
    ),
    PopoverArrowDirection.up => Offset(
      arrowCenter,
      content.top - PopoverTuning.arrowLength,
    ),
    PopoverArrowDirection.left => Offset(
      content.left - PopoverTuning.arrowLength,
      arrowCenter,
    ),
    PopoverArrowDirection.right => Offset(
      content.right + PopoverTuning.arrowLength,
      arrowCenter,
    ),
  };

  /// The popover's whole box, arrow included.
  Rect get bounds => content.expandToInclude(
    Rect.fromCenter(center: anchor, width: 0, height: 0),
  );

  @override
  bool operator ==(Object other) =>
      other is PopoverPlacement &&
      other.content == content &&
      other.arrowDirection == arrowDirection &&
      other.arrowCenter == arrowCenter;

  @override
  int get hashCode => Object.hash(content, arrowDirection, arrowCenter);

  @override
  String toString() =>
      'PopoverPlacement($content, ${arrowDirection.name}, $arrowCenter)';
}

/// The measured tuning of an iOS 27 popover (measured on an action sheet
/// presented from a source view).
@internal
abstract final class PopoverTuning {
  /// The spring a popover presents on: a CASpringAnimation of stiffness
  /// 331.9 and damping 29.15 (response 0.345 s, damping ratio 0.80),
  /// scaling the popover and fading it in together.
  static const presentSpring = Spring.response(0.3449, dampingRatio: 0.8);

  /// The spring a popover dismisses on: stiffness 283.97, damping 28.65
  /// (response 0.373 s, damping ratio 0.85).
  static const dismissSpring = Spring.response(0.3729, dampingRatio: 0.85);

  /// The scale a popover grows from and shrinks to, about its arrow tip.
  static const double hiddenScale = 0.01;

  /// The length of the arrow from the content's edge to its tip: UIKit's
  /// popover `arrowHeight` (read from UIKit, notes private).
  static const double arrowLength = 13;

  /// The width of the arrow where its straight sides, extended, meet the
  /// content's edge: UIKit's popover `arrowBase`.
  static const double arrowBase = 26;

  /// How far beyond [arrowBase] on each side the fillet between the
  /// content's edge and the arrow's side starts, so the arrow leaves the
  /// edge over `arrowBase + 2 * arrowFilletReach` (37): read from the path
  /// UIKit draws.
  static const double arrowFilletReach = 5.5;

  /// The least distance from the arrow's center at which a corner next to
  /// the arrow ends: half of [arrowBase] plus 3. A corner that would reach
  /// closer is drawn smaller, as UIKit draws it.
  static const double arrowCornerGap = arrowBase / 2 + 3;

  /// The nearest the arrow's center comes to a corner of the content. A
  /// placement that would push the arrow closer is not taken.
  ///
  /// Fitted to the 15 simulator placements. UIKit pins an arrow whose
  /// center comes within 49 of a side (an offset past 71 from the center
  /// of a 240 wide popover, read from UIKit, notes private) and draws it
  /// into the corner; [placePopover] never asks for that shape.
  static const double arrowCornerClearance = 48;
}

/// The motion of an iOS 27 popover: one progress that scales the popover
/// about its arrow tip from [PopoverTuning.hiddenScale] and fades it
/// in on [PopoverTuning.presentSpring], and shrinks and fades it back
/// on [PopoverTuning.dismissSpring].
///
/// Under Reduce Motion (the motion's [Motion.traits]) the popover keeps its
/// size and only fades, on the same springs. Read from UIKit, notes
/// private: UIKit's popover animation uses the identity transform instead
/// of its shrink under Reduce Motion.
///
/// Android's predictive back runs the dismissal under the finger: the
/// popover shrinks into its arrow and fades with the gesture's progress,
/// a commit finishes on [PopoverTuning.dismissSpring] from the gesture's
/// velocity, and a cancel springs back on [PopoverTuning.presentSpring].
/// Android has no popover of iOS's to measure, so this is the dismissal's
/// own path, not a recording.
class PopoverMotion extends PresentedProgress {
  /// Creates the motion of a popover that is not shown yet.
  PopoverMotion({this.hiddenScale = PopoverTuning.hiddenScale})
    : super(
        openSpring: PopoverTuning.presentSpring,
        closeSpring: PopoverTuning.dismissSpring,
        rest: _rest,
      );

  /// The scale of the hidden popover.
  final double hiddenScale;

  /// The space a popover keeps from the screen's sides, which
  /// [placePopover] keeps and a host leaves out of the width it offers the
  /// content.
  static const double margin = 10;

  /// The progress rests within 1e-3 (NEAR): that lands the far edge of a
  /// 300 pt popover by up to 0.3 pt, looser than [MotionRest.length];
  /// resting at 0.1 pt keeps an action sheet's dismissal 64 ms longer.
  static const double _rest = 1e-3;

  /// The scale of the popover about its arrow tip.
  @override
  double get scale => traits.reduceMotion
      ? 1
      : math.max(0, hiddenScale + (1 - hiddenScale) * progress);
}

/// Places a popover of [size] next to [source] inside [screen], the way
/// UIKit places an iOS 27 popover with any arrow direction.
///
/// Each side of the source is a candidate in the order above, below, then
/// the trailing and the leading side: the popover centers on the source
/// along that side, then slides as little as it must to stay
/// [PopoverMotion.margin] from the screen's sides and inside
/// [padding] (the safe area, keyboard included). Toward the source it may
/// slide by up to the arrow's length, so the arrow tip overlaps the
/// source a little rather than the popover changing sides. A side where
/// that is not enough is skipped, and so is one where the slide would
/// bring the arrow, which stays on the source's center, within
/// [PopoverTuning.arrowCornerClearance] of a corner. Of the rest the
/// one that slides least in total wins, earlier candidates on ties. When
/// no side works the popover goes above or below, where there is more
/// room.
///
/// Checked against 15 placements on the iOS 27 simulator.
PopoverPlacement placePopover({
  required Size size,
  required Rect source,
  required Size screen,
  EdgeInsets padding = EdgeInsets.zero,
  TextDirection textDirection = TextDirection.ltr,
}) {
  const arrow = PopoverTuning.arrowLength;
  const margin = PopoverMotion.margin;
  const clearance = PopoverTuning.arrowCornerClearance;
  final left = margin + padding.left;
  final right = screen.width - margin - padding.right;
  final top = padding.top;
  final bottom = screen.height - padding.bottom;
  final candidates = textDirection == TextDirection.ltr
      ? const [
          PopoverArrowDirection.down,
          PopoverArrowDirection.up,
          PopoverArrowDirection.left,
          PopoverArrowDirection.right,
        ]
      : const [
          PopoverArrowDirection.down,
          PopoverArrowDirection.up,
          PopoverArrowDirection.right,
          PopoverArrowDirection.left,
        ];
  PopoverPlacement? best;
  var bestShift = double.infinity;
  for (final edge in candidates) {
    final vertical =
        edge == PopoverArrowDirection.down || edge == PopoverArrowDirection.up;
    final double ideal;
    final double low;
    final double high;
    final double center;
    final double start;
    final double end;
    final double length;
    final double crossLength;
    if (vertical) {
      ideal = edge == PopoverArrowDirection.down
          ? source.top - arrow - size.height
          : source.bottom + arrow;
      low = top;
      high = bottom;
      length = size.height;
      start = left;
      end = right;
      center = source.center.dx;
      crossLength = size.width;
    } else {
      ideal = edge == PopoverArrowDirection.right
          ? source.left - arrow - size.width
          : source.right + arrow;
      low = left;
      high = right;
      length = size.width;
      start = top;
      end = bottom;
      center = source.center.dy;
      crossLength = size.height;
    }
    if (high - low < length || end - start < crossLength) continue;
    final along = ideal.clamp(low, high - length);
    final slide = (along - ideal).abs();
    if (slide > arrow) continue;
    final crossIdeal = center - crossLength / 2;
    final placed = crossIdeal.clamp(start, end - crossLength);
    if (center - placed < clearance ||
        placed + crossLength - center < clearance) {
      continue;
    }
    final shift = slide + (placed - crossIdeal).abs();
    if (shift < bestShift) {
      bestShift = shift;
      best = _placement(edge, size, along, placed, center);
    }
  }
  if (best != null) return best;
  final above = source.top - top;
  final below = bottom - source.bottom;
  final edge = above >= below
      ? PopoverArrowDirection.down
      : PopoverArrowDirection.up;
  final x = (source.center.dx - size.width / 2)
      .clamp(left, math.max(left, right - size.width))
      .toDouble();
  final y = edge == PopoverArrowDirection.down
      ? math.max(top, source.top - arrow - size.height)
      : math.min(bottom - size.height, source.bottom + arrow);
  final inset = math.min(clearance, size.width / 2);
  final center = source.center.dx.clamp(x + inset, x + size.width - inset);
  return _placement(
    edge,
    size,
    y.clamp(top, math.max(top, bottom - size.height)),
    x,
    center,
  );
}

PopoverPlacement _placement(
  PopoverArrowDirection edge,
  Size size,
  double along,
  double placed,
  double center,
) {
  final vertical =
      edge == PopoverArrowDirection.down || edge == PopoverArrowDirection.up;
  final content = vertical
      ? Rect.fromLTWH(placed, along, size.width, size.height)
      : Rect.fromLTWH(along, placed, size.width, size.height);
  return PopoverPlacement(
    content: content,
    arrowDirection: edge,
    arrowCenter: center,
  );
}
