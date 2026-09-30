// ignore_for_file: avoid_setters_without_getters

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/liquid_shape.dart';

/// Connects a [LiquidGlassLoupe] to the [LiquidGlassLoupeSource] whose
/// content it magnifies.
///
/// Create one per source, like a [LayerLink], and pass it to both widgets.
class LiquidGlassLoupeLink {
  _RenderLiquidGlassLoupeSource? _source;

  /// Whether a [LiquidGlassLoupeSource] is currently attached.
  bool get hasSource => _source != null;
}

/// Marks the content that [LiquidGlassLoupe]s with the same [link] magnify.
///
/// The child becomes a repaint boundary. Loupes must paint after it, for
/// example above it in a [Stack], and must not be inside it.
class LiquidGlassLoupeSource extends SingleChildRenderObjectWidget {
  /// Creates a loupe source for [child].
  const LiquidGlassLoupeSource({
    required this.link,
    required super.child,
    super.key,
  });

  /// The link that loupes use to find this source.
  final LiquidGlassLoupeLink link;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLiquidGlassLoupeSource(link);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderLiquidGlassLoupeSource).link = link;
  }
}

/// A liquid glass magnifier, like the iOS 27 text-selection loupe.
///
/// The loupe re-renders the source content under the lens at
/// [magnification] times the device resolution instead of enlarging the
/// backdrop the glass captured, so text and vector content stay sharp. The
/// glass then refracts and lights that magnified content like any other
/// backdrop.
///
/// Only the region under the lens is re-rendered, once per composited frame
/// while the loupe is shown.
///
/// ```dart
/// final link = LiquidGlassLoupeLink();
///
/// Stack(
///   children: [
///     LiquidGlassLoupeSource(link: link, child: content),
///     Positioned(
///       left: x,
///       top: y,
///       child: LiquidGlassLoupe(link: link),
///     ),
///   ],
/// );
/// ```
class LiquidGlassLoupe extends StatelessWidget {
  /// Creates a loupe that magnifies the content of [link]'s source.
  const LiquidGlassLoupe({
    required this.link,
    super.key,
    this.size = const Size(116, 86),
    this.shape,
    this.magnification = 1.25,
    this.focalPointOffset = Offset.zero,
    this.settings = defaultSettings,
    this.appearance = const LiquidGlassAppearance(),
    this.shadows = const [],
    this.child,
  }) : assert(magnification > 0, 'magnification must be positive');

  /// Glass optics measured on the iOS 27 loupe (Reduce Motion off): a clear
  /// lens with a narrow 8 / 28 bevel, no frost and a hairline rim.
  static const LiquidGlassSettings defaultSettings = LiquidGlassSettings(
    refractionHeight: 8,
    refractionAmount: 28,
    frost: 0,
    contourStrength: 0.08,
    contourWidth: 0.75,
  );

  /// The source whose content is magnified.
  final LiquidGlassLoupeLink link;

  /// The size of the lens. The iOS 27 loupe measures 116 × 86.
  final Size size;

  /// The lens shape. Defaults to a capsule, as on iOS 27.
  final LiquidShape? shape;

  /// How much the source content is enlarged. The iOS 27 loupe measures
  /// `1.25`.
  final double magnification;

  /// Offset from the lens center to the source point shown at the center,
  /// as in [RawMagnifier.focalPointOffset]. The iOS 27 loupe floats above
  /// the touch point and shows it: `Offset(0, 75)` there.
  final Offset focalPointOffset;

  /// The glass optics and lighting.
  final LiquidGlassSettings settings;

  /// The glass appearance.
  final LiquidGlassAppearance appearance;

  /// Shadows cast by the lens.
  final List<BoxShadow> shadows;

  /// Optional foreground painted above the glass.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final lensShape =
        shape ?? LiquidRoundedRectangle(borderRadius: size.shortestSide / 2);
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _LoupeContent(
            link: link,
            shape: lensShape,
            magnification: magnification,
            focalPointOffset: focalPointOffset,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          ),
          LiquidGlass.withOwnLayer(
            settings: settings,
            appearance: appearance,
            shape: lensShape,
            shadows: shadows,
            child: child ?? const SizedBox.expand(),
          ),
        ],
      ),
    );
  }
}

class _RenderLiquidGlassLoupeSource extends RenderProxyBox {
  _RenderLiquidGlassLoupeSource(this._link);

  LiquidGlassLoupeLink _link;
  set link(LiquidGlassLoupeLink value) {
    if (identical(value, _link)) return;
    if (attached && identical(_link._source, this)) _link._source = null;
    _link = value;
    if (attached) _link._source = this;
  }

