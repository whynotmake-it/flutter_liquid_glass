import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_color_model.dart';
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
    @Deprecated(
      'Resamples the captured backdrop and zooms about the layer center. '
      'Use LiquidGlassLoupe for magnifiers.',
    )
    this.magnification = 1.0,
    this.frost = 5.0,
    this.dispersion = 0.0,
    this.highlight = 1.0,
    this.highlightWidth = 1.2,
    this.highlightWrap = 0.5,
    this.highlightOppositeStrength = 1.0,
    this.curvatureLighting = 0.0,
    this.contourStrength = 0.0,
    this.contourWidth = 0.0,
    this.contourOffset = 0.0,
    this.contourTransmittance = 0.0,
    this.contourDirectionality = 0.0,
    this.bevelShadowStrength = 0.0,
    this.bevelShadowDepth = 12.0,
    this.bevelShadowOffset = 0.0,
    this.bevelShadowDirectionality = 0.0,
    this.bevelShadowSizeResponse = 0.0,
    this.exteriorShadowSizeResponse = 0.0,
    this.tintAmount = 0.0,
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
      dispersion: number('dispersion', 0),
      highlight: number('highlight', 1),
      highlightWidth: number('highlightWidth', 1.2),
      highlightWrap: number('highlightWrap', .5),
      highlightOppositeStrength: number('highlightOppositeStrength', 1),
      curvatureLighting: number('curvatureLighting', 0),
      contourStrength: number('contourStrength', 0),
      contourWidth: number('contourWidth', 0),
      contourOffset: number('contourOffset', 0),
      contourTransmittance: number('contourTransmittance', 0),
      contourDirectionality: number('contourDirectionality', 0),
      bevelShadowStrength: number('bevelShadowStrength', 0),
      bevelShadowDepth: number('bevelShadowDepth', 12),
      bevelShadowOffset: number('bevelShadowOffset', 0),
      bevelShadowDirectionality: number('bevelShadowDirectionality', 0),
      bevelShadowSizeResponse: number('bevelShadowSizeResponse', 0),
      exteriorShadowSizeResponse: number('exteriorShadowSizeResponse', 0),
      tintAmount: number('tintAmount', 0),
    );
  }

  /// Light-mode structural settings fitted to an iOS 27 toolbar capsule.
  ///
  /// This is a useful starting point, not a universal Apple-material preset:
  /// platform materials vary with appearance, control role, and accessibility
  /// settings. Override [frost] when the surrounding design needs a clearer or
  /// softer surface.
  ///
  /// The lighting is the measured iOS 27 rim: a 1.2 pt glint on both walls
  /// along the light axis and a 0.75 pt dark border outside the silhouette
  /// that concentrates where the glint fades. iOS 27 shows no inner bevel
  /// shadow on solid backdrops.
  const LiquidGlassSettings.ios27ToolbarLight({
    this.frost = 7.0,
    this.tintAmount = 0.0,
  }) : refractionHeight = 20.0,
       refractionAmount = 60.0,
       refractionFitsShape = true,
       smoothRefraction = true,
       magnification = 1.0,
       dispersion = 0.0,
       highlight = 1.0,
       highlightWidth = 1.2,
       highlightWrap = 0.5,
       highlightOppositeStrength = 1.0,
       curvatureLighting = 0.0,
       contourStrength = 0.43,
       contourWidth = 0.75,
       contourOffset = 0.0,
       contourTransmittance = 0.0,
       contourDirectionality = 0.77,
       bevelShadowStrength = 0.0,
       bevelShadowDepth = 18.0,
       bevelShadowOffset = 4.0,
       bevelShadowDirectionality = 0.75,
       bevelShadowSizeResponse = 0.0,
       exteriorShadowSizeResponse = 1.0;

  /// Dark-mode structural settings fitted to an iOS 27 toolbar capsule.
  ///
  /// Use this alongside [LiquidGlassSettings.ios27ToolbarLight] when the
  /// surrounding application follows the platform brightness. The glint is
  /// identical to light mode; the border is stronger and vanishes entirely
  /// where the normal faces the light axis.
  const LiquidGlassSettings.ios27ToolbarDark({
    this.frost = 5.0,
    this.tintAmount = 0.0,
  }) : refractionHeight = 20.0,
       refractionAmount = 60.0,
       refractionFitsShape = true,
       smoothRefraction = true,
       magnification = 1.0,
       dispersion = 0.0,
       highlight = 1.0,
       highlightWidth = 1.2,
       highlightWrap = 0.5,
       highlightOppositeStrength = 1.0,
       curvatureLighting = 0.0,
       contourStrength = 0.88,
       contourWidth = 0.75,
       contourOffset = 0.0,
       contourTransmittance = 0.0,
       contourDirectionality = 1.0,
       bevelShadowStrength = 0.0,
       bevelShadowDepth = 18.0,
       bevelShadowOffset = 4.0,
       bevelShadowDirectionality = 0.75,
       bevelShadowSizeResponse = 0.0,
       exteriorShadowSizeResponse = 0.0;

  /// Settings fitted to iOS 27 `Glass.clear`, identical in light and dark.
  ///
  /// Clear glass has the same glint line and angular falloff as the toolbar;
  /// its brighter glint comes from its color model. The border exists only
  /// where the normal is perpendicular to the light axis. The Liquid Glass
  /// slider only blurs clear glass, so [frost] defaults to
  /// [ios27ClearFrost] for [tintAmount]. Pair it with
  /// [LiquidGlassAppearance.ios27Clear].
  ///
  /// The lens is the full 20 pt / 60 pt bevel on every shape. At slider 0
  /// the blur is 0.35 pt, which up to about 3.5x device pixel ratio stays
  /// within the renderer's 1.25 device-pixel in-pass kernel and so costs no
  /// blur pass. Pass [frost] to override, for example `frost: 0` for
  /// unsoftened glass.
  factory LiquidGlassSettings.ios27Clear({
    double tintAmount = 0,
    double? frost,
  }) => LiquidGlassSettings._ios27Clear(
    frost: frost ?? ios27ClearFrost(tintAmount),
    tintAmount: tintAmount,
  );

  const LiquidGlassSettings._ios27Clear({
    required this.frost,
    required this.tintAmount,
  }) : refractionHeight = 20.0,
       refractionAmount = 60.0,
       refractionFitsShape = false,
       smoothRefraction = true,
       magnification = 1.0,
       dispersion = 0.0,
       highlight = 1.0,
       highlightWidth = 1.2,
       highlightWrap = 0.5,
       highlightOppositeStrength = 1.0,
       curvatureLighting = 0.0,
       contourStrength = 0.36,
       contourWidth = 0.75,
       contourOffset = 0.0,
       contourTransmittance = 0.0,
       contourDirectionality = 1.0,
       bevelShadowStrength = 0.0,
       bevelShadowDepth = 18.0,
       bevelShadowOffset = 4.0,
       bevelShadowDirectionality = 0.75,
       bevelShadowSizeResponse = 0.0,
       exteriorShadowSizeResponse = 0.0;

  /// Creates fitted iOS 27 toolbar structural settings for [brightness].
  factory LiquidGlassSettings.ios27Toolbar({
    required Brightness brightness,
    double? frost,
    double tintAmount = 0,
  }) => brightness == Brightness.dark
      ? LiquidGlassSettings.ios27ToolbarDark(
          frost: frost ?? 5.0,
          tintAmount: tintAmount,
        )
      : LiquidGlassSettings.ios27ToolbarLight(
          frost: frost ?? 7.0,
          tintAmount: tintAmount,
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
         dispersion: 4 * (dispersion / 100),
         frost: frost,
       );

  /// Backdrop blur of iOS 27 `.clear` glass, in logical pixels, for the
  /// Settings Liquid Glass slider position [tintAmount] (`0` Clear, `1`
  /// Tinted).
  ///
  /// Clear glass has no wash or tint at any position; the slider only
  /// blurs. The blur grows exponentially at one rate up to the Settings
  /// middle tick and at twice that rate beyond it: 0.35, 1.28 and 16.4 pt at
  /// 0, 0.5 and 1.
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
  /// center of all glass in the layer.
  ///
  /// `1` preserves the backdrop, values above `1` magnify and values below
  /// `1` reveal more content. The bevel's [refractionAmount] is applied on
  /// top.
  ///
  /// This resamples the backdrop the glass already captured, so magnified
  /// content pixelates, and a layer with several shapes zooms about their
  /// common center rather than each shape's. Use `LiquidGlassLoupe` for
  /// magnifiers: it re-renders the content at full resolution.
  @Deprecated(
    'Resamples the captured backdrop and zooms about the layer center. Use '
    'LiquidGlassLoupe for magnifiers.',
  )
  final double magnification;

  /// Backdrop blur sigma in logical pixels.
  ///
  /// The value is absolute and does not change with the material's size.
  final double frost;

  /// Wavelength separation for the edge displacement.
  final double dispersion;

  /// Strength of the glint along the light axis.
  ///
  /// The glint recolors the face instead of adding white: it pulls the lit
  /// material toward a target brighter than SDR white carrying the face's own
  /// chroma amplified, so glass over color glints in that color. `1` is the
  /// strength measured on iOS 27 in both appearances.
  final double highlight;

  /// Width of the glint line in logical pixels, measured inward from the
  /// silhouette. A faint bleed reaches four times as deep.
  ///
  /// `0` follows [contourWidth].
  final double highlightWidth;

  /// Angular spread of the glint around the SDF contour.
  ///
  /// `0.5` fades the glint linearly with the normal's component
  /// perpendicular to the light axis, as on iOS 27. Lower values confine it
  /// to normals aligned with the light axis; higher values carry it further
  /// around corners and curved edges.
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

  /// Peak absorption of the dark border derived from the SDF.
  final double contourStrength;

  /// Distance in logical pixels over which the border fades outward from
  /// the silhouette.
  final double contourWidth;

  /// Outward shift of the border's start relative to the silhouette.
  ///
  /// The border remains derived from the same SDF as the glass and
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

  /// How strongly the border concentrates where the glint fades.
  ///
  /// `0` darkens the whole silhouette evenly. `1` keeps the border only where
  /// the normal is perpendicular to the light axis and removes it where the
  /// glint sits, as in iOS 27 dark mode.
  final double contourDirectionality;

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

  /// Position of the iOS 27 Liquid Glass slider in Settings, from `0`
  /// (Clear) to `1` (Tinted).
  ///
  /// Apps set this themselves; the renderer does not read the system value.
  /// The slider makes the iOS 27 neutral wash more opaque, strengthens the
  /// dark border and diffuses the backdrop. The glint is unchanged. It is one
  /// uniform per layer and adds no per-pixel work.
  final double tintAmount;

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

  /// Effective slider position, clamped to `0...1`.
  double get effectiveTintAmount => tintAmount.clamp(0.0, 1.0);

  /// Effective backdrop blur sigma for regular glass.
  double get effectiveFrost => frostFor(const LiquidGlassColorModel.direct());

  /// Backdrop blur sigma for glass using [colorModel].
  ///
  /// Apple fades backdrop detail with [tintAmount] by mixing toward a fully
  /// diffused face. A single Gaussian cannot mix, so the slider adds the
  /// blur that attenuates detail with a 23 pt period by the same fraction,
  /// calibrated against Apple's toolbar captures. Clear glass carries its
  /// slider blur in [frost] instead (see [ios27ClearFrost]).
  double frostFor(LiquidGlassColorModel colorModel) {
    final amount = effectiveTintAmount;
    if (amount <= 0) return frost;
    final detail = colorModel.sliderDetail(amount);
    const referenceVariance = 23.0 * 23.0 / (2 * math.pi * math.pi);
    return math.sqrt(frost * frost - referenceVariance * math.log(detail));
  }

  /// Effective chromatic aberration.
  double get effectiveDispersion => dispersion;

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

  /// Effective contour directionality.
  double get effectiveContourDirectionality => contourDirectionality;

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
    double? dispersion,
    double? highlight,
    double? highlightWidth,
    double? highlightWrap,
    double? highlightOppositeStrength,
    double? curvatureLighting,
    double? contourStrength,
    double? contourWidth,
    double? contourOffset,
    double? contourTransmittance,
    double? contourDirectionality,
    double? bevelShadowStrength,
    double? bevelShadowDepth,
    double? bevelShadowOffset,
    double? bevelShadowDirectionality,
    double? bevelShadowSizeResponse,
    double? exteriorShadowSizeResponse,
    double? tintAmount,
  }) => LiquidGlassSettings(
    refractionHeight: refractionHeight ?? this.refractionHeight,
    refractionAmount: refractionAmount ?? this.refractionAmount,
    refractionFitsShape: refractionFitsShape ?? this.refractionFitsShape,
    smoothRefraction: smoothRefraction ?? this.smoothRefraction,
    magnification: magnification ?? this.magnification,
    frost: frost ?? this.frost,
    dispersion: dispersion ?? this.dispersion,
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
    contourDirectionality: contourDirectionality ?? this.contourDirectionality,
    bevelShadowStrength: bevelShadowStrength ?? this.bevelShadowStrength,
    bevelShadowDepth: bevelShadowDepth ?? this.bevelShadowDepth,
    bevelShadowOffset: bevelShadowOffset ?? this.bevelShadowOffset,
    bevelShadowDirectionality:
        bevelShadowDirectionality ?? this.bevelShadowDirectionality,
    bevelShadowSizeResponse:
        bevelShadowSizeResponse ?? this.bevelShadowSizeResponse,
    exteriorShadowSizeResponse:
        exteriorShadowSizeResponse ?? this.exteriorShadowSizeResponse,
    tintAmount: tintAmount ?? this.tintAmount,
  );

  /// Serializes the public material vector for example presets and tooling.
  Map<String, Object> toJson() => {
    'refractionHeight': refractionHeight,
    'refractionAmount': refractionAmount,
    'refractionFitsShape': refractionFitsShape,
    'smoothRefraction': smoothRefraction,
    'magnification': magnification,
    'frost': frost,
    'dispersion': dispersion,
    'highlight': highlight,
    'highlightWidth': highlightWidth,
    'highlightWrap': highlightWrap,
    'highlightOppositeStrength': highlightOppositeStrength,
    'curvatureLighting': curvatureLighting,
    'contourStrength': contourStrength,
    'contourWidth': contourWidth,
    'contourOffset': contourOffset,
    'contourTransmittance': contourTransmittance,
    'contourDirectionality': contourDirectionality,
    'bevelShadowStrength': bevelShadowStrength,
    'bevelShadowDepth': bevelShadowDepth,
    'bevelShadowOffset': bevelShadowOffset,
    'bevelShadowDirectionality': bevelShadowDirectionality,
    'bevelShadowSizeResponse': bevelShadowSizeResponse,
    'exteriorShadowSizeResponse': exteriorShadowSizeResponse,
    'tintAmount': tintAmount,
  };

  @override
  List<Object?> get props => [
    refractionHeight,
    refractionAmount,
    refractionFitsShape,
    smoothRefraction,
    magnification,
    frost,
    dispersion,
    highlight,
    highlightWidth,
    highlightWrap,
    highlightOppositeStrength,
    curvatureLighting,
    contourStrength,
    contourWidth,
    contourOffset,
    contourTransmittance,
    contourDirectionality,
    bevelShadowStrength,
    bevelShadowDepth,
    bevelShadowOffset,
    bevelShadowDirectionality,
    bevelShadowSizeResponse,
    exteriorShadowSizeResponse,
    tintAmount,
  ];
}
