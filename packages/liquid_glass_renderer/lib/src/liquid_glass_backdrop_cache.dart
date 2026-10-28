import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_renderer/src/internal/backdrop_seed.dart';
import 'package:liquid_glass_renderer/src/internal/retained_glass_clip.dart';
import 'package:meta/meta.dart';

/// A copy of what lies under a glass surface, which the surface's
/// `LiquidGlassLayer` paints over instead of reading its backdrop, while
/// nothing the glass samples has changed since the copy was taken. Give it
/// to the layer as `LiquidGlassBackdrop.cached`.
///
/// A backdrop filter reads and filters everything under the glass every
/// frame, even when that is a page that does not move: the page below a
/// sheet, an alert or a popover. Give the layer of such a surface a cache
/// whose [source] is the repaint boundary that holds everything under it,
/// drawn untransformed at the screen's origin (the boundary of the route
/// below). The cache then copies that boundary after a frame, blurred as the
/// layer's blur pass would blur it, and the glass paints over the copy: no
/// backdrop read and no blur pass.
///
/// The copy holds only what [source] draws. The one thing between the
/// boundary and the glass that the glass accounts for is [overlay], a
/// uniform color (a dimming barrier) it lays over the copy itself, so the
/// color may animate without a new copy.
///
/// The copy serves a frame only while the layers the boundary draws within
/// a band around the glass are the same ones it was taken from; a frame in
/// which they changed reads the backdrop as before. The band takes in all
/// that a backdrop filter in it reads, and all of the boundary when the
/// filter's reach is unknown. A copy is taken only after the whole boundary
/// and the frost have stayed the same for a frame, so continuous motion
/// anywhere in it costs no copies. A boundary that holds a texture, a
/// platform view or a layer the cache cannot compare never holds still and
/// is never copied.
///
/// A layer reads its backdrop as before while the source is null, not
/// composited or not drawn untransformed at the screen's origin, or drawn
/// under an opacity, a filter, a shader mask or a clip other than a rect,
/// or while a rect clip above it cuts into what the glass samples. It also
/// does while the layer is inside a `LiquidGlassCapture` or a fractional
/// `Opacity` or `FadeTransition`, or shares its backdrop
/// (`useBackdropGroup` or `backdropKey`). Dispose the cache with the
/// surface.
class LiquidGlassBackdropCache {
  /// Creates a cache of what [source] draws.
  LiquidGlassBackdropCache({required this.source});

  /// The repaint boundary that holds everything under the glass, or null
  /// when there is none.
  final RenderObject? Function() source;

  /// The uniform color painted between [source] and the glass, such as a
  /// dimming barrier; transparent when there is none.
  ///
  /// The glass lays it over the copy; set it every frame it changes.
  ui.Color overlay = const ui.Color(0x00000000);

  // How far the band a copy is checked over reaches past the region it was
  // taken for, as a share of the source's height: room for the glass to
  // move without a new copy, little enough that a control animating
  // elsewhere on the page (the button that opened the surface) does not
  // invalidate it.
  static const double _bandMargin = 0.15;

  ui.Image? _image;
  Rect _copied = Rect.zero;
  List<Object?> _signature = const [];
  double _sigma = -1;
  List<Object?>? _previousPage;
  double _previousSigma = -1;
  bool _capturing = false;
  bool _disposed = false;

  /// How many copies the cache has taken.
  @visibleForTesting
  int debugCaptures = 0;

  /// Whether the source can be copied: built, composited and drawn as it
  /// is, untransformed at the screen's origin.
  bool get ready => _source() != null;

  // The source, its layer, and the screen rect the layers above it clip it
  // to.
  ({RenderBox boundary, OffsetLayer layer, Rect visible})? _source() {
    final boundary = source();
    if (boundary == null || !boundary.attached || boundary is! RenderBox) {
      return null;
    }
    // ignore: invalid_use_of_protected_member
    final layer = boundary.layer;
    if (layer is! OffsetLayer || !_isOrigin(boundary.getTransformTo(null))) {
      return null;
    }
    final visible = _visibleArea(layer);
    if (visible == null) return null;
    return (boundary: boundary, layer: layer, visible: visible);
  }

