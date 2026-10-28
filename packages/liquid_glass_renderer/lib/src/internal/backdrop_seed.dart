import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/internal/ancestor_clip.dart';
import 'package:liquid_glass_renderer/src/internal/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/internal/glass_frame_clock.dart';
import 'package:liquid_glass_renderer/src/internal/retained_glass_clip.dart';
import 'package:liquid_glass_renderer/src/internal/running_under_flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';

/// The device pixels of the first view, or `null` without one.
Size? _screenPixels() {
  final views = RendererBinding.instance.renderViews;
  return views.isEmpty ? null : views.first.flutterView.physicalSize;
}

/// Sizes the pass of one backdrop effect so that it changes size rarely, which
/// is when Impeller allocates a render target.
///
/// A pass is grown to [PixelBuckets]: [PixelBuckets.fine] up to
/// [smallMaxSide] device pixels, [PixelBuckets.standard] above. A pass that is
/// not changing size keeps those buckets (a coarse bucket would only make it
/// bigger). Once a pass covering more than [largeFraction] of the screen
/// changes size it is bucketed at [PixelBuckets.coarse] and only grows: it
/// keeps the largest size it needed until the size it needs has been unchanged
/// for [stableFrames] frames, which also ends the coarse sizing. State is per
/// effect.
@internal
class BackdropPassSizing {
  /// The longest side, in device pixels, of a pass bucketed at
  /// [PixelBuckets.fine]. A bucket adds up to `bucket - 1` px per side of
  /// backdrop copy and blur fill, a noticeable share of a 250x100 px pill,
  /// while 32 px still turns a per-frame stretch into a size change every ~12
  /// frames at typical animation speeds.
  static const smallMaxSide = 192;

  /// A pass covering more than this fraction of the screen's pixels is large.
  static const largeFraction = 0.25;

  /// A large pass stays large until it covers less than this fraction.
  static const largeKeepFraction = 0.125;

  /// Frames a pass's size must stay unchanged before it counts as no longer
  /// changing, and before a large pass may shrink.
  static const stableFrames = 30;

  /// Switches the coarse, grow-only sizing of large passes off, to measure
  /// what it saves.
  @visibleForTesting
  static bool debugStabilizeLargePasses = true;

  /// The bucket, in device pixels, for a pass of [width] by [height] device
  /// pixels; [large] passes use [PixelBuckets.coarse].
  static int bucketFor(double width, double height, {bool large = false}) =>
      large
      ? PixelBuckets.coarse
      : math.max(width, height) <= smallMaxSide
      ? PixelBuckets.fine
      : PixelBuckets.standard;

  bool _large = false;
  bool _changing = false;
  Size? _wanted;
  Offset? _origin;
  int _wantedFrame = -1;
  int _still = 0;
  Rect? _rect;
  Rect? _fresh;
  int _stable = 0;
  int _frame = -1;

  /// Whether the pass is currently sized as a large, changing one.
  bool get large => _large && _changing;

  /// Whether the size the pass needs changed within the last [stableFrames]
  /// frames. A resizing pass is placed on a
  /// global pixel grid (see [planSeededBackdropPass]); one that only moves is
  /// given a size that is a function of its own extent.
  bool get resizing => _changing;

  /// Decides whether a pass of [width] by [height] logical pixels at
  /// [devicePixelRatio] is sized coarsely now.
  ///
  /// [cutOrigin] is the pass's snapped origin in device pixels when a clip or
  /// the screen cuts it: its cut size then follows the origin, so a pass that
  /// moves there counts as changing size.
  bool decideLarge(
    double width,
    double height,
    double devicePixelRatio, {
    Offset? cutOrigin,
  }) {
    final screen = _screenPixels();
    if (!debugStabilizeLargePasses || screen == null) return _reset();
    final fraction =
        width *
        height *
        devicePixelRatio *
        devicePixelRatio /
        (screen.width * screen.height);
    _large = _large ? fraction >= largeKeepFraction : fraction > largeFraction;
    final frame = GlassFrameClock.frame;
    if (frame != _wantedFrame) {
      _wantedFrame = frame;
      final size = Size(width, height);
      final moved =
          _wanted != null &&
          (_wanted != size || (cutOrigin != null && _origin != cutOrigin));
      _wanted = size;
      _origin = cutOrigin;
      _still = moved ? 0 : _still + 1;
      if (moved) {
        _changing = true;
      } else if (_still >= stableFrames) {
        _changing = false;
      }
    }
    if (!(_large && _changing)) {
      _rect = null;
      _fresh = null;
      _stable = 0;
      return false;
    }
    return true;
  }

  bool _reset() {
    _large = false;
    _changing = false;
    _rect = null;
    _fresh = null;
    _stable = 0;
    return false;
  }

  /// The rect a large pass is given for [fresh], the rect it needs now.
  Rect stabilize(Rect fresh) {
    final frame = GlassFrameClock.frame;
    if (frame != _frame) {
      _frame = frame;
      _stable = _fresh == fresh ? _stable + 1 : 0;
      _fresh = fresh;
    }
    final previous = _rect;
    Rect result;
    if (previous == null) {
      result = fresh;
    } else if (_stable >= stableFrames) {
      result = fresh;
    } else if (_contains(previous, fresh)) {
      result = previous;
    } else if (fresh.width >= previous.width &&
        fresh.height >= previous.height) {
      // Bigger in both ways, or the same size somewhere else: no extra growth.
      result = fresh;
    } else {
      result = previous.expandToInclude(fresh);
    }
    return _rect = result;
  }

