import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/painting/glass_color_parameters.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_backdrop_filter.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/painting/rect_scaling.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/plan/band_look.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/atlas_lease.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_frost.dart'
    show transparentPixel;
import 'package:liquid_glass_renderer/src/rendering/copy_read.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';
import 'package:liquid_glass_renderer/src/rendering/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_filter.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_uniforms.dart';
import 'package:liquid_glass_renderer/src/rendering/shape_set.dart';

/// One draw of the final glass shader: every uniform and sampler it reads,
/// in sections that each own their uniforms.
///
/// [GlassShading] writes all of a draw before it makes a filter or paint of
/// it, so no draw depends on what another left in the shader.
@internal
@immutable
final class GlassDraw {
  /// Creates the draw, with a [band] exactly when its [variant] draws one.
  GlassDraw({
    required this.variant,
    required this.face,
    required GlowUniforms glow,
    required this.geometry,
    required this.mapping,
    this.reading = const BackdropReading(),
    this.band,
  }) : glow = FinalShaderVariant.all[variant].glows ? glow : noGlowUniforms,
       assert(
         (band != null) == FinalShaderVariant.all[variant].band,
         'A band variant draws a band, and no other variant does.',
       );

  /// The index in [FinalShaderVariant.all] of the shader it draws with.
  final int variant;

  /// The material: settings, appearance and color models.
  final GlassFace face;

  /// The touch glow, none where the variant draws none
  /// ([FinalShaderVariant.glows]).
  final GlowUniforms glow;

  /// Where the shader reads its shapes.
  final GeometryBinding geometry;

  /// From fragment coordinates into the matte.
  final MatteMapping mapping;

  /// What the shader reads under the glass.
  final GlassReading reading;

  /// The scroll edge the band variant draws beside the glass.
  final BandUniforms? band;

  /// This draw with the parts given changed.
  GlassDraw copyWith({MatteMapping? mapping, GlassReading? reading}) =>
      GlassDraw(
        variant: variant,
        face: face,
        glow: glow,
        geometry: geometry,
        mapping: mapping ?? this.mapping,
        reading: reading ?? this.reading,
        band: band,
      );

  @override
  bool operator ==(Object other) =>
      other is GlassDraw &&
      other.variant == variant &&
      other.face == face &&
      _sameLanes(other.glow, glow) &&
      other.geometry == geometry &&
      other.mapping == mapping &&
      other.reading == reading &&
      other.band == band;

  @override
  int get hashCode => Object.hash(variant, geometry, mapping, reading);

  static bool _sameLanes(GlowUniforms a, GlowUniforms b) =>
      identical(a, b) ||
      a.length == b.length &&
          a.entries.every((lane) => listEquals(b[lane.key], lane.value));
}

