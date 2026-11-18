import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';

/// An atlas on loan from the page a geometry renderer drew it into
/// (`renderAtlas`).
///
/// The images are the page's: whoever holds a lease never disposes them, and
/// draws with them only until the renderer that lent it renders another
/// atlas or releases this one. After that the page may be drawn over, and
/// what still draws with the lease shows other atlases or fails.
@immutable
final class AtlasLease {
  /// The atlas at [place] in [image], with [looks] beside it.
  const AtlasLease({
    required this.image,
    required this.place,
    this.looks = const [],
  });

  /// The page the atlas shares with the others of its frame: its strips
  /// sampled bilinearly, its table texel by texel.
  final ui.Image image;

  /// Where the atlas lies in [image].
  final AtlasPlace place;

  /// The looks beside the atlas, in its layout, for the variants that read
  /// them: the tint, or tint, response and color model weights.
  final List<ui.Image> looks;

  /// The atlas alone, for glass that reads none of the looks beside it.
  AtlasLease get withoutLooks =>
      looks.isEmpty ? this : AtlasLease(image: image, place: place);

  @override
  bool operator ==(Object other) =>
      other is AtlasLease &&
      identical(other.image, image) &&
      other.place == place &&
      listEquals(other.looks, looks);

  @override
  int get hashCode =>
      Object.hash(identityHashCode(image), place, Object.hashAll(looks));
}
