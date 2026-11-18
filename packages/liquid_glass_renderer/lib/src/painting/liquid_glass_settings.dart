import 'dart:math' as math;
import 'dart:ui' show Brightness;

import 'package:liquid_glass_renderer/src/painting/ios27_measures.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_frost.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_haze.dart';
import 'package:meta/meta.dart';

/// The short sides, in logical pixels, where the fitted frost response of
/// [FittedFrost.frostSigmaAt] bends: it rises from `small` through
/// the toolbar's and a large control's, and grows no more past `largest`.
@internal
const frostFitShortSides = (
  small: 63.0,
  toolbar: 94.0,
  large: 118.0,
  largest: 150.0,
);

// The fitted frost, in logical pixels, fitted to iOS 27 at each of
// frostFitShortSides: cards and sheets diffuse more than controls.
const _frostFitSigmas = (
  small: _minBlurPassSigma,
  toolbar: _regularFrostAtClear,
  large: 5.6,
  largest: 8.0,
);

// Smallest non-zero base blur, in logical pixels, used as a floor and by
// clear glass at tinted slider positions. A fitted frost is raised further,
// per device, at render time ([FittedFrost.frostSigmaAt]).
const double _minBlurPassSigma = 2.1;

// Base frost of regular glass at slider position `0`, in logical pixels.
// Fitted to the pinned iOS 27 captures; [ios27RegularFrost] starts here and
// grows with the slider.
const double _regularFrostAtClear = 4.5;

// `5.8` device px reaches ImpellerBlur.halfResolutionSigma through
// ImpellerBlur.deviceSigma at every device pixel ratio from 2 and stays
// below `2.1 * 3 = 6.3`, so 3x screens keep the `2.1` floor
// (frost_floor_test.dart).
const double _frostFloorDevicePx = 5.8;

// iOS 27's blur radius in the middle of a panel's glass, in
// [ios27BlurUnit]s.
const double _ios27PanelBlurRadius = 4;

// The fraction of the blur in the middle of the glass that one sigma for
// all of it takes: against captures of native glass it fits best between
// 0.75 (a card) and 0.9 (a capsule).
const double _hazedFrostFraction = 0.85;

/// The optics and lighting of the glass a layer draws.
///
/// This object contains the optical profile and shared surface lighting.
/// Per-shape color response and materialization belong to
/// [LiquidGlassAppearance]. The renderer derives the glint, the dark contour
/// and the inner bevel shadow from the same SDF, so these controls remain
/// stable across toolbars, capsules, and tabs.
///
/// [sliderPosition] is stored once: a [frost] and a [haze] fitted to iOS 27
/// follow it, so a copy at another position ([copyWith]) is the glass of
/// that position.
///
/// Lighting strengths are display-referred. The defaults of the unnamed
/// constructor may be retuned before 1.0; the version-named presets
/// (`ios27*`) track Apple's appearance on that OS version.
/// `LiquidGlassMaterial` gives settings with the appearance and the shadows
/// that match them.
@immutable
final class LiquidGlassSettings {
  /// Creates settings from optical and lighting controls.
  ///
  /// The defaults are the light iOS 27 regular glass
  /// ([LiquidGlassSettings.ios27Regular]). Distances are logical pixels;
  /// strengths use the `0` to `1` range.
  const LiquidGlassSettings({
    this.refractionHeight = _defaultRefractionHeight,
    this.refractionAmount = _defaultRefractionAmount,
    this.refractionFitsShape = true,
    this.backdropShrink = 0,
    this.backdropPull = 0,
    this.backdropPullDepth = 0,
    this.aberration = 0,
    this.aberrationDepth = 0,
    this.frost = const LiquidGlassFrost.ios27Regular(),
    this.dispersion = 0,
    this.glintStrength = _defaultGlintStrength,
    this.contourStrength = _lightContourStrength,
    this.contourDirectionality = _lightContourDirectionality,
    this.bevelShadowStrength = _regularBevelShadowStrength,
    this.sliderPosition = 0,
    this.haze = const LiquidGlassHaze.ios27Regular(
      brightness: Brightness.light,
    ),
  });