  static bool _contains(Rect outer, Rect inner) =>
      outer.left <= inner.left &&
      outer.top <= inner.top &&
      outer.right >= inner.right &&
      outer.bottom >= inner.bottom;
}

/// A pass's blur, taken over by the pass as its seed; see
/// `SeededBackdropPassLayer.bindFilter`.
@internal
class PassBlur {
  const PassBlur({
    required this.sigma,
    required this.tileMode,
    required this.withoutBlur,
    this.blurOnly = false,
  });

  /// The blur's sigma in the pass layer's coordinates, the same on both axes
  /// (glass blurs are round).
  final double sigma;

  /// The blur's tile mode, which decides what it reads past the backdrop's
  /// edge.
  final TileMode tileMode;

  /// The filter without that blur.
  final ui.ImageFilter withoutBlur;

  /// Whether the filter is nothing but the blur, so [withoutBlur] does
  /// nothing. Natively such a filter is a plain blur, which Impeller already
  /// crops to its clip.
  final bool blurOnly;
}

/// Whether [layer] was disposed, as far as asserts can tell.
///
/// `Layer.debugDisposed` throws a `LateInitializationError` when asserts are
/// off (profile and release), so it may only be read inside an assert. Without
/// asserts this is `false`: mutating a disposed layer's properties is
/// harmless there, and that is all this guards.
bool _layerDisposed(Layer layer) {
  var disposed = false;
  assert(() {
    disposed = layer.debugDisposed;
    return true;
  }(), 'reads debugDisposed only while asserts are on');
  return disposed;
}

/// Whether Impeller renders what [layer] holds in a pass of its own.
bool _createsOwnPass(ContainerLayer layer) => switch (layer) {
  OpacityLayer(:final alpha) => alpha == null || alpha < 255,
  ColorFilterLayer() => true,
  ImageFilterLayer() => true,
  ShaderMaskLayer() => true,
  ClipRectLayer(:final clipBehavior) ||
  ClipRRectLayer(:final clipBehavior) ||
  ClipRSuperellipseLayer(:final clipBehavior) ||
  ClipPathLayer(
    :final clipBehavior,
  ) => clipBehavior == Clip.antiAliasWithSaveLayer,
  NativeClipLayer(:final enabled, :final clipBehavior) =>
    enabled && clipBehavior == Clip.antiAliasWithSaveLayer,
  _ => false,
};

/// How a glass's pass is seeded; see [SeededBackdropPassLayer].
@internal
enum BackdropSeed {
  /// No pass: the glass filter reads the backdrop itself.
  none,

  /// The pass is seeded by an identity backdrop filter, and the glass filter
  /// (blur and shader, or blur and color transfer) then runs over the small
  /// pass instead of over the whole backdrop. Used where Impeller would not
  /// crop a blur seed (see `SeededBackdropPassLayer._blurSeedCrops`).
  identity,

  /// The pass is seeded by a plain blur of the backdrop, which Impeller crops
  /// to the pass, and the glass filter in it is only the shader (or the color
  /// transfer).
  blur,
}

/// The backdrop filter that seeds a natively seeded pass.
///
/// The scene builder takes a backdrop key only from a [BackdropFilterLayer],
/// and the key's id is private to it, so the seed is one: a layer that is
/// never in the tree, only added to the scene by its pass, with whatever the
/// pass puts in it (see `SeededBackdropPassLayer._addSeededPass`) as its
/// children.
class _SeedLayer extends BackdropFilterLayer {
  void Function(ui.SceneBuilder builder)? addInner;

  @override
  void addChildrenToScene(ui.SceneBuilder builder) => addInner?.call(builder);

  /// Adds this layer and what [addInner] adds to [builder].
  void addTo(ui.SceneBuilder builder) => addToScene(builder);

  /// Forgets the engine layer of the last scene, for a scene that does not
  /// contain this layer.
  void dropEngineLayer() => engineLayer = null;

  @override
  void dispose() {
    addInner = null;
    super.dispose();
  }
}

/// How a backdrop effect's pass is placed; see [planSeededBackdropPass].
@internal
class BackdropPassPlan {
  const BackdropPassPlan._(
    this.layerRect,
    this.globalRect,
    this.frameLocalRect, {
    required this.hidden,
    this.layerToGlobal,
    this.devicePixelRatio = 1,
    this.resizing = false,
  });

  /// No pass can be predicted (rotation, skew, perspective): the effect
  /// paints without one.
  static const unsupported = BackdropPassPlan._(
    null,
    null,
    null,
    hidden: false,
  );

  /// Everything the effect could touch is clipped away.
  static const clipped = BackdropPassPlan._(null, null, null, hidden: true);

  /// The pass in the coordinates of the layer that holds it.
  final Rect? layerRect;

  /// The pass in screen coordinates, snapped outward to device pixels. Its
  /// top-left is the origin fragment coordinates are relative to.
  final Rect? globalRect;

  /// The pass in the owner's coordinates as seen by retained layers, which
  /// are shifted by the compositor translation.
  final Rect? frameLocalRect;

  /// Whether the effect paints nothing.
  final bool hidden;

  /// Maps layer coordinates to screen coordinates.
  final Matrix4? layerToGlobal;

