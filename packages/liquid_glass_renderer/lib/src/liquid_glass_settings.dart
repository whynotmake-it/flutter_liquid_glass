import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';

/// Material parameters for the liquid-glass compositor.
///
/// The public surface follows the observable Apple material axes: one optical
/// profile, one transmission/tint axis, one highlight lobe, and one dielectric
/// contour. The renderer derives the paired edge highlights and the dark
/// silhouette from the same SDF, so these controls remain stable across the
/// toolbar, capsule, tab, and loupe scenes.
class LiquidGlassSettings with Equatable {
  /// Creates a material from optical, color, and lighting controls.
  ///
  /// Distances are logical pixels. Strength, wrap, directionality, and size
  /// response values conventionally use the `0` to `1` range.
  const LiquidGlassSettings({
    this.visibility = 1.0,
    this.tint = const Color.fromARGB(0, 255, 255, 255),
    this.thickness = 20.0,
    this.edgeRefraction = 106.13,
    this.refractionSpread = 0.0,
    this.backdropScale = 1.0,
    this.frost = 5.0,
    this.chromaticAberration = 0.01,
    this.saturation = 1.5,
    this.transmissionGamma = 1.0,
    this.vibrancy = 0.0,
    this.highlight = 1.0,
    this.highlightWidth = 0.0,
    this.highlightWrap = 0.25,
    this.highlightOppositeStrength = 1.0,
    this.curvatureLighting = 0.0,
    this.contourStrength = 0.0,
    this.contourWidth = 0.0,
    this.contourOffset = 0.0,
    this.contourTransmittance = 0.0,
    this.bevelShadowStrength = 0.0,
    this.bevelShadowDepth = 12.0,
    this.bevelShadowOffset = 0.0,
    this.bevelShadowDirectionality = 0.0,
    this.bevelShadowSizeResponse = 0.0,
    this.exteriorShadowSizeResponse = 0.0,
  });

  /// Restores a material vector produced by [toJson].
  factory LiquidGlassSettings.fromJson(Map<String, Object?> json) {
    double number(String key, double fallback) =>
        (json[key] as num?)?.toDouble() ?? fallback;
    final tintValue = json['tint'];
    final tint = tintValue is num
        ? Color(tintValue.toInt())
        : const Color.fromARGB(0, 255, 255, 255);
    return LiquidGlassSettings(
      visibility: number('visibility', 1),
      tint: tint,
      thickness: number('thickness', 20),
      edgeRefraction: number('edgeRefraction', 106.13),
      refractionSpread: number('refractionSpread', 0),
      backdropScale: number('backdropScale', 1),
      frost: number('frost', 5),
      chromaticAberration: number('chromaticAberration', .01),
      saturation: number('saturation', 1.5),
      transmissionGamma: number('transmissionGamma', 1),
      vibrancy: number('vibrancy', 0),
      highlight: number('highlight', 1),
      highlightWidth: number('highlightWidth', 0),
      highlightWrap: number('highlightWrap', .25),
      highlightOppositeStrength: number('highlightOppositeStrength', 1),
      curvatureLighting: number('curvatureLighting', 0),
      contourStrength: number('contourStrength', 0),
      contourWidth: number('contourWidth', 0),
      contourOffset: number('contourOffset', 0),
      contourTransmittance: number('contourTransmittance', 0),
      bevelShadowStrength: number('bevelShadowStrength', 0),
      bevelShadowDepth: number('bevelShadowDepth', 12),
      bevelShadowOffset: number('bevelShadowOffset', 0),
      bevelShadowDirectionality: number('bevelShadowDirectionality', 0),
      bevelShadowSizeResponse: number('bevelShadowSizeResponse', 0),
      exteriorShadowSizeResponse: number('exteriorShadowSizeResponse', 0),
    );
  }

