import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';

enum ShapeType {
  ellipse(0),
  rrect(1);

  const ShapeType(this.value);
  final int value;
}

abstract class RawShape {
  const RawShape({
    required this.position,
    required this.size,
    this.rotation = 0.0,
  });

  static const byteWindowSize = 8;

  final Offset position;
  final Size size;
  final double rotation;

  ShapeType get type;

  Float32List encodeWindow(Size canvasSize);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RawShape &&
          runtimeType == other.runtimeType &&
          position == other.position &&
          size == other.size &&
          rotation == other.rotation;

  @override
  int get hashCode => position.hashCode ^ size.hashCode ^ rotation.hashCode;
}

class RawEllipse extends RawShape {
  const RawEllipse({
    required super.position,
    required super.size,
    super.rotation,
  });

  @override
  ShapeType get type => ShapeType.ellipse;

  @override
  Float32List encodeWindow(Size canvasSize) {
    final data = Float32List(RawShape.byteWindowSize);
    data[0] = type.value.toDouble();
    data[1] = position.dx / canvasSize.width;
    data[2] = position.dy / canvasSize.height;
    data[3] = size.width / 2 / canvasSize.width;
    data[4] = rotation;
    data[5] = size.height / 2 / canvasSize.height;
    data[6] = 0.0;
    data[7] = 0.0;
    return data;
  }
}

class RawRRect extends RawShape {
  const RawRRect({
    required super.position,
    required super.size,
    required this.cornerRadius,
    super.rotation,
  });

  final double cornerRadius;

  @override
  ShapeType get type => ShapeType.rrect;

  @override
  Float32List encodeWindow(Size canvasSize) {
    final data = Float32List(RawShape.byteWindowSize);
    data[0] = type.value.toDouble();
    data[1] = position.dx / canvasSize.width;
    data[2] = position.dy / canvasSize.height;
    data[3] = size.width / 2 / canvasSize.width;
    data[4] = rotation;
    data[5] = size.height / 2 / canvasSize.height;
    data[6] = cornerRadius /
        (canvasSize.shortestSide > 0 ? canvasSize.shortestSide : 1);
    data[7] = 0.0;
    return data;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is RawRRect &&
          runtimeType == other.runtimeType &&
          cornerRadius == other.cornerRadius;

  @override
  int get hashCode => super.hashCode ^ cornerRadius.hashCode;
}

class RawShapes extends StatelessWidget {
  const RawShapes({
    super.key,
    required this.shapes,
  });

  final List<RawShape> shapes;

  @override
  Widget build(BuildContext context) {
    return ShaderBuilder(
      assetKey: 'packages/flutter_liquid_glass/lib/assets/shaders/shapes.frag',
      (context, shader, child) {
        return _RawShapes(
          shader: shader,
          shapes: shapes,
        );
      },
    );
  }
}

class _RawShapes extends LeafRenderObjectWidget {
  const _RawShapes({
    required this.shader,
    required this.shapes,
  });

  final Shader shader;
  final List<RawShape> shapes;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderRawShapes(
      shader: shader,
      shapes: shapes,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRawShapes renderObject,
  ) {
    renderObject
      ..shader = shader
      ..shapes = shapes;
  }
}

class _RenderRawShapes extends RenderBox {
  _RenderRawShapes({
    required Shader shader,
    required List<RawShape> shapes,
  })  : _shader = shader,
        _shapes = shapes;

  Shader _shader;
  set shader(Shader value) {
    if (_shader == value) return;
    _shader = value;
    markNeedsPaint();
  }

  List<RawShape> _shapes;
  List<RawShape> get shapes => _shapes;
  set shapes(List<RawShape> value) {
    if (listEquals(_shapes, value)) return;
    _shapes = value;
    _updateShapeTexture();
  }

  ui.Image? _shapeTexture;
  bool _textureUpdateInProgress = false;

  void _updateShapeTexture() async {
    if (!hasSize) {
      return;
    }
    if (_textureUpdateInProgress) return;
    _textureUpdateInProgress = true;

    final newShapes = List<RawShape>.from(_shapes);

    if (newShapes.isEmpty) {
      _shapeTexture?.dispose();
      _shapeTexture = null;
      _textureUpdateInProgress = false;
      markNeedsPaint();
      return;
    }

    final shapeData = Float32List(newShapes.length * 8);
    for (var i = 0; i < newShapes.length; i++) {
      final window = newShapes[i].encodeWindow(size);
      shapeData.setRange(i * 8, i * 8 + 8, window);
    }

    final buffer =
        await ui.ImmutableBuffer.fromUint8List(shapeData.buffer.asUint8List());
    final imageDescriptor = ui.ImageDescriptor.raw(
      buffer,
      width: newShapes.length * 2,
      height: 1,
      pixelFormat: ui.PixelFormat.rgbaFloat32,
    );
    final codec = await imageDescriptor.instantiateCodec();
    final frame = await codec.getNextFrame();

    _shapeTexture?.dispose();
    _shapeTexture = frame.image;
    _textureUpdateInProgress = false;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _updateShapeTexture();
  }

  @override
  void detach() {
    _shapeTexture?.dispose();
    _shapeTexture = null;
    super.detach();
  }

  @override
  bool get sizedByParent => true;

  @override
  void performResize() {
    size = constraints.biggest;
    _updateShapeTexture();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_shapeTexture == null || _shapes.isEmpty) return;

    final paint = Paint();
    final shader = _shader as FragmentShader;

    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, _shapes.length.toDouble());
    shader.setImageSampler(0, _shapeTexture!);
    paint.shader = shader;
    context.canvas.drawRect(offset & size, paint);
  }
}