  /// Whether the size the pass needs changed within the last
  /// [BackdropPassSizing.stableFrames] frames (see
  /// [BackdropPassSizing.resizing]).
  final bool resizing;

  /// The device pixel ratio the pass was snapped with.
  final double devicePixelRatio;

  /// The screen-space origin of the pass, if there is one.
  Offset? get globalOrigin => globalRect?.topLeft;
}

/// Device pixels of tolerance when snapping: floating point noise in a rect
/// that is on the pixel grid must not cost a whole pixel (and a new size).
const _pixelEpsilon = 1e-3;

Rect _snapOutward(Rect rect, double dpr) => Rect.fromLTRB(
  (rect.left * dpr + _pixelEpsilon).floorToDouble() / dpr,
  (rect.top * dpr + _pixelEpsilon).floorToDouble() / dpr,
  (rect.right * dpr - _pixelEpsilon).ceilToDouble() / dpr,
  (rect.bottom * dpr - _pixelEpsilon).ceilToDouble() / dpr,
);

/// Places the pass around a backdrop effect.
///
/// The pass is [innerLayerRect] (what the effect's own clip covers, in the
/// coordinates of the layer that holds the pass) grown by [reach], the
/// distance a blur reads past its clip, cut to [ownerClip] and to every clip
/// painted above [owner], then snapped outward to whole device pixels: that
/// is the coverage Impeller gives the pass, so the origin derived here is the
/// one the effect's shaders observe. [paintOffset] maps owner coordinates to
/// the layer's, and [translation] is retained compositor motion applied below
/// the owner since the layer was painted. A large pass is sized by [sizing]
/// (see [BackdropPassSizing]).
@internal
BackdropPassPlan planSeededBackdropPass({
  required RenderBox owner,
  required Rect innerLayerRect,
  required Offset paintOffset,
  required Offset translation,
  required double reach,
  required double devicePixelRatio,
  Rect? ownerClip,
  BackdropPassSizing? sizing,
}) {
  final toGlobal = owner.getTransformTo(null);
  if (!isRectilinearTransform(toGlobal)) return BackdropPassPlan.unsupported;
  final toLocal = Matrix4.tryInvert(toGlobal);
  if (toLocal == null) return BackdropPassPlan.unsupported;
  final shift = translation - paintOffset;
  final wanted = innerLayerRect.shift(shift).inflate(reach);
  var local = wanted;
  if (ownerClip != null) local = local.intersect(ownerClip);
  if (local.isEmpty) return BackdropPassPlan.clipped;
  var global = MatrixUtils.transformRect(toGlobal, local);
  final outer = screenPaintClipAbove(owner);
  if (outer != null) global = global.intersect(outer);
  if (global.isEmpty) return BackdropPassPlan.clipped;
  // Impeller reuses an offscreen target only when its size is exactly equal,
  // so a pass that changes size every frame (an animated pill) allocates and
  // frees images every frame, and so does one that merely moves if its size
  // depends on where it is. Grow the pass to device-pixel buckets, then cut
  // it to the same clips as above: the effect still paints only inside its
  // own clip, and the pass outside it is cleared.
  final wantedGlobal = MatrixUtils.transformRect(toGlobal, wanted);
  // The pixels the wanted rect needs by its own extent, which a translation
  // does not change (rounding noise must not cost a pixel).
  final needWidth = math.max(
    1,
    (wantedGlobal.width * devicePixelRatio - _pixelEpsilon).ceil(),
  );
  final needHeight = math.max(
    1,
    (wantedGlobal.height * devicePixelRatio - _pixelEpsilon).ceil(),
  );
  Rect? limit;
  if (ownerClip != null) {
    limit = MatrixUtils.transformRect(toGlobal, ownerClip);
  }
  if (outer != null) limit = limit?.intersect(outer) ?? outer;
  final screen = _screenPixels();
  if (screen != null) {
    final view = Offset.zero & (screen / devicePixelRatio);
    limit = limit?.intersect(view) ?? view;
  }
  final cut =
      limit != null &&
      (wantedGlobal.left * devicePixelRatio <
              limit.left * devicePixelRatio - _pixelEpsilon ||
          wantedGlobal.top * devicePixelRatio <
              limit.top * devicePixelRatio - _pixelEpsilon ||
          wantedGlobal.right * devicePixelRatio >
              limit.right * devicePixelRatio + _pixelEpsilon ||
          wantedGlobal.bottom * devicePixelRatio >
              limit.bottom * devicePixelRatio + _pixelEpsilon);
  final large =
      sizing?.decideLarge(
        needWidth / devicePixelRatio,
        needHeight / devicePixelRatio,
        devicePixelRatio,
        cutOrigin: cut
            ? Offset(
                (wantedGlobal.left * devicePixelRatio + _pixelEpsilon)
                    .floorToDouble(),
                (wantedGlobal.top * devicePixelRatio + _pixelEpsilon)
                    .floorToDouble(),
              )
            : null,
      ) ??
      false;
  final bucket = BackdropPassSizing.bucketFor(
    needWidth.toDouble(),
    needHeight.toDouble(),
    large: large,
  );
  Rect bucketed;
  if (large || (sizing?.resizing ?? false)) {
    // The pass changes size: bucket it on a global grid, so a growing edge
    // that the screen cuts still changes the cut size only on bucket steps.
    bucketed = wantedGlobal.expandToPixelBuckets(
      devicePixelRatio,
      bucketSize: bucket,
    );
    // The size before the clips cut it is what the hysteresis keeps stable:
    // the clips then cut the same rect from frame to frame.
    if (large) bucketed = sizing!.stabilize(bucketed);
  } else {
    // The pass keeps its size: the size is the glass's own extent (plus the
    // pixel its fractional origin can need) rounded up to a bucket, and the
    // origin is the snapped position, so a pure translation never changes it.
    //
    // On an axis where that would reach past a clip or the screen, the cut
    // size would follow the origin, changing every frame the glass moves (a
    // sheet growing from a screen edge): that axis keeps the global grid.
    int up(int value) => (value + bucket - 1) ~/ bucket * bucket;
    (double, double) axis(
      double near,
      double far,
      int need,
      double? limitNear,
      double? limitFar,
    ) {
      final start = (near * devicePixelRatio + _pixelEpsilon).floorToDouble();
      final end = start + up(need + 1);
      if (limitNear != null &&
          limitFar != null &&
          (start < limitNear * devicePixelRatio - _pixelEpsilon ||
              end > limitFar * devicePixelRatio + _pixelEpsilon)) {
        return (
          (near * devicePixelRatio / bucket).floorToDouble() * bucket,
          (far * devicePixelRatio / bucket).ceilToDouble() * bucket,
        );
      }
      return (start, end);
    }

    final (x0, x1) = axis(
      wantedGlobal.left,
      wantedGlobal.right,
      needWidth,
      limit?.left,
      limit?.right,
    );
    final (y0, y1) = axis(
      wantedGlobal.top,
      wantedGlobal.bottom,
      needHeight,
      limit?.top,
      limit?.bottom,
    );
    bucketed = Rect.fromLTRB(
      x0 / devicePixelRatio,
      y0 / devicePixelRatio,
      x1 / devicePixelRatio,
      y1 / devicePixelRatio,
    );
  }
  if (ownerClip != null) {
    bucketed = bucketed.intersect(
      MatrixUtils.transformRect(toGlobal, ownerClip),
    );
  }
  if (outer != null) bucketed = bucketed.intersect(outer);
  // Floating point can leave the bucket a hair inside the exact rect.
  global = global.expandToInclude(bucketed);
  final snapped = _snapOutward(global, devicePixelRatio);
  final snappedLocal = MatrixUtils.transformRect(toLocal, snapped);
  return BackdropPassPlan._(
    snappedLocal.shift(-shift),
    snapped,
    snappedLocal.shift(-translation),
    hidden: false,
    layerToGlobal: toGlobal.clone()
      ..translateByDouble(shift.dx, shift.dy, 0, 1),
    devicePixelRatio: devicePixelRatio,
    resizing: sizing?.resizing ?? false,
  );
}