  /// A light, clear preset fitted to an iOS 27 toolbar-sized capsule.
  ///
  /// This is a useful starting point, not a universal Apple-material preset:
  /// platform materials vary with appearance, control role, and accessibility
  /// settings. Override [frost] when the surrounding design needs a clearer or
  /// softer surface.
  const LiquidGlassSettings.ios27ToolbarLight({
    this.visibility = 1.0,
    this.frost = 7.0,
  }) : tint = const Color.from(
         alpha: 0.407,
         red: 253 / 255,
         green: 252 / 255,
         blue: 253 / 255,
       ),
       thickness = 12.0,
       edgeRefraction = 27.42,
       refractionSpread = 0.0,
       backdropScale = 1.0,
       chromaticAberration = 0.005,
       saturation = 0.9,
       transmissionGamma = 0.9,
       vibrancy = 0.15,
       highlight = 0.25,
       highlightWidth = 0.75,
       highlightWrap = 0.25,
       highlightOppositeStrength = 0.5,
       curvatureLighting = 0.0,
       contourStrength = 0.15,
       contourWidth = 0.65,
       contourOffset = 0.25,
       contourTransmittance = 0.8,
       bevelShadowStrength = 0.04,
       bevelShadowDepth = 18.0,
       bevelShadowOffset = 4.0,
       bevelShadowDirectionality = 0.75,
       bevelShadowSizeResponse = 0.0,
       exteriorShadowSizeResponse = 1.0;

  /// A dark-appearance preset fitted to an iOS 27 toolbar-sized capsule.
  ///
  /// Use this alongside [LiquidGlassSettings.ios27ToolbarLight] when the
  /// surrounding application follows the platform brightness.
  const LiquidGlassSettings.ios27ToolbarDark({
    this.visibility = 1.0,
    this.frost = 5.0,
  }) : tint = const Color.from(
         alpha: 0.56,
         red: 57.142857 / 255,
         green: 57.142857 / 255,
         blue: 57.142857 / 255,
       ),
       thickness = 12.0,
       edgeRefraction = 27.42,
       refractionSpread = 0.0,
       backdropScale = 1.0,
       chromaticAberration = 0.005,
       saturation = 2.6,
       transmissionGamma = 0.58,
       vibrancy = 0.1,
       highlight = 0.25,
       highlightWidth = 0.0,
       highlightWrap = 0.25,
       highlightOppositeStrength = 0.5,
       curvatureLighting = 0.0,
       contourStrength = 0.25,
       contourWidth = 0.5,
       contourOffset = 0.0,
       contourTransmittance = 0.8,
       bevelShadowStrength = 0.04,
       bevelShadowDepth = 18.0,
       bevelShadowOffset = 4.0,
       bevelShadowDirectionality = 0.75,
       bevelShadowSizeResponse = 0.0,
       exteriorShadowSizeResponse = 0.0;

  /// Creates the fitted iOS 27 toolbar material for [brightness].
  ///
  /// The light and dark appearances have independently fitted transmission
  /// curves; dark appearance is not a simple inversion of the light tint.
  factory LiquidGlassSettings.ios27Toolbar({
    required Brightness brightness,
    double visibility = 1.0,
    double? frost,
  }) => brightness == Brightness.dark
      ? LiquidGlassSettings.ios27ToolbarDark(
          visibility: visibility,
          frost: frost ?? 5.0,
        )
      : LiquidGlassSettings.ios27ToolbarLight(
          visibility: visibility,
          frost: frost ?? 7.0,
        );

  /// Creates settings from Figma-style percentage controls.
  ///
  /// [refraction] and [dispersion] use a `0` to `100` scale. [depth] and
  /// [frost] remain logical-pixel values.
  LiquidGlassSettings.figma({
    required double refraction,
    required double depth,
    required double dispersion,
    required double frost,
    double visibility = 1.0,
    Color tint = const Color.fromARGB(0, 255, 255, 255),
  }) : this(
         visibility: visibility,
         edgeRefraction: (refraction / 100) * 106.13,
         thickness: depth,
         refractionSpread: 0,
         chromaticAberration: 4 * (dispersion / 100),
         frost: frost,
         saturation: 1.5,
         tint: tint,
       );

  /// Returns the material settings supplied by the nearest glass layer.
  static LiquidGlassSettings of(BuildContext context) {
    return LiquidGlassRenderScope.of(context).settings;
  }

  /// Multiplies visible material effects for transitions from `0` to `1`.
  final double visibility;

  /// Material tint; alpha controls how strongly it mixes with the backdrop.
  final Color tint;

  /// Optical profile depth in logical pixels.
  final double thickness;

  /// Peak edge displacement in logical pixels at the optical rim. The
  /// renderer solves the internal optical index from this value.
  final double edgeRefraction;

