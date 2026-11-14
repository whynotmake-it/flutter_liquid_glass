import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_frost.dart'
    show transparentPixel;
import 'package:liquid_glass_renderer/src/rendering/copy_read.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';
import 'package:liquid_glass_renderer/src/rendering/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_filter.dart';
import 'package:liquid_glass_renderer/src/rendering/shape_set.dart';

/// One draw of the final glass shader: every uniform and sampler it reads,
/// in sections that each own their uniforms.
///
/// [GlassShading] writes all of a draw before it makes a filter or paint of
/// it, so no draw depends on what another left in the shader.
@internal
@immutable
final class GlassDraw {
  /// Creates the draw.
  const GlassDraw({
    required this.variant,
    required this.face,
    required this.glow,
    required this.matte,
    required this.mapping,
    this.reading = LiveReading.backdrop,
    this.band,
  });

  /// The index in [FinalShaderVariant.all] of the shader it draws with.
  final int variant;

  /// The material: settings, appearance and color models.
  final GlassFace face;

  /// The touch glow, as `LiquidGlassGlow.uniformsOf` lays it out.
  final List<double> glow;

  /// Where the shader reads its shapes.
  final MatteBinding matte;

  /// From fragment coordinates into the matte.
  final MatteMapping mapping;

  /// What the shader reads under the glass.
  final GlassReading reading;

  /// The scroll edge the band variant draws beside the glass; a variant
  /// without one lays nothing over what it reads.
  final BandOverlay? band;

  /// This draw with the parts given changed.
  GlassDraw copyWith({MatteMapping? mapping, GlassReading? reading}) =>
      GlassDraw(
        variant: variant,
        face: face,
        glow: glow,
        matte: matte,
        mapping: mapping ?? this.mapping,
        reading: reading ?? this.reading,
        band: band,
      );

  @override
  bool operator ==(Object other) =>
      other is GlassDraw &&
      other.variant == variant &&
      other.face == face &&
      listEquals(other.glow, glow) &&
      other.matte == matte &&
      other.mapping == mapping &&
      other.reading == reading &&
      other.band == band;

  @override
  int get hashCode => Object.hash(variant, matte, mapping, reading);
}

/// The final shader's floats one layout of the glass's material sets.
@internal
@immutable
final class GlassFace {
  const GlassFace._({
    required this.face,
    required this.wrap,
    required this.gamma,
    required this.material,
    required this.blurFade,
    required this.colorModels,
  });

  /// The material of [appearance] under [settings], its color model in one
  /// of the slots [colorModels] fill.
  ///
  /// Colors go in at 8 bits a channel. The shader fades the whole material
  /// with visibility, so the color factors go in at full strength. Frosted
  /// glass cross-fades its blur away ([blurs]), unfrosted glass stays alpha 1
  /// and cross-fades its material in the shader, so both match the backdrop
  /// at visibility 0.
  factory GlassFace.of({
    required LiquidGlassSettings settings,
    required LiquidGlassAppearance appearance,
    required List<GlassColorParameters> colorModels,
    required double devicePixelRatio,
    required bool blurs,
  }) {
    final dpr = devicePixelRatio;
    final tint = appearance.tint;
    final contour = (settings.contourStrength.clamp(0.0, 1.0) * 255).round();
    return GlassFace._(
      face: List.unmodifiable(<double>[
        _channel(tint.r),
        _channel(tint.g),
        _channel(tint.b),
        _channel(tint.a),
        settings.effectiveDisplacementScale * dpr,
        settings.dispersion,
        settings.effectiveEdgeDistanceRange * dpr,
        settings.highlight,
        1 - settings.effectiveBackdropShrink,
        appearance.colorModel.saturation,
        0,
        1,
        1,
        1,
        1,
        1,
        0,
        0,
        0,
        contour / 255,
        GlassRim.bevelShadowDirectionality,
        0,
        GlassRim.highlightWidth * dpr,
        GlassRim.highlightOppositeStrength,
        settings.contourWidth * dpr,
        0,
        settings.contourDirectionality,
        0,
      ]),
      wrap: GlassRim.highlightWrap,
      gamma: appearance.colorModel.transmissionGamma,
      material: List.unmodifiable(<double>[
        appearance.colorModel.vibrancy,
        settings.effectiveTintAmount,
        settings.bevelShadowStrength,
        GlassRim.bevelShadowDepth * dpr,
        GlassRim.bevelShadowOffset * dpr,
        colorModelCode(appearance.colorModel, colorModels),
        appearance.visibility,
      ]),
      blurFade: blurs ? 1 : 0,
      colorModels: List.unmodifiable(<double>[
        for (var i = 0; i < 3; i++)
          ...i < colorModels.length
              ? colorModels[i].toShaderParameters(
                  settings.effectiveTintAmount,
                )
              : _noModel,
      ]),
    );
  }

