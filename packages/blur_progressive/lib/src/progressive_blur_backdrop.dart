// ignore_for_file: avoid_setters_without_getters

import 'dart:ui' as ui;

import 'package:blur_progressive/src/shaders.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';

/// Defines the direction and extent of the progressive blur gradient.
///
/// The gradient is defined by a [start] and [end] point in normalized
/// coordinates (0..1), where (0, 0) is the top-left and (1, 1) is the
/// bottom-right of the widget.
///
/// [startIntensity] and [endIntensity] control how much blur is applied at the
/// start and end of the gradient respectively, where 0.0 means no blur and 1.0
/// means full blur (up to [ProgressiveBlurBackdrop.maxBlurRadius]).
@immutable
class ProgressiveBlurGradient {
  /// Creates a progressive blur gradient definition.
  const ProgressiveBlurGradient({
    this.start = Alignment.topCenter,
    this.end = Alignment.bottomCenter,
    this.startIntensity = 0.0,
    this.endIntensity = 1.0,
  });

  /// Creates a top-to-bottom progressive blur gradient.
  ///
  /// Blur increases from [startIntensity] at the top to [endIntensity] at the
  /// bottom.
  const ProgressiveBlurGradient.topToBottom({
    this.startIntensity = 0.0,
    this.endIntensity = 1.0,
  })  : start = Alignment.topCenter,
        end = Alignment.bottomCenter;

  /// Creates a bottom-to-top progressive blur gradient.
  ///
  /// Blur increases from [startIntensity] at the bottom to [endIntensity] at
  /// the top.
  const ProgressiveBlurGradient.bottomToTop({
    this.startIntensity = 0.0,
    this.endIntensity = 1.0,
  })  : start = Alignment.bottomCenter,
        end = Alignment.topCenter;

  /// Creates a left-to-right progressive blur gradient.
  ///
  /// Blur increases from [startIntensity] at the left to [endIntensity] at the
  /// right.
  const ProgressiveBlurGradient.leftToRight({
    this.startIntensity = 0.0,
    this.endIntensity = 1.0,
  })  : start = Alignment.centerLeft,
        end = Alignment.centerRight;

  /// Creates a right-to-left progressive blur gradient.
  ///
  /// Blur increases from [startIntensity] at the right to [endIntensity] at
  /// the left.
  const ProgressiveBlurGradient.rightToLeft({
    this.startIntensity = 0.0,
    this.endIntensity = 1.0,
  })  : start = Alignment.centerRight,
        end = Alignment.centerLeft;

  /// The start point of the gradient in alignment coordinates.
  ///
  /// Alignment(-1, -1) is top-left, Alignment(1, 1) is bottom-right.
  final Alignment start;

  /// The end point of the gradient in alignment coordinates.
  ///
  /// Alignment(-1, -1) is top-left, Alignment(1, 1) is bottom-right.
  final Alignment end;

  /// The blur intensity at the [start] of the gradient (0.0 to 1.0).
  ///
  /// 0.0 means no blur, 1.0 means full blur.
  final double startIntensity;

  /// The blur intensity at the [end] of the gradient (0.0 to 1.0).
  ///
  /// 0.0 means no blur, 1.0 means full blur.
  final double endIntensity;

  /// Converts the [start] alignment to normalized UV coordinates (0..1).
  Offset startUV() => Offset(
        (start.x + 1.0) / 2.0,
        (start.y + 1.0) / 2.0,
      );