/// Parent of one native backdrop effect (a clip around a backdrop filter).
///
/// Impeller runs `ImageFilter.compose(blur, shader)` over the whole backdrop
/// texture: only a plain blur as the outermost backdrop filter is cropped to
/// its clip. So, wherever Impeller renders ([enabled]), this layer paints the
/// effect inside a pass of exactly the planned rect (the glass plus what its
/// blur reads), seeded by a plain blur that Impeller crops to that rect (or an
/// identity, see [BackdropSeed]), and the effect's own filter runs over the
/// small pass without its blur. Its shaders see a pass with a known origin.
///
/// Every seed reads the backdrop for itself. It shares one read with other
/// seeds only through the key the glass was given (a `BackdropGroup`): when
/// every filter of a key is equal, Impeller runs that filter once over the
/// whole texture with no crop, so seeds of one key alternate between two
/// filters that differ by far less than a pixel ([seedSigmaStep],
/// [seedMatrixStep]).
///
/// Whether that is wanted is decided every frame, when the scene is prepared
/// and everything painted before this layer is final
/// ([updateSubtreeNeedsAddToScene]). When it is not, the layer is just a
/// parent: the children paint directly, with the backdrop key they would have
/// had without it, exactly as an effect that never had a pass. The owner is
/// told through [onActiveChanged] so it can map coordinates accordingly
/// before the scene is built.
@internal
class SeededBackdropPassLayer extends ContainerLayer {
  /// How glass passes are seeded: [BackdropSeed.blur] wherever Impeller
  /// renders, and [BackdropSeed.none] on Skia, on the web, and under
  /// `flutter test`, whose tester renders seeded passes wrongly. The suite can
  /// still run seeded with `--dart-define=LIQUID_GLASS_SEED_PASSES=true`.
  static BackdropSeed get mode => debugModeOverride ?? _defaultMode;

  /// Replaces [mode] for a test.
  @visibleForTesting
  static BackdropSeed? debugModeOverride;

  static final BackdropSeed _defaultMode =
      !kIsWeb &&
          ui.ImageFilter.isShaderFilterSupported &&
          (!runningUnderFlutterTest ||
              const bool.fromEnvironment('LIQUID_GLASS_SEED_PASSES'))
      ? BackdropSeed.blur
      : BackdropSeed.none;

  /// Whether glass paints in seeded passes at all.
  static bool get enabled => mode != BackdropSeed.none;

