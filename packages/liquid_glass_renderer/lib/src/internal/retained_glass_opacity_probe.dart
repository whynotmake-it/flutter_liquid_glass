import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

/// Scopes not already replayed once around the original combined effect.
/// Computed only when source ancestry is refreshed, never per animation tick.
List<RenderObject> independentGlassOpacityScopes(
  Iterable<List<RenderObject>> chains,
) {
  final counts = <RenderObject, int>{};
  var chainCount = 0;
  for (final chain in chains) {
    chainCount++;
    for (final scope in chain) {
      counts.update(scope, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  return [
    for (final entry in counts.entries)
      if (entry.value != chainCount) entry.key,
  ];
}

/// Native-opaque local scopes need no isolated passes. Shared ancestors are
/// still replayed by the original effect, including fractional and zero alpha.
/// [exactOpaque] keeps a near-one fade on its fractional presentation even
/// when native alpha rounds up; it does not change the submitted opacity.
bool areGlassOpacityScopesOpaque(
  List<RenderObject> scopes, {
  bool exactOpaque = false,
}) {
  for (var i = 0; i < scopes.length; i++) {
    final opacity = switch (scopes[i]) {
      RenderOpacity(:final opacity) => opacity,
      RenderAnimatedOpacity(:final opacity) => opacity.value,
      _ => 1.0,
    };
    if (exactOpaque
        ? opacity != 1
        : ui.Color.getAlphaFromOpacity(opacity) != 255) {
      return false;
    }
  }
  return true;
}

/// Selection classification, not a composited alpha: 0 hidden, 128 fractional,
/// 255 opaque. A product rounded to zero must not discard visible descendants
/// before their shared parent has composited them.
/// [exactOpaque] uses the raw upper endpoint for presentation selection only.
int glassOpacityChainState(
  List<RenderObject> scopes, {
  bool exactOpaque = false,
}) {
  var state = 255;
  for (var i = 0; i < scopes.length; i++) {
    final opacity = switch (scopes[i]) {
      RenderOpacity(:final opacity) => opacity,
      RenderAnimatedOpacity(:final opacity) => opacity.value,
      _ => 1.0,
    };
    final alpha = ui.Color.getAlphaFromOpacity(opacity);
    if (alpha == 0) return 0;
    if (exactOpaque ? opacity < 1 : alpha < 255) state = 128;
  }
  return state;
}

/// Native alpha255 can occur before a fade finishes. Releasing its immutable
/// subset cache then would rebuild geometry when the animation reverses.
bool isSettledOpaqueGlassScope(RenderObject scope) => switch (scope) {
  RenderOpacity(:final opacity) => opacity == 1,
  RenderAnimatedOpacity(:final opacity) =>
    opacity.value == 1 &&
        (opacity is AlwaysStoppedAnimation<double> ||
            !opacity.status.isAnimating),
  _ => true,
};

/// Unlike rounded native alpha0, an exact, stopped zero blocks the chain
/// until a new fade starts. Other scopes cannot make that chain visible.
bool isSettledTransparentGlassScope(RenderObject scope) => switch (scope) {
  RenderOpacity(:final opacity) => opacity == 0,
  RenderAnimatedOpacity(:final opacity) =>
    opacity.value == 0 &&
        (opacity is AlwaysStoppedAnimation<double> ||
            !opacity.status.isAnimating),
  _ => false,
};

/// Whether a dormant isolated pass may still be needed by the current fade.
/// Retention uses raw values and status, never quantized submission alpha.
bool isUnfinishedGlassOpacityChain(List<RenderObject> scopes) =>
    !scopes.any(isSettledTransparentGlassScope) &&
    !scopes.every(isSettledOpaqueGlassScope);

/// Experimental replay of opacity ancestry bypassed by layer-owned effects.
/// Only scopes common to every contributor are handled here. Independent
/// overlapping scopes require separate cached material, not a combined replay.
class RetainedGlassOpacityProbe {
  /// Keeps this incomplete scope experiment out of the production path.
  static const enabled = bool.fromEnvironment(
    'HOIST_GLASS_OPACITY',
    defaultValue: true,
  );
  final _layer = LayerHandle<_ScopedEffectLayer>();
  List<RenderObject> _scopes = [];

  /// Collects shared opacity ancestors bypassed by the material owner.
  void update(RenderBox owner, Iterable<RenderBox> shapes) {
    if (!enabled) return;
    List<RenderObject>? common;
    for (final shape in shapes) {
      final scopes = <RenderObject>[];
      for (
        var node = shape.parent;
        node != null && node != owner;
        node = node.parent
      ) {
        if (node is RenderOpacity || node is RenderAnimatedOpacity) {
          scopes.add(node);
        }
      }
      if (common == null) {
        common = scopes;
      } else {
        common.removeWhere((scope) => !scopes.contains(scope));
      }
    }
    _scopes = common ?? [];
    if (_scopes.isEmpty) _layer.layer = null;
  }

  /// Reconciles alpha before the current retained scene is submitted.
  void sync() {
    if (!enabled || _layer.layer == null) return;
    var opacity = 1.0;
    for (final scope in _scopes) {
      opacity *= switch (scope) {
        RenderOpacity() => ui.Color.getAlphaFromOpacity(scope.opacity) / 255,
        RenderAnimatedOpacity() =>
          ui.Color.getAlphaFromOpacity(scope.opacity.value) / 255,
        _ => 1.0,
      };
    }
    _layer.layer!.alpha = ui.Color.getAlphaFromOpacity(opacity);
  }

  /// Wraps only hoisted effects, leaving normal child opacity untouched.
  void paint(
    PaintingContext context,
    Offset offset,
    PaintingContextCallback painter,
  ) {
    if (!enabled || _scopes.isEmpty) {
      painter(context, offset);
      return;
    }
    _layer.layer ??= _ScopedEffectLayer();
    sync();
    context.pushLayer(_layer.layer!, painter, offset);
  }

  /// Releases temporary native-layer ownership and source references.
  void dispose() {
    _layer.layer = null;
    _scopes = [];
  }
}

/// Replays shared opacity ancestry once around cached, ordered material leaves.
/// The original composition remains outside this temporary tree.
class RetainedGlassOpacityTree {
  final _root = LayerHandle<ContainerLayer>(ContainerLayer());
  final _nodes = <RenderObject, LayerHandle<_ScopedEffectLayer>>{};

  /// Leaves have native alpha255: every opacity belongs to its ancestry node.
  ContainerLayer select(
    List<(List<RenderObject>, ContainerLayer, ui.Rect?)> leaves,
  ) {
    final root = _root.layer!;
    final children = <ContainerLayer, List<Layer>>{root: []};
    final bounds = <_ScopedEffectLayer, ui.Rect?>{};
    for (final (scopes, leaf, seedBounds) in leaves) {
      var parent = root;
      for (final scope in scopes.reversed) {
        final node = _nodes
            .putIfAbsent(
              scope,
              () => LayerHandle<_ScopedEffectLayer>(_ScopedEffectLayer()),
            )
            .layer!;
        final siblings = children.putIfAbsent(parent, () => []);
        if (!siblings.contains(node)) siblings.add(node);
        children.putIfAbsent(node, () => []);
        final opacity = switch (scope) {
          RenderOpacity(:final opacity) => opacity,
          RenderAnimatedOpacity(:final opacity) => opacity.value,
          _ => 1.0,
        };
        node
          ..alpha = ui.Color.getAlphaFromOpacity(opacity)
          ..keepFractionalSeed =
              const bool.fromEnvironment(
                'PROBE_STABLE_NEAR_OPAQUE_SEED',
                defaultValue: true,
              ) &&
              opacity > 0 &&
              opacity < 1;
        bounds[node] = bounds.containsKey(node)
            ? (bounds[node] == null || seedBounds == null
                  ? null
                  : bounds[node]!.expandToInclude(seedBounds))
            : seedBounds;
        parent = node;
      }
      children[parent]!.add(leaf);
    }
    // Remove obsolete relationships before attaching new ones. Unchanged
    // topology does not dirty native layers on ordinary alpha-only ticks.
    final changed = <ContainerLayer>[];
    for (final parent in [root, ..._nodes.values.map((h) => h.layer!)]) {
      final desired = children[parent] ?? const <Layer>[];
      var current = parent.firstChild;
      var same = true;
      for (final child in desired) {
        if (!identical(current, child)) {
          same = false;
          break;
        }
        current = current?.nextSibling;
      }
      if (!same || current != null) changed.add(parent);
    }
    for (final parent in changed) {
      parent.removeAllChildren();
    }
    for (final parent in changed) {
      for (final child in children[parent] ?? const <Layer>[]) {
        child.remove();
        parent.append(child);
      }
    }
    for (final entry in bounds.entries) {
      entry.key.seedBounds = entry.value;
    }
    _nodes.removeWhere((scope, handle) {
      if (bounds.containsKey(handle.layer)) return false;
      // Detached nodes will not submit again to replace their old native
      // subtree. Release that ownership now, not at the next settled fade.
      handle.layer = null;
      return true;
    });
    return root;
  }

  /// Nearest active local seed bounds, valid after [select] attaches the leaf.
  ui.Rect? captureBoundsFor(ContainerLayer leaf) {
    for (var node = leaf.parent; node != null; node = node.parent) {
      if (node is _ScopedEffectLayer &&
          node.alpha > 0 &&
          (node.alpha < 255 || node.keepFractionalSeed)) {
        return node.seedBounds;
      }
      if (identical(node, _root.layer)) break;
    }
    return null;
  }

  /// Release temporary native ancestry at restoration or source invalidation.
  void clear() {
    _root.layer!.removeAllChildren();
    for (final handle in _nodes.values) {
      handle.layer!.removeAllChildren();
      handle.layer = null;
    }
    _nodes.clear();
  }

  /// Releases the temporary tree and its root holder.
  void dispose() {
    clear();
    _root.layer = null;
  }
}

class _ScopedEffectLayer extends ContainerLayer {
  ui.Rect? _seedBounds;
  ui.Rect? get seedBounds => _seedBounds;
  set seedBounds(ui.Rect? value) {
    if (_seedBounds == value) return;
    _seedBounds = value;
    markNeedsAddToScene();
  }

  static const _identity = ui.ColorFilter.matrix([
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);
  int _alpha = 255;
  bool _keepFractionalSeed = false;
  bool get keepFractionalSeed => _keepFractionalSeed;
  set keepFractionalSeed(bool value) {
    if (_keepFractionalSeed == value) return;
    _keepFractionalSeed = value;
    markNeedsAddToScene();
  }

  int get alpha => _alpha;
  set alpha(int value) {
    if (_alpha == value) return;
    _alpha = value;
    markNeedsAddToScene();
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    if (_alpha == 0 || (_alpha == 255 && !_keepFractionalSeed)) {
      engineLayer = null;
      if (_alpha == 255) addChildrenToScene(builder);
      return;
    }
    final previous = engineLayer;
    engineLayer = builder.pushOpacity(
      _alpha,
      oldLayer: previous is ui.OpacityEngineLayer ? previous : null,
    );
    final captureBounds = _seedBounds;
    final clip = captureBounds == null
        ? null
        : builder.pushClipRect(captureBounds, clipBehavior: Clip.hardEdge);
    final seed = builder.pushBackdropFilter(_identity);
    addChildrenToScene(builder);
    builder.pop();
    if (clip != null) builder.pop();
    builder.pop();
    // The submitted native parent keeps the child alive, not this Dart handle.
    seed.dispose();
    clip?.dispose();
  }
}
