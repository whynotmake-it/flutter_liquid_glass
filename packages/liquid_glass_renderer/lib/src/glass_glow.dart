import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';
import 'package:motor/motor.dart';

/// {@template glass_glow}
/// If placed as a descendant of a [GlassGlowLayer], this widget will
/// send touch updates to that layer to create a glow effect.
/// {@endtemplate}
class GlassGlow extends StatelessWidget {
  /// {@macro glass_glow}
  const GlassGlow({
    required this.child,
    this.glowColor = Colors.white24,
    this.glowRadius = 1,
    this.hitTestBehavior = HitTestBehavior.opaque,
    super.key,
  });

  /// The radius of the glow effect relative to the layer's shortest side.
  ///
  /// A value of 0.8 means the glow radius will be 80% of the shortest
  /// dimension (width or height) of the [GlassGlowLayer].
  ///
  /// Defaults to 1.
  final double glowRadius;

  /// The color of the glow effect.
  ///
  /// The glow will have this colors opacity at the center, and will fade out
  /// to fully transparent at the edge of the glow.
  final Color glowColor;

  /// The hit test behavior of this gesture listener.
  ///
  /// Defaults to [HitTestBehavior.opaque].
  final HitTestBehavior hitTestBehavior;

  /// The child that will be painted above the glow effect.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: hitTestBehavior,
      onPointerDown: (event) => _handlePointer(context, event),
      onPointerMove: (event) => _handlePointer(context, event),
      onPointerUp: (event) => _removeTouch(context),
      onPointerCancel: (event) => _removeTouch(context),
      child: child,
    );
  }

  void _handlePointer(BuildContext context, PointerEvent event) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final layerState = GlassGlowLayer.maybeOf(context);
      final layerRenderBox =
          layerState?.context.findRenderObject() as RenderBox?;
      if (layerRenderBox != null) {
        final layerLocalPosition = layerRenderBox.globalToLocal(event.position);
        final center = Offset(
          layerRenderBox.size.width / 2,
          layerRenderBox.size.height / 2,
        );
        layerState?.updateTouch(
          layerLocalPosition - center,
          radius: glowRadius,
          color: glowColor,
        );
      }
    }
  }

  void _removeTouch(BuildContext context) {
    GlassGlowLayer.maybeOf(context)?.removeTouch();
  }
}

/// {@template glass_glow}
/// Represents a layer that can paint a glowing effect below its child.
///
/// Any child [GlassGlow] will send touch updates to this layer to
/// update the glow effect.
///
/// This is similar to how an `InkWell` works with a `Material` widget.
/// {@endtemplate}
class GlassGlowLayer extends StatefulWidget {
  /// {@macro glass_glow}
  const GlassGlowLayer({
    required this.child,
    super.key,
  });

  /// The child that will be painted above the glow effect.
  final Widget child;

  @override
  State<GlassGlowLayer> createState() => GlassGlowLayerState();

  @internal
  // ignore: public_member_api_docs
  static GlassGlowLayerState? maybeOf(BuildContext context) {
    return context.findAncestorStateOfType<GlassGlowLayerState>();
  }
}

@internal
class GlassGlowLayerState extends State<GlassGlowLayer>
    with TickerProviderStateMixin {
  late final _offsetController = MotionController<Offset>(
    vsync: this,
    converter: const OffsetMotionConverter(),
    initialValue: Offset.zero,
    motion: const Motion.smoothSpring(duration: Duration(seconds: 1)),
  );

  late final _alphaController = BoundedSingleMotionController(
    vsync: this,
    motion: const Motion.smoothSpring(),
  );

  late final _radiusController = SingleMotionController(
    vsync: this,
    motion: const Motion.smoothSpring(),
  )..value = 1;

  bool _dragging = false;
  double _baseRadius = 0;
  Color _baseColor = const Color.fromARGB(0, 0, 0, 0);

  @override
  void dispose() {
    _offsetController.dispose();
    _alphaController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  void updateTouch(
    Offset offset, {
    required double radius,
    required Color color,
  }) {
    _baseRadius = radius;
    _baseColor = color;

    if (!_dragging) {
      _dragging = true;
      _radiusController.motion =
          _alphaController.motion = const Motion.interactiveSpring();
      _radiusController.animateTo(1, from: 0);
      _alphaController.animateTo(1, from: 0);
    }

    _offsetController.value = offset;
  }

  void removeTouch() {
    if (!_dragging) return;
    _radiusController.motion =
        _alphaController.motion = const Motion.smoothSpring();
    _dragging = false;
    _offsetController.animateTo(Offset.zero);
    _radiusController.animateTo(10);
    _alphaController.animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _offsetController,
        _alphaController,
        _radiusController,
      ]),
      builder: (context, child) {
        return _RenderGlassGlowLayerWidget(
          glowRadius: _baseRadius * _radiusController.value,
          glowColor: _baseColor.withValues(
            alpha: _baseColor.a * _alphaController.value,
          ),
          glowOffset: _offsetController.value,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _RenderGlassGlowLayerWidget extends SingleChildRenderObjectWidget {
  const _RenderGlassGlowLayerWidget({
    required this.glowRadius,
    required this.glowColor,
    required this.glowOffset,
    required super.child,
  });

  final double glowRadius;
  final Color glowColor;
  final Offset glowOffset;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderGlassGlowLayer(
      glowRadius: glowRadius,
      glowColor: glowColor,
      glowOffset: glowOffset,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderGlassGlowLayer renderObject,
  ) {
    renderObject
      ..glowRadius = glowRadius
      ..glowColor = glowColor
      ..glowOffset = glowOffset;
  }
}

class _RenderGlassGlowLayer extends RenderProxyBox {
  _RenderGlassGlowLayer({
    required double glowRadius,
    required Color glowColor,
    required Offset glowOffset,
  })  : _glowRadius = glowRadius,
        _glowColor = glowColor,
        _glowOffset = glowOffset;

  double _glowRadius;
  double get glowRadius => _glowRadius;
  set glowRadius(double value) {
    if (_glowRadius == value) return;
    _glowRadius = value;
    markNeedsPaint();
  }

  Color _glowColor;
  Color get glowColor => _glowColor;
  set glowColor(Color value) {
    if (_glowColor == value) return;
    _glowColor = value;
    markNeedsPaint();
  }

  Offset _glowOffset;
  Offset get glowOffset => _glowOffset;
  set glowOffset(Offset value) {
    if (_glowOffset == value) return;
    _glowOffset = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final bounds = offset & size;

    canvas.save();

    final center = bounds.center;
    final glowPosition = center + _glowOffset;

    final gradient = RadialGradient(
      colors: [
        _glowColor,
        _glowColor.withValues(alpha: 0),
      ],
      stops: const [0.0, 1.0],
    );

    final radius = _glowRadius * size.shortestSide;

    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: glowPosition, radius: radius),
      )
      ..blendMode = BlendMode.plus;

    canvas
      ..drawCircle(
        glowPosition,
        radius,
        paint,
      )
      ..restore();
    super.paint(context, offset);
  }
}
