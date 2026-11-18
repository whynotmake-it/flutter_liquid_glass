import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/rendering/ancestor_clip.dart';
import 'package:liquid_glass_renderer/src/rendering/clip_shape.dart';
import 'package:liquid_glass_renderer/src/rendering/follower_transform.dart';
import 'package:meta/meta.dart';

/// Retains clip ancestry common to every contributor in one glass pass.
///
/// These layers sit outside the pass's moving OffsetLayer: scrolling moves
/// material through a viewport, not the viewport through the material.
@internal
class RetainedGlassClip {
  RenderBox? _owner;
  Offset _paintOffset = Offset.zero;
  final List<_ClipEntry> _entries = [];
  bool _hasIndividualClips = false;

  bool get hasIndividualClips => _hasIndividualClips;

  void update(RenderBox owner, Iterable<RenderBox> shapes) {
    _owner = owner;
    List<RenderBox>? common;
    final all = <RenderBox>{};
    for (final shape in shapes) {
      final ancestors = _clipAncestors(shape, owner).toList();
      all.addAll(ancestors);
      if (common == null) {
        common = ancestors.reversed.toList();
      } else {
        common.removeWhere((node) => !ancestors.contains(node));
      }
    }
    final nodes = common ?? const <RenderBox>[];
    _hasIndividualClips = all.length != nodes.length;
    var same = nodes.length == _entries.length;
    for (var i = 0; same && i < nodes.length; i++) {
      same = identical(nodes[i], _entries[i].source);
    }
    if (same) return;
    _clearClips();
    _entries.addAll(nodes.map(_ClipEntry.new));
  }

  void sync() {
    final owner = _owner;
    if (owner == null || !owner.attached) return;
    for (final entry in _entries) {
      entry.sync(owner, _paintOffset);
    }
  }

  /// Intersection of the enabled clips' bounds in the owner's coordinates,
  /// as of the last [sync], or `null` when none clips.
  Rect? get ownerBounds {
    Rect? result;
    for (final entry in _entries) {
      final bounds = entry.ownerBounds;
      if (bounds == null) continue;
      result = result?.intersect(bounds) ?? bounds;
    }
    return result;
  }

  void pushLayer(
    PaintingContext context,
    ContainerLayer effect,
    PaintingContextCallback painter,
    Offset offset,
  ) {
    _paintOffset = offset;
    sync();
    void push(PaintingContext context, Offset offset, int index) {
      if (index == _entries.length) {
        context.pushLayer(effect, painter, offset);
      } else {
        _entries[index].push(
          context,
          (context, offset) => push(context, offset, index + 1),
          offset,
        );
      }
    }

    push(context, offset, 0);
  }

  void paintWithIndividualClips(
    Canvas canvas,
    RenderBox shape,
    Offset effectTranslation,
    VoidCallback painter,
  ) {
    final owner = _owner;
    if (owner == null || !hasIndividualClips) {
      painter();
      return;
    }
    final clips = _clipAncestors(shape, owner)
        .where((source) => !_entries.any((entry) => entry.source == source))
        .toList()
        .reversed
        .toList();
    final clipContext = _CanvasClipContext(canvas);

    void paint(int index) {
      if (index == clips.length) {
        painter();
        return;
      }
      final source = clips[index];
      final (shape, behavior) = clipShapeOf(source)!;
      final transform = Matrix4.translationValues(
        -effectTranslation.dx,
        -effectTranslation.dy,
        0,
      )..multiply(transformToNow(source, owner));
      final inverse = Matrix4.tryInvert(transform);
      if (inverse == null) return;
      canvas
        ..save()
        ..transform(transform.storage);
      void descend() {
        canvas.transform(inverse.storage);
        paint(index + 1);
      }

      shape.clipAndPaint(clipContext, behavior, descend);
      canvas.restore();
    }

    paint(0);
  }

  void dispose() => _clearClips();

  void _clearClips() {
    for (final entry in _entries) {
      entry.dispose();
    }
    _entries.clear();
  }
}

Iterable<RenderBox> _clipAncestors(RenderBox shape, RenderBox owner) sync* {
  for (
    var node = shape.parent;
    node != null && node != owner;
    node = node.parent
  ) {
    if (node is RenderClipRect ||
        node is RenderClipRRect ||
        node is RenderClipRSuperellipse ||
        node is RenderClipOval ||
        node is RenderClipPath ||
        node is RenderViewportBase) {
      yield node as RenderBox;
    }
  }
}

