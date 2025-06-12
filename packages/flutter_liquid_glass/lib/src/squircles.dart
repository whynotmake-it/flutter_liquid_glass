import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';

class Squircle {
  const Squircle({
    required this.center,
    required this.size,
    required this.cornerRadius,
  });

  final Offset center;
  final Size size;
  final double cornerRadius;
}

class RawSquircles extends StatelessWidget {
  const RawSquircles({
    super.key,
    required this.squircle1,
    required this.squircle2,
    this.blend = 20,
    this.chromaticAberration = .01,
    this.debugRenderRefractionMap = false,
  });

  final Squircle squircle1;
  final Squircle squircle2;
  final double blend;
  final double chromaticAberration;

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
              blend: blend,
              chromaticAberration: chromaticAberration,
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
    required this.blend,
    required this.chromaticAberration,
    required this.debugRenderRefractionMap,
  });

  final FragmentShader shapesShader;
  final FragmentShader displacementShader;
  final Squircle squircle1;
  final Squircle squircle2;
  final double blend;
  final double chromaticAberration;
  final bool debugRenderRefractionMap;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderRawShapes(
      shapesShader: shapesShader,
      displacementShader: displacementShader,
      squircle1: squircle1,
      squircle2: squircle2,
      blend: blend,
      chromaticAberration: chromaticAberration,
      debugRenderRefractionMap: debugRenderRefractionMap,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRawShapes renderObject,
  ) {
    renderObject
      ..squircle1 = squircle1
      ..squircle2 = squircle2
      ..blend = blend
      ..chromaticAberration = chromaticAberration
      ..debugRenderRefractionMap = debugRenderRefractionMap;
  }
}

class _RenderRawShapes extends RenderBox {
  _RenderRawShapes({
    required FragmentShader shapesShader,
    required FragmentShader displacementShader,
    required Squircle squircle1,
    required Squircle squircle2,
    required double blend,
    required double chromaticAberration,
    bool debugRenderRefractionMap = false,
  })  : _shapesShader = shapesShader,
        _displacementShader = displacementShader,
        _squircle1 = squircle1,
        _squircle2 = squircle2,
        _blend = blend,
        _chromaticAberration = chromaticAberration;

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

  double _blend;
  set blend(double value) {
    if (_blend == value) return;
    _blend = value;
    markNeedsPaint();
  }

  double _chromaticAberration;
  set chromaticAberration(double value) {
    if (_chromaticAberration == value) return;
    _chromaticAberration = value;
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
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, _squircle1.center.dx)
      ..setFloat(3, _squircle1.center.dy)
      ..setFloat(4, _squircle1.size.width)
      ..setFloat(5, _squircle1.size.height)
      ..setFloat(6, _squircle1.cornerRadius)
      ..setFloat(7, _squircle2.center.dx)
      ..setFloat(8, _squircle2.center.dy)
      ..setFloat(9, _squircle2.size.width)
      ..setFloat(10, _squircle2.size.height)
      ..setFloat(11, _squircle2.cornerRadius)
      ..setFloat(12, _blend)
      ..setFloat(13, 20.0);

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

    final glassColor = Color.fromARGB(0, 255, 255, 255);

    _displacementShader
      ..setImageSampler(
        1,
        liquidShapes.toImageSync(size.width.toInt(), size.height.toInt()),
      )
      ..setFloat(2, 4.0)
      ..setFloat(3, _chromaticAberration)
      ..setFloat(4, glassColor.r)
      ..setFloat(5, glassColor.g)
      ..setFloat(6, glassColor.b)
      ..setFloat(7, glassColor.a);

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