  static const _identity = ColorFilter.matrix(<double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  BackdropPassPlan _plan = BackdropPassPlan.unsupported;
  Rect? _modifiedBounds;
  bool _active = true;
  BackdropFilterLayer? _filter;
  BackdropKey? _key;

  /// Runs when the decision to seed, rather than paint without a pass,
  /// changes while the scene is prepared.
  VoidCallback? onActiveChanged;

  /// Whether the pass stays seeded while its size changes. FakeGlass passes
  /// do: on Pixel 10 their seed saved SoC energy on a resizing sheet (-16%)
  /// and on moving layers (-24%), where real glass's seed cost GPU energy
  /// (+26%) while resizing (see [_nativeSeedFor]).
  bool seedWhileResizing = false;

  /// Whether the pass is in effect: the owner planned one and it is seeded
  /// (see [nativeSeed]). Starts optimistic; the first scene preparation
  /// decides.
  bool get active => _active;

  /// How the pass is seeded (see [mode]), `none` while it is not in effect.
  BackdropSeed get nativeSeed => _active ? _seed : BackdropSeed.none;

  /// The pass the owner asked for, whether or not it is in effect.
  BackdropPassPlan get plan => _plan;

  /// The pass, in this layer's parent's coordinates, already snapped to
  /// device pixels; `null` when the children paint without a pass.
  Rect? get passRect => _active ? _plan.layerRect : null;

  /// The area the children can change, in the same coordinates. Outside it
  /// the pass holds exactly what was painted before it.
  Rect? get modifiedBounds => _modifiedBounds;

  /// Paints nothing: the effect is clipped away entirely.
  bool get hidden => _plan.hidden;

  /// Applies the owner's [plan] for an effect whose children change
  /// [modified].
  void apply(BackdropPassPlan plan, Rect? modified) {
    final changed =
        plan.layerRect != _plan.layerRect ||
        plan.hidden != _plan.hidden ||
        modified != _modifiedBounds;
    _plan = plan;
    _modifiedBounds = modified;
    if (changed) markNeedsAddToScene();
    _syncKey();
  }

  /// The backdrop key the wrapped filter has natively, which it paints with
  /// whenever there is no pass.
  BackdropKey? get backdropGroupKey => _key;

  /// Tells the layer which filter it wraps and the key it paints with when
  /// there is no pass.
  ///
  /// Inside a pass the filter has no key: the pass's seed carries it (see
  /// [_decideSeedKey]).
  ///
  /// With a [blur], the filter's blur can be left to the pass: when it seeds
  /// its backdrop with the blur (see [BackdropSeed.blur]) the filter
  /// is swapped for [PassBlur.withoutBlur]. [full] is then the filter the
  /// owner would have without that; the owner must keep it current, because
  /// the pass puts it back when the seed ends.
  void bindFilter(
    BackdropFilterLayer filter,
    BackdropKey? key, {
    ui.ImageFilter? full,
    PassBlur? blur,
  }) {
    _fullFilter = full ?? filter.filter;
    _blur = blur;
    if (!identical(key, _key)) {
      _leaveGroup();
      _key = key;
      if (key != null) (_groups[key] ??= _KeyGroup()).members.add(this);
    }
    // The filter is owner-created; remember the blend mode it asked for
    // unless it is the one this layer set.
    if (!identical(_filter, filter) ||
        !_blendOverridden ||
        filter.blendMode != BlendMode.src) {
      _blendOverridden = false;
      _ownerBlendMode = filter.blendMode;
    }
    _filter = filter;
    _syncKey();
    // The owner has just put its own filter on the layer.
    _applyFilter();
  }

  BlendMode _ownerBlendMode = BlendMode.srcOver;
  bool _blendOverridden = false;
  ui.ImageFilter? _fullFilter;
  PassBlur? _blur;

  void _applyFilter() {
    final filter = _filter;
    if (filter == null || _layerDisposed(filter)) return;
    // The pass has blurred its backdrop already (as the seed), so the glass
    // filter keeps only what comes after the blur.
    final blur = _blur;
    final blurred = blur != null && _seed == BackdropSeed.blur;
    final wanted = blurred ? blur.withoutBlur : _fullFilter;
    if (wanted != null && !identical(filter.filter, wanted)) {
      filter.filter = wanted;
    }
  }

  void _leaveGroup() {
    final key = _key;
    if (key != null) _groups[key]?.members.remove(this);
  }

  static final _groups = Expando<_KeyGroup>('SeededBackdropPassLayer groups');

  PassFilterClip? _filterClip;
  Path? _silhouette;

  /// The true outline of the effect, when the child clip is only a rect that
  /// covers it (so the clip, and the backdrop layer under it, keep one size
  /// from frame to frame). The pass cuts the effect to this outline with its
  /// outside-clear. In the same coordinates as the child clip; ignored while
  /// the children paint without a pass.
  Path? get silhouette => _silhouette;
  set silhouette(Path? value) {
    if (identical(value, _silhouette)) return;
    _silhouette = value;
    markNeedsAddToScene();
  }

  /// The clip around the wrapped filter, and the part of the pass outside it;
  /// `null` when the children are not one clip around one filter.
  PassFilterClip? _readFilterClip(Rect rect) {
    final clip = firstChild;
    if (clip == null || clip.nextSibling != null) return null;
    Object geometry;
    final Clip behavior;
    switch (clip) {
      case ClipRectLayer(:final clipRect?, :final clipBehavior):
        geometry = clipRect;
        behavior = clipBehavior;
      case ClipPathLayer(:final clipPath?, :final clipBehavior):
        geometry = clipPath;
        behavior = clipBehavior;
      default:
        return null;
    }
    if (behavior == Clip.none) return null;
    if (_silhouette case final outline?) geometry = outline;
    final last = _filterClip;
    if (last != null &&
        last.rect == rect &&
        (geometry is Path
            ? identical(last.geometry, geometry)
            : last.geometry == geometry) &&
        last.behavior == behavior) {
      return last;
    }
    final Path outside;
    if (geometry is Rect) {
      outside = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect)
        ..addRect(geometry);
    } else {
      outside = Path.combine(
        PathOperation.difference,
        Path()..addRect(rect),
        geometry as Path,
      );
    }
    return _filterClip = PassFilterClip(
      rect,
      geometry,
      behavior,
      outside,
      behavior != Clip.hardEdge,
    );
  }