  static double _channel(double value) =>
      (value * 255).round().clamp(0, 255) / 255;

  // A slot no shape reads.
  static final _noModel = List<double>.filled(24, 0);

  /// uFace: tint, optics, light, highlight and contour colors, rim, contour.
  final List<double> face;

  /// uProfile.z, the highlight's wrap.
  final double wrap;

  /// uProfile.w, the transmission gamma.
  final double gamma;

  /// uMaterial: vibrancy, tint amount, bevel, model code, visibility.
  final List<double> material;

  /// uBlurFade: 1 where the frost fades out with visibility.
  final double blurFade;

  /// uColorModelParams: three slots of the color models.
  final List<double> colorModels;

  /// The bevel's displacement, which reads the backdrop by device pixels.
  double get displacement => face[4];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlassFace &&
          other.wrap == wrap &&
          other.gamma == gamma &&
          other.blurFade == blurFade &&
          listEquals(other.face, face) &&
          listEquals(other.material, material) &&
          listEquals(other.colorModels, colorModels);

  @override
  int get hashCode => Object.hash(wrap, gamma, blurFade, face[0], face[4]);
}

/// How deep into glass drawn with [settings] and how far out of it the final
/// shader reads the geometry, in device pixels: the bevel and the rim
/// lighting inward (rimReach() in liquid_glass_final_render_core.glsl), the
/// contour's [contourExtent] outward, each a pixel more. A geometry atlas
/// holds constants past them, and where the geometry is smooth one texel
/// for 4 x 4 device pixels at a [devicePixelRatio] of 2 or more, else for
/// 2 x 2: the density of the low-res matte the atlas replaced.
@internal
GlassReach glassReach(
  LiquidGlassSettings settings, {
  required double devicePixelRatio,
  required double contourExtent,
}) {
  final dpr = devicePixelRatio;
  // kGlintBleedReach: the glint's bleed is gone this many widths in.
  const glintBleedReach = 4.0;
  var rim = 0.0;
  if (settings.highlight > 0) {
    rim = max(rim, GlassRim.highlightWidth * dpr * glintBleedReach);
  }
  if (settings.contourStrength > 0 && settings.contourWidth > 0) {
    rim = max(rim, 0.5);
  }
  if (settings.bevelShadowStrength >= 0.001) {
    rim = max(
      rim,
      (GlassRim.bevelShadowDepth + GlassRim.bevelShadowOffset) * dpr * 1.001 +
          0.01,
    );
  }
  return GlassReach(
    inward: max(settings.effectiveRefractionHeight * dpr, rim) + 1,
    outward: contourExtent + 1,
    coarseTexel: dpr >= 2 ? 4 : 2,
  );
}

/// Where the final shader takes the glass's geometry from: the distance to
/// its edge, its normal and half its thickness at a pixel of the geometry
/// buffer. The geometry is one function of the shapes and the pixel
/// (gpu/sdf.glsl), and the two cases are the two ways to have its value:
/// worked out at the fragment, or read from the atlas that holds it.
///
/// What the glass is decides which, never whether it moves: glass that is
/// one shape is [ComputedGeometry] at rest and in motion, and anything else
/// (several shapes, a fused body, the glass of a group) is
/// [AtlasGeometry]. The shader variant follows from the case
/// ([FinalShaderVariant.shape]).
@internal
@immutable
sealed class GlassGeometry {
  const GlassGeometry();
}

