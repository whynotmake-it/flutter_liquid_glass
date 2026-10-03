import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:meta/meta.dart';

/// Material parameters for the liquid-glass compositor.
///
/// This object contains the optical profile and shared surface lighting.
/// Per-shape color response and materialization belong to
/// [LiquidGlassAppearance]. The renderer derives the glint, the dark border
/// and the inner bevel shadow from the same SDF, so these controls remain
/// stable across toolbars, capsules, and tabs.
class LiquidGlassSettings with Equatable {
  /// Creates a material from optical and lighting controls.
  ///
  /// The defaults are the light iOS 27 toolbar
  /// ([LiquidGlassSettings.ios27ToolbarLight]) at slider position `0`.
  /// Distances are logical pixels; strengths use the `0` to `1` range.
  const LiquidGlassSettings({
    this.refractionHeight = 20.0,
    this.refractionAmount = 60.0,
    this.refractionFitsShape = true,
    this.backdropShrink = 0.0,
    this.frost = 2.0,
    this.dispersion = 0.0,
    this.highlight = 1.0,
    this.contourStrength = 0.43,
    this.contourDirectionality = 0.77,
    this.bevelShadowStrength = 0.036,
    this.tintAmount = 0.0,
  });

  /// Restores a material vector produced by [toJson].
  factory LiquidGlassSettings.fromJson(Map<String, Object?> json) {
    const defaults = LiquidGlassSettings();
    double number(String key, double fallback) =>
        (json[key] as num?)?.toDouble() ?? fallback;
    return LiquidGlassSettings(
      refractionHeight: number('refractionHeight', defaults.refractionHeight),
      refractionAmount: number('refractionAmount', defaults.refractionAmount),
      refractionFitsShape:
          json['refractionFitsShape'] as bool? ?? defaults.refractionFitsShape,
      backdropShrink: number('backdropShrink', defaults.backdropShrink),
      frost: number('frost', defaults.frost),
      dispersion: number('dispersion', defaults.dispersion),
      highlight: number('highlight', defaults.highlight),
      contourStrength: number('contourStrength', defaults.contourStrength),
      contourDirectionality: number(
        'contourDirectionality',
        defaults.contourDirectionality,
      ),
      bevelShadowStrength: number(
        'bevelShadowStrength',
        defaults.bevelShadowStrength,
      ),
      tintAmount: number('tintAmount', defaults.tintAmount),
    );
  }

  /// Light-mode settings fitted to an iOS 27 toolbar capsule.
  ///
  /// This is a useful starting point, not a universal Apple-material preset:
  /// platform materials vary with appearance, control role, and accessibility
  /// settings. Override [frost] when the surrounding design needs a clearer or
  /// softer surface.
  ///
  /// The lighting is the measured iOS 27 rim: a 1.2 pt glint on both walls
  /// along the light axis, a 0.75 pt dark border outside the silhouette that
  /// concentrates where the glint fades, and a faint inner shadow cast by the
  /// rim, fitted on the Reduce Motion off references. These are the defaults
  /// of the unnamed constructor.
  ///
  /// [frost] defaults to [ios27RegularFrost] for [tintAmount].
  factory LiquidGlassSettings.ios27ToolbarLight({
    double tintAmount = 0,
    double? frost,
  }) => LiquidGlassSettings(
    frost: frost ?? ios27RegularFrost(tintAmount),
    tintAmount: tintAmount,
  );

  /// Dark-mode settings fitted to an iOS 27 toolbar capsule.
  ///
  /// The glint is dimmed; the border is stronger and
  /// vanishes entirely where the normal faces the light axis.
  ///
  /// [frost] defaults to [ios27RegularFrost] for [tintAmount].
  factory LiquidGlassSettings.ios27ToolbarDark({
    double tintAmount = 0,
    double? frost,
  }) => LiquidGlassSettings(
    frost: frost ?? ios27RegularFrost(tintAmount),
    highlight: 0.8,
    contourStrength: 0.88,
    contourDirectionality: 1,
    tintAmount: tintAmount,
  );