  // Inside a pass the filter has no key (the seed carries it) and paints with
  // `BlendMode.src`: the pass then holds only the filter's output, in its
  // clip, which is composited over the parent pass like the native filter's
  // output would be.
  void _syncKey() {
    final filter = _filter;
    if (filter == null) return;
    final inPass = passRect != null;
    filter.backdropKey = inPass ? null : _key;
    filter.blendMode = inPass ? BlendMode.src : _ownerBlendMode;
    _blendOverridden = inPass;
    if (!inPass && _seed != BackdropSeed.none) {
      _seed = BackdropSeed.none;
      _applyFilter();
    }
  }

  @override
  void dispose() {
    if (_blendOverridden && _filter != null && !_layerDisposed(_filter!)) {
      _filter!.blendMode = _ownerBlendMode;
    }
    _seed = BackdropSeed.none;
    _applyFilter();
    _fullFilter = null;
    _blur = null;
    _seedFilter = null;
    _seedKey = null;
    _filter = null;
    _leaveGroup();
    _key = null;
    onActiveChanged = null;
    _outsidePicture?.dispose();
    _outsidePicture = null;
    _seedLayer?.dispose();
    _seedLayer = null;
    super.dispose();
  }

  @override
  void updateSubtreeNeedsAddToScene() {
    _decide();
    super.updateSubtreeNeedsAddToScene();
  }

  // Everything painted before this layer, including the effects whose own
  // decisions came earlier in this same pass over the tree, is final here.
  // A native seed reads the backdrop when the scene is rasterized, like any
  // backdrop filter, so the pass is only added to the scene again when its
  // own decision changes.
  void _decide() {
    final rect = _plan.layerRect;
    _setSeed(_nativeSeedFor(rect));
    if (rect != null && !hidden) {
      _settleActive(_seed != BackdropSeed.none);
      // The owner may have remapped its filter on the way.
      _applyFilter();
    }
    _decideSeedKey();
  }

  // MARK: Native seed

  // How the pass is seeded this frame (`none` while it is not in effect), and
  // what the seed was last painted with.
  BackdropSeed _seed = BackdropSeed.none;
  BackdropKey? _seedKey;
  int _seedVariant = 0;
  ui.ImageFilter? _seedFilter;
  BackdropSeed _seedFilterMode = BackdropSeed.none;
  double _seedFilterSigma = 0;
  TileMode _seedFilterTileMode = TileMode.mirror;
  int _seedFilterVariant = 0;

  // Whether another seed paints with this pass's key this frame.
  bool _seedShared = false;

  /// The offset, in sigma, between two seed blurs that share a key: above the
  /// engine's tolerance when it compares blurs (`kEhCloseEnough`, 1e-3), and
  /// far below anything a blur can show.
  @visibleForTesting
  static const seedSigmaStep = 0.004;

  /// The scale of the red channel of the second of two identity seeds that
  /// share a key. Color matrices are compared bit for bit; this changes no
  /// 8 bit value (it adds at most 0.026 of a level).
  @visibleForTesting
  static const seedMatrixStep = 1e-4;

  /// How the pass is seeded, whether or not it is in effect.
  @visibleForTesting
  BackdropSeed get debugSeed => _seed;

  /// The backdrop key the seed filter is pushed with, if any.
  @visibleForTesting
  BackdropKey? get debugSeedKey => _seedKey;

  /// Whether the seed's key is shared with another seed.
  @visibleForTesting
  bool get debugSeedShared => _seedShared;

  /// The filter that seeds the pass, if it is seeded.
  @visibleForTesting
  ui.ImageFilter? get debugSeedFilter =>
      _seed == BackdropSeed.none ? null : _seedFilterFor();

  /// The seed this pass wants. A pass whose size is changing is not seeded,
  /// unless it is [seedWhileResizing]: the seed is a render target of the
  /// pass's size, which Impeller reuses only at exactly the same size, so it
  /// allocates and frees one on every bucket step, where the glass's own
  /// filter over its clip, which is what the pass then paints, does not
  /// (Pixel 10, a sheet resizing continuously: GPU +26% seeded, +3% without).
  /// It is seeded again once its size has been unchanged for
  /// [BackdropPassSizing.stableFrames] frames. A glass without a blur has
  /// nothing a pass would crop (its shader already only runs inside the
  /// glass's own layer), and a glass that is nothing but a blur is a plain
  /// blur natively, which Impeller crops by itself: both stay as they are.
  /// A blur seed is an identity seed where Impeller would not crop the blur
  /// (see [_blurSeedCrops]).
  BackdropSeed _nativeSeedFor(Rect? rect) {
    final mode = SeededBackdropPassLayer.mode;
    final blur = _blur;
    if (mode == BackdropSeed.none ||
        rect == null ||
        hidden ||
        blur == null ||
        blur.sigma <= 0 ||
        blur.blurOnly ||
        (_plan.resizing && !seedWhileResizing) ||
        _readFilterClip(rect) == null) {
      return BackdropSeed.none;
    }
    // A blur Impeller would not crop is no better than the glass's own, which
    // then runs over the small pass instead.
    return mode == BackdropSeed.blur && !_blurSeedCrops()
        ? BackdropSeed.identity
        : mode;
  }

