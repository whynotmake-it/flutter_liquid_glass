import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_haze.dart';
import 'package:meta/meta.dart';

/// Material parameters for the liquid-glass compositor.
///
/// This object contains the optical profile and shared surface lighting.
/// Per-shape color response and materialization belong to
/// [LiquidGlassAppearance]. The renderer derives the glint, the dark border
/// and the inner bevel shadow from the same SDF, so these controls remain
/// stable across toolbars, capsules, and tabs.
///
/// Lighting strengths are display-referred. The defaults of the unnamed
/// constructor may be retuned before 1.0; the version-named presets
/// (`ios27*`) track Apple's appearance on that OS version.
@immutable
final class LiquidGlassSettings {
  /// Creates a material from optical and lighting controls.
  ///
  /// The defaults are the light iOS 27 regular glass
  /// ([LiquidGlassSettings.ios27RegularLight]) at slider position `0`, and
  /// may be retuned before 1.0.
  /// Distances are logical pixels; strengths use the `0` to `1` range.
  const LiquidGlassSettings({
    this.refractionHeight = _defaultRefractionHeight,
    this.refractionAmount = _defaultRefractionAmount,
    this.refractionFitsShape = _defaultRefractionFitsShape,
    this.backdropShrink = _defaultBackdropShrink,
    this.backdropShrinkRim = _defaultBackdropShrinkRim,
    this.backdropPull = _defaultBackdropPull,
    this.backdropPullHeight = _defaultBackdropPullHeight,
    this.aberration = _defaultAberration,
    this.aberrationDepth = _defaultAberrationDepth,
    double? frost,
    this.dispersion = _defaultDispersion,
    this.highlight = _defaultHighlight,
    this.contourStrength = _defaultContourStrength,
    this.contourDirectionality = _defaultContourDirectionality,
    this.bevelShadowStrength = _defaultBevelShadowStrength,
    this.tintAmount = _defaultTintAmount,
    this.haze = _defaultHaze,
  }) : frost = frost ?? _defaultRegularFrost,
       _frostIsFloorEligible = frost == null,
       _frostIsClear = false;

  /// The public fields with [frost] already resolved; [floorEligible] and
  /// [clearFrost] set [_frostIsFloorEligible] and [_frostIsClear].
  const LiquidGlassSettings._({
    required this.frost,
    required bool floorEligible,
    this.refractionHeight = _defaultRefractionHeight,
    this.refractionAmount = _defaultRefractionAmount,
    this.refractionFitsShape = _defaultRefractionFitsShape,
    this.backdropShrink = _defaultBackdropShrink,
    this.backdropShrinkRim = _defaultBackdropShrinkRim,
    this.backdropPull = _defaultBackdropPull,
    this.backdropPullHeight = _defaultBackdropPullHeight,
    this.aberration = _defaultAberration,
    this.aberrationDepth = _defaultAberrationDepth,
    this.dispersion = _defaultDispersion,
    this.highlight = _defaultHighlight,
    this.contourStrength = _defaultContourStrength,
    this.contourDirectionality = _defaultContourDirectionality,
    this.bevelShadowStrength = _defaultBevelShadowStrength,
    this.tintAmount = _defaultTintAmount,
    this.haze = _defaultHaze,
    bool clearFrost = false,
  }) : _frostIsFloorEligible = floorEligible,
       _frostIsClear = clearFrost;