  /// The copy of the source blurred by [sigma] logical pixels that is still
  /// exact for this frame inside [region] (screen logical pixels: all the
  /// glass may sample, frost and refraction included), or null, and the
  /// glass reads its backdrop this frame. A null result also schedules a
  /// copy after this frame when the source and [sigma] have held still since
  /// the previous call.
  ///
  /// Called while the frame composites, when the source's layers are final.
  @internal
  ui.Image? imageFor({
    required double sigma,
    required double devicePixelRatio,
    required Rect region,
  }) {
    final source = _source();
    if (source == null) return null;
    final (:boundary, :layer, :visible) = source;
    // Past the source's edges there is nothing to copy or to change.
    final reach = region.intersect(Offset.zero & boundary.size);
    // The copy holds the source unclipped.
    if (visible.intersect(reach) != reach) return null;
    final image = _image;
    if (image != null &&
        sigma == _sigma &&
        _copied.left <= reach.left &&
        _copied.top <= reach.top &&
        _copied.right >= reach.right &&
        _copied.bottom >= reach.bottom &&
        _same(_sign(layer, _copied), _signature)) {
      // Whether the whole source holds still matters only once the copy
      // stops serving: until then, signing all of it every frame is wasted.
      _previousPage = null;
      return image;
    }
    final page = _sign(layer, Rect.largest);
    final previousPage = _previousPage;
    final stable =
        previousPage != null &&
        sigma == _previousSigma &&
        _same(page, previousPage);
    _previousPage = page;
    _previousSigma = sigma;
    if (stable && !_capturing) {
      _capturing = true;
      final size = boundary.size;
      final top =
          ((reach.top - size.height * _bandMargin) * devicePixelRatio)
              .floorToDouble() /
          devicePixelRatio;
      final band = Rect.fromLTRB(
        0,
        top,
        size.width,
        reach.bottom + size.height * _bandMargin,
      ).intersect(Offset.zero & size);
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _capturing = false;
        _capture(band, sigma, devicePixelRatio);
      });
    }
    return null;
  }

  // Copies the source as the frame that just composited left it, valid
  // while [band] stays the same; nothing paints between compositing and
  // the post-frame callbacks.
  void _capture(Rect band, double sigma, double devicePixelRatio) {
    if (_disposed || band.isEmpty) return;
    final source = _source();
    if (source == null) return;
    final (:boundary, :layer, visible: _) = source;
    final signature = _sign(layer, band);
    // The whole source at its own origin: its pixels are the screen's.
    final raw = layer.toImageSync(
      Offset.zero & boundary.size,
      pixelRatio: devicePixelRatio,
    );
    var image = raw;
    if (sigma > 0) {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImage(
        raw,
        Offset.zero,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma * devicePixelRatio,
            sigmaY: sigma * devicePixelRatio,
            tileMode: TileMode.mirror,
          ),
      );
      final picture = recorder.endRecording();
      image = picture.toImageSync(raw.width, raw.height);
      picture.dispose();
      raw.dispose();
    }
    _image?.dispose();
    _image = image;
    _copied = band;
    _signature = signature;
    _sigma = sigma;
    debugCaptures++;
  }

  /// Releases the copy.
  void dispose() {
    _disposed = true;
    _image?.dispose();
    _image = null;
    _signature = const [];
    _previousPage = null;
  }

  static bool _isOrigin(Matrix4 m) {
    const epsilon = 1e-6;
    final s = m.storage;
    return (s[0] - 1).abs() < epsilon &&
        (s[5] - 1).abs() < epsilon &&
        s[1].abs() < epsilon &&
        s[4].abs() < epsilon &&
        s[12].abs() < epsilon &&
        s[13].abs() < epsilon;
  }

  static bool _same(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (identical(x, y)) continue;
      // An image filter is unchanged only as the same object: comparing a
      // shader filter by value creates its native filter, which takes the
      // shader's uniforms then rather than when the scene is built.
      if (x is ui.ImageFilter) return false;
      if (x != y) return false;
    }
    return true;
  }

  // The screen rect the layers above [layer] clip it to, or null when they
  // draw it other than as it is: through an opacity, a filter, a shader
  // mask, a pass, a clip that is not a rect, or a layer the cache does not
  // know.
  static Rect? _visibleArea(Layer layer) {
    final above = [
      for (var node = layer.parent; node != null; node = node.parent) node,
    ];
    var visible = Rect.largest;
    final transform = Matrix4.identity();
    // From the root down, below the root's own transform, which maps
    // logical pixels to device pixels.
    for (var i = above.length - 2; i >= 0; i--) {
      final node = above[i];
      Rect? clip;
      switch (node) {
        case OpacityLayer(alpha: final alpha?) when alpha < 255:
          return null;
        case ImageFilterLayer() ||
            ColorFilterLayer() ||
            ShaderMaskLayer() ||
            BackdropFilterLayer() ||
            SeededBackdropPassLayer(scenePass: _?):
          return null;
        case ClipRectLayer(:final clipRect?, :final clipBehavior)
            when clipBehavior != Clip.none:
          clip = clipRect;
        case NativeClipLayer(
              enabled: true,
              geometry: final Rect geometry,
              :final clipBehavior,
            )
            when clipBehavior != Clip.none:
          clip = geometry;
        case ClipRRectLayer(:final clipBehavior) ||
                ClipRSuperellipseLayer(:final clipBehavior) ||
                ClipPathLayer(:final clipBehavior) ||
                NativeClipLayer(enabled: true, :final clipBehavior)
            when clipBehavior != Clip.none:
          return null;
        case OffsetLayer() ||
            AnnotatedRegionLayer() ||
            LeaderLayer() ||
            ClipRectLayer() ||
            ClipRRectLayer() ||
            ClipRSuperellipseLayer() ||
            ClipPathLayer() ||
            NativeClipLayer() ||
            SeededBackdropPassLayer():
          break;
        case _ when node.runtimeType == ContainerLayer:
          break;
        default:
          return null;
      }
      if (clip != null) {
        visible = visible.intersect(MatrixUtils.transformRect(transform, clip));
      }
      node.applyTransform(i == 0 ? layer : above[i - 1], transform);
    }
    return visible;
  }

  // What the source contributes inside [region] (screen logical px): every
  // leaf whose bounds reach the region, with the transform, clip, opacity
  // and filters it is drawn under. Two equal signatures draw the same
  // pixels there. A backdrop filter that draws into the region reads around
  // it, so the region grows by what each such filter reads until it holds
  // all of it. Inside another filter's or a seed's pass a filter reads only
  // that pass; on the screen it may read anything, so the region becomes
  // the whole source, except for a seed, which reads a known margin around
  // its pass. A leaf the framework cannot see into (a texture, a platform
  // view, a follower, a layer of a type it does not know) never compares
  // equal.
  static List<Object?> _sign(Layer root, Rect region) {
    var area = region;
    while (true) {
      final out = <Object?>[];
      final reads = _signOnce(root, area, out);
      if (reads == area) return out;
      area = reads;
    }
  }

  // Signs [root] over [region] into [out], and returns [region] grown by
  // what the backdrop filters that draw into it read.
  static Rect _signOnce(Layer root, Rect region, List<Object?> out) {
    var reads = region;

    void walk(
      Layer layer,
      Matrix4 transform,
      Rect? clip,
      Rect? pass,
      List<Object?> state, {
      bool filtered = false,
    }) {
      bool reaches(Rect local) {
        // A filter above can move pixels anywhere: its whole subtree counts.
        if (filtered) return true;
        var bounds = MatrixUtils.transformRect(transform, local);
        if (clip != null) bounds = bounds.intersect(clip);
        return bounds.overlaps(region);
      }

      void leaf(Object? content) {
        out
          ..add(content)
          ..add(transform.clone())
          ..add(clip)
          ..addAll(state)
          ..add(#leaf);
      }

      Rect clipped(Rect local) {
        final bounds = MatrixUtils.transformRect(transform, local);
        return clip == null ? bounds : clip.intersect(bounds);
      }

      Matrix4 shifted(Offset offset) =>
          transform.clone()..translateByDouble(offset.dx, offset.dy, 0, 1);

      var next = transform;
      var nextClip = clip;
      var nextPass = pass;
      var nextState = state;
      var nextFiltered = filtered;
      switch (layer) {
        case PictureLayer():
          if (reaches(layer.canvasBounds)) leaf(layer.picture);
          return;
        case TextureLayer(:final rect) || PlatformViewLayer(:final rect):
          if (reaches(rect)) leaf(Object());
          return;
        case TransformLayer():
          next = shifted(layer.offset);
          if (layer.transform case final matrix?) next.multiply(matrix);
        case OpacityLayer():
          next = shifted(layer.offset);
          nextState = [...state, layer.alpha];
        case ImageFilterLayer():
          next = shifted(layer.offset);
          nextState = [...state, layer.imageFilter];
          nextClip = null;
          nextFiltered = true;
        case OffsetLayer():
          next = shifted(layer.offset);
        case ClipRectLayer():
          if (layer.clipBehavior != Clip.none) {
            nextClip = clipped(layer.clipRect!);
            nextState = [...state, layer.clipRect, layer.clipBehavior];
          }
        case ClipRRectLayer():
          if (layer.clipBehavior != Clip.none) {
            nextClip = clipped(layer.clipRRect!.outerRect);
            nextState = [...state, layer.clipRRect, layer.clipBehavior];
          }
        case ClipRSuperellipseLayer():
          if (layer.clipBehavior != Clip.none) {
            nextClip = clipped(layer.clipRSuperellipse!.outerRect);
            nextState = [...state, layer.clipRSuperellipse, layer.clipBehavior];
          }
        case ClipPathLayer():
          if (layer.clipBehavior != Clip.none) {
            nextClip = clipped(layer.clipPath!.getBounds());
            nextState = [...state, layer.clipPath, layer.clipBehavior];
          }
        case NativeClipLayer(
          enabled: true,
          :final geometry?,
          :final clipBehavior,
        ):
          if (clipBehavior != Clip.none) {
            nextClip = clipped(switch (geometry) {
              final Rect rect => rect,
              final RRect rect => rect.outerRect,
              final RSuperellipse rect => rect.outerRect,
              final Path path => path.getBounds(),
              _ => Rect.largest,
            });
            nextState = [...state, geometry, clipBehavior];
          }
        case ColorFilterLayer():
          nextState = [...state, layer.colorFilter];
        case BackdropFilterLayer():
          // It writes everything inside its clip, and its children paint
          // in a pass of that size.
          final bounds = clip ?? pass ?? Rect.largest;
          if (filtered || bounds.overlaps(region)) {
            out.add(layer.blendMode);
            leaf(layer.filter);
            reads = reads.expandToInclude(pass ?? Rect.largest);
          }
          nextState = [...state, layer.filter];
          nextPass = bounds;
        case SeededBackdropPassLayer(hidden: true):
          return;
        case SeededBackdropPassLayer(:final scenePass?):
          final bounds = clipped(scenePass.rect);
          if (filtered || bounds.overlaps(region)) {
            leaf(scenePass.seed);
            var seedReads = MatrixUtils.transformRect(
              transform,
              scenePass.reads,
            );
            if (pass != null) seedReads = seedReads.intersect(pass);
            reads = reads.expandToInclude(seedReads);
          }
          nextClip = bounds;
          nextPass = bounds;
          nextState = [...state, scenePass.seed, scenePass.clip];
        case ShaderMaskLayer():
          // A FragmentShader keeps its identity while its uniforms change.
          final shader = layer.shader is ui.FragmentShader
              ? Object()
              : layer.shader;
          nextState = [...state, shader, layer.maskRect, layer.blendMode];
        case LeaderLayer():
          next = shifted(layer.offset);
        case AnnotatedRegionLayer() ||
            NativeClipLayer() ||
            SeededBackdropPassLayer():
          break;
        case ContainerLayer() when layer.runtimeType == ContainerLayer:
          break;
        default:
          leaf(Object());
          return;
      }
      if (layer is ContainerLayer) {
        for (
          var child = layer.firstChild;
          child != null;
          child = child.nextSibling
        ) {
          walk(
            child,
            next,
            nextClip,
            nextPass,
            nextState,
            filtered: nextFiltered,
          );
        }
      }
    }

    walk(root, Matrix4.identity(), null, null, const []);
    return reads;
  }
}