  /// Converts the [end] alignment to normalized UV coordinates (0..1).
  Offset endUV() => Offset(
        (end.x + 1.0) / 2.0,
        (end.y + 1.0) / 2.0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProgressiveBlurGradient &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end &&
          startIntensity == other.startIntensity &&
          endIntensity == other.endIntensity;

  @override
  int get hashCode => Object.hash(start, end, startIntensity, endIntensity);
}

/// A widget that applies a progressive Gaussian blur to its backdrop.
///
/// The blur intensity varies across the widget based on a configurable
/// [gradient]. This is useful for creating depth-of-field effects, frosted
/// glass with varying opacity, or any effect where blur should transition
/// smoothly across a region.
///
/// The blur is implemented as a two-pass separated Gaussian blur using a
/// fragment shader, applied as a backdrop filter. This means it blurs the
/// content behind this widget, not the widget's own children.
///
/// Requires Impeller to be enabled (Skia is not supported).
///
/// ## Example
///
/// ```dart
/// ProgressiveBlurBackdrop(
///   maxBlurRadius: 20.0,
///   gradient: const ProgressiveBlurGradient.topToBottom(),
///   child: Container(
///     width: 300,
///     height: 200,
///     color: Colors.white.withOpacity(0.1),
///   ),
/// )
/// ```
class ProgressiveBlurBackdrop extends StatefulWidget {
  /// Creates a [ProgressiveBlurBackdrop].
  const ProgressiveBlurBackdrop({
    this.child,
    this.maxBlurRadius = 20.0,
    this.gradient = const ProgressiveBlurGradient(),
    super.key,
  });

  /// The widget below this widget in the tree.
  ///
  /// If null, the widget will expand to fill its constraints and act as a pure
  /// backdrop blur with no child content.
  final Widget? child;

  /// The maximum blur radius in pixels.
  ///
  /// The actual blur at any point is scaled by the gradient's intensity at that
  /// point. Must be non-negative.
  ///
  /// Defaults to 20.0.
  final double maxBlurRadius;

  /// The gradient that controls how blur intensity varies across the widget.
  ///
  /// Defaults to a top-to-bottom gradient with intensity from 0.0 to 1.0.
  final ProgressiveBlurGradient gradient;

