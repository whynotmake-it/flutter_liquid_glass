import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// A random layer tree and random changes to it; [seed] reproduces both.
///
/// Holds what a frame can do to layers without paint or with it: move, fade,
/// clip, repaint, add and remove children, and put a texture or platform view
/// under what follows.
final class GeneratedLayers {
  GeneratedLayers(this.seed) : _random = Random(seed) {
    root = ContainerLayer();
    _fill(root, 0);
  }

  final int seed;
  final Random _random;
  late final ContainerLayer root;

  static const screen = Size(1080, 2400);

  double _coord(double max) => _random.nextDouble() * max;

  ui.Picture _picture() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 10, 10),
      Paint(),
    );
    return recorder.endRecording();
  }

  PictureLayer _leaf() {
    final bounds = Rect.fromLTWH(
      _coord(screen.width),
      _coord(screen.height),
      20 + _coord(400),
      20 + _coord(200),
    );
    final layer = PictureLayer(bounds)..picture = _picture();
    return layer;
  }

  Layer _node(int depth) {
    final roll = _random.nextInt(depth > 4 ? 2 : 12);
    switch (roll) {
      case 0 || 1:
        return _leaf();
      case 2 || 3:
        final layer = OffsetLayer(offset: Offset(_coord(100), _coord(400)));
        _fill(layer, depth + 1);
        return layer;
      case 4:
        final layer = TransformLayer(
          transform: Matrix4.translationValues(_coord(50), _coord(50), 0),
        );
        _fill(layer, depth + 1);
        return layer;
      case 5:
        final layer = OpacityLayer(alpha: _random.nextInt(256));
        _fill(layer, depth + 1);
        return layer;
      case 6:
        final layer = ClipRectLayer(
          clipRect: Rect.fromLTWH(0, 0, 200 + _coord(800), 200 + _coord(800)),
        );
        _fill(layer, depth + 1);
        return layer;
      case 7:
        final layer = ClipRRectLayer(
          clipRRect: RRect.fromRectXY(
            Rect.fromLTWH(0, 0, 200 + _coord(800), 200 + _coord(800)),
            8,
            8,
          ),
        );
        _fill(layer, depth + 1);
        return layer;
      case 8:
        final layer = ImageFilterLayer(
          imageFilter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        );
        _fill(layer, depth + 1);
        return layer;
      case 9:
        return TextureLayer(
          rect: const Rect.fromLTWH(0, 0, 300, 300),
          textureId: _random.nextInt(4),
        );
      case 10:
        final layer = ContainerLayer();
        _fill(layer, depth + 1);
        return layer;
      default:
        return PlatformViewLayer(
          rect: const Rect.fromLTWH(0, 0, 200, 200),
          viewId: _random.nextInt(4),
        );
    }
  }

  void _fill(ContainerLayer layer, int depth) {
    final count = 1 + _random.nextInt(depth == 0 ? 8 : 4);
    for (var i = 0; i < count; i++) {
      layer.append(_node(depth));
    }
  }

  List<Layer> _all() {
    final all = <Layer>[];
    void visit(Layer layer) {
      all.add(layer);
      if (layer is ContainerLayer) {
        for (var c = layer.firstChild; c != null; c = c.nextSibling) {
          visit(c);
        }
      }
    }

    visit(root);
    return all;
  }

  /// Changes one thing a frame can change.
  void mutate() {
    final all = _all();
    final layer = all[_random.nextInt(all.length)];
    switch (layer) {
      case PictureLayer():
        if (_random.nextBool()) {
          layer.picture = _picture();
        } else {
          _replace(layer);
        }
      case TextureLayer() || PlatformViewLayer():
        _replace(layer);
      case OpacityLayer():
        layer.alpha = _random.nextInt(3) == 0 ? 0 : _random.nextInt(256);
      case TransformLayer():
        layer.transform = Matrix4.translationValues(
          _coord(50),
          _coord(50),
          0,
        );
      case ImageFilterLayer():
        layer.imageFilter = ui.ImageFilter.blur(
          sigmaX: 1 + _coord(3),
          sigmaY: 1 + _coord(3),
        );
      case OffsetLayer():
        layer.offset = Offset(_coord(100), _coord(400));
      case ClipRectLayer():
        layer.clipRect = Rect.fromLTWH(0, 0, _coord(800) + 1, _coord(800) + 1);
      case ClipRRectLayer():
        layer.clipRRect = RRect.fromRectXY(
          Rect.fromLTWH(0, 0, _coord(800) + 1, _coord(800) + 1),
          8,
          8,
        );
      case ContainerLayer():
        if (_random.nextBool() || layer.firstChild == null) {
          layer.append(_node(3));
        } else {
          final children = <Layer>[];
          for (var c = layer.firstChild; c != null; c = c.nextSibling) {
            children.add(c);
          }
          children[_random.nextInt(children.length)].remove();
        }
      default:
        break;
    }
  }

  void _replace(Layer layer) {
    final parent = layer.parent;
    if (parent == null) return;
    layer.remove();
    parent.append(_node(4));
  }
}