  /// Face reach of the SDF optical profile. `0` keeps the optical slope at the
  /// physical edge thickness; `1` carries the eased slope across the full
  /// face. This is a profile/refractive-field control, not a backdrop zoom.
  final double refractionSpread;

  /// Display scale of the backdrop on the deep face of the material.
  ///
  /// `1` preserves the backdrop. Values below `1` reveal more content while
  /// values above `1` magnify. The renderer fades this mapping to identity at
  /// the SDF contour so edge refraction remains continuous. Large
  /// magnification should instead paint a higher-resolution backdrop with
  /// Flutter's [RawMagnifier] before applying glass.
  final double backdropScale;

  /// Backdrop blur sigma in logical pixels.
  ///
  /// The value is absolute and does not change with the material's size.
  final double frost;

  /// Wavelength separation for the edge displacement.
  final double chromaticAberration;

  /// Saturation applied to transmitted backdrop content.
  final double saturation;

  /// Display-referred transfer applied to transmitted content.
  final double transmissionGamma;

  /// Backdrop-aware chroma lift.
  final double vibrancy;

  /// Strength of the paired directional highlight lobe.
  final double highlight;

  /// Width of the directional highlight band in logical pixels.
  ///
  /// `0` preserves the legacy behavior of following [contourWidth]. Keeping
  /// this independent lets a thin dielectric contour coexist with the wider
  /// optical highlight visible on Apple glass.
  final double highlightWidth;

  /// Angular spread of directional highlights around the SDF contour.
  ///
  /// `0` confines the lobe to normals nearly aligned with the light axis;
  /// larger values wrap it more gradually through corners and curved edges.
  final double highlightWrap;

  /// Relative energy of the highlight opposite the light-facing rim.
  ///
  /// `0` produces only the primary lobe and `1` gives both opposing lobes
  /// equal energy. This remains in the same SDF lighting pass.
  final double highlightOppositeStrength;

  /// How strongly local boundary curvature shapes directional lighting.
  ///
  /// `0` keeps equal lighting energy on straight and curved boundary
  /// sections. `1` suppresses directional highlight and face shading on
  /// locally straight sections while preserving them around curves. The
  /// curvature field is encoded with the cached SDF geometry, so this does
  /// not add a texture sample or rendering pass.
  final double curvatureLighting;

  /// Strength of the dark dielectric contour derived from the SDF.
  final double contourStrength;

  /// Width of the dielectric contour in logical pixels.
  final double contourWidth;

  /// Signed placement of the contour relative to the mathematical boundary.
  ///
  /// Positive values move the contour outward and negative values move it
  /// inward. The contour remains derived from the same SDF as the glass and
  /// highlights, so it follows blended geometry without a canvas shadow or a
  /// second rendering pass.
  final double contourOffset;

  /// Fraction of transmitted backdrop preserved beneath the dark contour.
  ///
  /// `0` makes the contour fully absorptive at [contourStrength]; `1` keeps
  /// the backdrop unchanged while retaining the independently composited
  /// highlight. This lets the highlight eclipse the contour without a canvas
  /// stroke or another rendering pass.
  final double contourTransmittance;

  /// Strength of the ambient shadow immediately inside the raised bevel.
  final double bevelShadowStrength;

  /// Distance in logical pixels over which the bevel shadow fades inward.
  final double bevelShadowDepth;

  /// Inward offset of the inner-shadow peak from the boundary.
  final double bevelShadowOffset;

  /// How strongly the inner bevel shadow follows the configured light.
  ///
  /// `0` preserves an even ambient shadow around the whole SDF contour. `1`
  /// keeps only boundary sections whose normal axis aligns with the configured
  /// light vector (where the contour tangent is orthogonal to the light).
  /// Values between them blend the ambient and directional responses without
  /// a new texture sample or rendering pass.
  final double bevelShadowDirectionality;

  /// How strongly inner-shadow energy grows with the SDF group's size.
  ///
  /// `0` preserves the configured strength at every size. `1` keeps compact
  /// controls unchanged, then smoothly increases wall energy for larger
  /// individual or smooth-unioned surfaces. This uses existing geometry bounds
  /// and adds no texture sample or rendering pass.
  final double bevelShadowSizeResponse;

  /// How strongly caller-provided exterior shadows grow on larger surfaces.
  ///
  /// `0` preserves the supplied [BoxShadow] exactly. `1` progressively grows
  /// its energy and blur above the fitted 94-pixel control baseline.
  final double exteriorShadowSizeResponse;

