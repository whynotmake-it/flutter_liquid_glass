import 'dart:math';
import 'dart:ui';

import 'package:liquid_glass_renderer/src/painting/rect_scaling.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';
import 'package:meta/meta.dart';

/// What Impeller does to a layer a clip cuts: it cuts the layer to the clip,
/// and starts fragment coordinates at the cut, only once the part it cuts off
/// either axis is 30 % or more of what is left (ComputeSaveLayerCoverage,
/// impeller/entity/save_layer_utils.cc; in_frame_copy_test fails when it
/// changes).
@internal
abstract final class ImpellerLayers {
  /// How far above and left of its pixels a read's layers are added, in
  /// device pixels.
  ///
  /// Impeller places a layer drawn inside another, such as the one a
  /// paragraph that fades at its edge is painted through, by the floor of its
  /// origin less the origin of the layer around it. Where the copy's edge
  /// cuts such a layer the two origins are the same number, less what 32-bit
  /// floats lose on the way: the copy's passes through the place of the glass
  /// on the screen, a fraction that moves with it. A hair above a whole pixel
  /// the floor is one pixel short, and the layer's content, all of the text,
  /// would stand one pixel of the copy aside, up to four of the screen's, for
  /// the frames the glass spent there (a lens sweeping over faded text on a
  /// Pixel 6a: 46 to 58 frames in 12 s, none without the fade). Drawn a
  /// little below whole pixels the floor always falls the same way. The
  /// read's own layers are placed by rounding, so nothing on the screen
  /// moves. Measured on the device only: no host test sees it.
  static const double nestedOriginBias = 1 / 32;

  /// The skew under which text drawn into a smaller copy lies where it is
  /// drawn: under a translation and a scale alone Impeller sets glyphs on
  /// whole pixels of their target (impeller/entity/contents/text_contents.cc).
  /// See `CopyPlace.deviceToCopy`; copy_text_motion_test fails when that
  /// changes.
  static const double glyphSkew = 1e-6;

  /// The rows a layer keeps past the rows pinned in it. Impeller sometimes
  /// sizes a layer drawn under a transform a hair off whole pixels, as a
  /// pressed sheet's, a row short; without the spare row a haze's mix finds
  /// no strip and draws the copy unhazed, and the glass flickers from frame
  /// to frame (sheet_haze_host_test).
  static const int spareRows = 1;

  /// Where an opacity pass that a glass seeds starts on the screen, in
  /// logical pixels: Impeller bounds it by the clips around it, rounded out
  /// to device pixels, and fragment coordinates start there.
  static Offset passOrigin(Rect clip, double devicePixelRatio) => Offset(
    (clip.left * devicePixelRatio).floorToDouble() / devicePixelRatio,
    (clip.top * devicePixelRatio).floorToDouble() / devicePixelRatio,
  );

  /// Whether Impeller draws a layer of [layer] whole inside a clip of
  /// [clip], both in the same space.
  static bool keepsWhole(Rect layer, Rect clip) {
    final cut = layer.intersect(clip);
    if (cut.isEmpty) return false;
    return (layer.width - cut.width) / cut.width < 0.3 &&
        (layer.height - cut.height) / cut.height < 0.3;
  }

  /// Whether Impeller draws a layer of [layer] whole inside [clip] (logical
  /// pixels). It measures the layer as drawn: the whole pixels it grows to
  /// can tip a layer just under the bound over it.
  static bool keepsWholeOn(DeviceBox layer, Rect clip, ViewPixels view) =>
      keepsWhole(layer.rect, clip.scaled(view.devicePixelRatio));

  /// Whether Impeller starts the fragments of a layer of [layer] inside a
  /// clip of [clip], both in the same space, at the layer's top left: where
  /// the clip cuts neither its top nor its left, or where it draws the layer
  /// whole.
  static bool keepsCorner(Rect layer, Rect clip) =>
      (layer.left >= clip.left && layer.top >= clip.top) ||
      keepsWhole(layer, clip);

  /// The layer, at the screen's pixels, that holds [footprint] inside [clip]
  /// (logical pixels).
  ///
  /// The glass reads what lies past the clip, so the layer grows into the
  /// clip, empty, until the part cut off is less than Impeller's bound;
  /// where the clip leaves no room, it is cut to the clip. NEAR: there,
  /// glass reads the copy mirrored at the clip, up to 163 levels off over
  /// the 30 px of glass the host test leaves above such a clip.
  static DeviceBox layerIn(DeviceBox footprint, Rect clip, ViewPixels view) {
    if (keepsWholeOn(footprint, clip, view)) return footprint;
    (double, double)? grow(double lo, double hi, double from, double to) {
      final cut = max(from - lo, 0) + max(hi - to, 0);
      final inside = min(hi, to) - max(lo, from);
      if (inside <= 0) return null;
      // A margin below 30 % keeps rounding off the threshold.
      final wanted = cut / 0.28;
      if (inside >= wanted) return (lo, hi);
      if (lo < from && hi > to) return null;
      if (lo < from) {
        final end = max(lo, from) + wanted;
        return end <= to ? (lo, end) : null;
      }
      final start = min(hi, to) - wanted;
      return start >= from ? (start, hi) : null;
    }

    final logical = view.logical(footprint);
    final x = grow(logical.left, logical.right, clip.left, clip.right);
    final y = grow(logical.top, logical.bottom, clip.top, clip.bottom);
    final inside = view.cover(logical.intersect(clip));
    if (x == null || y == null) return inside;
    final grown = view.cover(Rect.fromLTRB(x.$1, y.$1, x.$2, y.$2));
    return keepsWholeOn(grown, clip, view) ? grown : inside;
  }

  /// A device pixel at the top left and one at the bottom right of [layer]
  /// (logical pixels): a clip path that covers them too keeps its bounds at
  /// the layer's, so Impeller does not cut the layer.
  static (Rect, Rect) pinsOf(Rect layer, double devicePixelRatio) {
    final pixel = 1 / devicePixelRatio;
    return (
      layer.topLeft & Size.square(pixel),
      Rect.fromPoints(
        layer.bottomRight - Offset(pixel, pixel),
        layer.bottomRight,
      ),
    );
  }
}