/// The final shader's floats one layout of the glass's material sets.
@internal
@immutable
final class GlassFace {
  const GlassFace._({required this.face, required this.colorModels});

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
    required WornAppearance appearance,
    required List<GlassColorParameters> colorModels,
    required double devicePixelRatio,
    required bool blurs,
  }) {
    final dpr = devicePixelRatio;
    final tint = appearance.tint;
    final model = appearance.colorModel;
    final contour = (settings.contourStrength.clamp(0.0, 1.0) * 255).round();
    return GlassFace._(
      face: laneBlock(FaceLane.values, {
        FaceLane.tint: [
          _channel(tint.r),
          _channel(tint.g),
          _channel(tint.b),
          _channel(tint.a),
        ],
        FaceLane.displacementScale: [settings.effectiveDisplacementScale * dpr],
        FaceLane.dispersion: [settings.dispersion],
        FaceLane.glintStrength: [settings.glintStrength],
        FaceLane.backdropScale: [1 - settings.effectiveBackdropShrink],
        FaceLane.saturation: [model.saturation],
        FaceLane.contourAlpha: [contour / 255],
        FaceLane.rimReach: [rimReach(settings, devicePixelRatio: dpr)],
        FaceLane.glintWidth: [GlassRim.glintWidth * dpr],
        FaceLane.edgeWidth: [settings.contourWidth * dpr],
        FaceLane.contourDirectionality: [settings.contourDirectionality],
        FaceLane.vibrancy: [model.vibrancy],
        FaceLane.bevelShadowStrength: [settings.bevelShadowStrength],
        FaceLane.bevelShadowDepth: [GlassRim.bevelShadowDepth * dpr],
        FaceLane.bevelShadowOffset: [GlassRim.bevelShadowOffset * dpr],
        FaceLane.colorModelCode: [colorModelCode(model, colorModels)],
        FaceLane.visibility: [appearance.visibility],
        FaceLane.blurFade: [if (blurs) 1 else 0],
        FaceLane.transmissionGamma: [model.transmissionGamma],
        FaceLane.readDepth: [readDepth(settings, devicePixelRatio: dpr)],
      }),
      colorModels: List.unmodifiable(<double>[
        for (var i = 0; i < colorModelSlotCount; i++)
          ...i < colorModels.length
              ? colorModels[i].toShaderParameters(
                  settings.effectiveSliderPosition,
                )
              : _noModel,
      ]),
    );
  }

  static double _channel(double value) =>
      (value * 255).round().clamp(0, 255) / 255;

  // A slot no shape reads.
  static final _noModel = List<double>.filled(
    laneBlockFloats(ColorModelLane.values),
    0,
  );

  static final _displacementAt = laneOffset(
    FaceLane.values,
    FaceLane.displacementScale,
  );

  static final _blurFadeAt = laneOffset(FaceLane.values, FaceLane.blurFade);

  /// uFace, by [FaceLane].
  final List<double> face;

  /// uColorModelParams: three slots of the color models.
  final List<double> colorModels;

  /// The bevel's displacement, which reads the backdrop by device pixels.
  double get displacement => face[_displacementAt];

  /// 1 where the frost fades out with visibility.
  double get blurFade => face[_blurFadeAt];

  /// This face over a copy its haze is mixed into. The haze is drawn at full
  /// strength whatever the glass's visibility, so such glass fades by its
  /// alpha as frosted glass does, and not to the hazed copy.
  GlassFace get hazed => blurFade == 1
      ? this
      : GlassFace._(
          face: List.unmodifiable(<double>[...face]..[_blurFadeAt] = 1),
          colorModels: colorModels,
        );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlassFace &&
          listEquals(other.face, face) &&
          listEquals(other.colorModels, colorModels);

  @override
  int get hashCode => Object.hash(face[0], displacement, blurFade);
}

/// How deep inside the edge of glass drawn with [settings] its rim lighting
/// and contour reach, in device pixels: the glint's bleed, the contour's
/// half pixel and the bevel shadow's strip, each only where it draws.
@internal
double rimReach(
  LiquidGlassSettings settings, {
  required double devicePixelRatio,
}) {
  final dpr = devicePixelRatio;
  var rim = 0.0;
  if (settings.glintStrength > 0) {
    rim = max(rim, GlassRim.glintWidth * dpr * GlassGlint.bleedReach);
  }
  if (settings.contourStrength > 0 && settings.contourWidth > 0) {
    rim = max(rim, 0.5);
  }
  if (settings.bevelShadowStrength >= 0.001) {
    rim = max(
      rim,
      _saturatingSmoothstep(
        (GlassRim.bevelShadowDepth + GlassRim.bevelShadowOffset) * dpr,
      ),
    );
  }
  return rim;
}

/// How deep into glass drawn with [settings] the final shader reads its
/// geometry, in device pixels: a pixel past the bevel and the rim, deeper
/// than which only coverage reads the distance.
@internal
double readDepth(
  LiquidGlassSettings settings, {
  required double devicePixelRatio,
}) =>
    max(
      settings.effectiveRefractionHeight * devicePixelRatio,
      rimReach(settings, devicePixelRatio: devicePixelRatio),
    ) +
    1;