  /// [tint] after applying [visibility].
  Color get effectiveTint => tint.withValues(alpha: tint.a * visibility);

  /// [thickness] after applying [visibility].
  double get effectiveThickness => thickness * visibility;

  /// [edgeRefraction] after applying [visibility].
  double get effectiveEdgeRefraction => edgeRefraction * visibility;

  /// [refractionSpread] after applying [visibility].
  double get effectiveRefractionSpread => refractionSpread * visibility;

  /// [backdropScale] interpolated from identity by [visibility].
  double get effectiveBackdropScale =>
      1 + (backdropScale.clamp(.25, 4.0) - 1) * visibility;

  /// [frost] after applying [visibility].
  double get effectiveFrost => frost * visibility;

  /// [chromaticAberration] after applying [visibility].
  double get effectiveChromaticAberration => chromaticAberration * visibility;

  /// [saturation] interpolated from neutral by [visibility].
  double get effectiveSaturation => 1 + (saturation - 1) * visibility;

  /// [transmissionGamma] interpolated from neutral by [visibility].
  double get effectiveTransmissionGamma =>
      1 + (transmissionGamma - 1) * visibility;

  /// [vibrancy] after applying [visibility].
  double get effectiveVibrancy => vibrancy * visibility;

  /// [highlight] after applying [visibility].
  double get effectiveHighlight => highlight * visibility;

  /// Effective highlight width in logical pixels.
  double get effectiveHighlightWidth => highlightWidth;

  /// Effective highlight angular wrap.
  double get effectiveHighlightWrap => highlightWrap;

  /// [highlightOppositeStrength] after applying [visibility].
  double get effectiveHighlightOppositeStrength =>
      highlightOppositeStrength * visibility;

  /// [curvatureLighting] after applying [visibility].
  double get effectiveCurvatureLighting => curvatureLighting * visibility;

  /// [contourStrength] after applying [visibility].
  double get effectiveContourStrength => contourStrength * visibility;

  /// Effective contour width in logical pixels.
  double get effectiveContourWidth => contourWidth;

  /// Effective contour offset in logical pixels.
  double get effectiveContourOffset => contourOffset;

  /// Effective transmitted fraction beneath the contour.
  double get effectiveContourTransmittance => contourTransmittance;

  /// [bevelShadowStrength] after applying [visibility].
  double get effectiveBevelShadowStrength => bevelShadowStrength * visibility;

  /// Effective bevel-shadow depth in logical pixels.
  double get effectiveBevelShadowDepth => bevelShadowDepth;

  /// Effective bevel-shadow offset in logical pixels.
  double get effectiveBevelShadowOffset => bevelShadowOffset;

  /// [bevelShadowDirectionality] after applying [visibility].
  double get effectiveBevelShadowDirectionality =>
      bevelShadowDirectionality * visibility;

  /// Effective bevel-shadow size response.
  double get effectiveBevelShadowSizeResponse => bevelShadowSizeResponse;

  /// [exteriorShadowSizeResponse] after applying [visibility].
  double get effectiveExteriorShadowSizeResponse =>
      exteriorShadowSizeResponse * visibility;

  /// Internal optical index derived from the public peak displacement. The
  /// public value remains observable and comparable across sizes.
  double get effectiveOpticalIndex {
    final depth = effectiveThickness;
    if (depth <= 0 || effectiveEdgeRefraction <= 0) return 1;
    final ratio = effectiveEdgeRefraction / (8.0 * depth);
    return math.sqrt(1.0 + ratio * ratio);
  }

  /// Shared displacement codec scale for the geometry and final passes. The
  /// public edge value is the analytic peak of the profile; using it directly
  /// avoids wasting RGBA8 codes on unreachable displacement range.
  double get effectiveDisplacementScale =>
      math.max(1e-3, 1.05 * effectiveEdgeRefraction);

