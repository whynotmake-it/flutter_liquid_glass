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
    this.refractionHeight = 20.0,
    this.refractionAmount = 60.0,
    this.refractionFitsShape = true,
    this.smoothRefraction = true,
    this.magnification = 1.0,
    this.frost = 5.0,
    this.chromaticAberration = 0.0,
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
  ///
  /// Vectors written before the refraction model was simplified are still
  /// accepted: `thickness` maps to [refractionHeight], `edgeRefraction` to
  /// [refractionAmount] (both describe the displacement at the silhouette)
  /// and `backdropScale` to [magnification]. `refractionSpread` has no
  /// equivalent and is ignored; a [refractionHeight] of at least half the
  /// shape's short side gives the same full-face lens.
  factory LiquidGlassSettings.fromJson(Map<String, Object?> json) {
    double number(String key, double fallback) =>
        (json[key] as num?)?.toDouble() ?? fallback;
    double legacy(String key, String legacyKey, double fallback) =>
        number(key, number(legacyKey, fallback));
    return LiquidGlassSettings(
      refractionHeight: legacy('refractionHeight', 'thickness', 20),
      refractionAmount: legacy('refractionAmount', 'edgeRefraction', 60),
      refractionFitsShape: switch (json['refractionFitsShape']) {
        final bool value => value,
        'false' => false,
        _ => true,
      },
      smoothRefraction: switch (json['smoothRefraction']) {
        final bool value => value,
        'false' => false,
        _ => true,
      },
      magnification: legacy('magnification', 'backdropScale', 1),
      frost: number('frost', 5),
      chromaticAberration: number('chromaticAberration', 0),
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
  }) : refractionHeight = 20.0,
       refractionAmount = 60.0,
       refractionFitsShape = true,
       smoothRefraction = true,
       magnification = 1.0,
       chromaticAberration = 0.0,
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
  }) : refractionHeight = 20.0,
       refractionAmount = 60.0,
       refractionFitsShape = true,
       smoothRefraction = true,
       magnification = 1.0,
       chromaticAberration = 0.0,
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

  /// Optics of iOS 27 `.clear` glass at the Settings Liquid Glass slider
  /// position [tintAmount] (`0` Clear, `1` Tinted): the full 20 pt / 60 pt
  /// lens on every shape and the fitted clear-glass blur,
  /// [ios27ClearFrost]. Lighting uses the defaults.
  ///
  /// At slider 0 the blur is 0.35 pt. Up to about 3.5x device pixel ratio
  /// that stays within the renderer's 1.25 device-pixel in-pass kernel, so
  /// it costs no blur pass (measured within noise on Metal). Larger slider
  /// positions need a real blur and use the blur pass.
  /// Pass [frost] to override, for example `frost: 0` for unsoftened glass.
  factory LiquidGlassSettings.ios27Clear({
    double tintAmount = 0,
    double? frost,
  }) => LiquidGlassSettings(
    frost: frost ?? ios27ClearFrost(tintAmount),
    refractionFitsShape: false,
  );

  /// Creates settings from Figma-style percentage controls.
  ///
  /// [refraction] and [dispersion] use a `0` to `100` scale. [depth] and
  /// [frost] remain logical-pixel values. [depth] is the bevel
  /// ([refractionHeight]); `100` [refraction] pulls content from four bevel
  /// widths inside the silhouette.
  LiquidGlassSettings.figma({
    required double refraction,
    required double depth,
    required double dispersion,
    required double frost,
  }) : this(
         refractionHeight: depth,
         refractionAmount: (refraction / 100) * 4 * depth,
         chromaticAberration: 4 * (dispersion / 100),
         frost: frost,
       );

  /// Backdrop blur of iOS 27 `.clear` glass, in logical pixels, for the
  /// Settings Liquid Glass slider position [tintAmount] (`0` Clear, `1`
  /// Tinted).
  ///
  /// Clear glass has no wash or tint at any position; the slider only
  /// blurs. The fit to the Reduce Motion off checkpoints stays nearly sharp
  /// up to the slider's middle tick, then frosts quickly: 0.35 pt at 0,
  /// about 1.3 at 0.5, 4.6 at 0.75 and 16 at 1.
  static double ios27ClearFrost(double tintAmount) {
    final amount = tintAmount.clamp(0.0, 1.0);
    return 0.35 *
        math.exp(
          2.6 * math.min(amount, 0.5) + 5.1 * math.max(amount - 0.5, 0.0),
        );
  }

  /// Returns the material settings supplied by the nearest glass layer.
  static LiquidGlassSettings of(BuildContext context) {
    return LiquidGlassRenderScope.of(context).settings;
  }

  /// Width of the refracting bevel in logical pixels, measured inward from
  /// the silhouette.
  ///
  /// Glass is modeled as a flat face with a rounded bevel of this width.
  /// Only the bevel refracts; the face beyond it shows the backdrop
  /// undisplaced. Apple calls this the refraction height; iOS 27 glass
  /// measures `20`, the text loupe `8`. See [refractionFitsShape] for how
  /// small shapes limit it.
  final double refractionHeight;

  /// How far inside the silhouette, in logical pixels, the outermost pixel
  /// of the glass samples the backdrop.
  ///
  /// The displacement falls off across the bevel as a quarter circle,
  /// `refractionAmount * (1 - sqrt(1 - x * x))` with `x` going from `1` at
  /// the silhouette to `0` at [refractionHeight], so the bevel joins the
  /// face without a crease. The ratio to [refractionHeight] sets how
  /// rod-like the rim reads: above `1`, content near the rim is mirrored.
  /// iOS 27 glass measures `60`, the text loupe `28`. `0` disables
  /// refraction.
  final double refractionAmount;

  /// Whether small shapes shrink the lens to fit.
  ///
  /// When `true`, as on iOS 27 regular glass, buttons and toolbars, the
  /// bevel is at most a quarter of the shape's short side and the rim
  /// samples no deeper than the shape's center line. A 63 pt tall button
  /// therefore refracts with a height of about `16` and an amount of about
  /// `32`, while large surfaces keep the configured values.
  ///
  /// When `false`, as on iOS 27 `.clear` glass, the configured lens is kept
  /// until the bevel would pass the center line; below that the whole lens
  /// scales down with the shape.
  final bool refractionFitsShape;

  /// Whether the backdrop is sampled bilinearly instead of from the nearest
  /// pixel. On by default.
  ///
  /// Refraction samples the backdrop at fractional positions. With nearest
  /// sampling, refracted lines snap to whole device pixels and read as
  /// jagged; bilinear sampling moves them smoothly, as on Apple's glass.
  /// Undisplaced glass still reproduces the backdrop exactly. It uses the
  /// same single texture fetch and no extra pass, and measured within noise
  /// on Metal. Set it to `false` for the previous nearest sampling.
  final bool smoothRefraction;

  /// Magnification of the backdrop seen through the whole face, about the
  /// center of the glass.
  ///
  /// `1` preserves the backdrop, values above `1` magnify (the iOS 27 text
  /// loupe measures `1.25`) and values below `1` reveal more content. The
  /// bevel's [refractionAmount] is applied on top.
  final double magnification;

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

  /// Effective bevel width; never negative.
  double get effectiveRefractionHeight => math.max(0, refractionHeight);

  /// Effective edge displacement; never negative.
  double get effectiveRefractionAmount => math.max(0, refractionAmount);

  /// Effective shape-fitting mode of the lens.
  bool get effectiveRefractionFitsShape => refractionFitsShape;

  /// Effective backdrop sampling mode.
  bool get effectiveSmoothRefraction => smoothRefraction;

  /// Effective magnification constrained to the supported range.
  double get effectiveMagnification => magnification.clamp(.25, 4.0);

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

  /// Shared displacement codec scale for the geometry and final passes.
  /// [refractionAmount] is the exact peak of the profile, so the RGBA8 code
  /// range is spent only on reachable displacement.
  double get effectiveDisplacementScale =>
      math.max(1e-3, effectiveRefractionAmount);

  /// Lighting depth of the rim in logical pixels.
  ///
  /// The geometry matte encodes signed edge distance up to four times this
  /// depth, so rim lighting keeps its precision even when [refractionHeight]
  /// is small or refraction is disabled.
  double get effectiveEdgeDistanceRange => math.max(12, refractionHeight);

  /// Returns a copy with the supplied material controls replaced.
  LiquidGlassSettings copyWith({
    double? refractionHeight,
    double? refractionAmount,
    bool? refractionFitsShape,
    bool? smoothRefraction,
    double? magnification,
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
    refractionHeight: refractionHeight ?? this.refractionHeight,
    refractionAmount: refractionAmount ?? this.refractionAmount,
    refractionFitsShape: refractionFitsShape ?? this.refractionFitsShape,
    smoothRefraction: smoothRefraction ?? this.smoothRefraction,
    magnification: magnification ?? this.magnification,
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
    'refractionHeight': refractionHeight,
    'refractionAmount': refractionAmount,
    'refractionFitsShape': refractionFitsShape,
    'smoothRefraction': smoothRefraction,
    'magnification': magnification,
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
    refractionHeight,
    refractionAmount,
    refractionFitsShape,
    smoothRefraction,
    magnification,
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