  /// Restores a material vector produced by [toJson].
  ///
  /// The JSON schema is experimental and may change between releases.
  ///
  /// The device blur floor is not serialized: restored settings carry an
  /// explicit [frost], which the renderer uses as given.
  @experimental
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
      backdropShrinkRim: number(
        'backdropShrinkRim',
        defaults.backdropShrinkRim,
      ),
      backdropPull: number('backdropPull', defaults.backdropPull),
      backdropPullHeight: number(
        'backdropPullHeight',
        defaults.backdropPullHeight,
      ),
      aberration: number('aberration', defaults.aberration),
      aberrationDepth: number('aberrationDepth', defaults.aberrationDepth),
      // Omitted frost keeps the default regular frost, including its device
      // and size response. An explicit value is the caller's and is used
      // verbatim.
      frost: (json['frost'] as num?)?.toDouble(),
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
      haze: switch (json['haze']) {
        final Map<String, Object?> haze => LiquidGlassHaze.fromJson(haze),
        _ => defaults.haze,
      },
    );
  }

  /// Light-mode settings fitted to iOS 27 regular glass (`Glass.regular`,
  /// which Apple also uses for toolbars and `.glass` buttons).
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
  /// [frost] defaults to [ios27RegularFrost] for [tintAmount], which starts at
  /// `4.5` logical pixels. The renderer may raise a preset or default frost
  /// further on the device, so the blur pass downsamples there.
  factory LiquidGlassSettings.ios27RegularLight({
    double tintAmount = 0,
    double? frost,
  }) => LiquidGlassSettings._(
    frost: frost ?? ios27RegularFrost(tintAmount),
    floorEligible: frost == null,
    tintAmount: tintAmount,
    haze: LiquidGlassHaze.ios27Regular(
      brightness: Brightness.light,
      tintAmount: tintAmount,
    ),
  );

  /// Dark-mode settings fitted to iOS 27 regular glass.
  ///
  /// The glint is dimmed; the border is stronger and
  /// vanishes entirely where the normal faces the light axis.
  ///
  /// [frost] defaults to [ios27RegularFrost] for [tintAmount], which starts at
  /// `4.5` logical pixels. The renderer may raise a preset or default frost
  /// further on the device, so the blur pass downsamples there.
  factory LiquidGlassSettings.ios27RegularDark({
    double tintAmount = 0,
    double? frost,
  }) => LiquidGlassSettings._(
    frost: frost ?? ios27RegularFrost(tintAmount),
    floorEligible: frost == null,
    contourStrength: 0.88,
    contourDirectionality: 1,
    tintAmount: tintAmount,
    haze: LiquidGlassHaze.ios27Regular(
      brightness: Brightness.dark,
      tintAmount: tintAmount,
    ),
  );

  /// Settings fitted to iOS 27 `Glass.clear`, identical in light and dark.
  ///
  /// Clear glass has the same glint line and angular falloff as regular glass;
  /// its brighter glint comes from its color model. The border exists only
  /// where the normal is perpendicular to the light axis, and there is no
  /// inner shadow. The Liquid Glass slider only blurs clear glass, so [frost]
  /// defaults to [ios27ClearFrost] for [tintAmount]. Pair it with
  /// [LiquidGlassAppearance.ios27Clear].
  ///
  /// The lens is the full 20 pt / 60 pt bevel on glass from 93 points on its
  /// short side and narrows with smaller glass; see [refractionFitsShape].
  /// At slider 0 the glass is completely clear and unblurred. Where one blur
  /// stands in for the haze, tinted positions floor it at `2.1` logical
  /// pixels. Pass [frost] to override, for example `frost: 0` for
  /// unsoftened glass at every position.
  factory LiquidGlassSettings.ios27Clear({
    double tintAmount = 0,
    double? frost,
  }) => LiquidGlassSettings._(
    refractionFitsShape: false,
    frost: frost ?? _ios27ClearBlur(tintAmount),
    floorEligible: frost == null,
    contourStrength: 0.36,
    contourDirectionality: 1,
    bevelShadowStrength: 0,
    tintAmount: tintAmount,
    haze: LiquidGlassHaze.ios27Clear(tintAmount: tintAmount),
    clearFrost: true,
  );

  /// Creates fitted iOS 27 regular glass settings for [brightness].
  factory LiquidGlassSettings.ios27Regular({
    required Brightness brightness,
    double? frost,
    double tintAmount = 0,
  }) => brightness == Brightness.dark
      ? LiquidGlassSettings.ios27RegularDark(
          frost: frost,
          tintAmount: tintAmount,
        )
      : LiquidGlassSettings.ios27RegularLight(
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
  /// matches Apple's at toolbar size, light and dark: 4.5, 6.9 and 18.7 pt at
  /// 0, 0.5 and 1, growing faster beyond the Settings middle tick. Apple
  /// diffuses larger glass more and smaller glass less; the presets scale this
  /// toolbar-size value by the glass's short side.
  static double ios27RegularFrost(double tintAmount) {
    final amount = tintAmount.clamp(0.0, 1.0);
    return 4.5 *
        math.exp(
          0.85 * math.min(amount, 0.5) + 2 * math.max(amount - 0.5, 0.0),
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
  ///
  /// This is Apple's measured curve; [LiquidGlassSettings.ios27Clear] renders
  /// no blur at slider 0 and floors tinted positions at `2.1` logical pixels.
  static double ios27ClearFrost(double tintAmount) {
    final amount = tintAmount.clamp(0.0, 1.0);
    return 0.35 *
        math.exp(
          2.6 * math.min(amount, 0.5) + 5.1 * math.max(amount - 0.5, 0.0),
        );
  }

  /// Smallest non-zero base blur, in logical pixels, used as a floor and by
  /// clear glass at tinted slider positions.
  ///
  /// Preset and default frost is raised further, per device, at render time;
  /// see [frostSigmaAt].
  static const double _minBlurPassSigma = 2.1;

  /// Base frost of the regular presets and the unnamed constructor at slider
  /// position `0`, in logical pixels. Fitted to the pinned iOS 27 captures;
  /// [ios27RegularFrost] starts here and grows with the slider.
  static const double _defaultRegularFrost = 4.5;
  static const double _defaultRefractionHeight = 20;
  static const double _defaultRefractionAmount = 60;
  static const bool _defaultRefractionFitsShape = true;
  static const double _defaultBackdropShrink = 0;
  static const double _defaultBackdropShrinkRim = 0;
  static const double _defaultBackdropPull = 0;
  static const double _defaultBackdropPullHeight = 0;
  static const double _defaultAberration = 0;
  static const double _defaultAberrationDepth = 0;
  static const double _defaultDispersion = 0;
  static const double _defaultHighlight = 0.6;
  static const double _defaultContourStrength = 0.43;
  static const double _defaultContourDirectionality = 0.77;
  static const double _defaultBevelShadowStrength = 0.036;
  static const double _defaultTintAmount = 0;
  static const LiquidGlassHaze _defaultHaze = LiquidGlassHaze(lighten: 0.675);

  /// Device-space blur sigma at which Impeller first downsamples its Gaussian.
  ///
  /// Impeller 3.47.1 `GaussianBlurFilterContents::CalculateScale` returns
  /// `1.0` for a sigma up to `4` device pixels and otherwise
  /// `2^round(log2(4 / sigma))`, so the scale stays `1.0` until
  /// `4 * sqrt(2) ~= 5.657` device pixels. `ScaleSigma` maps a logical sigma
  /// `s` to `s * (1 - 3.4e-3 * s + 3.4e-6 * s^2)` before the device scale
  /// multiplies it, so a logical floor `k` at device scale `d` reaches the
  /// gate at `k * (1 - 3.4e-3 * k/d + 3.4e-6 * (k/d)^2) >= 4 * sqrt(2)`. `5.8`
  /// clears that for every `d >= 2` (the tightest case, `d = 2`, is `5.743`
  /// device pixels) and stays below `2.1 * 3 = 6.3`, so 3x displays keep
  /// the `2.1` floor. Below 2x the floor is capped; see [frostSigmaAt].
  static const double _frostFloorDevicePx = 5.8;

  /// The blur [LiquidGlassSettings.ios27Clear] renders at slider position
  /// [tintAmount]: `0` at slider 0, where the glass is completely clear,
  /// and `2.1` logical pixels or more everywhere else.
  static double _ios27ClearBlur(double tintAmount) {
    if (tintAmount <= 0) return 0;
    return math.max(_minBlurPassSigma, ios27ClearFrost(tintAmount));
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
  /// When `false`, as on iOS 27 `.clear` glass, the bevel is at most 0.36
  /// of the shape's short side and the rim samples up to 0.65 of it inside,
  /// past the center line of a small shape, which mirrors what lies there. A
  /// 44 pt tall button refracts with a height of about `16` and an amount of
  /// about `29`.
  ///
  /// When `true`, glass more than 64 logical pixels across its short side
  /// also bends the backdrop partly toward its center instead of straight
  /// in from its edge, as iOS 27 regular glass does: what shows through the
  /// rim of a card or a tall capsule leans along the edge near its corners.
  /// Shapes of a `LiquidGlassBlendGroup` do so together, by the size of the
  /// largest of them. Glass no larger, and `.clear` glass, bends straight in.
  ///
  /// Shapes of a `LiquidGlassBlendGroup` also share one lens, sized by the
  /// smallest of them, as the elements of an iOS 27 glass container do.
  final bool refractionFitsShape;

  /// How much the backdrop seen through the face is shrunk, about the center
  /// of the layer's glass or the line through it that [backdropShrinkRim]
  /// sets: `0` keeps its size, `0.08` shows it at 92%.
  ///
  /// Clamped to `0` to `0.75`, so the glass can reveal more of its
  /// surroundings but never enlarges (and pixelates) the captured backdrop.
  /// Magnifiers should re-render their content at full resolution instead
  /// (the example app's loupe does). The bevel's [refractionAmount] is applied
  /// on top.
  ///
  /// All glass in one layer shares that center and line, so give a shrinking
  /// shape its own layer when it should shrink about itself.
  final double backdropShrink;

  /// Where [backdropShrink] shrinks about, from `0` to `1`.
  ///
  /// At `0`, the center of the layer's glass: a point moves in proportion to
  /// its distance from that center. At `1`, the nearest point of the long
  /// center line of the layer's glass bounds, which spans the long side less
  /// the short side: a point moves in proportion to its distance from that
  /// line. A capsule then minifies across its straight part and radially about
  /// the centers of its round ends, and the middle of a long lens shows the
  /// backdrop in place along its length, as a lifted iOS lens does. In between,
  /// the line is that fraction of its full length. A circle or square has no
  /// line. Clamped to `0` to `1`.
  final double backdropShrinkRim;

  /// How far outside itself the glass reads the backdrop at its edge, in
  /// logical pixels: the edge pulls its surroundings in, so the glass shows
  /// more of what is around it, as a lifted iOS lens does.
  ///
  /// The pull is whole at the edge and falls along a quarter circle to
  /// nothing [backdropPullHeight] from it, so the middle of glass deeper
  /// than that shows the backdrop in place and at its own size, where
  /// [backdropShrink] shows all of it smaller. It points away from the long
  /// center line of the layer's glass bounds, which spans the long side less
  /// the short side, and the depth is measured from a capsule of those
  /// bounds. The bevel reads the pulled backdrop, as glass lying over it
  /// would. `0` pulls nothing. Never negative.
  final double backdropPull;

  /// How deep [backdropPull] reaches from the edge, in logical pixels.
  ///
  /// `0` pulls nothing.
  final double backdropPullHeight;

  /// How far the glass parts the colors of what it shows, in logical
  /// pixels: red shows what lies up to this far one way and blue what lies
  /// up to this far the other way, so a bright line under the glass shows
  /// with a red side and a blue side, and dimmer, as under a lifted iOS
  /// lens.
  ///
  /// The way red reads is the edge's outward direction mirrored across the
  /// line that falls from the upper left to the lower right, 52.5 degrees
  /// below the horizontal (read from UIKit on iOS 27.2; notes private). At
  /// the upper left and the lower right of a rounded end it points out of
  /// the glass, at the upper right and the lower left into it, and between
  /// them it runs 15 degrees off the edge: leftward along the top,
  /// rightward along the bottom, up the left side and down the right one.
  /// It does not turn with the text direction.
  ///
  /// Each color is read at several points up to that distance, the far ones
  /// weighing most, and green on both sides of its place. The parted color
  /// lies over the glass in full at the edge and fades to nothing
  /// [aberrationDepth] from it. The edge's outward direction is the one
  /// away from the long center line of the layer's glass bounds, as for
  /// [backdropPull]. Unlike [dispersion], it does not need the bevel and
  /// shows over the whole depth. `0` parts nothing. Never negative.
  final double aberration;

  /// How deep from the edge [aberration] fades to nothing, in logical
  /// pixels.
  ///
  /// `0` parts nothing.
  final double aberrationDepth;

  /// Backdrop blur, as an approximate Gaussian-equivalent sigma in logical
  /// pixels.
  ///
  /// The renderer may round or adjust the blur it actually applies. The
  /// default is `4.5`. Default and preset frost grow with the glass's short
  /// side (see [ios27RegularFrost]), and the renderer may raise them on the
  /// device so Impeller downsamples the blur pass there. An explicitly passed
  /// frost is always used as given.
  ///
  /// The default and the presets' frost is the one blur that stands in for
  /// iOS 27's two where the glass draws no [haze] ([frostSigmaAt]). Where it
  /// draws its haze, it blurs the backdrop itself by far less
  /// ([hazedFrostSigmaAt]).
  final double frost;

  /// Separation of the color channels in the refracted edge.
  ///
  /// Red is displaced by `1 + dispersion / 2` and blue by
  /// `1 - dispersion / 2` times the edge displacement. Negative values bend
  /// blue more, as real glass does; the iOS 27 loupe measures about `-0.06`
  /// and other iOS 27 glass `0`. Non-zero values are more expensive to
  /// render, so leave this at `0` unless the glass needs the effect.
  final double dispersion;

  /// Strength of the glint along the light axis.
  ///
  /// The glint recolors the face instead of adding white: it pulls the lit
  /// material toward a target brighter than SDR white carrying the face's own
  /// chroma amplified, so glass over color glints in that color. The light,
  /// dark and clear presets all use `0.6`: the reference rim is a soft, low
  /// plateau, and higher values overexpose the first pixel inside the
  /// silhouette.
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
  /// from the same position ([ios27RegularFrost], [ios27ClearFrost]).
  final double tintAmount;

  /// The wide blur of the backdrop mixed into what the glass shows through,
  /// drawn where the glass reads a copy of the backdrop.
  ///
  /// The default is the haze of light iOS 27 regular glass at slider position
  /// `0`; the iOS 27 presets take theirs from their brightness and
  /// [tintAmount]. Under a haze the frost of a preset is the little blur iOS
  /// leaves the backdrop itself ([hazedFrostSigmaAt]). Pass
  /// [LiquidGlassHaze.none] for glass frosted by [frost] alone.
  final LiquidGlassHaze haze;

  /// Whether [frost] came from the default constructor's default or a
  /// preset's floored path, so the renderer may raise it to the device's
  /// Impeller downsampling point. An explicitly passed [frost] clears it.
  final bool _frostIsFloorEligible;

  // Whether a preset's frost is that of clear glass.
  final bool _frostIsClear;

  /// Whether [frost] is the default constructor's or a preset's, which the
  /// renderer draws as iOS 27 does, and not one passed explicitly, which it
  /// draws as given.
  @internal
  bool get frostIsPreset => _frostIsFloorEligible;

  /// The blur sigma, in logical pixels, that glass whose short side is
  /// [shapeShortSide] logical pixels blurs the backdrop by where it draws its
  /// [haze], on a display of [deviceScale] device pixels per logical pixel.
  ///
  /// An explicitly passed [frost] renders as given (a negative one as `0`).
  /// The frost of the default constructor or a regular preset is the blur iOS
  /// 27 leaves the backdrop under the haze: none up to 64 points, where
  /// controls and bars show the page sharp, growing linearly to 6.6 logical
  /// pixels at 160 points. Clear glass, which has no haze up to the middle
  /// tick, blurs by up to 1.2 logical pixels with [tintAmount]. Without
  /// [shapeShortSide] the value at toolbar size (94 points) is used. A
  /// regular preset given no haze keeps the one blur of [frostSigmaAt].
  ///
  /// Near, not identical: iOS blurs the middle of the glass by 7.8 logical
  /// pixels at 160 points and its rim by half of that; the renderer blurs
  /// all of it by one sigma between the two.
  double hazedFrostSigmaAt(double deviceScale, {double? shapeShortSide}) {
    if (!_frostIsFloorEligible) return math.max<double>(0, frost);
    if (frost <= 0) return 0;
    if (_frostIsClear) {
      return _hazedFrostShare *
          _ios27BlurSigma *
          1.5 *
          tintAmount.clamp(0.0, 0.5);
    }
    if (haze.isNone) {
      return frostSigmaAt(deviceScale, shapeShortSide: shapeShortSide);
    }
    final side = shapeShortSide != null && shapeShortSide > 0
        ? shapeShortSide
        : 94.0;
    final grown = ((side - 64) / 96).clamp(0.0, 1.0);
    return _hazedFrostShare * _ios27BlurSigma * 5 * 0.8 * grown;
  }

  // The sigma, in logical pixels, a unit of iOS 27's blur radius comes to
  // over its pyramid of smaller copies.
  static const double _ios27BlurSigma = 1.94;

  // The share of the blur in the middle of the glass that one sigma for all
  // of it takes: against captures of native glass it lies closest between
  // 0.75 (a card) and 0.9 (a capsule).
  static const double _hazedFrostShare = 0.85;

  /// The blur sigma, in logical pixels, that this [frost] renders with on a
  /// display of [deviceScale] device pixels per logical pixel, for glass
  /// whose short side is [shapeShortSide] logical pixels, where the glass
  /// draws no [haze] and one blur stands in for both.
  ///
  /// An explicitly passed [frost] renders as given (a negative one as `0`).
  /// The frost of the default constructor or a preset grows with the short
  /// side: larger glass is diffused more and smaller glass less, from the
  /// value fitted at toolbar size (94 pt), by at most 1.78 times. It is then
  /// raised so the blur pass is downsampled on the display, at most to what
  /// a 2x display needs; `0` stays `0`. Without [shapeShortSide] the toolbar
  /// value is used. Pass the smaller axis scale when [deviceScale] is not
  /// uniform.
  double frostSigmaAt(double deviceScale, {double? shapeShortSide}) {
    final sigma = math.max<double>(0, frost);
    if (!_frostIsFloorEligible || sigma <= 0) return sigma;
    var sizedSigma = sigma;
    if (shapeShortSide != null && shapeShortSide > 0) {
      // Fitted size response: 2.1 pt at 63 pt, 4.5 pt at 94 pt, 5.6 pt at
      // 118 pt, and 8 pt at 150 pt. Large material cards and sheets are
      // diffused noticeably more than controls. Scale the slider curve by its
      // ratio to the toolbar value so tinted positions keep their fitted
      // growth.
      double smooth(double t) {
        final clamped = t.clamp(0.0, 1.0);
        return clamped * clamped * (3 - 2 * clamped);
      }

      final sizeFrost =
          _minBlurPassSigma +
          2.4 * smooth((shapeShortSide - 63) / 31) +
          1.1 * smooth((shapeShortSide - 94) / 24) +
          2.4 * ((shapeShortSide - 118) / 32).clamp(0.0, 1.0);
      final sizeScale = (sizeFrost / _defaultRegularFrost).clamp(0.0, 1.78);
      sizedSigma = math.max(_minBlurPassSigma, sigma * sizeScale);
    }
    final scale = deviceScale > 0 ? deviceScale : 1.0;
    return math.max(sizedSigma, _frostFloorDevicePx / math.max(scale, 2.0));
  }

  /// Returns a copy with the supplied material controls replaced.
  LiquidGlassSettings copyWith({
    double? refractionHeight,
    double? refractionAmount,
    bool? refractionFitsShape,
    double? backdropShrink,
    double? backdropShrinkRim,
    double? backdropPull,
    double? backdropPullHeight,
    double? aberration,
    double? aberrationDepth,
    double? frost,
    double? dispersion,
    double? highlight,
    double? contourStrength,
    double? contourDirectionality,
    double? bevelShadowStrength,
    double? tintAmount,
    LiquidGlassHaze? haze,
  }) => LiquidGlassSettings._(
    refractionHeight: refractionHeight ?? this.refractionHeight,
    refractionAmount: refractionAmount ?? this.refractionAmount,
    refractionFitsShape: refractionFitsShape ?? this.refractionFitsShape,
    backdropShrink: backdropShrink ?? this.backdropShrink,
    backdropShrinkRim: backdropShrinkRim ?? this.backdropShrinkRim,
    backdropPull: backdropPull ?? this.backdropPull,
    backdropPullHeight: backdropPullHeight ?? this.backdropPullHeight,
    aberration: aberration ?? this.aberration,
    aberrationDepth: aberrationDepth ?? this.aberrationDepth,
    frost: frost ?? this.frost,
    // Passing an explicit frost makes it the caller's, not the preset's.
    floorEligible: frost == null && _frostIsFloorEligible,
    dispersion: dispersion ?? this.dispersion,
    highlight: highlight ?? this.highlight,
    contourStrength: contourStrength ?? this.contourStrength,
    contourDirectionality: contourDirectionality ?? this.contourDirectionality,
    bevelShadowStrength: bevelShadowStrength ?? this.bevelShadowStrength,
    tintAmount: tintAmount ?? this.tintAmount,
    haze: haze ?? this.haze,
    clearFrost: _frostIsClear,
  );

  /// Serializes the public material vector for example presets and tooling.
  ///
  /// [frost] is written explicitly, so a restored map is a flat material
  /// vector: it does not retain the preset's device- or size-dependent
  /// response. The JSON schema is experimental and may change between
  /// releases.
  @experimental
  Map<String, Object> toJson() => {
    'refractionHeight': refractionHeight,
    'refractionAmount': refractionAmount,
    'refractionFitsShape': refractionFitsShape,
    'backdropShrink': backdropShrink,
    'backdropShrinkRim': backdropShrinkRim,
    'backdropPull': backdropPull,
    'backdropPullHeight': backdropPullHeight,
    'aberration': aberration,
    'aberrationDepth': aberrationDepth,
    'frost': frost,
    'dispersion': dispersion,
    'highlight': highlight,
    'contourStrength': contourStrength,
    'contourDirectionality': contourDirectionality,
    'bevelShadowStrength': bevelShadowStrength,
    'tintAmount': tintAmount,
    'haze': haze.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is LiquidGlassSettings &&
          other.refractionHeight == refractionHeight &&
          other.refractionAmount == refractionAmount &&
          other.refractionFitsShape == refractionFitsShape &&
          other.backdropShrink == backdropShrink &&
          other.backdropShrinkRim == backdropShrinkRim &&
          other.backdropPull == backdropPull &&
          other.backdropPullHeight == backdropPullHeight &&
          other.aberration == aberration &&
          other.aberrationDepth == aberrationDepth &&
          other.frost == frost &&
          other.dispersion == dispersion &&
          other.highlight == highlight &&
          other.contourStrength == contourStrength &&
          other.contourDirectionality == contourDirectionality &&
          other.bevelShadowStrength == bevelShadowStrength &&
          other.tintAmount == tintAmount &&
          other.haze == haze &&
          other._frostIsFloorEligible == _frostIsFloorEligible &&
          other._frostIsClear == _frostIsClear;

  @override
  int get hashCode => Object.hash(
    refractionHeight,
    refractionAmount,
    refractionFitsShape,
    backdropShrink,
    backdropShrinkRim,
    backdropPull,
    backdropPullHeight,
    aberration,
    aberrationDepth,
    frost,
    dispersion,
    highlight,
    contourStrength,
    contourDirectionality,
    bevelShadowStrength,
    tintAmount,
    haze,
    _frostIsFloorEligible,
    _frostIsClear,
  );

  @override
  String toString() =>
      'LiquidGlassSettings($refractionHeight, $refractionAmount, '
      '$refractionFitsShape, $backdropShrink, $backdropShrinkRim, '
      '$backdropPull, $backdropPullHeight, $aberration, $aberrationDepth, '
      '$frost, $dispersion, $highlight, $contourStrength, '
      '$contourDirectionality, $bevelShadowStrength, $tintAmount, $haze, '
      '$_frostIsFloorEligible, $_frostIsClear)';
}

/// The rim every glass draws, fitted to iOS 27 and shared by every preset:
/// the glint inside the silhouette, the dark contour outside it and the
/// inner bevel shadow, in logical pixels.
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
