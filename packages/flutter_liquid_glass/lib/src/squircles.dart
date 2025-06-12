import 'dart:math';
import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';

class Squircle with EquatableMixin {
  const Squircle({
    required this.center,
    required this.size,
    required this.cornerRadius,
  });

  final Offset center;
  final Size size;
  final double cornerRadius;

  @override
  List<Object?> get props => [center, size, cornerRadius];
}

class LiquidGlassSettings with EquatableMixin {
  const LiquidGlassSettings({
    this.glassColor = const Color.fromARGB(16, 255, 255, 255),
    this.thickness = 20,
    this.chromaticAberration = .01,
    this.blend = 20,
    this.lightAngle = 0.5 * pi,
    this.lightIntensity = 10,
    this.ambientStrength = .005,
    this.outlineIntensity = 0,
  });

  final Color glassColor;
  final double thickness;
  final double chromaticAberration;
  final double blend;
  final double lightAngle;
  final double lightIntensity;
  final double ambientStrength;
  final double outlineIntensity;

  @override
  List<Object?> get props => [
        glassColor,
        thickness,
        chromaticAberration,
        blend,
        lightAngle,
        lightIntensity,
        ambientStrength,
        outlineIntensity,
      ];
}

class RawSquircles extends StatelessWidget {
  const RawSquircles({
    super.key,
    required this.squircle1,
    required this.squircle2,
    required this.settings,
    this.debugRenderRefractionMap = false,
  });

  final Squircle squircle1;
  final Squircle squircle2;
  final LiquidGlassSettings settings;

  final bool debugRenderRefractionMap;

  @override
  Widget build(BuildContext context) {
    return ShaderBuilder(
      assetKey: 'packages/flutter_liquid_glass/lib/assets/shaders/shapes.frag',
      (context, shapesShader, child) {
        return ShaderBuilder(
          assetKey:
              'packages/flutter_liquid_glass/lib/assets/shaders/displacement.frag',
          (context, displacementShader, child) {
            return _RawShapes(
              shapesShader: shapesShader,
              displacementShader: displacementShader,
              squircle1: squircle1,
              squircle2: squircle2,
              settings: settings,
              debugRenderRefractionMap: debugRenderRefractionMap,
            );
          },
          child: child,
        );
      },
    );
  }
}

class _RawShapes extends LeafRenderObjectWidget {
  const _RawShapes({
    required this.shapesShader,
    required this.displacementShader,
    required this.squircle1,
    required this.squircle2,
    required this.settings,
    required this.debugRenderRefractionMap,
  });

  final FragmentShader shapesShader;
  final FragmentShader displacementShader;
  final Squircle squircle1;
  final Squircle squircle2;
  final LiquidGlassSettings settings;
  final bool debugRenderRefractionMap;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderRawShapes(
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      shapesShader: shapesShader,
      displacementShader: displacementShader,
      squircle1: squircle1,
      squircle2: squircle2,
      settings: settings,
      debugRenderRefractionMap: debugRenderRefractionMap,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRawShapes renderObject,
  ) {
    renderObject
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..squircle1 = squircle1
      ..squircle2 = squircle2
      ..settings = settings
      ..debugRenderRefractionMap = debugRenderRefractionMap;
  }
}

class _RenderRawShapes extends RenderBox {
  _RenderRawShapes({
    required double devicePixelRatio,
    required FragmentShader shapesShader,
    required FragmentShader displacementShader,
    required Squircle squircle1,
    required Squircle squircle2,
    required LiquidGlassSettings settings,
    bool debugRenderRefractionMap = false,
  })  : _devicePixelRatio = devicePixelRatio,
        _shapesShader = shapesShader,
        _displacementShader = displacementShader,
        _squircle1 = squircle1,
        _squircle2 = squircle2,
        _settings = settings;

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  final FragmentShader _shapesShader;
  final FragmentShader _displacementShader;

  Squircle _squircle1;
  set squircle1(Squircle value) {
    if (_squircle1 == value) return;
    _squircle1 = value;
    markNeedsPaint();
  }

  Squircle _squircle2;
  set squircle2(Squircle value) {
    if (_squircle2 == value) return;
    _squircle2 = value;
    markNeedsPaint();
  }

  LiquidGlassSettings _settings;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    _settings = value;
    markNeedsPaint();
  }

  bool _debugRenderRefractionMap = false;
  set debugRenderRefractionMap(bool value) {
    if (_debugRenderRefractionMap == value) return;
    _debugRenderRefractionMap = value;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  void performResize() {
    size = constraints.biggest;
  }

  Picture _drawLiquidShapes(Offset offset, Size size) {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    final paint = Paint();

    _shapesShader
      ..setFloat(0, size.width * _devicePixelRatio)
      ..setFloat(1, size.height * _devicePixelRatio)
      ..setFloat(2, _squircle1.center.dx + offset.dx)
      ..setFloat(3, _squircle1.center.dy + offset.dy)
      ..setFloat(4, _squircle1.size.width)
      ..setFloat(5, _squircle1.size.height)
      ..setFloat(6, _squircle1.cornerRadius)
      ..setFloat(7, _squircle2.center.dx + offset.dx)
      ..setFloat(8, _squircle2.center.dy + offset.dy)
      ..setFloat(9, _squircle2.size.width)
      ..setFloat(10, _squircle2.size.height)
      ..setFloat(11, _squircle2.cornerRadius)
      ..setFloat(12, _settings.blend)
      ..setFloat(13, _settings.thickness);

    paint.shader = _shapesShader;
    canvas.drawRect(offset & size, paint);

    return recorder.endRecording();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final liquidShapes = _drawLiquidShapes(offset, size);

    if (_debugRenderRefractionMap) {
      context.canvas.drawPicture(liquidShapes);
      return;
    }

    if (_settings.thickness <= 0) {
      super.paint(context, offset);
    }

    // Get screen size
    _displacementShader
      ..setImageSampler(
        1,
        liquidShapes.toImageSync(
          (size).width.toInt(),
          (size).height.toInt(),
        ),
      )
      ..setFloat(2, _settings.chromaticAberration)
      ..setFloat(3, _settings.glassColor.r)
      ..setFloat(4, _settings.glassColor.g)
      ..setFloat(5, _settings.glassColor.b)
      ..setFloat(6, _settings.glassColor.a)
      ..setFloat(7, _settings.lightAngle)
      ..setFloat(8, _settings.lightIntensity)
      ..setFloat(9, _settings.ambientStrength)
      ..setFloat(10, _settings.outlineIntensity)
      ..setFloat(11, _settings.thickness)
      ..setFloat(12, 1.51)
      ..setFloat(13, size.width)
      ..setFloat(14, size.height)
      ..setFloat(15, 0)
      ..setFloat(16, 0);

    context.pushLayer(
      BackdropFilterLayer(
        filter: ImageFilter.shader(
          _displacementShader,
        ),
      ),
      (context, offset) {
        super.paint(context, offset);
      },
      offset,
    );
  }
}