  @override
  bool get isRepaintBoundary => true;

  OffsetLayer? get sourceLayer => layer as OffsetLayer?;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _link._source = this;
  }

  @override
  void detach() {
    if (identical(_link._source, this)) _link._source = null;
    super.detach();
  }
}

class _LoupeContent extends LeafRenderObjectWidget {
  const _LoupeContent({
    required this.link,
    required this.shape,
    required this.magnification,
    required this.focalPointOffset,
    required this.devicePixelRatio,
  });

  final LiquidGlassLoupeLink link;
  final LiquidShape shape;
  final double magnification;
  final Offset focalPointOffset;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLoupeContent()
    ..link = link
    ..shape = shape
    ..magnification = magnification
    ..focalPointOffset = focalPointOffset
    ..devicePixelRatio = devicePixelRatio;

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLoupeContent renderObject,
  ) {
    renderObject
      ..link = link
      ..shape = shape
      ..magnification = magnification
      ..focalPointOffset = focalPointOffset
      ..devicePixelRatio = devicePixelRatio;
  }
}

class _RenderLoupeContent extends RenderBox {
  LiquidGlassLoupeLink? _link;
  set link(LiquidGlassLoupeLink value) {
    if (identical(value, _link)) return;
    _link = value;
    markNeedsPaint();
  }

  LiquidShape? _shape;
  set shape(LiquidShape value) {
    if (value == _shape) return;
    _shape = value;
    markNeedsPaint();
  }

  double _magnification = 1;
  set magnification(double value) {
    if (value == _magnification) return;
    _magnification = value;
    markNeedsPaint();
  }

  Offset _focalPointOffset = Offset.zero;
  set focalPointOffset(Offset value) {
    if (value == _focalPointOffset) return;
    _focalPointOffset = value;
    markNeedsPaint();
  }

  double _devicePixelRatio = 1;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  final _layerHandle = LayerHandle<_LoupeContentLayer>();

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final source = _link?._source;
    if (source == null || !source.attached || !source.hasSize) {
      _layerHandle.layer = null;
      return;
    }
    assert(
      !_isDescendantOf(source),
      'A LiquidGlassLoupe cannot magnify a LiquidGlassLoupeSource that '
      'contains it.',
    );
    // The loupe and its source can move independently, so the mapping is
    // taken at paint time; the layer re-renders the region on compositing.
    final toSource = getTransformTo(source);
    final focalPoint = MatrixUtils.transformPoint(
      toSource,
      size.center(Offset.zero) + _focalPointOffset,
    );
    final sourceRect = Rect.fromCenter(
      center: focalPoint,
      width: size.width / _magnification,
      height: size.height / _magnification,
    );
    final lens = offset & size;
    final layer = (_layerHandle.layer ??= _LoupeContentLayer())
      ..source = source
      ..sourceRect = sourceRect
      ..lens = lens
      ..clip = _shape!.getOuterPath(lens)
      ..pixelRatio = _devicePixelRatio * _magnification;
    context.addLayer(layer);
  }

  bool _isDescendantOf(RenderObject ancestor) {
    for (var node = parent; node != null; node = node.parent) {
      if (identical(node, ancestor)) return true;
    }
    return false;
  }

  @override
  void dispose() {
    _layerHandle.layer = null;
    super.dispose();
  }
}

/// Re-renders the source region under the lens when the scene is built, so
/// the content is complete and current for this frame.
class _LoupeContentLayer extends Layer {
  _RenderLiquidGlassLoupeSource? source;
  Rect sourceRect = Rect.zero;
  Rect lens = Rect.zero;
  Path clip = Path();
  double pixelRatio = 1;

  ui.Image? _image;
  ui.Picture? _picture;

  @override
  bool get alwaysNeedsAddToScene => true;

  @override
  void addToScene(ui.SceneBuilder builder) {
    final sourceLayer = source?.sourceLayer;
    if (sourceLayer == null || !sourceLayer.attached || sourceRect.isEmpty) {
      return;
    }
    final image = sourceLayer.toImageSync(sourceRect, pixelRatio: pixelRatio);
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..clipPath(clip)
      ..drawImageRect(
        image,
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
        lens,
        Paint()..filterQuality = FilterQuality.low,
      );
    final picture = recorder.endRecording();
    builder.addPicture(Offset.zero, picture);
    _release();
    _image = image;
    _picture = picture;
  }

  void _release() {
    _picture?.dispose();
    _image?.dispose();
    _picture = null;
    _image = null;
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }
}