  /// Returns a copy with the supplied material controls replaced.
  LiquidGlassSettings copyWith({
    double? visibility,
    Color? tint,
    double? thickness,
    double? edgeRefraction,
    double? refractionSpread,
    double? backdropScale,
    double? frost,
    double? chromaticAberration,
    double? saturation,
    double? transmissionGamma,
    double? vibrancy,
    double? highlight,
    double? highlightWidth,
    double? highlightWrap,
    double? highlightOppositeStrength,
    double? curvatureLighting,
    double? contourStrength,
    double? contourWidth,
    double? contourOffset,
    double? contourTransmittance,
    double? bevelShadowStrength,
    double? bevelShadowDepth,
    double? bevelShadowOffset,
    double? bevelShadowDirectionality,
    double? bevelShadowSizeResponse,
    double? exteriorShadowSizeResponse,
  }) => LiquidGlassSettings(
    visibility: visibility ?? this.visibility,
    tint: tint ?? this.tint,
    thickness: thickness ?? this.thickness,
    edgeRefraction: edgeRefraction ?? this.edgeRefraction,
    refractionSpread: refractionSpread ?? this.refractionSpread,
    backdropScale: backdropScale ?? this.backdropScale,
    frost: frost ?? this.frost,
    chromaticAberration: chromaticAberration ?? this.chromaticAberration,
    saturation: saturation ?? this.saturation,
    transmissionGamma: transmissionGamma ?? this.transmissionGamma,
    vibrancy: vibrancy ?? this.vibrancy,
    highlight: highlight ?? this.highlight,
    highlightWidth: highlightWidth ?? this.highlightWidth,
    highlightWrap: highlightWrap ?? this.highlightWrap,
    highlightOppositeStrength:
        highlightOppositeStrength ?? this.highlightOppositeStrength,
    curvatureLighting: curvatureLighting ?? this.curvatureLighting,
    contourStrength: contourStrength ?? this.contourStrength,
    contourWidth: contourWidth ?? this.contourWidth,
    contourOffset: contourOffset ?? this.contourOffset,
    contourTransmittance: contourTransmittance ?? this.contourTransmittance,
    bevelShadowStrength: bevelShadowStrength ?? this.bevelShadowStrength,
    bevelShadowDepth: bevelShadowDepth ?? this.bevelShadowDepth,
    bevelShadowOffset: bevelShadowOffset ?? this.bevelShadowOffset,
    bevelShadowDirectionality:
        bevelShadowDirectionality ?? this.bevelShadowDirectionality,
    bevelShadowSizeResponse:
        bevelShadowSizeResponse ?? this.bevelShadowSizeResponse,
    exteriorShadowSizeResponse:
        exteriorShadowSizeResponse ?? this.exteriorShadowSizeResponse,
  );

  /// Serializes the public material vector for example presets and tooling.
  Map<String, Object> toJson() => {
    'visibility': visibility,
    'tint': tint.toARGB32(),
    'thickness': thickness,
    'edgeRefraction': edgeRefraction,
    'refractionSpread': refractionSpread,
    'backdropScale': backdropScale,
    'frost': frost,
    'chromaticAberration': chromaticAberration,
    'saturation': saturation,
    'transmissionGamma': transmissionGamma,
    'vibrancy': vibrancy,
    'highlight': highlight,
    'highlightWidth': highlightWidth,
    'highlightWrap': highlightWrap,
    'highlightOppositeStrength': highlightOppositeStrength,
    'curvatureLighting': curvatureLighting,
    'contourStrength': contourStrength,
    'contourWidth': contourWidth,
    'contourOffset': contourOffset,
    'contourTransmittance': contourTransmittance,
    'bevelShadowStrength': bevelShadowStrength,
    'bevelShadowDepth': bevelShadowDepth,
    'bevelShadowOffset': bevelShadowOffset,
    'bevelShadowDirectionality': bevelShadowDirectionality,
    'bevelShadowSizeResponse': bevelShadowSizeResponse,
    'exteriorShadowSizeResponse': exteriorShadowSizeResponse,
  };

  @override
  List<Object?> get props => [
    visibility,
    tint,
    thickness,
    edgeRefraction,
    refractionSpread,
    backdropScale,
    frost,
    chromaticAberration,
    saturation,
    transmissionGamma,
    vibrancy,
    highlight,
    highlightWidth,
    highlightWrap,
    highlightOppositeStrength,
    curvatureLighting,
    contourStrength,
    contourWidth,
    contourOffset,
    contourTransmittance,
    bevelShadowStrength,
    bevelShadowDepth,
    bevelShadowOffset,
    bevelShadowDirectionality,
    bevelShadowSizeResponse,
    exteriorShadowSizeResponse,
  ];
}