  /// Settings fitted to iOS 27 regular glass (`Glass.regular`, which Apple
  /// also uses for toolbars and `.glass` buttons) in [brightness], at the
  /// Liquid Glass slider position [sliderPosition].
  ///
  /// This is a useful starting point, not a universal Apple-material preset:
  /// platform materials vary with appearance, control role, and accessibility
  /// settings. Pass a [frost] when the surrounding design needs a clearer or
  /// softer surface.
  ///
  /// The lighting is the measured iOS 27 rim: a 1.2 pt glint on both walls
  /// along the light axis, a 0.75 pt dark contour outside the silhouette
  /// that concentrates where the glint fades, and a faint inner shadow cast
  /// by the rim, fitted on the Reduce Motion off references. In dark mode
  /// the contour is stronger and vanishes entirely where the normal faces
  /// the light axis. The light ones are the defaults of the unnamed
  /// constructor.
  ///
  /// [frost] defaults to [LiquidGlassFrost.ios27Regular], and [haze] is
  /// [LiquidGlassHaze.ios27Regular] of [brightness].
  const LiquidGlassSettings.ios27Regular({
    required Brightness brightness,
    this.sliderPosition = 0,
    this.frost = const LiquidGlassFrost.ios27Regular(),
  }) : refractionHeight = _defaultRefractionHeight,
       refractionAmount = _defaultRefractionAmount,
       refractionFitsShape = true,
       backdropShrink = 0,
       backdropPull = 0,
       backdropPullDepth = 0,
       aberration = 0,
       aberrationDepth = 0,
       dispersion = 0,
       glintStrength = _defaultGlintStrength,
       contourStrength = brightness == Brightness.dark
           ? 0.88
           : _lightContourStrength,
       contourDirectionality = brightness == Brightness.dark
           ? 1
           : _lightContourDirectionality,
       bevelShadowStrength = _regularBevelShadowStrength,
       haze = brightness == Brightness.dark
           ? const LiquidGlassHaze.ios27Regular(brightness: Brightness.dark)
           : const LiquidGlassHaze.ios27Regular(brightness: Brightness.light);

  /// Settings fitted to iOS 27 `Glass.clear`, identical in light and dark,
  /// at the Liquid Glass slider position [sliderPosition].
  ///
  /// Clear glass has the same glint line and angular falloff as regular glass;
  /// its brighter glint comes from its color model. The contour exists only
  /// where the normal is perpendicular to the light axis, and there is no
  /// inner shadow. The Liquid Glass slider only blurs clear glass:
  /// [frost] defaults to [LiquidGlassFrost.ios27Clear], and [haze] is
  /// [LiquidGlassHaze.ios27Clear]. Pair it with
  /// [LiquidGlassAppearance.ios27Clear].
  ///
  /// The lens is the full 20 pt / 60 pt bevel on glass from 93 points on its
  /// short side and narrows with smaller glass; see [refractionFitsShape].
  /// At slider 0 the glass is completely clear and unblurred. Pass a
  /// [frost] to override, for example `LiquidGlassFrost.sigma(0)` for
  /// unsoftened glass at every position.
  const LiquidGlassSettings.ios27Clear({
    this.sliderPosition = 0,
    this.frost = const LiquidGlassFrost.ios27Clear(),
  }) : refractionHeight = _defaultRefractionHeight,
       refractionAmount = _defaultRefractionAmount,
       refractionFitsShape = false,
       backdropShrink = 0,
       backdropPull = 0,
       backdropPullDepth = 0,
       aberration = 0,
       aberrationDepth = 0,
       dispersion = 0,
       glintStrength = _defaultGlintStrength,
       contourStrength = 0.36,
       contourDirectionality = 1,
       bevelShadowStrength = 0,
       haze = const LiquidGlassHaze.ios27Clear();

  static const double _defaultRefractionHeight = 20;
  static const double _defaultRefractionAmount = 60;
  static const double _defaultGlintStrength = 0.6;
  static const double _lightContourStrength = 0.43;
  static const double _lightContourDirectionality = 0.77;
  static const double _regularBevelShadowStrength = 0.036;

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
  /// of the layer's glass: `0` keeps its size, `0.08` shows it at 92%.
  ///
  /// Clamped to `0` to `0.75`, so the glass can reveal more of its
  /// surroundings but never enlarges (and pixelates) the captured backdrop.
  /// Magnifiers should re-render their content at full resolution instead
  /// (the example app's loupe does). The bevel's [refractionAmount] is applied
  /// on top.
  ///
  /// All glass in one layer shares that center, so give a shrinking
  /// shape its own layer when it should shrink about itself.
  final double backdropShrink;

