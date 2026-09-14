import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';

/// Material parameters for the liquid-glass compositor.
///
/// This object contains the optical profile and shared surface lighting.
/// Per-shape color response and materialization belong to
/// [LiquidGlassAppearance]. The renderer derives paired edge highlights and
/// the dark silhouette from the same SDF, so these controls remain stable
/// across the toolbar, capsule, tab, and loupe scenes.
class LiquidGlassSettings with Equatable {
  /// Creates a material from optical and lighting controls.
  ///
  /// Distances are logical pixels. Strength, wrap, directionality, and size
  /// response values conventionally use the `0` to `1` range.
  const LiquidGlassSettings({
    this.thickness = 20.0,
    this.edgeRefraction = 106.13,
    this.refractionSpread = 0.0,
    this.backdropScale = 1.0,
    this.frost = 5.0,
    this.chromaticAberration = 0.01,
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
    return LiquidGlassSettings(
      thickness: number('thickness', 20),
      edgeRefraction: number('edgeRefraction', 106.13),
      refractionSpread: number('refractionSpread', 0),
      backdropScale: number('backdropScale', 1),
      frost: number('frost', 5),
      chromaticAberration: number('chromaticAberration', .01),
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

  /// Light-mode structural settings fitted to an iOS 27 toolbar capsule.
  ///
  /// This is a useful starting point, not a universal Apple-material preset:
  /// platform materials vary with appearance, control role, and accessibility
  /// settings. Override [frost] when the surrounding design needs a clearer or
  /// softer surface.
  const LiquidGlassSettings.ios27ToolbarLight({
    this.frost = 7.0,
  }) : thickness = 12.0,
       edgeRefraction = 27.42,
       refractionSpread = 0.0,
       backdropScale = 1.0,
       chromaticAberration = 0.005,
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

  /// Dark-mode structural settings fitted to an iOS 27 toolbar capsule.
  ///
  /// Use this alongside [LiquidGlassSettings.ios27ToolbarLight] when the
  /// surrounding application follows the platform brightness.
  const LiquidGlassSettings.ios27ToolbarDark({
    this.frost = 5.0,
  }) : thickness = 12.0,
       edgeRefraction = 27.42,
       refractionSpread = 0.0,
       backdropScale = 1.0,
       chromaticAberration = 0.005,
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

  /// Creates fitted iOS 27 toolbar structural settings for [brightness].
  factory LiquidGlassSettings.ios27Toolbar({
    required Brightness brightness,
    double? frost,
  }) => brightness == Brightness.dark
      ? LiquidGlassSettings.ios27ToolbarDark(
          frost: frost ?? 5.0,
        )
      : LiquidGlassSettings.ios27ToolbarLight(
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
  }) : this(
         edgeRefraction: (refraction / 100) * 106.13,
         thickness: depth,
         refractionSpread: 0,
         chromaticAberration: 4 * (dispersion / 100),
         frost: frost,
       );

  /// Returns the material settings supplied by the nearest glass layer.
  static LiquidGlassSettings of(BuildContext context) {
    return LiquidGlassRenderScope.of(context).settings;
  }

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

  /// Effective optical thickness.
  double get effectiveThickness => thickness;

  /// Effective peak edge displacement.
  double get effectiveEdgeRefraction => edgeRefraction;

  /// Effective optical face reach.
  double get effectiveRefractionSpread => refractionSpread;

  /// Effective backdrop scale constrained to the supported range.
  double get effectiveBackdropScale => backdropScale.clamp(.25, 4.0);

  /// Effective backdrop blur sigma.
  double get effectiveFrost => frost;

  /// Effective chromatic aberration.
  double get effectiveChromaticAberration => chromaticAberration;

  /// Effective highlight strength.
  double get effectiveHighlight => highlight;

  /// Effective highlight width in logical pixels.
  double get effectiveHighlightWidth => highlightWidth;

  /// Effective highlight angular wrap.
  double get effectiveHighlightWrap => highlightWrap;

  /// Effective opposite-highlight strength.
  double get effectiveHighlightOppositeStrength => highlightOppositeStrength;

  /// Effective curvature-lighting response.
  double get effectiveCurvatureLighting => curvatureLighting;

  /// Effective contour strength.
  double get effectiveContourStrength => contourStrength;

  /// Effective contour width in logical pixels.
  double get effectiveContourWidth => contourWidth;

  /// Effective contour offset in logical pixels.
  double get effectiveContourOffset => contourOffset;

  /// Effective transmitted fraction beneath the contour.
  double get effectiveContourTransmittance => contourTransmittance;

  /// Effective bevel-shadow strength.
  double get effectiveBevelShadowStrength => bevelShadowStrength;

  /// Effective bevel-shadow depth in logical pixels.
  double get effectiveBevelShadowDepth => bevelShadowDepth;

  /// Effective bevel-shadow offset in logical pixels.
  double get effectiveBevelShadowOffset => bevelShadowOffset;

  /// Effective bevel-shadow directionality.
  double get effectiveBevelShadowDirectionality => bevelShadowDirectionality;

  /// Effective bevel-shadow size response.
  double get effectiveBevelShadowSizeResponse => bevelShadowSizeResponse;

  /// Effective exterior-shadow size response.
  double get effectiveExteriorShadowSizeResponse => exteriorShadowSizeResponse;

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
    double? thickness,
    double? edgeRefraction,
    double? refractionSpread,
    double? backdropScale,
    double? frost,
    double? chromaticAberration,
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
    thickness: thickness ?? this.thickness,
    edgeRefraction: edgeRefraction ?? this.edgeRefraction,
    refractionSpread: refractionSpread ?? this.refractionSpread,
    backdropScale: backdropScale ?? this.backdropScale,
    frost: frost ?? this.frost,
    chromaticAberration: chromaticAberration ?? this.chromaticAberration,
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
    'thickness': thickness,
    'edgeRefraction': edgeRefraction,
    'refractionSpread': refractionSpread,
    'backdropScale': backdropScale,
    'frost': frost,
    'chromaticAberration': chromaticAberration,
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
    thickness,
    edgeRefraction,
    refractionSpread,
    backdropScale,
    frost,
    chromaticAberration,
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