/// The geometry in an atlas (geometry_tiling.dart), and the looks beside it
/// where the shapes' appearances differ.
@internal
final class AtlasGeometry extends GlassGeometry {
  /// The atlas at [place] in [image], with [looks] beside it.
  const AtlasGeometry({
    required this.image,
    required this.place,
    this.looks = const [],
  });

  /// The atlas of glass that has no geometry yet.
  static final AtlasGeometry none = AtlasGeometry(
    image: transparentPixel,
    place: AtlasLayout.unplaced,
  );

  /// The page the atlas shares with the others of its frame: its strips
  /// sampled bilinearly, its table texel by texel.
  final ui.Image image;

  /// uGeometryAtlas: where the atlas lies in [image].
  final AtlasPlace place;

  /// The looks beside the atlas, in its layout, for the variants that read
  /// them: the tint, or tint, response and color model shares.
  final List<ui.Image> looks;

  @override
  bool operator ==(Object other) =>
      other is AtlasGeometry &&
      identical(other.image, image) &&
      other.place == place &&
      listEquals(other.looks, looks);

  @override
  int get hashCode =>
      Object.hash(identityHashCode(image), place, Object.hashAll(looks));
}

/// The geometry of glass that is one shape, which the shader works out at
/// each fragment (shape_geometry.glsl): nothing is tiled, drawn into a page
/// or submitted for it.
@internal
final class ComputedGeometry extends GlassGeometry {
  /// The geometry of [shape], one shape in the geometry buffer's pixels.
  ComputedGeometry(ShapeSet shape)
    : assert(shape.count == 1, 'The shader works out one shape.'),
      floats = Float32List(40) {
    floats
      ..setRange(0, 12, shape.shapes)
      ..setRange(12, 24, shape.superellipses)
      ..setRange(24, 36, shape.superellipsesLower);
    if (Tiling.innerBoxOf(shape, 0) case (
      final width,
      final height,
      final radius,
    )) {
      floats[36] = width;
      floats[37] = height;
      floats[38] = radius;
      floats[39] = shape.shapes[10];
    }
  }

  /// uShapeData, uRseData and uShapeInner, in that order.
  final Float32List floats;

  @override
  bool operator ==(Object other) =>
      other is ComputedGeometry && listEquals(other.floats, floats);

  @override
  int get hashCode => Object.hashAll(floats);
}

/// What glass reads by its depth from the edge of a capsule of its bounds,
/// in device pixels: how far outside itself it reads the backdrop at its
/// edge and how deep that reaches, half the center line both point away from
/// (positive along x, negative along y) and half the short side of the
/// material, and how far apart it parts the colors and how deep that fades.
@internal
typedef GlassEdgeReads = ({
  double pull,
  double pullHeight,
  double line,
  double halfMinor,
  double aberration,
  double aberrationDepth,
});

/// What the final shader shades: the glass's geometry and where its buffer
/// lies, with what the glass's own size and settings give the bevel.
@internal
@immutable
final class MatteBinding {
  /// Creates the binding. Rects, points and sizes are in device pixels.
  const MatteBinding({
    required this.geometry,
    required this.origin,
    required this.size,
    required this.halfMinor,
    required this.refractionHeight,
    required this.fitsShape,
    required this.materialCenter,
    required this.shrinkAxis,
    this.edge = plainEdge,
  });

  /// The [edge] of glass that neither pulls nor parts colors.
  static const GlassEdgeReads plainEdge = (
    pull: 0,
    pullHeight: 0,
    line: 0,
    halfMinor: 0,
    aberration: 0,
    aberrationDepth: 0,
  );

  /// Where the shader takes the geometry from.
  final GlassGeometry geometry;

  /// uGeometryBounds.xy: where the geometry buffer's top-left lies.
  final Offset origin;

  /// uGeometryBounds.zw: the geometry buffer's size, one texel a pixel.
  final Size size;