/// All a change of settings asks of the geometry of glass drawn with them
/// at a [devicePixelRatio]: how deep into the glass the final shader reads
/// it ([inward]), how far its contour reaches out ([contourOutset]) and
/// whether its shapes lean ([leans]).
@internal
@immutable
final class GeometryNeed {
  /// The need of glass drawn with [settings] at [devicePixelRatio].
  factory GeometryNeed.of(
    LiquidGlassSettings settings, {
    required double devicePixelRatio,
  }) {
    final dpr = devicePixelRatio;
    final exactInward = readDepth(settings, devicePixelRatio: dpr);
    var inward = 1.0;
    while (inward < exactInward) {
      inward *= _inwardBucketGrowth;
    }
    return GeometryNeed._(
      devicePixelRatio: dpr,
      inward: inward,
      exactInward: exactInward,
      contourOutset: settings.contourWidth <= 0
          ? 0
          : max(0.5 / dpr, settings.contourWidth + 1 / dpr),
      leans: settings.refractionFitsShape,
    );
  }

  const GeometryNeed._({
    required this.devicePixelRatio,
    required this.inward,
    required this.exactInward,
    required this.contourOutset,
    required this.leans,
  });

  /// The device pixel ratio the geometry is encoded at.
  final double devicePixelRatio;

  /// How deep into the glass its geometry is encoded, in device pixels.
  final double inward;

  /// [inward] before it was bucketed.
  final double exactInward;

  /// How far a contour reaches out of a shape, in logical pixels.
  final double contourOutset;

  /// Whether the shapes are encoded leaning
  /// ([LiquidGlassSettings.refractionFitsShape]).
  final bool leans;

  /// The room a buffer keeps around its shapes, in logical pixels.
  double get room => max(0.5 / devicePixelRatio, contourOutset);

  /// How deep into the glass and how far out of it the geometry is tiled,
  /// in device pixels.
  GlassReach get reach => GlassReach(
    inward: inward,
    exactInward: exactInward,
    outward: room * devicePixelRatio + 1,
    coarseTexel: devicePixelRatio >= 2 ? 4 : 2,
  );

  /// Whether geometry encoded for this need serves [other].
  bool covers(GeometryNeed other) =>
      devicePixelRatio == other.devicePixelRatio &&
      contourOutset == other.contourOutset &&
      leans == other.leans &&
      inward >= other.inward;

  @override
  bool operator ==(Object other) =>
      other is GeometryNeed &&
      other.devicePixelRatio == devicePixelRatio &&
      other.inward == inward &&
      other.contourOutset == contourOutset &&
      other.leans == leans;

  @override
  int get hashCode =>
      Object.hash(devicePixelRatio, inward, contourOutset, leans);
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
  /// The geometry in the atlas of [lease].
  const AtlasGeometry(this.lease);

  /// The atlas of glass that has no geometry yet, which no renderer lent.
  static final AtlasGeometry none = AtlasGeometry(
    AtlasLease(image: transparentPixel, place: AtlasLayout.unplaced),
  );

  /// The atlas, lent by the renderer that drew it.
  final AtlasLease lease;

  @override
  bool operator ==(Object other) =>
      other is AtlasGeometry && other.lease == lease;

  @override
  int get hashCode => lease.hashCode;
}

/// The geometry of glass that is one shape, which the shader works out at
/// each fragment (shape_geometry.glsl): nothing is tiled, drawn into a page
/// or submitted for it.
@internal
final class ComputedGeometry extends GlassGeometry {
  /// The geometry of [shape], one shape in the geometry buffer's pixels.
  ComputedGeometry(ShapeSet shape)
    : assert(shape.count == 1, 'The shader works out one shape.'),
      shapeData = shape.shapes,
      rseData = List.unmodifiable([
        ...shape.superellipses,
        ...shape.superellipsesLower,
      ]),
      inner = List.unmodifiable(switch (Tiling.innerBoxOf(shape, 0)) {
        (final width, final height, final radius) => [
          width,
          height,
          radius,
          shape.at(0, ShapeLane.distanceScale),
        ],
        null => const [0.0, 0.0, 0.0, 0.0],
      });