  /// Whether Impeller crops a plain blur of this pass's backdrop to the pass.
  ///
  /// It only does when the pass, grown by the blur's padding, lies inside the
  /// texture it reads (`CalculateDownsamplePassArgs` needs the expanded
  /// coverage hint inside the input snapshot); otherwise it downsamples and
  /// blurs the whole backdrop, as the native path does. A pass reaching a
  /// screen edge is cut there by the screen, so its padded hint always leaves
  /// it. Only the root pass is a known size (the screen); a pass inside
  /// another is assumed not to.
  bool _blurSeedCrops() {
    final global = _plan.globalRect;
    final toGlobal = _plan.layerToGlobal;
    final screen = _screenPixels();
    final sigma = _blur?.sigma ?? 0;
    if (global == null ||
        toGlobal == null ||
        screen == null ||
        sigma <= 0 ||
        !_inRootPass(this)) {
      return false;
    }
    final dpr = _plan.devicePixelRatio;
    final m = toGlobal.storage;
    // `ScaleSigma` and the kernel radius of Impeller 3.47's blur.
    final damped = math.min(sigma, 500.0);
    final scaledSigma =
        damped * (1 - 3.4e-3 * damped + 3.4e-6 * damped * damped);
    double padding(double axis) {
      final device = math.min(scaledSigma * dpr * axis, 500.0);
      final radius = device > 0.5 ? (device - 0.5) * 1.73205080757 : 0.0;
      // The padding is whole pixels, with one more for rounding.
      return radius.ceilToDouble() + 1;
    }

    final padX = padding(math.sqrt(m[0] * m[0] + m[1] * m[1]));
    final padY = padding(math.sqrt(m[4] * m[4] + m[5] * m[5]));
    return global.left * dpr - padX >= 0 &&
        global.top * dpr - padY >= 0 &&
        global.right * dpr + padX <= screen.width &&
        global.bottom * dpr + padY <= screen.height;
  }

  void _setSeed(BackdropSeed seed) {
    if (seed == _seed) return;
    _seed = seed;
    markNeedsAddToScene();
  }

  // The pass is in effect or not; the owner maps its coordinates accordingly.
  void _settleActive(bool inEffect) {
    if (inEffect == _active) return;
    _active = inEffect;
    _syncKey();
    onActiveChanged?.call();
  }

  /// Decides the key the seed is pushed with: the glass's own, if it has one.
  /// Whatever shares it reads the backdrop at the first of them, as it does
  /// without a pass.
  void _decideSeedKey() {
    BackdropKey? key;
    var variant = 0;
    _seedShared = false;
    final own = _key;
    if (_seed != BackdropSeed.none && own != null) {
      final order = _groups[own]?.participants(this);
      final index = order?.indexOf(this) ?? 0;
      key = own;
      variant = index < 0 ? 0 : index % 2;
      _seedShared = (order?.length ?? 0) > 1;
    }
    if (!identical(key, _seedKey) || variant != _seedVariant) {
      _seedKey = key;
      _seedVariant = variant;
      markNeedsAddToScene();
    }
  }

  /// The filter that seeds the pass: an identity, or a plain blur of the same
  /// sigma as the glass's own; one of two near copies of it while its key is
  /// shared (see [seedSigmaStep]).
  ui.ImageFilter _seedFilterFor() {
    final mode = _seed;
    final sigma = _blur?.sigma ?? 0;
    final tileMode = _blur?.tileMode ?? TileMode.mirror;
    final variant = _seedKey == null ? 0 : _seedVariant;
    final cached = _seedFilter;
    if (cached != null &&
        _seedFilterMode == mode &&
        _seedFilterSigma == sigma &&
        _seedFilterTileMode == tileMode &&
        _seedFilterVariant == variant) {
      return cached;
    }
    _seedFilterMode = mode;
    _seedFilterSigma = sigma;
    _seedFilterTileMode = tileMode;
    _seedFilterVariant = variant;
    return _seedFilter = switch (mode) {
      BackdropSeed.blur => ui.ImageFilter.blur(
        sigmaX: sigma + variant * seedSigmaStep,
        sigmaY: sigma + variant * seedSigmaStep,
        tileMode: tileMode,
      ),
      _ when variant == 0 => _identity,
      _ => ColorFilter.matrix(<double>[
        1 + seedMatrixStep, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, 1, 0, //
      ]),
    };
  }

  _SeedLayer? _seedLayer;
  ui.Picture? _outsidePicture;
  Path? _outsidePath;
  bool _outsideAntiAlias = false;

  /// Draws, in the pass, a picture that clears what lies in the pass but not
  /// under the effect's clip ([PassFilterClip.outside]).
  void _clearOutside(ui.SceneBuilder builder, PassFilterClip clip) {
    if (!identical(_outsidePath, clip.outside) ||
        _outsideAntiAlias != clip.antiAlias) {
      _outsidePicture?.dispose();
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawPath(
        clip.outside,
        Paint()
          ..blendMode = BlendMode.clear
          ..isAntiAlias = clip.antiAlias
          ..color = const Color(0xFF000000),
      );
      _outsidePicture = recorder.endRecording();
      _outsidePath = clip.outside;
      _outsideAntiAlias = clip.antiAlias;
    }
    builder.addPicture(Offset.zero, _outsidePicture!);
  }

