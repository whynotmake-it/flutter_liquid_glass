import 'package:apple_liquid_glass/src/motions/bar_motion.dart';
import 'package:apple_liquid_glass/src/motions/bar_transition_spec.dart';
import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// Where one item of a bar sits in a layout handed to [GlassBarMotion].
@internal
@immutable
class GlassBarItemLayout {
  /// Creates an item layout.
  const GlassBarItemLayout(this.id, this.rect);

  /// The identity of the item across layouts.
  final Object id;

  /// The item's box in the bar's coordinates.
  final Rect rect;
}

/// One glass capsule of a bar layout handed to [GlassBarMotion]: a group
/// of items that share one piece of glass.
@immutable
class GlassBarCapsuleLayout {
  /// Creates a capsule layout.
  const GlassBarCapsuleLayout(
    this.id,
    this.rect,
    @internal this.items, {
    this.segment,
    this.anonymous = false,
  });

  /// The identity of the capsule across layouts.
  final Object id;

  /// Whether the capsule has no identity of its own, as a group without an
  /// id: it then continues the capsule without one of its segment whose
  /// center lies nearest (UIKit's bar groups carry no identity across a
  /// push: `[plus more]` `[1x]` -> `[Show Preferences]` keeps the inner group's
  /// glass, the nearer one).
  final bool anonymous;

  /// The side of the bar the capsule belongs to, such as its leading or
  /// trailing groups; null puts every such capsule on one side.
  ///
  /// A capsule changes only into a capsule of its own segment: an [id]
  /// found in another segment is a new capsule, and a newborn grows out of
  /// a capsule of its segment that stays only. When a segment keeps no
  /// capsule through the change, its capsules appear and leave in place
  /// (see [GlassBarTransitionSpec.segmentDelay]).
  final Object? segment;

  /// The capsule's box in the bar's coordinates.
  final Rect rect;

  /// The items in the capsule.
  @internal
  final List<GlassBarItemLayout> items;
}

/// A capsule of a bar in one frame.
@immutable
class GlassBarCapsuleFrame {
  /// Creates a frame.
  const GlassBarCapsuleFrame(
    this.id,
    this.rect, {
    required this.leaving,
    this.segment,
    this.opacity = 1,
    this.apart = false,
  });

  /// The identity of the capsule.
  final Object id;

  /// The capsule's box, swell included.
  final Rect rect;

  /// Whether the capsule is on its way out.
  final bool leaving;

  /// The segment of the capsule's layout.
  final Object? segment;

  /// How present the capsule's glass is, 0 to 1.
  final double opacity;

  /// Whether the capsule appears or leaves in place: UIKit draws it in a
  /// glass container of its own, so it never fuses with the other
  /// capsules of the bar.
  final bool apart;
}

/// An item of a bar in one frame.
@immutable
class GlassBarItemFrame {
  /// Creates a frame.
  const GlassBarItemFrame(
    this.id, {
    required this.center,
    required this.size,
    required this.scale,
    required this.presence,
    required this.blur,
    required this.leaving,
  });

  /// The identity of the item.
  final Object id;

  /// The center of the item.
  final Offset center;

  /// The item's laid-out size; [scale] applies on top.
  final Size size;

  /// The scale the item is drawn at.
  final double scale;

  /// How present the item is, 0 gone and 1 fully there; UIKit draws it at
  /// this opacity.
  final double presence;

  /// The blur the item is drawn with, in logical pixels.
  final double blur;

  /// Whether the item is on its way out.
  final bool leaving;
}

/// The identity a capsule on its way out takes when a capsule of the new
/// layout carries the id it had.
@internal
class GlassBarDepartedId {
  /// Wraps the [id] a leaving capsule had.
  GlassBarDepartedId(this.id);

  /// The id the capsule had.
  final Object id;

  @override
  String toString() => 'GlassBarDepartedId($id)';
}