  /// Settings fitted to iOS 27 `Glass.clear`, identical in light and dark.
  ///
  /// Clear glass has the same glint line and angular falloff as the toolbar;
  /// its brighter glint comes from its color model. The border exists only
  /// where the normal is perpendicular to the light axis, and there is no
  /// inner shadow. The Liquid Glass slider only blurs clear glass, so [frost]
  /// defaults to [ios27ClearFrost] for [tintAmount]. Pair it with
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
  }) => LiquidGlassSettings(
    refractionFitsShape: false,
    frost: frost ?? ios27ClearFrost(tintAmount),
    contourStrength: 0.36,
    contourDirectionality: 1,
    bevelShadowStrength: 0,
    tintAmount: tintAmount,
    highlight: .6,
  );

  /// Creates fitted iOS 27 toolbar settings for [brightness].
  factory LiquidGlassSettings.ios27Toolbar({
    required Brightness brightness,
    double? frost,
    double tintAmount = 0,
  }) => brightness == Brightness.dark
      ? LiquidGlassSettings.ios27ToolbarDark(
          frost: frost,
          tintAmount: tintAmount,
        )
      : LiquidGlassSettings.ios27ToolbarLight(
          frost: frost,
          tintAmount: tintAmount,
        );

  /// Backdrop blur of iOS 27 regular glass (`.regular`, and the `.glass`
  /// buttons and toolbars built from it), in logical pixels, for the Settings
  /// Liquid Glass slider position [tintAmount] (`0` Clear, `1` Tinted).
  ///
  /// Apple keeps part of the backdrop with about 1.5 pt of blur and mixes the
  /// rest toward a fully diffused face; the slider only moves that mix. A
  /// single blur cannot mix, so this is the blur whose rendered detail best
  /// matches Apple's at toolbar size, light and dark: 2, 6.1 and 16.6 pt at
  /// 0, 0.5 and 1, growing at a slightly faster exponential rate up to the
  /// Settings middle tick than beyond it. Apple diffuses larger glass more
  /// and smaller glass less.
  static double ios27RegularFrost(double tintAmount) {
    final amount = tintAmount.clamp(0.0, 1.0);
    return 2 *
        math.exp(
          2.23 * math.min(amount, 0.5) + 2 * math.max(amount - 0.5, 0.0),
        );
  }

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
  /// measures `20`, Apple's text loupe `8`. See [refractionFitsShape] for how
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
  /// iOS 27 glass measures `60`, Apple's text loupe `28`. `0` disables
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

  /// How much the backdrop seen through the face is shrunk, about the center
  /// of the layer's glass: `0` keeps its size, `0.08` shows it at 92%.
  ///
  /// Clamped to `0` to `0.75`, so the glass can reveal more of its
  /// surroundings but never enlarges (and pixelates) the captured backdrop.
  /// Magnifiers should re-render their content at full resolution instead
  /// (the example app's loupe does). The bevel's [refractionAmount] is applied
  /// on top.
  ///
  /// All glass in one layer shares the center, so give a shrinking shape its
  /// own layer when it should shrink about itself.
  final double backdropShrink;

  /// Backdrop blur sigma in logical pixels.
  ///
  /// The value is absolute and does not change with the material's size.
  /// The default is [ios27RegularFrost] at slider position `0`.
  final double frost;

  /// Separation of the color channels in the refracted edge.
  ///
  /// Red is displaced by `1 + dispersion / 2` and blue by
  /// `1 - dispersion / 2` times the edge displacement. Negative values bend
  /// blue more, as real glass does; the iOS 27 loupe measures about `-0.06`
  /// and other iOS 27 glass `0`. At `0` the glass reads the backdrop once
  /// per pixel instead of three times.
  final double dispersion;

  /// Strength of the glint along the light axis.
  ///
  /// The glint recolors the face instead of adding white: it pulls the lit
  /// material toward a target brighter than SDR white carrying the face's own
  /// chroma amplified, so glass over color glints in that color. `1` is the
  /// strength an iPhone shows on iOS 27 in light mode; the dark toolbar and
  /// clear presets dim it to `0.8` and `0.6`. Apple's simulator captures,
  /// which are SDR, correspond to about `0.56`.
  final double highlight;

  /// Peak absorption of the dark border just outside the silhouette, which
  /// is 0.75 logical pixels wide. `0` removes the border.
  final double contourStrength;

  /// How strongly the border concentrates where the glint fades.
  ///
  /// `0` darkens the whole silhouette evenly. `1` keeps the border only where
  /// the normal is perpendicular to the light axis and removes it where the
  /// glint sits, as in iOS 27 dark mode.
  final double contourDirectionality;

  /// Fraction of the light transmitted through the glass that the inner
  /// shadow cast by the rim absorbs at its peak. The glass's own emission is
  /// not shaded. The shadow falls 6 pt below the lit top wall, stays at the
  /// rim on the sides and is absent at the bottom, as on iOS 27.
  final double bevelShadowStrength;

  /// Position of the iOS 27 Liquid Glass slider in Settings, from `0`
  /// (Clear) to `1` (Tinted).
  ///
  /// Apps set this themselves; the renderer does not read the system value.
  /// The slider makes the iOS 27 neutral wash more opaque and strengthens the
  /// dark border; the glint is unchanged, and the direct color model ignores
  /// it. It does not change [frost]: the iOS 27 presets derive their blur
  /// from the same position ([ios27RegularFrost], [ios27ClearFrost]). It is
  /// one uniform per layer and adds no per-pixel work.
  final double tintAmount;

  /// Effective bevel width; never negative.
  double get effectiveRefractionHeight => math.max(0, refractionHeight);

  /// Effective edge displacement; never negative.
  double get effectiveRefractionAmount => math.max(0, refractionAmount);

  /// Effective backdrop shrink, clamped to `0` to `0.75`.
  double get effectiveBackdropShrink => backdropShrink.clamp(0.0, 0.75);

  /// Effective slider position, clamped to `0` to `1`.
  double get effectiveTintAmount => tintAmount.clamp(0.0, 1.0);

  /// Effective blur sigma; never negative.
  double get effectiveFrost => math.max(0, frost);

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

  /// Width of the dark border in logical pixels; `0` without a border.
  @internal
  double get contourWidth => contourStrength > 0 ? GlassRim.contourWidth : 0;

  /// Returns a copy with the supplied material controls replaced.
  LiquidGlassSettings copyWith({
    double? refractionHeight,
    double? refractionAmount,
    bool? refractionFitsShape,
    double? backdropShrink,
    double? frost,
    double? dispersion,
    double? highlight,
    double? contourStrength,
    double? contourDirectionality,
    double? bevelShadowStrength,
    double? tintAmount,
  }) => LiquidGlassSettings(
    refractionHeight: refractionHeight ?? this.refractionHeight,
    refractionAmount: refractionAmount ?? this.refractionAmount,
    refractionFitsShape: refractionFitsShape ?? this.refractionFitsShape,
    backdropShrink: backdropShrink ?? this.backdropShrink,
    frost: frost ?? this.frost,
    dispersion: dispersion ?? this.dispersion,
    highlight: highlight ?? this.highlight,
    contourStrength: contourStrength ?? this.contourStrength,
    contourDirectionality: contourDirectionality ?? this.contourDirectionality,
    bevelShadowStrength: bevelShadowStrength ?? this.bevelShadowStrength,
    tintAmount: tintAmount ?? this.tintAmount,
  );

  /// Serializes the public material vector for example presets and tooling.
  Map<String, Object> toJson() => {
    'refractionHeight': refractionHeight,
    'refractionAmount': refractionAmount,
    'refractionFitsShape': refractionFitsShape,
    'backdropShrink': backdropShrink,
    'frost': frost,
    'dispersion': dispersion,
    'highlight': highlight,
    'contourStrength': contourStrength,
    'contourDirectionality': contourDirectionality,
    'bevelShadowStrength': bevelShadowStrength,
    'tintAmount': tintAmount,
  };

  @override
  List<Object?> get props => [
    refractionHeight,
    refractionAmount,
    refractionFitsShape,
    backdropShrink,
    frost,
    dispersion,
    highlight,
    contourStrength,
    contourDirectionality,
    bevelShadowStrength,
    tintAmount,
  ];
}

/// The fitted iOS 27 rim geometry every preset shares. These were settings
/// until every preset and the example used the same values.
@internal
abstract final class GlassRim {
  /// Width of the glint line inward from the silhouette, in logical pixels.
  static const double highlightWidth = 1.2;

  /// Angular spread of the glint: `0.5` fades it linearly with the normal's
  /// component perpendicular to the light axis.
  static const double highlightWrap = 0.5;

  /// Energy of the glint opposite the light-facing rim, relative to it.
  static const double highlightOppositeStrength = 1;

  /// Width of the dark border outside the silhouette, in logical pixels.
  static const double contourWidth = 0.75;

  /// Distance over which the inner bevel shadow fades inward, in logical
  /// pixels.
  static const double bevelShadowDepth = 16;

  /// Displacement of the inner bevel shadow along the light, in logical
  /// pixels.
  static const double bevelShadowOffset = 6;

  /// How strongly the inner bevel shadow follows the light direction.
  static const double bevelShadowDirectionality = 0.5;
}