  /// Adds a pass over [rect] seeded by [seed], a backdrop filter Impeller runs
  /// over the backdrop (under [key], when it has one), with this layer's
  /// children inside it. The pass holds only the output of the effect in its
  /// [clip]: what the seed leaves outside it is cleared, and the pass is
  /// composited over the parent.
  void _addSeededPass(
    ui.SceneBuilder builder,
    Rect rect, {
    required ui.ImageFilter seed,
    required PassFilterClip clip,
    BackdropKey? key,
  }) {
    final oldClip = engineLayer;
    engineLayer = builder.pushClipRect(
      rect,
      clipBehavior: ui.Clip.hardEdge,
      oldLayer: oldClip is ui.ClipRectEngineLayer ? oldClip : null,
    );
    (_seedLayer ??= _SeedLayer())
      ..filter = seed
      ..backdropKey = key
      ..blendMode = BlendMode.srcOver
      ..addInner = (inner) {
        addChildrenToScene(inner);
        _clearOutside(inner, clip);
      }
      ..addTo(builder);
    builder.pop();
  }

  /// The pass [addToScene] adds around the children, in this layer's
  /// parent's coordinates, or null when they paint without one: the rect
  /// it clips them to, the filter that seeds it, the backdrop that filter
  /// reads (a blur reads three sigmas past the pass), and the clip it cuts
  /// the effect to.
  ({Rect rect, ui.ImageFilter seed, Rect reads, PassFilterClip clip})?
  get scenePass {
    final rect = passRect;
    if (hidden || rect == null || _seed == BackdropSeed.none) return null;
    final clip = _readFilterClip(rect);
    if (clip == null) return null;
    final blur = _seed == BackdropSeed.blur ? _blur : null;
    return (
      rect: rect,
      seed: _seedFilterFor(),
      reads: blur == null ? rect : rect.inflate(3 * blur.sigma),
      clip: clip,
    );
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    if (scenePass case final pass?) {
      _addSeededPass(
        builder,
        pass.rect,
        seed: pass.seed,
        clip: pass.clip,
        key: _seedKey,
      );
      return;
    }
    _forgetEngineLayers();
    if (!hidden) addChildrenToScene(builder);
  }

  /// Forgets the retained engine layers of a pass that is not being added.
  void _forgetEngineLayers() {
    engineLayer = null;
    _seedLayer?.dropEngineLayer();
  }
}

/// The clip around the effect inside a pass, and what the pass holds outside
/// it.
@internal
class PassFilterClip {
  // ignore: avoid_positional_boolean_parameters
  PassFilterClip(
    this.rect,
    this.geometry,
    this.behavior,
    this.outside,
    this.antiAlias,
  );

  final Rect rect;

  /// The clip's [Rect] or [Path].
  final Object geometry;
  final Clip behavior;

  /// The pass rect minus the clip.
  final Path outside;
  final bool antiAlias;
}

/// The passes whose filters share one backdrop key.
class _KeyGroup {
  final Set<SeededBackdropPassLayer> members = {};

  /// The members of [pass]'s layer tree that paint, in paint order.
  List<SeededBackdropPassLayer> participants(SeededBackdropPassLayer pass) {
    Layer root = pass;
    while (root.parent != null) {
      root = root.parent!;
    }
    final result = [
      for (final m in members)
        if (m.attached && !m.hidden && identical(_rootOf(m), root)) m,
    ];
    if (result.length > 1) result.sort(_comparePaintOrder);
    return result;
  }
}

Layer _rootOf(Layer layer) {
  var root = layer;
  while (root.parent != null) {
    root = root.parent!;
  }
  return root;
}

/// Orders two layers of one tree by paint order.
int _comparePaintOrder(Layer a, Layer b) {
  if (identical(a, b)) return 0;
  final pa = <Layer>[for (Layer? l = a; l != null; l = l.parent) l];
  final pb = <Layer>[for (Layer? l = b; l != null; l = l.parent) l];
  var i = pa.length - 1;
  var j = pb.length - 1;
  while (i > 0 && j > 0 && identical(pa[i - 1], pb[j - 1])) {
    i--;
    j--;
  }
  // An ancestor paints before what it holds.
  if (i == 0) return -1;
  if (j == 0) return 1;
  for (var l = pa[i - 1].nextSibling; l != null; l = l.nextSibling) {
    if (identical(l, pb[j - 1])) return -1;
  }
  return 1;
}

/// Whether Impeller paints [layer] in the root pass: nothing above it paints
/// in an offscreen pass of its own.
bool _inRootPass(Layer layer) {
  for (var p = layer.parent; p != null; p = p.parent) {
    if (_createsOwnPass(p)) return false;
    switch (p) {
      // An opacity seed is a backdrop filter, but only a pass while seeded.
      case OpacitySeedLayer(seeded: true):
        return false;
      case OpacitySeedLayer():
        break;
      case BackdropFilterLayer():
      case SeededBackdropPassLayer(passRect: != null):
        return false;
      default:
        break;
    }
  }
  return true;
}