  /// uBevel.z: half the short side of the glass, which sizes the bevel.
  final double halfMinor;

  /// uBevel.x: how far in the refraction reaches.
  final double refractionHeight;

  /// uBevel.y: whether refraction fits the shape.
  final bool fitsShape;

  /// uMaterialCenter, in the matte.
  final Offset materialCenter;

  /// uBackdropShrinkAxis.
  final Offset shrinkAxis;

  /// uBackdropPull and uBackdropAberration.
  final GlassEdgeReads edge;

  @override
  bool operator ==(Object other) =>
      other is MatteBinding &&
      other.geometry == geometry &&
      other.origin == origin &&
      other.size == size &&
      other.halfMinor == halfMinor &&
      other.refractionHeight == refractionHeight &&
      other.fitsShape == fitsShape &&
      other.materialCenter == materialCenter &&
      other.shrinkAxis == shrinkAxis &&
      other.edge == edge;

  @override
  int get hashCode => Object.hash(
    geometry,
    origin,
    size,
    halfMinor,
    materialCenter,
    shrinkAxis,
  );
}

/// From fragment coordinates to the matte, both in device pixels, and the
/// part of the matte past which the backdrop the shader reads holds nothing.
@internal
@immutable
final class MatteMapping {
  /// The mapping [toMatte] (basis x.x, y.x, x.y, y.y, then offset) and the
  /// device rect [backdropBounds] of the matte.
  const MatteMapping(this.toMatte, this.backdropBounds);

  /// The mapping from the fragments of a draw whose coordinate zero lies at
  /// [origin] on the screen, in device pixels, one fragment [scale] of
  /// them, through [screenToMatte] (logical pixels) into the matte.
  /// [backdropBounds] is in the matte's logical pixels, null for none.
  factory MatteMapping.of(
    Matrix4 screenToMatte, {
    required double devicePixelRatio,
    Offset origin = Offset.zero,
    double scale = 1,
    Rect? backdropBounds,
  }) {
    final dpr = devicePixelRatio;
    final o = MatrixUtils.transformPoint(screenToMatte, Offset.zero);
    final ax = MatrixUtils.transformPoint(screenToMatte, const Offset(1, 0));
    final ay = MatrixUtils.transformPoint(screenToMatte, const Offset(0, 1));
    final bounds = backdropBounds ?? Rect.largest;
    return MatteMapping(
      (
        (ax.dx - o.dx) * scale,
        (ay.dx - o.dx) * scale,
        (ax.dy - o.dy) * scale,
        (ay.dy - o.dy) * scale,
        o.dx * dpr + (ax.dx - o.dx) * origin.dx + (ay.dx - o.dx) * origin.dy,
        o.dy * dpr + (ax.dy - o.dy) * origin.dx + (ay.dy - o.dy) * origin.dy,
      ),
      bounds.scaled(dpr),
    );
  }

  /// Maps nothing anywhere: the mapping before the glass has a place.
  static const MatteMapping none = MatteMapping((0, 0, 0, 0, 0, 0), Rect.zero);

  /// uFilterToMatteBasis and uFilterToMatteOffset.
  final (double, double, double, double, double, double) toMatte;

  /// uBackdropBounds.
  final Rect backdropBounds;

  @override
  bool operator ==(Object other) =>
      other is MatteMapping &&
      other.toMatte == toMatte &&
      other.backdropBounds == backdropBounds;

  @override
  int get hashCode => Object.hash(toMatte, backdropBounds);
}

/// What the final shader reads under the glass.
@internal
@immutable
sealed class GlassReading {
  const GlassReading();
}

/// The backdrop a filter is given: the live one, or a layer's corner the
/// filter reads as the screen.
@internal
final class LiveReading extends GlassReading {
  const LiveReading._();

  /// The reading.
  static const LiveReading backdrop = LiveReading._();
}

