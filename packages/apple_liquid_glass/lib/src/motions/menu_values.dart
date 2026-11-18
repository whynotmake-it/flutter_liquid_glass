import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/menu_layout.dart';
import 'package:apple_liquid_glass/src/motions/menu_motion.dart';
import 'package:apple_liquid_glass/src/motions/menu_tuning.dart';
import 'package:flutter/painting.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// How the page under an open menu dims: black, alpha only, on a spring
/// of its own that starts a delay after the menu's open or close.
@immutable
class MenuDim {
  /// Creates a dim from explicit values.
  const MenuDim({
    required this.openSpring,
    required this.openDelay,
    required this.closeSpring,
    required this.closeDelay,
  });

  /// The spring the dim comes in on.
  final Spring openSpring;

  /// Seconds from the menu's open to the dim's.
  final double openDelay;

  /// The spring the dim goes on; the menu's glass fades on it too as the
  /// menu closes.
  final Spring closeSpring;

  /// Seconds from the menu's close to the dim's.
  final double closeDelay;

  /// The dim of an iOS 27 context menu (iPhone 16 Pro, context-menu.md).
  static const context = MenuDim(
    openSpring: Spring.response(0.32, dampingRatio: 0.8),
    openDelay: 0.0145,
    closeSpring: Spring.response(0.35, dampingRatio: 0.85),
    closeDelay: 0.0125,
  );
}

/// The fusion of a liquid morph's two shapes over its turns.
///
/// UIKit's menu out of a button and its zoom out of a glass view run the
/// same liquid morph: every open and every close starts its own envelope
/// ([MenuTuning.fusionEnvelope]), and the fusion radius is the
/// largest envelope still running, limited to
/// [MenuTuning.fusionRadius], so a reversal never makes it jump.
class FusionTurns {
  /// Fuses with [tuning]'s envelope.
  FusionTurns(this.tuning);

  /// The envelope every turn follows.
  final MenuTuning tuning;

  final List<({double start, bool opening})> _turns = [];

  /// Starts the envelope of an open, or a close when [opening] is false,
  /// at time [t].
  void start(double t, {required bool opening}) =>
      _turns.add((start: t, opening: opening));

  /// The fusion radius at time [t].
  double radiusAt(double t) {
    var radius = 0.0;
    for (final turn in _turns) {
      radius = math.max(
        radius,
        tuning.fusionEnvelope(t - turn.start, opening: turn.opening),
      );
    }
    if (radius < tuning.fusionCutoff) return 0;
    return math.min(radius, tuning.fusionRadius);
  }

  /// Drops every envelope.
  void clear() => _turns.clear();

  /// Whether every envelope has ended by time [t]; the ended ones are
  /// dropped.
  bool endedAt(double t) {
    _turns.removeWhere(
      (({double start, bool opening}) turn) =>
          tuning.fusionEnded(t - turn.start, opening: turn.opening),
    );
    return _turns.isEmpty;
  }
}

/// Where a context menu stands and what it grows out of: UIKit's context
/// menu attaches to the lifted preview of the held view and grows out of a
/// blob at the held view's center, on glass of its own.
///
/// [MenuMotion.placeAttached] places the menu beside [preview], and
/// [MenuMotion.previewShift] is how far the preview moves to fit.
@immutable
class MenuAttachment {
  /// Creates an attachment to the lifted [preview] of the view [held].
  const MenuAttachment({
    required this.held,
    required this.preview,
    this.accessory = 0,
    this.gap = measuredGap,
    this.margin = MenuTuning.contextMargin,
  });

  /// The held view's frame at rest, in the menu's coordinates; the menu
  /// grows out of its center.
  final Rect held;

  /// The lifted preview's frame before any shift, in the menu's
  /// coordinates.
  final Rect preview;

  /// The extent above the preview taken by an accessory and its gap, which
  /// shifts with the preview and must stay inside the safe area too.
  final double accessory;

  /// The space between the preview and the menu.
  final double gap;

  /// The distance the preview and the menu keep from the safe area's edges.
  final double margin;

  /// Fits the preferred preview uniformly inside the safe area's margins
  /// (iOS 27 fit captures).
  static Size fitPreview({
    required Size preferred,
    required Size bounds,
    EdgeInsets padding = EdgeInsets.zero,
    double accessory = 0,
    double margin = MenuTuning.contextMargin,
  }) {
    if (preferred.isEmpty) return preferred;
    final width = math.max<double>(
      0,
      bounds.width - padding.horizontal - margin * 2,
    );
    final height = math.max<double>(
      0,
      bounds.height - padding.vertical - margin * 2 - accessory,
    );
    final scale = math.min<double>(
      1,
      math.min(width / preferred.width, height / preferred.height),
    );
    return preferred * scale;
  }

  /// Space UIKit leaves between an open preview and its menu, in points
  /// (iPhone 16 Pro, iOS 27).
  static const double measuredGap = 16;

  /// The share of the held view a context menu grows out of.
  static const double measuredBlobScale = 0.4;

