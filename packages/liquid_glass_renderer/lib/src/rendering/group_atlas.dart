import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/painting/rect_scaling.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/atlas_lease.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/shading.dart';
import 'package:liquid_glass_renderer/src/rendering/shape_set.dart';

/// One glass of a group: its `shapes`, where their origin lies on the
/// screen (`onScreen`, device pixels), the rect its shader paints (`drawn`,
/// the screen's logical pixels) and the `appearance` it draws with.
@internal
typedef GroupMember = ({
  ShapeSet shapes,
  Offset onScreen,
  Rect drawn,
  WornAppearance appearance,
});

/// One geometry atlas of a group's glass, its origin on the first's. Glass
/// that moves together lies where it lay in it, so a scroll under it renders
/// nothing and only moves the mapping.
@internal
final class GroupAtlas {
  /// A group's shared atlas, drawn with Flutter GPU by the renderer it is given
  /// and owns.
  GroupAtlas(this._renderer);

  /// How many times a group's atlas was drawn.
  @visibleForTesting
  static int debugRenders = 0;

  final FlutterGpuGeometryRenderer _renderer;
  var _signature = const <Object?>[];

  /// The atlas, once gathered, with the tint beside it where the glass's
  /// tints differ.
  AtlasLease? lease;

  /// Where the geometry buffer lies, in logical pixels from [origin].
  Rect bounds = Rect.zero;

  /// Where the geometry buffer's origin lies on the screen, in logical
  /// pixels.
  Offset origin = Offset.zero;

  /// Draws the atlas of [glass] again for [need], the first glass's, unless
  /// it lies as it lay.
  void gather(List<GroupMember> glass, GeometryNeed need) {
    final dpr = need.devicePixelRatio;
    final base = glass.first.onScreen;
    origin = base / dpr;
    // A 64th of a pixel keeps rounding in the layers' moves from drawing the
    // atlas again; the glass lies that much off, unseen.
    double fixed(double value) => (value * 64).roundToDouble() / 64;
    final signature = <Object?>[need];
    for (final member in glass) {
      final at = member.onScreen - base;
      signature.addAll([
        member.shapes,
        member.appearance.tint,
        fixed(at.dx),
        fixed(at.dy),
      ]);
    }
    if (lease != null && listEquals(signature, _signature)) return;
    _signature = signature;
    debugRenders++;
    Rect? rect;
    for (final member in glass) {
      final shown = member.drawn;
      final drawn = shown.scaled(dpr).shift(-base);
      rect = rect?.expandToInclude(drawn) ?? drawn;
    }
    final all = rect!;
    final reach = need.reach;
    final room = reach.outward.ceilToDouble() + 1;
    final left = (all.left - room).floorToDouble();
    final top = (all.top - room).floorToDouble();
    final width = (all.right + room - left).ceil();
    final height = (all.bottom + room - top).ceil();
    final firstTint = glass.first.appearance.tint;
    final mixed = glass.any((member) => member.appearance.tint != firstTint);
    final shapes = ShapeSet.join([
      for (final member in glass)
        (
          member.shapes,
          Offset(
            fixed(member.onScreen.dx - base.dx) - left,
            fixed(member.onScreen.dy - base.dy) - top,
          ),
        ),
    ]);
    lease = _renderer.renderAtlas(
      Tiling.shapes(
        shapes,
        width: width,
        height: height,
        reach: reach,
        looks: mixed
            ? shapeLooks(
                [
                  for (final member in glass)
                    for (var i = 0; i < member.shapes.count; i++)
                      member.appearance,
                ],
                colorModels: const [],
                tintOnly: true,
              )
            : null,
      ),
    );
    bounds = Rect.fromLTWH(left / dpr, top / dpr, width / dpr, height / dpr);
  }

  /// Releases the renderer.
  void dispose() => _renderer.dispose();
}