/// A copy of the backdrop, as [GlassSampling] lays it out.
@internal
final class CopyReading extends GlassReading {
  /// The copy [sampling] describes.
  CopyReading(GlassSampling sampling)
    : origin = sampling.image == null ? Offset.zero : sampling.origin,
      scale = sampling.scale,
      reduced = sampling.reduced,
      frost = sampling.frost,
      size = sampling.size,
      image = sampling.image;

  /// uBackdropOrigin: where a paint's fragment zero lies on the screen;
  /// zero for a filter, whose fragments start there.
  final Offset origin;

  /// Device pixels per fragment.
  final int scale;

  /// uBackdropReduced.
  final double reduced;

  /// The frost, in device pixels, the shader's taps add.
  final double frost;

  /// uSize of a paint; a filter's is the engine's.
  final Size? size;

  /// The image a paint samples; a filter samples its input.
  final ui.Image? image;

  @override
  bool operator ==(Object other) =>
      other is CopyReading &&
      identical(other.image, image) &&
      other.origin == origin &&
      other.scale == scale &&
      other.reduced == reduced &&
      other.frost == frost &&
      other.size == size;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(image), origin, scale, reduced, frost, size);
}

/// An opaque color in place of the backdrop, for glass painted as a rect.
@internal
final class SolidReading extends GlassReading {
  /// Reads [color] over a target of [size] device pixels.
  const SolidReading(this.color, this.size);

  /// The color, in extended sRGB.
  final ui.Color color;

  /// uSize: only backdrop reads divide by it, so any nonzero size works.
  final Size size;

  @override
  bool operator ==(Object other) =>
      other is SolidReading && other.color == color && other.size == size;

  @override
  int get hashCode => Object.hash(color, size);
}

/// The scroll edge the band variant draws: uBand and the fade laid over
/// what the glass reads.
@internal
@immutable
final class BandOverlay {
  const BandOverlay._(this.band, this.overlay);

  /// The band [look] in a draw whose fragment zero lies at [origin] on the
  /// screen, one fragment [scale] device pixels: [shown] (device pixels from
  /// [origin]) of the band in it, frosted by [whole] device pixels, of which
  /// [held] is in what it reads already.
  factory BandOverlay.of(
    BandLook look, {
    required Offset origin,
    required int scale,
    required Rect shown,
    required double whole,
    required double held,
  }) {
    final paint = look.paint;
    final dpr = look.devicePixelRatio;
    final from = look.origin.dy;
    double row(double y) => ((y + from) * dpr - origin.dy) / scale;
    final fade = paint.fade;
    final alpha = fade.a * paint.presence;
    return BandOverlay._(
      List.unmodifiable(<double>[
        shown.left / scale,
        shown.top / scale,
        shown.right / scale,
        shown.bottom / scale,
        sqrt(max(whole * whole - held * held, 0)) / scale,
        row(paint.whole),
        row(paint.gone),
        paint.brightness,
        fade.r * alpha,
        fade.g * alpha,
        fade.b * alpha,
        alpha,
        row(paint.lineStart),
        row(paint.lineEnd),
        paint.lineGray,
        paint.presence,
        paint.saturation,
        0,
        0,
        0,
      ]),
      List.unmodifiable(<double>[fade.r, fade.g, fade.b, alpha]),
    );
  }

  /// uBand.
  final List<double> band;

  /// uBackdropOverlay.
  final List<double> overlay;

  @override
  bool operator ==(Object other) =>
      other is BandOverlay &&
      listEquals(other.band, band) &&
      listEquals(other.overlay, overlay);

  @override
  int get hashCode => Object.hashAll(overlay);
}

