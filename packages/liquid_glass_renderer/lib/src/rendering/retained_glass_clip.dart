import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/rendering/ancestor_clip.dart';
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
      final (geometry, behavior) = clipGeometryOf(source)!;
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

      final paintGeometry = source is RenderClipOval
          ? _ovalPath(geometry as Rect)
          : geometry;
      switch (paintGeometry) {
        case final Rect rect:
          clipContext.clipRectAndPaint(
            rect,
            behavior,
            rect,
            descend,
          );
        case final RRect rrect:
          clipContext.clipRRectAndPaint(
            rrect,
            behavior,
            rrect.outerRect,
            descend,
          );
        case final RSuperellipse rse:
          clipContext.clipRSuperellipseAndPaint(
            rse,
            behavior,
            rse.outerRect,
            descend,
          );
        case final Path path:
          clipContext.clipPathAndPaint(
            path,
            behavior,
            path.getBounds(),
            descend,
          );
      }
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

  // A clipper's path and an oval's, held while the clipper, the size and
  // its reclip, or the oval's rect, hold: a new path each frame would add
  // the clip again and break every copy signed over it.
  CustomClipper<Path>? _clipper;
  Size? _clipperSize;
  Path? _clipperPath;
  Rect? _ovalRect;
  Path? _oval;

  void _reclip() => _clipperPath = null;

  (Object, Clip) _geometryOf(RenderBox source) {
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
      return (_clipperPath!, source.clipBehavior);
    }
    final (geometry, behavior) = clipGeometryOf(source)!;
    if (source is RenderClipOval) {
      if (_oval == null || geometry != _ovalRect) {
        _ovalRect = geometry as Rect;
        _oval = _ovalPath(geometry);
      }
      return (_oval!, behavior);
    }
    return (geometry, behavior);
  }

  void sync(RenderBox owner, Offset offset) {
    final layer = handle.layer!;
    if (!source.attached) {
      layer.enabled = false;
      return;
    }
    final (geometry, behavior) = _geometryOf(source);
    layer.enabled = behavior != Clip.none;
    if (!layer.enabled) return;
    layer.clipBehavior = behavior;
    final transform = transformToNow(source, owner);
    final current = layer.geometry;
    if ((geometry is Path
            ? identical(geometry, current)
            : current == geometry) &&
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
    layer.geometry = geometry;
  }

  Rect? get ownerBounds {
    final transform = _transform;
    final geometry = handle.layer!.geometry;
    if (!handle.layer!.enabled ||
        transform == null ||
        geometry == null ||
        !isRectilinearTransform(transform)) {
      return null;
    }
    return MatrixUtils.transformRect(transform, clipGeometryBounds(geometry));
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

Path _ovalPath(Rect rect) => Path()..addOval(rect);

@internal
class NativeClipLayer extends ContainerLayer {
  Object? _geometry;
  Object? get geometry => _geometry;
  set geometry(Object value) {
    if (value is Path ? identical(value, _geometry) : _geometry == value) {
      return;
    }
    _geometry = value;
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
    if (_enabled) {
      final oldLayer = engineLayer;
      engineLayer = switch (_geometry) {
        final Rect rect => builder.pushClipRect(
          rect,
          clipBehavior: _clipBehavior,
          oldLayer: oldLayer is ui.ClipRectEngineLayer ? oldLayer : null,
        ),
        final RRect rect => builder.pushClipRRect(
          rect,
          clipBehavior: _clipBehavior,
          oldLayer: oldLayer is ui.ClipRRectEngineLayer ? oldLayer : null,
        ),
        final RSuperellipse rect => builder.pushClipRSuperellipse(
          rect,
          clipBehavior: _clipBehavior,
          oldLayer: oldLayer is ui.ClipRSuperellipseEngineLayer
              ? oldLayer
              : null,
        ),
        final Path path => builder.pushClipPath(
          path,
          clipBehavior: _clipBehavior,
          oldLayer: oldLayer is ui.ClipPathEngineLayer ? oldLayer : null,
        ),
        _ => throw StateError('Missing native clip geometry'),
      };
      addChildrenToScene(builder);
      builder.pop();
    } else {
      engineLayer = null;
      addChildrenToScene(builder);
    }
  }
}
