import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';

/// The layers one reader of the frame keeps between scenes, each standing for a
/// part of the frame whose content holds.
///
/// A scene takes an engine layer once, and a reader the engine retains adds
/// what it kept without being asked: no other reader can tell. So a kept layer
/// only goes back into the scenes of the reader that made it.
@internal
final class HeldLayers {
  final _kept = Map<Object, _Kept>.identity();
  int _scene = 0;

  /// Whether the layer kept of [node] is in the scene being built.
  bool holds(Object node) => _kept[node]?.scene == _scene;

  /// The layer kept of [node] for the scene being built, if it was made of
  /// the content [node] has had since [content].
  ui.OffsetEngineLayer? take(Object node, int content) {
    final kept = _kept[node];
    if (kept == null) return null;
    if (kept.content != content) {
      kept.layer.dispose();
      _kept.remove(node);
      return null;
    }
    kept.scene = _scene;
    return kept.layer;
  }

  /// Keeps [layer], which the scene being built holds, as [node] with the
  /// content it has had since [content].
  void keep(Object node, int content, ui.OffsetEngineLayer layer) {
    _kept[node] = _Kept(layer, content, _scene);
  }

  /// The scene is built: lets go of what it took none of.
  void built() {
    _kept.removeWhere((_, kept) {
      if (kept.scene == _scene) return false;
      kept.layer.dispose();
      return true;
    });
    _scene++;
  }

  /// Lets go of every layer.
  void dispose() {
    for (final kept in _kept.values) {
      kept.layer.dispose();
    }
    _kept.clear();
  }
}

final class _Kept {
  _Kept(this.layer, this.content, this.scene);

  final ui.OffsetEngineLayer layer;
  final int content;
  int scene;
}

/// A scene a read of what lies under glass adds itself to.
///
/// What only moves the coordinates waits for what needs them: a picture takes a
/// translation as its offset, and a layer pushed costs both threads.
@internal
final class SceneOut {
  /// Adds to [builder], the coordinates there taken by [matrix] if any.
  SceneOut(this.builder, this.matrix, this.held, {this.flat = false});

  /// What the reader this scene is built for keeps between scenes.
  final HeldLayers held;

  /// Whether this is the copy of a read whose glass frosts all it shows
  /// (GlassRead.flat): what that frost hides is not drawn.
  final bool flat;

  /// The scene.
  final ui.SceneBuilder builder;

  /// The transform no layer holds yet, then the translation [at] after it.
  Matrix4? matrix;

  /// The translation no layer holds yet.
  Offset at = Offset.zero;

  /// Layers pushed and not popped.
  int pushes = 0;

  final _marks = <(Matrix4?, Offset, int)>[];

  /// Takes the coordinates by [by].
  void transform(Matrix4 by) {
    if (MatrixUtils.getAsTranslation(by) case final shift?) {
      at += shift;
      return;
    }
    matrix = (matrix ?? Matrix4.identity()).clone()
      ..translateByDouble(at.dx, at.dy, 0, 1)
      ..multiply(by);
    at = Offset.zero;
  }

  /// Pushes the waiting transform with its translation.
  void settleMatrix() {
    final held = matrix;
    if (held == null) return;
    builder.pushTransform(
      at == Offset.zero
          ? held.storage
          : (held.clone()..translateByDouble(at.dx, at.dy, 0, 1)).storage,
    );
    matrix = null;
    at = Offset.zero;
    pushes++;
  }

  /// Leaves the coordinates of what comes next to the layers pushed.
  void settle() {
    settleMatrix();
    if (at == Offset.zero) return;
    builder.pushOffset(at.dx, at.dy);
    at = Offset.zero;
    pushes++;
  }

  /// Adds [picture] at the coordinates' origin.
  void picture(ui.Picture picture) {
    settleMatrix();
    builder.addPicture(at, picture);
  }

  /// Adds [texture] where it lies in the coordinates.
  void texture(TextureLayer texture) {
    settleMatrix();
    final rect = texture.rect;
    builder.addTexture(
      texture.textureId,
      offset: at + rect.topLeft,
      width: rect.width,
      height: rect.height,
      freeze: texture.freeze,
      filterQuality: texture.filterQuality,
    );
  }

  /// Remembers where the coordinates stand, for [leave].
  void mark() => _marks.add((matrix, at, pushes));

  /// Takes the coordinates back to the last [mark].
  void leave() {
    final (heldMatrix, heldAt, pushed) = _marks.removeLast();
    while (pushes > pushed) {
      builder.pop();
      pushes--;
    }
    matrix = heldMatrix;
    at = heldAt;
  }

  /// Pops everything pushed.
  void finish() {
    _marks.clear();
    while (pushes > 0) {
      builder.pop();
      pushes--;
    }
  }
}