  /// How far outside itself the glass reads the backdrop at its edge, in
  /// logical pixels: the edge pulls its surroundings in, so the glass shows
  /// more of what is around it, as a lifted iOS lens does.
  ///
  /// The pull is whole at the edge and falls along a quarter circle to
  /// nothing [backdropPullDepth] from it, so the middle of glass deeper
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
  final double backdropPullDepth;

  /// How far the glass parts the colors of what it shows, in logical
  /// pixels: red shows what lies up to this far one way and blue what lies
  /// up to this far the other way, so a bright line under the glass shows
  /// with a red side and a blue side, and dimmer, as under a lifted iOS
  /// lens.
  ///
  /// The way red reads is the edge's outward direction mirrored across the
  /// line that falls from the upper left to the lower right, 52.5 degrees
  /// below the horizontal (read from UIKit on iOS 27.2). At
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

  /// How far the glass blurs the backdrop.
  ///
  /// The default, [LiquidGlassFrost.ios27Regular], follows
  /// [sliderPosition], the size of the glass and the display, and under a
  /// [haze] it is the little blur iOS 27 leaves the backdrop itself. A
  /// [LiquidGlassFrost.sigma] is drawn as given; the renderer may round the
  /// blur it applies.
  final LiquidGlassFrost frost;

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
  final double glintStrength;

  /// Peak absorption of the dark contour just outside the silhouette, which
  /// is 0.75 logical pixels wide. `0` removes the contour.
  final double contourStrength;

  /// How strongly the contour concentrates where the glint fades.
  ///
  /// `0` darkens the whole silhouette evenly. `1` keeps the contour only where
  /// the normal is perpendicular to the light axis and removes it where the
  /// glint sits, as in iOS 27 dark mode.
  final double contourDirectionality;

  /// Fraction of the light transmitted through the glass that the inner
  /// shadow cast by the rim absorbs at its peak. The glass's own emission is
  /// not shaded. The shadow falls 6 pt below the lit top wall, stays at the
  /// rim on the sides and is absent at the bottom, as on iOS 27.
  final double bevelShadowStrength;

  /// Position of the iOS 27 Liquid Glass slider in Settings, from `0`
  /// (Clear) to `1` (Tinted). It is not a color: a shape's color is its
  /// [LiquidGlassAppearance.tint].
  ///
  /// Apps set this themselves; the renderer does not read the system value.
  /// The slider makes the iOS 27 neutral wash more opaque and strengthens the
  /// dark contour; the glint is unchanged, and the direct color model ignores
  /// it. A [frost] and a [haze] fitted to iOS 27 follow it; ones given as
  /// numbers do not.
  final double sliderPosition;

  /// The wide blur of the backdrop mixed into what the glass shows through,
  /// drawn where the glass reads a copy of the backdrop.
  ///
  /// The default is the haze of light iOS 27 regular glass, which follows
  /// [sliderPosition]. Pass [LiquidGlassHaze.none] for glass frosted by
  /// [frost] alone.
  final LiquidGlassHaze haze;