/// Where a final shader variant takes each uniform the glass writes: floats
/// read from its program by name, samplers in the order they are declared.
///
/// `FragmentShader.getImageSampler` counts samplers in the order the
/// program's reflection lists them, which is not the order
/// `setImageSampler` binds them in (Flutter 3.47): in a variant with looks
/// it can put the backdrop third.
@internal
final class FinalLayout {
  /// The layout of [shader], a shader of [variant].
  FinalLayout(ui.FragmentShader shader, FinalShaderVariant variant)
    : size = _float(shader, 'uSize'),
      geometryBounds = _float(shader, 'uGeometryBounds'),
      face = _float(shader, 'uFace'),
      profile = _float(shader, 'uProfile'),
      material = _float(shader, 'uMaterial'),
      mapping = _float(shader, 'uMapping'),
      mappingEnd = _float(shader, 'uMappingEnd'),
      colorModels = _float(shader, 'uColorModelParams'),
      geometryAtlas = variant.shape ? null : _float(shader, 'uGeometryAtlas'),
      shape = variant.shape ? _float(shader, 'uShapeData') : null,
      bevel = _float(shader, 'uBevel'),
      effects = _float(shader, 'uEffects'),
      band = variant.band ? _float(shader, 'uBand') : null,
      looks = switch (variant.kind) {
        FinalShaderKind.single => 0,
        FinalShaderKind.tint => 1,
        FinalShaderKind.material => 3,
      };

  static int _float(ui.FragmentShader shader, String name) =>
      shader.getUniformFloat(name).shaderIndex;

  /// The float index of uSize.
  final int size;

  /// The float index of uGeometryBounds.
  final int geometryBounds;

  /// The float index of uFace.
  final int face;

  /// The float index of uProfile.
  final int profile;

  /// The float index of uMaterial.
  final int material;

  /// The float index of uMapping.
  final int mapping;

  /// The float index of uMappingEnd.
  final int mappingEnd;

  /// The float index of uColorModelParams.
  final int colorModels;

  /// The float index of uGeometryAtlas, in the variants that read an atlas.
  final int? geometryAtlas;

  /// The float index of uShapeData, which uRseData and uShapeInner follow,
  /// in the variants that work one shape out.
  final int? shape;

  /// The float index of uBevel.
  final int bevel;

  /// The float index of uEffects.
  final int effects;

  /// uBand, in the band variant.
  final int? band;

  /// uBackgroundTexture's sampler: what the glass reads.
  final int backdrop = 0;

  /// uGeometryTexture's sampler: the atlas, filtered. A variant that works
  /// one shape out has none of the samplers from here on.
  final int geometry = 1;

  /// uGeometryTable's sampler: the atlas, texel by texel.
  final int table = 2;

  /// The first look sampler: uLookTint, then uLookResponse and uLookShares.
  final int firstLook = 3;

  /// How many looks the variant reads.
  final int looks;
}

/// The glass's final shaders and the only code that writes them.
///
/// A shader filter takes its uniforms when it is first converted, which a
/// scene may do frames after it was made, and a paint when it records. So
/// every filter made here is converted at once and holds its draw: a later
/// draw written to the same shader cannot reach it.
@internal
final class GlassShading {
  /// Shades with [shaders], one per [FinalShaderVariant.all].
  GlassShading(this.shaders)
    : _layouts = List<FinalLayout?>.filled(shaders.length, null);

  /// The shaders, by variant.
  final List<ui.FragmentShader> shaders;

  final List<FinalLayout?> _layouts;

  /// A filter that draws [draw] over its input.
  ui.ImageFilter filter(GlassDraw draw) => shaderFilterNow(_write(draw));

  /// Draws [rect] with [draw] on [canvas]. Its edge is hard, as a filter's
  /// clip cuts.
  void paintRect(ui.Canvas canvas, Rect rect, GlassDraw draw) {
    final paint = ui.Paint()
      ..shader = _write(draw)
      ..isAntiAlias = false;
    canvas.drawRect(rect, paint);
  }

  static const _clear = <double>[0, 0, 0, 0];