  /// The blob a context menu of [menuHeight] grows out of and retracts into
  /// for a held view of [held] size, centered on the held view: 0.4 of the
  /// held view's shorter side tall and 0.4 of its width, at most 0.4 of the
  /// menu's height, wide.
  ///
  /// Fitted to the menu morph layer at its smallest on an iPhone 16 Pro
  /// (iOS 27, `context_menu/growth.json`, within 0.3 pt): 60 x 40 -> 24 x
  /// 16, 120 x 80 -> 48 x 32, 80 x 160 -> 32 x 32 and 300 x 200 -> 83.2 x
  /// 80 under a 208-point menu (the only menu height recorded, so the
  /// width cap is the measured one for that height).
  static Size blobSize(Size held, double menuHeight) => Size(
    measuredBlobScale * math.min(held.width, menuHeight),
    measuredBlobScale * held.shortestSide,
  );

  @override
  bool operator ==(Object other) =>
      other is MenuAttachment &&
      other.held == held &&
      other.preview == preview &&
      other.accessory == accessory &&
      other.gap == gap &&
      other.margin == margin;

  @override
  int get hashCode => Object.hash(held, preview, accessory, gap, margin);
}

/// One of the two shapes a menu morph is drawn from.
///
/// [rect] is the visible frame, already scaled; [localSize] is the frame
/// before the uniform [scale], which is the size content is laid out in.
class MenuBlob {
  /// Creates a blob.
  const MenuBlob({
    required this.rect,
    required this.radius,
    required this.scale,
    required this.localSize,
  });

  /// The visible frame.
  final Rect rect;

  /// The visible corner radius.
  final double radius;

  /// The uniform scale from [localSize] to [rect].
  final double scale;

  /// The frame before scaling.
  final Size localSize;

  /// The visible shape as a rounded rectangle.
  RRect get rrect => RRect.fromRectAndRadius(rect, Radius.circular(radius));

  /// The frame before scaling, centered on the visible one.
  Rect get localRect => Rect.fromCenter(
    center: rect.center,
    width: localSize.width,
    height: localSize.height,
  );
}

/// One card of a menu as drawn at the time the motion was last advanced
/// to: the root list is card 0, each open submenu stacks one more.
class MenuCard {
  /// Creates a card.
  const MenuCard({
    required this.layout,
    required this.rect,
    required this.scale,
    required this.rowOpacity,
    required this.progress,
    this.contentTop = 0,
    this.rowsOpacity = 1,
    this.platterOpacity = 1,
    this.headerBold = 1,
    this.chevronTurn = 1,
    this.closeOpacity = 1,
    this.backing = false,
    this.source,
  });

  /// The content of the card.
  final MenuLayout layout;

  /// The frame of the card in the menu's content coordinates, before
  /// [scale].
  final Rect rect;

  /// The scale of the card about the top center of the menu content.
  final double scale;

  /// The opacity of the card's rows; cards under an open card dim.
  final double rowOpacity;

  /// How far the card has grown out of its row, 1 for the root list.
  final double progress;

  /// The top of the card's content in the coordinates of [rect]: the
  /// content rides the row the card grew out of, so the header lies on
  /// that row while the card is small and the card hands it back to the
  /// row without a jump.
  final double contentTop;

  /// The opacity of the card's rows other than its header.
  final double rowsOpacity;

  /// The opacity of the card's platter.
  final double platterOpacity;

  /// How bold the header title is, 0 the row's weight and 1 the header's.
  final double headerBold;

  /// How far the header chevron has turned, 0 pointing at the trailing
  /// edge like the row's and 1 pointing down.
  final double chevronTurn;

  /// The opacity of the whole card while the menu closes, 1 otherwise.
  final double closeOpacity;

  /// Whether the card is on its way back into its row.
  final bool backing;

  /// The target of the card below that opened this one, null for the
  /// root list. Its header stands in for that row while the card shows.
  final int? source;
}

/// What a menu grows out of, in an overlay's coordinates.
class MenuSource {
  /// A button: [rect] morphs, takes the touches, and places the menu, which
  /// grows from its center.
  ///
  /// [height] is the height the menu's first blob derives from, [rect]'s by
  /// default; [radius] is the corner radius of the shape, a capsule's by
  /// default.
  MenuSource(Rect rect, {double? height, this.radius})
    : shape = rect,
      body = rect,
      origin = rect.center,
      height = height ?? rect.height;

  MenuSource._capsule({
    required this.shape,
    required this.body,
    required this.origin,
    required this.height,
  }) : radius = null;

  /// The shape that morphs.
  final Rect shape;

  /// What a finger presses: the button, or a capsule's tapped item. The
  /// menu's [MenuTuning.reach] applies to it.
  final Rect body;

  /// Where the menu grows from and closes into.
  final Offset origin;

  /// The height the menu's first blob derives from.
  final double height;

  /// The corner radius of [shape]; null for a capsule's.
  final double? radius;
}

/// A capsule of a bar: all of it morphs and shrinks to a square, while the
/// menu grows out of the tapped item and lands where the capsule says, not
/// where the item does (menu passport).
final class MenuCapsuleSource extends MenuSource {
  /// The capsule's [capsule] rect with its tapped [item]'s slot in it.
  ///
  /// [alone] says that the item is the only one in the capsule.
  MenuCapsuleSource({
    required Rect capsule,
    required Rect item,
    required super.height,
    required this.alone,
  }) : super._capsule(shape: capsule, body: item, origin: item.center);

  /// Whether the tapped item is the only one in the capsule.
  final bool alone;
}