  /// Returns a copy with the supplied controls replaced.
  LiquidGlassSettings copyWith({
    double? refractionHeight,
    double? refractionAmount,
    bool? refractionFitsShape,
    double? backdropShrink,
    double? backdropPull,
    double? backdropPullDepth,
    double? aberration,
    double? aberrationDepth,
    LiquidGlassFrost? frost,
    double? dispersion,
    double? glintStrength,
    double? contourStrength,
    double? contourDirectionality,
    double? bevelShadowStrength,
    double? sliderPosition,
    LiquidGlassHaze? haze,
  }) => LiquidGlassSettings(
    refractionHeight: refractionHeight ?? this.refractionHeight,
    refractionAmount: refractionAmount ?? this.refractionAmount,
    refractionFitsShape: refractionFitsShape ?? this.refractionFitsShape,
    backdropShrink: backdropShrink ?? this.backdropShrink,
    backdropPull: backdropPull ?? this.backdropPull,
    backdropPullDepth: backdropPullDepth ?? this.backdropPullDepth,
    aberration: aberration ?? this.aberration,
    aberrationDepth: aberrationDepth ?? this.aberrationDepth,
    frost: frost ?? this.frost,
    dispersion: dispersion ?? this.dispersion,
    glintStrength: glintStrength ?? this.glintStrength,
    contourStrength: contourStrength ?? this.contourStrength,
    contourDirectionality: contourDirectionality ?? this.contourDirectionality,
    bevelShadowStrength: bevelShadowStrength ?? this.bevelShadowStrength,
    sliderPosition: sliderPosition ?? this.sliderPosition,
    haze: haze ?? this.haze,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiquidGlassSettings &&
          other.refractionHeight == refractionHeight &&
          other.refractionAmount == refractionAmount &&
          other.refractionFitsShape == refractionFitsShape &&
          other.backdropShrink == backdropShrink &&
          other.backdropPull == backdropPull &&
          other.backdropPullDepth == backdropPullDepth &&
          other.aberration == aberration &&
          other.aberrationDepth == aberrationDepth &&
          other.frost == frost &&
          other.dispersion == dispersion &&
          other.glintStrength == glintStrength &&
          other.contourStrength == contourStrength &&
          other.contourDirectionality == contourDirectionality &&
          other.bevelShadowStrength == bevelShadowStrength &&
          other.sliderPosition == sliderPosition &&
          other.haze == haze;

  @override
  int get hashCode => Object.hash(
    refractionHeight,
    refractionAmount,
    refractionFitsShape,
    backdropShrink,
    backdropPull,
    backdropPullDepth,
    aberration,
    aberrationDepth,
    frost,
    dispersion,
    glintStrength,
    contourStrength,
    contourDirectionality,
    bevelShadowStrength,
    sliderPosition,
    haze,
  );

  @override
  String toString() =>
      'LiquidGlassSettings($refractionHeight, $refractionAmount, '
      '$refractionFitsShape, $backdropShrink, '
      '$backdropPull, $backdropPullDepth, $aberration, $aberrationDepth, '
      '$frost, $dispersion, $glintStrength, $contourStrength, '
      '$contourDirectionality, $bevelShadowStrength, $sliderPosition, $haze)';
}

/// What a [LiquidGlassSettings.frost] and [LiquidGlassSettings.haze] come to
/// at the settings' slider position, for glass of a size on a display.
@internal
extension FittedFrost on LiquidGlassSettings {
  /// Whether [LiquidGlassSettings.frost] is fitted to iOS 27, which the
  /// renderer draws as iOS 27 does, and not a [LiquidGlassFrost.sigma],
  /// which it draws as given.
  bool get frostIsFitted => frost is! LiquidGlassFixedFrost;

  /// The frost at toolbar size (94 pt) before the display raises it, in
  /// logical pixels: what [frostSigmaAt] grows with the glass.
  double get frostBase => switch (frost) {
    LiquidGlassFixedFrost(:final sigma) => sigma,
    LiquidGlassIos27RegularFrost() => ios27RegularFrost(sliderPosition),
    LiquidGlassIos27ClearFrost() =>
      sliderPosition <= 0
          ? 0
          : math.max(_minBlurPassSigma, ios27ClearFrost(sliderPosition)),
  };

  /// What [LiquidGlassSettings.haze] mixes in at the slider position, or
  /// null where it changes nothing.
  LiquidGlassFixedHaze? get drawnHaze => drawnHazeOf(haze, sliderPosition);

  /// The blur sigma, in logical pixels, that glass whose short side is
  /// [shapeShortSide] logical pixels blurs the backdrop by where it draws its
  /// haze, on a display of [devicePixelRatio] device pixels per logical
  /// pixel.
  ///
  /// A [LiquidGlassFrost.sigma] renders as given (a negative one as `0`); a
  /// fitted frost as its factory documents. Without [shapeShortSide] the
  /// value at toolbar size is used. A regular frost given no haze keeps the
  /// one blur of [frostSigmaAt].
  double hazedFrostSigmaAt(double devicePixelRatio, {double? shapeShortSide}) {
    switch (frost) {
      case LiquidGlassFixedFrost(:final sigma):
        return math.max<double>(0, sigma);
      case LiquidGlassIos27ClearFrost():
        if (sliderPosition <= 0) return 0;
        return _hazedFrostFraction *
            ios27BlurUnit *
            1.5 *
            sliderPosition.clamp(0.0, sliderMiddleTick);
      case LiquidGlassIos27RegularFrost():
        if (drawnHaze == null) {
          return frostSigmaAt(devicePixelRatio, shapeShortSide: shapeShortSide);
        }
        final side = shapeShortSide != null && shapeShortSide > 0
            ? shapeShortSide
            : frostFitShortSides.toolbar;
        return _hazedFrostFraction *
            ios27BlurUnit *
            _ios27PanelBlurRadius *
            ios27PanelProgress(side);
    }
  }