class _CanvasClipContext extends ClipContext {
  _CanvasClipContext(this.canvas);

  @override
  final Canvas canvas;
}

class _ClipEntry {
  _ClipEntry(this.source) {
    handle.layer = NativeClipLayer();
    forward.layer = TransformLayer(transform: Matrix4.identity());
    inverse.layer = TransformLayer(transform: Matrix4.identity());
  }

  final RenderBox source;
  final handle = LayerHandle<NativeClipLayer>();
  final forward = LayerHandle<TransformLayer>();
  final inverse = LayerHandle<TransformLayer>();
  Matrix4? _transform;
  Offset? _offset;

  CustomClipper<Path>? _clipper;
  Size? _clipperSize;
  Path? _clipperPath;

  void _reclip() => _clipperPath = null;

  (ClipShape, Clip) _shapeOf(RenderBox source) {
    if (source case RenderClipPath(:final clipper?, :final size)) {
      if (!identical(clipper, _clipper)) {
        final old = _clipper;
        old?.removeListener(_reclip);
        clipper.addListener(_reclip);
        _clipper = clipper;
        if (old == null ||
            old.runtimeType != clipper.runtimeType ||
            clipper.shouldReclip(old)) {
          _clipperPath = null;
        }
      }
      if (_clipperPath == null || _clipperSize != size) {
        _clipperPath = clipper.getClip(size);
        _clipperSize = size;
      }
      return (PathClip(_clipperPath!), source.clipBehavior);
    }
    return clipShapeOf(source)!;
  }

  void sync(RenderBox owner, Offset offset) {
    final layer = handle.layer!;
    if (!source.attached) {
      layer.enabled = false;
      return;
    }
    final (shape, behavior) = _shapeOf(source);
    layer.enabled = behavior != Clip.none;
    if (!layer.enabled) return;
    layer.clipBehavior = behavior;
    final transform = transformToNow(source, owner);
    if (layer.shape == shape &&
        _offset == offset &&
        MatrixUtils.matrixEquals(_transform, transform)) {
      return;
    }
    _offset = offset;
    _transform = transform;
    final ownerTransform = Matrix4.translationValues(offset.dx, offset.dy, 0)
      ..multiply(transform);
    forward.layer!.transform = ownerTransform;
    inverse.layer!.transform = Matrix4.inverted(ownerTransform);
    layer.shape = shape;
  }

  Rect? get ownerBounds {
    final transform = _transform;
    final shape = handle.layer!.shape;
    if (!handle.layer!.enabled ||
        transform == null ||
        shape == null ||
        !isRectilinearTransform(transform)) {
      return null;
    }
    return MatrixUtils.transformRect(transform, shape.bounds);
  }

  void push(
    PaintingContext context,
    PaintingContextCallback painter,
    Offset offset,
  ) {
    context.pushLayer(forward.layer!, (context, offset) {
      context.pushLayer(handle.layer!, (context, offset) {
        context.pushLayer(inverse.layer!, painter, offset);
      }, offset);
    }, offset);
  }

  void dispose() {
    _clipper?.removeListener(_reclip);
    _clipper = null;
    forward.layer = null;
    handle.layer = null;
    inverse.layer = null;
  }
}

@internal
class NativeClipLayer extends ContainerLayer {
  ClipShape? _shape;
  ClipShape? get shape => _shape;
  set shape(ClipShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsAddToScene();
  }

  Clip _clipBehavior = Clip.hardEdge;
  Clip get clipBehavior => _clipBehavior;
  set clipBehavior(Clip value) {
    if (_clipBehavior == value) return;
    _clipBehavior = value;
    markNeedsAddToScene();
  }

  bool _enabled = false;
  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    markNeedsAddToScene();
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    final shape = _enabled ? _shape : null;
    if (shape == null) {
      engineLayer = null;
      addChildrenToScene(builder);
      return;
    }
    engineLayer = shape.push(builder, _clipBehavior, oldLayer: engineLayer);
    addChildrenToScene(builder);
    builder.pop();
  }
}
