import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/internal/retained_glass_opacity_probe.dart';
import 'package:meta/meta.dart';

/// Retains clip ancestry common to every contributor in one glass pass.
///
/// These layers sit outside the pass's moving OffsetLayer: scrolling moves
/// material through a viewport, not the viewport through the material.
@internal
class RetainedGlassClip {
  /// Scope-specific passes already apply their opacity outside these clips.
  RetainedGlassClip({bool includeOpacity = true})
    : _opacity = includeOpacity ? RetainedGlassOpacityProbe() : null;

  RenderBox? _owner;
  Offset _paintOffset = Offset.zero;
  final List<_ClipEntry> _entries = [];
  final RetainedGlassOpacityProbe? _opacity;

  void update(RenderBox owner, Iterable<RenderBox> shapes) {
    _owner = owner;
    _opacity?.update(owner, shapes);
    List<RenderBox>? common;
    for (final shape in shapes) {
      final ancestors = <RenderBox>[];
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
          ancestors.add(node as RenderBox);
        }
      }
      if (common == null) {
        common = ancestors.reversed.toList();
      } else {
        common.removeWhere((node) => !ancestors.contains(node));
      }
    }
    final nodes = common ?? const <RenderBox>[];
    if (nodes.length == _entries.length) {
      var sameNodes = true;
      for (var i = 0; i < nodes.length; i++) {
        if (!identical(nodes[i], _entries[i].source)) {
          sameNodes = false;
          break;
        }
      }
      if (sameNodes) return;
    }
    _clearClips();
    _entries.addAll(nodes.map(_ClipEntry.new));
  }

  void sync() {
    final owner = _owner;
    if (owner == null || !owner.attached) return;
    _opacity?.sync();
    for (final entry in _entries) {
      entry.sync(owner, _paintOffset);
    }
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
        final opacity = _opacity;
        if (opacity == null) {
          context.pushLayer(effect, painter, offset);
        } else {
          opacity.paint(context, offset, (context, offset) {
            context.pushLayer(effect, painter, offset);
          });
        }
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

  void dispose() {
    _opacity?.dispose();
    _clearClips();
  }

  void _clearClips() {
    for (final entry in _entries) {
      entry.dispose();
    }
    _entries.clear();
  }
}

class _ClipEntry {
  _ClipEntry(this.source) {
    handle.layer = _NativeClipLayer();
    forward.layer = TransformLayer(transform: Matrix4.identity());
    inverse.layer = TransformLayer(transform: Matrix4.identity());
  }

  final RenderBox source;
  final handle = LayerHandle<_NativeClipLayer>();
  final forward = LayerHandle<TransformLayer>();
  final inverse = LayerHandle<TransformLayer>();
  Object? _geometry;
  Matrix4? _transform;
  Offset? _offset;

  void sync(RenderBox owner, Offset offset) {
    final layer = handle.layer!;
    if (!source.attached) {
      layer.enabled = false;
      return;
    }
    final (geometry, behavior) = switch (source) {
      final RenderClipRect clip => (
        clip.clipper?.getClip(clip.size) ?? Offset.zero & clip.size,
        clip.clipBehavior,
      ),
      final RenderClipRRect clip => (
        clip.clipper?.getClip(clip.size) ??
            clip.borderRadius
                .resolve(clip.textDirection)
                .toRRect(Offset.zero & clip.size),
        clip.clipBehavior,
      ),
      final RenderClipRSuperellipse clip => (
        clip.clipper?.getClip(clip.size) ??
            clip.borderRadius
                .resolve(clip.textDirection)
                .toRSuperellipse(Offset.zero & clip.size),
        clip.clipBehavior,
      ),
      final RenderClipOval clip => (
        clip.clipper?.getClip(clip.size) ?? Offset.zero & clip.size,
        clip.clipBehavior,
      ),
      final RenderClipPath clip => (
        clip.clipper?.getClip(clip.size) ?? Offset.zero & clip.size,
        clip.clipBehavior,
      ),
      final RenderViewportBase viewport => (
        Offset.zero & viewport.size,
        // Mirror RenderViewportBase.paint exactly. Its approximate clip API
        // describes per-sliver semantics, not the actual paint clip.
        // ignore: invalid_use_of_protected_member
        viewport.hasVisualOverflow ? viewport.clipBehavior : Clip.none,
      ),
      _ => throw StateError('Unsupported retained clip'),
    };
    layer.enabled = behavior != Clip.none;
    if (!layer.enabled) return;
    layer.clipBehavior = behavior;
    final transform = source.getTransformTo(owner);
    if (geometry is! Path &&
        _geometry == geometry &&
        _offset == offset &&
        MatrixUtils.matrixEquals(_transform, transform)) {
      return;
    }
    _geometry = geometry;
    _offset = offset;
    _transform = transform;
    final ownerTransform = Matrix4.translationValues(offset.dx, offset.dy, 0)
      ..multiply(transform);
    forward.layer!.transform = ownerTransform;
    inverse.layer!.transform = Matrix4.inverted(ownerTransform);
    layer.geometry = source is RenderClipOval
        ? (Path()..addOval(geometry as Rect))
        : geometry;
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
    forward.layer = null;
    handle.layer = null;
    inverse.layer = null;
  }
}

class _NativeClipLayer extends ContainerLayer {
  Object? _geometry;
  Object? get geometry => _geometry;
  set geometry(Object value) {
    if (value is! Path && _geometry == value) return;
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
