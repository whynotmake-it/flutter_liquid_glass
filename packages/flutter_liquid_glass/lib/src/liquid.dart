import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';

class Liquid extends StatelessWidget {
  const Liquid({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderBuilder(
      (context, shader, child) => _Liquid(
        shader: shader,
        child: child,
      ),
      assetKey:
          'packages/flutter_liquid_glass/lib/assets/shaders/displacement.frag',
      child: child,
    );
  }
}

class _Liquid extends SingleChildRenderObjectWidget {
  const _Liquid({
    required this.shader,
    required super.child,
    super.key,
  });

  final FragmentShader shader;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquid(shader: shader);
  }

  @override
  void updateRenderObject(BuildContext context, RenderLiquid renderObject) {
    super.updateRenderObject(context, renderObject);
  }
}

final _liquidKey = BackdropKey();

class RenderLiquid extends RenderProxyBox {
  RenderLiquid({
    required this.shader,
  });

  final FragmentShader shader;

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  bool get isRepaintBoundary => alwaysNeedsCompositing;

  @override
  OffsetLayer updateCompositedLayer(
      {required covariant ImageFilterLayer? oldLayer}) {
    final ImageFilterLayer layer = oldLayer ?? ImageFilterLayer();
    layer.imageFilter = ImageFilter.compose(
      inner: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      outer: ImageFilter.shader(shader),
    );
    return layer;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
  }
}