  ui.FragmentShader _write(GlassDraw draw) {
    final shader = shaders[draw.variant];
    final layout = _layouts[draw.variant] ??= FinalLayout(
      shader,
      FinalShaderVariant.all[draw.variant],
    );
    assert(
      (layout.shape != null) == (draw.matte.geometry is ComputedGeometry),
      'A draw takes the variant of its geometry.',
    );
    void put(int at, List<double> values) {
      for (var i = 0; i < values.length; i++) {
        shader.setFloat(at + i, values[i]);
      }
    }

    final face = draw.face;
    final matte = draw.matte;
    final toMatte = draw.mapping.toMatte;
    final bounds = draw.mapping.backdropBounds;
    final (
      origin,
      scale,
      reduced,
      frost,
      size,
      image,
      solid,
    ) = switch (draw.reading) {
      LiveReading() => (Offset.zero, 1, 0.0, 0.0, null, null, _clear),
      CopyReading(
        :final origin,
        :final scale,
        :final reduced,
        :final frost,
        :final size,
        :final image,
      ) =>
        (origin, scale, reduced, frost, size, image, _clear),
      SolidReading(:final color, :final size) => (
        Offset.zero,
        1,
        0.0,
        0.0,
        size,
        null,
        <double>[color.r, color.g, color.b, 1],
      ),
    };
    if (size != null) put(layout.size, [size.width, size.height]);
    put(layout.geometryBounds, [
      matte.origin.dx,
      matte.origin.dy,
      matte.size.width,
      matte.size.height,
    ]);
    put(layout.face, face.face);
    // The bevel shifts what it reads by device pixels: a fragment spans
    // [scale] of them.
    if (scale != 1) shader.setFloat(layout.face + 4, face.displacement / scale);
    put(layout.profile, [
      matte.materialCenter.dx,
      matte.materialCenter.dy,
      face.wrap,
      face.gamma,
    ]);
    put(layout.material, face.material);
    put(layout.mapping, [
      toMatte.$1,
      toMatte.$2,
      toMatte.$3,
      toMatte.$4,
      toMatte.$5,
      toMatte.$6,
      face.blurFade,
      bounds.left,
      bounds.top,
      bounds.right,
      bounds.bottom,
      origin.dx,
    ]);
    shader.setFloat(layout.mappingEnd, origin.dy);
    put(layout.colorModels, face.colorModels);
    put(layout.bevel, [
      matte.refractionHeight,
      if (matte.fitsShape) 1 else 0,
      matte.halfMinor,
    ]);
    put(layout.effects, solid);
    put(layout.effects + 4, draw.glow);
    // The frost's taps lie device pixels apart.
    put(layout.effects + 16, [
      matte.shrinkAxis.dx,
      matte.shrinkAxis.dy,
      reduced,
      frost / scale,
    ]);
    put(layout.effects + 20, draw.band?.overlay ?? _clear);
    put(layout.effects + 24, [
      matte.edge.pull,
      matte.edge.pullHeight,
      matte.edge.line,
      matte.edge.halfMinor,
      matte.edge.aberration,
      matte.edge.aberrationDepth,
    ]);
    if (layout.band case final at?) put(at, draw.band!.band);
    // Bound bilinear: up to Flutter 3.47 a filter's input samples as the image
    // here says (see bilinearShaderFilter).
    switch (matte.geometry) {
      case ComputedGeometry(:final floats):
        put(layout.shape!, floats);
        shader.setImageSampler(
          layout.backdrop,
          image ?? transparentPixel,
          filterQuality: FilterQuality.low,
        );
      case AtlasGeometry(image: final atlas, :final place, :final looks):
        put(layout.geometryAtlas!, [
          place.tableX.toDouble(),
          place.tableY.toDouble(),
          place.width.toDouble(),
          place.height.toDouble(),
        ]);
        // The atlas's strips are read filtered and the looks as the
        // geometry beside them; the table texel by texel, except where a
        // texture has one filter for all its samplers (atlasTableFilter).
        shader
          ..setImageSampler(
            layout.backdrop,
            image ?? atlas,
            filterQuality: FilterQuality.low,
          )
          ..setImageSampler(
            layout.geometry,
            atlas,
            filterQuality: FilterQuality.low,
          )
          ..setImageSampler(
            layout.table,
            atlas,
            filterQuality: atlasTableFilter,
          );
        for (var i = 0; i < min(layout.looks, looks.length); i++) {
          shader.setImageSampler(
            layout.firstLook + i,
            looks[i],
            filterQuality: FilterQuality.low,
          );
        }
    }
    return shader;
  }
}