  /// The blur sigma, in logical pixels, that the frost renders with on a
  /// display of [devicePixelRatio] device pixels per logical pixel, for glass
  /// whose short side is [shapeShortSide] logical pixels, where the glass
  /// draws no haze and one blur stands in for both.
  ///
  /// A [LiquidGlassFrost.sigma] renders as given (a negative one as `0`).
  /// A fitted frost grows with the short side and is raised for the display
  /// as [LiquidGlassFrost.ios27Regular] documents; `0` stays `0`. Without
  /// [shapeShortSide] the toolbar value is used. Pass the smaller axis scale
  /// when [devicePixelRatio] is not uniform.
  double frostSigmaAt(double devicePixelRatio, {double? shapeShortSide}) =>
      frostSigmaOf(
        frostBase,
        fitted: frostIsFitted,
        devicePixelRatio: devicePixelRatio,
        shapeShortSide: shapeShortSide,
      );
}

/// Backdrop blur of iOS 27 regular glass, in logical pixels, at toolbar size
/// for the Liquid Glass slider position [sliderPosition] where one blur
/// stands in for the haze: 4.5, 6.9 and 18.7 pt at 0, 0.5 and 1
/// ([LiquidGlassFrost.ios27Regular]).
@internal
double ios27RegularFrost(double sliderPosition) {
  final amount = sliderPosition.clamp(0.0, 1.0);
  final (:upTo, :past) = splitAtMiddleTick(amount);
  return _regularFrostAtClear * math.exp(0.85 * upTo + 2 * past);
}

/// Apple's measured backdrop blur of iOS 27 `.clear` glass, in logical
/// pixels, for the Liquid Glass slider position [sliderPosition]: 0.35, 1.28
/// and 16.4 pt at 0, 0.5 and 1 ([LiquidGlassFrost.ios27Clear], which draws
/// none at `0` and floors tinted positions at `2.1`).
@internal
double ios27ClearFrost(double sliderPosition) {
  final amount = sliderPosition.clamp(0.0, 1.0);
  final (:upTo, :past) = splitAtMiddleTick(amount);
  return 0.35 * math.exp(2.6 * upTo + 5.1 * past);
}

/// The rim every glass draws, fitted to iOS 27 and shared by every preset:
/// the glint inside the silhouette, the dark contour outside it and the
/// inner bevel shadow, in logical pixels.
@internal
abstract final class GlassRim {
  /// Width of the glint line inward from the silhouette, in logical pixels.
  static const double glintWidth = 1.2;

  /// Angular spread of the glint: `0.5`, measured on iOS 27, fades it
  /// linearly with the normal's component perpendicular to the light axis.
  static const double glintWrap = 0.5;

  /// Energy of the glint opposite the light-facing rim, relative to it.
  static const double glintOppositeStrength = 1;

  /// Width of the dark contour outside the silhouette, in logical pixels.
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

/// [FittedFrost.frostSigmaAt] of settings whose frost at toolbar size is
/// [frost], fitted to iOS 27 where [fitted] ([FittedFrost.frostIsFitted]).
@internal
double frostSigmaOf(
  double frost, {
  required bool fitted,
  required double devicePixelRatio,
  double? shapeShortSide,
}) {
  final sigma = math.max<double>(0, frost);
  if (!fitted || sigma <= 0) return sigma;
  var sizedSigma = sigma;
  if (shapeShortSide != null && shapeShortSide > 0) {
    double smooth(double t) {
      final clamped = t.clamp(0.0, 1.0);
      return clamped * clamped * (3 - 2 * clamped);
    }

    final (:small, :toolbar, :large, :largest) = frostFitShortSides;
    const fit = _frostFitSigmas;
    final sizeFrost =
        fit.small +
        (fit.toolbar - fit.small) *
            smooth((shapeShortSide - small) / (toolbar - small)) +
        (fit.large - fit.toolbar) *
            smooth((shapeShortSide - toolbar) / (large - toolbar)) +
        (fit.largest - fit.large) *
            ((shapeShortSide - large) / (largest - large)).clamp(0.0, 1.0);
    final sizeScale = sizeFrost / fit.toolbar;
    sizedSigma = math.max(
      _minBlurPassSigma,
      sigma * sizeScale,
    );
  }
  return math.max(
    sizedSigma,
    _frostFloorDevicePx / math.max(devicePixelRatio, 2.0),
  );
}