  /// uShapeData: the shape's row.
  final List<double> shapeData;

  /// uRseData: its superellipse, then a pair's bottom half.
  final List<double> rseData;

  /// uShapeInner: the rounded box it holds and its distance scale, zeros
  /// where none is known.
  final List<double> inner;

  @override
  bool operator ==(Object other) =>
      other is ComputedGeometry &&
      listEquals(other.shapeData, shapeData) &&
      listEquals(other.rseData, rseData) &&
      listEquals(other.inner, inner);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(shapeData),
    Object.hashAll(rseData),
    Object.hashAll(inner),
  );
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
/// lies, with what the glass's settings give the bevel.
@internal
@immutable
final class GeometryBinding {
  /// Creates the binding. Rects, points and sizes are in device pixels.
  const GeometryBinding({
    required this.source,
    required this.origin,
    required this.size,
    required this.refractionHeight,
    required this.fitsShape,
    required this.materialCenter,
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
  final GlassGeometry source;

  /// Where the geometry buffer's top-left lies.
  final Offset origin;

  /// The geometry buffer's size, one texel a pixel.
  final Size size;

  /// How far in the refraction reaches.
  final double refractionHeight;

  /// Whether refraction fits the shape.
  final bool fitsShape;

  /// The material's center, in the matte.
  final Offset materialCenter;

  /// uBackdropPull and uBackdropAberration.
  final GlassEdgeReads edge;

  @override
  bool operator ==(Object other) =>
      other is GeometryBinding &&
      other.source == source &&
      other.origin == origin &&
      other.size == size &&
      other.refractionHeight == refractionHeight &&
      other.fitsShape == fitsShape &&
      other.materialCenter == materialCenter &&
      other.edge == edge;

  @override
  int get hashCode => Object.hash(
    source,
    origin,
    size,
    materialCenter,
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
  /// [origin] on the screen, in device pixels, one fragment [targetShare] of
  /// them, through [screenToMatte] (logical pixels) into the matte.
  /// [backdropBounds] is in the matte's logical pixels, null for none.
  factory MatteMapping.of(
    Matrix4 screenToMatte, {
    required double devicePixelRatio,
    Offset origin = Offset.zero,
    double targetShare = 1,
    Rect? backdropBounds,
  }) {
    final dpr = devicePixelRatio;
    final o = MatrixUtils.transformPoint(screenToMatte, Offset.zero);
    final ax = MatrixUtils.transformPoint(screenToMatte, const Offset(1, 0));
    final ay = MatrixUtils.transformPoint(screenToMatte, const Offset(0, 1));
    final bounds = backdropBounds ?? Rect.largest;
    return MatteMapping(
      (
        (ax.dx - o.dx) * targetShare,
        (ay.dx - o.dx) * targetShare,
        (ax.dy - o.dy) * targetShare,
        (ay.dy - o.dy) * targetShare,
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

/// The backdrop a filter is given: the screen's, or a layer's corner the
/// filter reads as the screen.
@internal
final class BackdropReading extends GlassReading {
  /// The reading.
  const BackdropReading();
}

/// A copy of the backdrop, as [GlassSampling] lays it out.
@internal
final class CopyReading extends GlassReading {
  /// The copy [sampling] describes.
  CopyReading(GlassSampling sampling)
    : origin = sampling.image == null ? Offset.zero : sampling.origin,
      targetShare = sampling.targetShare,
      reduced = sampling.reduced,
      frost = sampling.frost,
      size = sampling.size,
      image = sampling.image;

  /// uBackdropOrigin: where a paint's fragment zero lies on the screen;
  /// zero for a filter, whose fragments start there.
  final Offset origin;

  /// Device pixels per fragment.
  final int targetShare;

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
      other.targetShare == targetShare &&
      other.reduced == reduced &&
      other.frost == frost &&
      other.size == size;

  @override
  int get hashCode => Object.hash(
    identityHashCode(image),
    origin,
    targetShare,
    reduced,
    frost,
    size,
  );
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

/// The scroll edge the band variant draws: uBand.
@internal
@immutable
final class BandUniforms {
  const BandUniforms._(this.floats);

  /// The band [look] in a draw whose fragment zero lies at [origin] on the
  /// screen, one fragment [targetShare] device pixels: [shown] (device pixels
  /// from [origin]) of the band in it, frosted by [whole] device pixels, of
  /// which [held] is in what it reads already.
  factory BandUniforms.of(
    BandLook look, {
    required Offset origin,
    required int targetShare,
    required Rect shown,
    required double whole,
    required double held,
  }) {
    final band = look.band;
    final dpr = look.devicePixelRatio;
    final from = look.origin.dy;
    double row(double y) => ((y + from) * dpr - origin.dy) / targetShare;
    final fade = band.fade;
    final alpha = fade.a * band.presence;
    final dissolve = look.dissolve;
    final (lineStart, lineEnd) = band.lineRows(
      look.shown.shift(-look.origin),
      dpr,
    );
    final line = band.drawnLine;
    return BandUniforms._(
      laneBlock(BandLane.values, {
        BandLane.rect: [
          shown.left / targetShare,
          shown.top / targetShare,
          shown.right / targetShare,
          shown.bottom / targetShare,
        ],
        BandLane.frost: [
          sqrt(max(whole * whole - held * held, 0)) / targetShare,
        ],
        BandLane.fadeWhole: [row(dissolve.whole)],
        BandLane.fadeGone: [row(dissolve.gone)],
        BandLane.brightness: [band.drawnBrightness],
        BandLane.fade: [fade.r * alpha, fade.g * alpha, fade.b * alpha, alpha],
        BandLane.hairlineRows: [row(lineStart), row(lineEnd)],
        BandLane.hairlineAlpha: [line.a],
        BandLane.presence: [band.presence],
        BandLane.saturation: [band.drawnSaturation],
        BandLane.hairlineColor: [line.r, line.g, line.b],
      }),
    );
  }

  /// uBand, by [BandLane].
  final List<double> floats;

  @override
  bool operator ==(Object other) =>
      other is BandUniforms && listEquals(other.floats, floats);

  @override
  int get hashCode => Object.hashAll(floats);
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
    : size = uniformAt(shader, 'uSize'),
      geometry = uniformAt(shader, 'uGeometry'),
      face = uniformAt(shader, 'uFace'),
      mapping = uniformAt(shader, 'uMapping'),
      colorModels = uniformAt(shader, 'uColorModelParams'),
      atlasPlace = variant.shape ? null : uniformAt(shader, 'uAtlasPlace'),
      shape = variant.shape
          ? (
              data: uniformAt(shader, 'uShapeData'),
              rse: uniformAt(shader, 'uRseData'),
              inner: uniformAt(shader, 'uShapeInner'),
            )
          : null,
      effects = uniformAt(shader, 'uEffects'),
      band = variant.band ? uniformAt(shader, 'uBand') : null,
      looks = variant.kind.looks.count;

  /// The float index of uSize.
  final int size;

  /// The float index of uGeometry.
  final int geometry;

  /// The float index of uFace.
  final int face;

  /// The float index of uMapping.
  final int mapping;

  /// The float index of uColorModelParams.
  final int colorModels;

  /// The float index of uAtlasPlace, in the variants that read an atlas.
  final int? atlasPlace;

  /// The float indices of uShapeData, uRseData and uShapeInner, in the
  /// variants that work one shape out.
  final ({int data, int rse, int inner})? shape;

  /// The float index of uEffects.
  final int effects;

  /// uBand, in the band variant.
  final int? band;

  /// uBackgroundTexture's sampler: what the glass reads.
  final int backdrop = 0;

  /// uAtlas's sampler: the atlas, filtered. A variant that works
  /// one shape out has none of the samplers from here on.
  final int atlas = 1;

  /// uAtlasTable's sampler: the atlas, texel by texel.
  final int table = 2;

  /// The first look sampler: uLookTint, then uLookResponse and uLookWeights.
  final int firstLook = 3;

  /// How many looks the variant reads.
  final int looks;
}

/// The glass's final shaders and the code that writes their draws.
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
      (layout.shape != null) == (draw.geometry.source is ComputedGeometry),
      'A draw takes the variant of its geometry.',
    );
    void put(int at, List<double> values) => putFloats(shader, at, values);

    final face = draw.face;
    final binding = draw.geometry;
    final toMatte = draw.mapping.toMatte;
    final bounds = draw.mapping.backdropBounds;
    final (
      origin,
      targetShare,
      reduced,
      frost,
      size,
      image,
      solid,
    ) = switch (draw.reading) {
      BackdropReading() => (Offset.zero, 1, 0.0, 0.0, null, null, _clear),
      CopyReading(
        :final origin,
        :final targetShare,
        :final reduced,
        :final frost,
        :final size,
        :final image,
      ) =>
        (origin, targetShare, reduced, frost, size, image, _clear),
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
    putLanes(shader, layout.geometry, GeometryLane.values, {
      GeometryLane.geometryOffset: [binding.origin.dx, binding.origin.dy],
      GeometryLane.geometrySize: [binding.size.width, binding.size.height],
      GeometryLane.materialCenter: [
        binding.materialCenter.dx,
        binding.materialCenter.dy,
      ],
      GeometryLane.refractionHeight: [binding.refractionHeight],
      GeometryLane.refractionFits: [if (binding.fitsShape) 1 else 0],
    });
    put(layout.face, face.face);
    if (targetShare != 1) {
      put(
        layout.face + GlassFace._displacementAt,
        [face.displacement / targetShare],
      );
    }
    putLanes(shader, layout.mapping, MappingLane.values, {
      MappingLane.filterToMatteBasis: [
        toMatte.$1,
        toMatte.$2,
        toMatte.$3,
        toMatte.$4,
      ],
      MappingLane.backdropBounds: [
        bounds.left,
        bounds.top,
        bounds.right,
        bounds.bottom,
      ],
      MappingLane.filterToMatteOffset: [toMatte.$5, toMatte.$6],
      MappingLane.backdropOrigin: [origin.dx, origin.dy],
    });
    put(layout.colorModels, face.colorModels);
    putLanes(shader, layout.effects, EffectsLane.values, {
      EffectsLane.solidBackdrop: solid,
      ...draw.glow,
      EffectsLane.backdropReduced: [reduced],
      EffectsLane.backdropFrost: [frost / targetShare],
      EffectsLane.backdropPull: [
        binding.edge.pull,
        binding.edge.pullHeight,
        binding.edge.line,
        binding.edge.halfMinor,
      ],
      EffectsLane.backdropAberration: [
        binding.edge.aberration,
        binding.edge.aberrationDepth,
      ],
    });
    if (layout.band case final at?) put(at, draw.band!.floats);
    // Bound bilinear: up to Flutter 3.47 a filter's input samples as the image
    // here says (see bilinearShaderFilter).
    switch (binding.source) {
      case ComputedGeometry(:final shapeData, :final rseData, :final inner):
        final at = layout.shape!;
        put(at.data, shapeData);
        put(at.rse, rseData);
        put(at.inner, inner);
        shader.setImageSampler(
          layout.backdrop,
          image ?? transparentPixel,
          filterQuality: FilterQuality.low,
        );
      case AtlasGeometry(
        lease: AtlasLease(image: final atlas, :final place, :final looks),
      ):
        putLanes(shader, layout.atlasPlace!, AtlasPlaceLane.values, {
          AtlasPlaceLane.tableOrigin: [
            place.tableX.toDouble(),
            place.tableY.toDouble(),
          ],
          AtlasPlaceLane.textureSize: [
            place.width.toDouble(),
            place.height.toDouble(),
          ],
        });
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
            layout.atlas,
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

double _saturatingSmoothstep(double depth) => depth * 1.001 + 0.01;

const double _inwardBucketGrowth = 1.5;