  @override
  State<ProgressiveBlurBackdrop> createState() =>
      _ProgressiveBlurBackdropState();
}

class _ProgressiveBlurBackdropState extends State<ProgressiveBlurBackdrop> {
  ui.FragmentProgram? _program;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<void> _loadShader() async {
    final program =
        await ui.FragmentProgram.fromAsset(ShaderKeys.progressiveBlur);
    if (mounted) {
      setState(() {
        _program = program;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ui.ImageFilter.isShaderFilterSupported || _program == null) {
      return widget.child ?? const SizedBox.expand();
    }

    return _RawProgressiveBlur(
      program: _program!,
      maxBlurRadius: widget.maxBlurRadius,
      gradient: widget.gradient,
      child: widget.child,
    );
  }
}

class _RawProgressiveBlur extends SingleChildRenderObjectWidget {
  const _RawProgressiveBlur({
    required this.program,
    required this.maxBlurRadius,
    required this.gradient,
    super.child,
  });

  final ui.FragmentProgram program;
  final double maxBlurRadius;
  final ProgressiveBlurGradient gradient;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderProgressiveBlurBackdrop(
      program: program,
      maxBlurRadius: maxBlurRadius,
      gradient: gradient,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderProgressiveBlurBackdrop renderObject,
  ) {
    renderObject
      ..program = program
      ..maxBlurRadius = maxBlurRadius
      ..gradient = gradient
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

/// The render object that applies the two-pass progressive blur as a backdrop
/// filter.
///
/// Uses two separate [ui.FragmentShader] instances (one per pass) so that each
/// can hold its own uniforms simultaneously.
class RenderProgressiveBlurBackdrop extends RenderProxyBox {
  /// Creates a [RenderProgressiveBlurBackdrop].
  RenderProgressiveBlurBackdrop({
    required ui.FragmentProgram program,
    required double maxBlurRadius,
    required ProgressiveBlurGradient gradient,
    required double devicePixelRatio,
  })  : _program = program,
        _horizontalShader = program.fragmentShader(),
        _verticalShader = program.fragmentShader(),
        _maxBlurRadius = maxBlurRadius,
        _gradient = gradient,
        _devicePixelRatio = devicePixelRatio;

  ui.FragmentProgram _program;
  ui.FragmentShader _horizontalShader;
  ui.FragmentShader _verticalShader;

  final LayerHandle<BackdropFilterLayer> _horizontalPassHandle =
      LayerHandle<BackdropFilterLayer>();
  final LayerHandle<BackdropFilterLayer> _verticalPassHandle =
      LayerHandle<BackdropFilterLayer>();
  final LayerHandle<ClipRectLayer> _clipRectHandle =
      LayerHandle<ClipRectLayer>();

  /// The shader program used to create per-pass shader instances.
  set program(ui.FragmentProgram value) {
    if (identical(_program, value)) return;
    _program = value;
    _horizontalShader.dispose();
    _verticalShader.dispose();
    _horizontalShader = value.fragmentShader();
    _verticalShader = value.fragmentShader();
    markNeedsPaint();
  }

  double _maxBlurRadius;

  /// The maximum blur radius in pixels.
  set maxBlurRadius(double value) {
    if (_maxBlurRadius == value) return;
    _maxBlurRadius = value;
    markNeedsPaint();
  }

  ProgressiveBlurGradient _gradient;

  /// The gradient controlling blur intensity distribution.
  set gradient(ProgressiveBlurGradient value) {
    if (_gradient == value) return;
    _gradient = value;
    markNeedsPaint();
  }

  double _devicePixelRatio;

  /// The device pixel ratio for coordinate scaling.
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  void _configureShader(
    ui.FragmentShader shader, {
    required Size size,
    required Offset screenOffset,
    required double horizontal,
  }) {
    final physicalSize = size * _devicePixelRatio;
    final physicalOffset = screenOffset * _devicePixelRatio;
    final startUV = _gradient.startUV();
    final endUV = _gradient.endUV();

    shader.setFloatUniforms((uniforms) {
      uniforms
        // uResolution (screen size)
        ..setSize(physicalSize)
        // uMaxBlurRadius
        ..setFloat(_maxBlurRadius * _devicePixelRatio)
        // uHorizontal (1.0 = horizontal, 0.0 = vertical)
        ..setFloat(horizontal)
        // uRect (origin x, origin y, width, height) in physical pixels
        ..setFloat(physicalOffset.dx)
        ..setFloat(physicalOffset.dy)
        ..setFloat(physicalSize.width)
        ..setFloat(physicalSize.height)
        // uProgressive (startX, startY, endX, endY) in local 0..1
        ..setFloat(startUV.dx)
        ..setFloat(startUV.dy)
        ..setFloat(endUV.dx)
        ..setFloat(endUV.dy)
        // uIntensity (startIntensity, endIntensity)
        ..setFloat(_gradient.startIntensity)
        ..setFloat(_gradient.endIntensity);
    });
  }

  @override
  void performLayout() {
    if (child != null) {
      child!.layout(constraints, parentUsesSize: true);
      size = child!.size;
    } else {
      size = constraints.biggest;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final paintSize = size;

    // Compute the widget's screen-space origin by applying the full
    // transform to the local offset. This is needed so the shader can
    // convert screen-space frag coords to local 0..1 UVs.
    final transform = getTransformTo(null);
    final screenOffset = MatrixUtils.transformPoint(transform, offset);

    // Configure each shader with its own direction uniforms.
    _configureShader(
      _horizontalShader,
      size: paintSize,
      screenOffset: screenOffset,
      horizontal: 1,
    );
    _configureShader(
      _verticalShader,
      size: paintSize,
      screenOffset: screenOffset,
      horizontal: 0,
    );

    final horizontalLayer = (_horizontalPassHandle.layer ??=
        BackdropFilterLayer())
      ..filter = ui.ImageFilter.shader(_horizontalShader);

    final verticalLayer = (_verticalPassHandle.layer ??= BackdropFilterLayer())
      ..filter = ui.ImageFilter.shader(_verticalShader);

    // Clip to our bounds so the backdrop filter only captures our area.
    _clipRectHandle.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & paintSize,
      (context, offset) {
        // Push horizontal pass
        context.pushLayer(
          horizontalLayer,
          (context, offset) {
            // Push vertical pass on top
            context.pushLayer(
              verticalLayer,
              (context, offset) {
                if (child != null) {
                  context.paintChild(child!, offset);
                }
              },
              offset,
            );
          },
          offset,
        );
      },
      oldLayer: _clipRectHandle.layer,
    );
  }

  @override
  void dispose() {
    _horizontalPassHandle.layer = null;
    _verticalPassHandle.layer = null;
    _clipRectHandle.layer = null;
    _horizontalShader.dispose();
    _verticalShader.dispose();
    super.dispose();
  }
}
