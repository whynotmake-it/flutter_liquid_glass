part of 'glass_form.dart';

mixin _Matrix on OpenNode {
  Matrix4? _own;

  @override
  void enter(SceneOut out, Rect band) {
    if (_own case final own?) out.transform(own);
  }

  Matrix4? _ownedBase;
  double _ownedDx = 0;
  double _ownedDy = 0;
  late Matrix4 _combined;

  bool _noteOwn(Matrix4 own) {
    final last = _own;
    final same = last != null && FormWorld._sameMatrix(last, own);
    if (!same) edited = true;
    _own = own;
    return same;
  }

  // Writes [world] under [own]. A translation stays in the world's offset, with
  // the base of what lies above: a scroll moves what lies under it, and a new
  // base would make everything below compute its own matrix again.
  bool _placeUnder(
    FormWorld outside,
    Matrix4 own,
    Rect? clip,
    StateChain state, {
    required double spread,
  }) {
    if (MatrixUtils.getAsTranslation(own) case final shift?) {
      _noteOwn(own);
      _ownedBase = null;
      return world.set(
        outside.base,
        outside.dx + shift.dx,
        outside.dy + shift.dy,
        clip,
        state,
        spread: spread,
      );
    }
    return world.set(
      _resolve(outside, own),
      0,
      0,
      clip,
      state,
      spread: spread,
    );
  }

  // The transform of what this layer holds. Allocates only when it changed.
  Matrix4 _resolve(FormWorld outside, Matrix4 own) {
    final same = _noteOwn(own);
    if (!same ||
        !identical(_ownedBase, outside.base) ||
        _ownedDx != outside.dx ||
        _ownedDy != outside.dy) {
      _ownedBase = outside.base;
      _ownedDx = outside.dx;
      _ownedDy = outside.dy;
      _combined = outside.base.clone()
        ..translateByDouble(outside.dx, outside.dy, 0, 1)
        ..multiply(own);
    }
    return _combined;
  }
}

/// A transform.
@internal
final class TransformNode extends OpenNode with _Matrix {
  /// Creates the node.
  TransformNode(TransformLayer super.layer);

  // Most transforms sit at a zero offset and keep their matrix, so the walk
  // compares it without building the effective one.
  @override
  bool updateWorld(FormWorld outside) {
    final layer = this.layer as TransformLayer;
    final offset = layer.offset;
    final matrix = layer.transform;
    final Matrix4 own;
    if (matrix != null && offset == Offset.zero) {
      own = matrix;
    } else {
      own = Matrix4.translationValues(offset.dx, offset.dy, 0);
      if (matrix != null) own.multiply(matrix);
    }
    return _placeUnder(
      outside,
      own,
      outside.clip,
      outside.state,
      spread: outside.spread,
    );
  }
}

/// A follower: its transform comes from its leader, which moves with no change
/// to this layer, so it is read every frame.
@internal
final class FollowerNode extends OpenNode with _Matrix {
  /// Creates the node.
  FollowerNode(FollowerLayer super.layer);

  @override
  bool get shows {
    final layer = this.layer as FollowerLayer;
    return layer.link.leader != null || (layer.showWhenUnlinked ?? false);
  }

  @override
  bool updateWorld(FormWorld outside) => _placeUnder(
    outside,
    followerTransformNow(layer as FollowerLayer),
    outside.clip,
    outside.state,
    spread: outside.spread,
  );
}

/// An opacity.
@internal
final class AlphaNode extends OpenNode {
  /// Creates the node.
  AlphaNode(OpacityLayer super.layer);

  StateChain? _chain;
  StateChain? _chainParent;
  int? _chainAlpha;
  Offset _placed = Offset.zero;

  @override
  bool get shows => (layer as OpacityLayer).alpha != 0;

  @override
  int saves({required bool flat}) =>
      leaves > 1 && ((layer as OpacityLayer).alpha ?? 255) != 255 ? 1 : 0;

  @override
  void enter(SceneOut out, Rect band) {
    final layer = this.layer as OpacityLayer;
    final alpha = layer.alpha ?? 255;
    if (alpha == 255) {
      out.at += layer.offset;
      return;
    }
    out.settleMatrix();
    out.builder.pushOpacity(alpha, offset: out.at + layer.offset);
    out.at = Offset.zero;
    out.pushes++;
  }

  @override
  bool updateWorld(FormWorld outside) {
    final layer = this.layer as OpacityLayer;
    final alpha = layer.alpha ?? 255;
    final offset = layer.offset;
    if (_chainAlpha != alpha || offset != _placed) {
      edited = true;
      _placed = offset;
    }
    if (_chain == null ||
        !identical(_chainParent, outside.state) ||
        _chainAlpha != alpha) {
      _chain = StateChain(outside.state, alpha);
      _chainParent = outside.state;
      _chainAlpha = alpha;
    }
    return world.set(
      outside.base,
      outside.dx + offset.dx,
      outside.dy + offset.dy,
      outside.clip,
      _chain!,
      spread: outside.spread,
    );
  }
}

/// An image filter: what lies under it may land anywhere.
@internal
final class FilterNode extends OpenNode {
  /// Creates the node.
  FilterNode(ImageFilterLayer super.layer);

  StateChain? _chain;
  StateChain? _chainParent;
  ui.ImageFilter? _chainFilter;
  ui.ImageFilter? _read;
  Offset _placed = Offset.zero;

  // What the filter takes beside its layer is not known: the engine tells
  // nothing of a filter.
  @override
  int saves({required bool flat}) =>
      (layer as ImageFilterLayer).imageFilter == null ? 0 : 1;

  @override
  void enter(SceneOut out, Rect band) {
    final layer = this.layer as ImageFilterLayer;
    final filter = layer.imageFilter;
    if (filter == null) return;
    out.settleMatrix();
    out.builder.pushImageFilter(filter, offset: out.at + layer.offset);
    out.at = Offset.zero;
    out.pushes++;
  }

  @override
  bool updateWorld(FormWorld outside) {
    final layer = this.layer as ImageFilterLayer;
    final filter = layer.imageFilter;
    final offset = layer.offset;
    if (!identical(_read, filter) || offset != _placed) {
      edited = true;
      _read = filter;
      _placed = offset;
    }
    if (filter == null) return world.inherit(outside);
    if (_chain == null ||
        !identical(_chainParent, outside.state) ||
        !identical(_chainFilter, filter)) {
      _chain = StateChain(outside.state, filter);
      _chainParent = outside.state;
      _chainFilter = filter;
    }
    return world.set(
      outside.base,
      outside.dx + offset.dx,
      outside.dy + offset.dy,
      null,
      _chain!,
      spread: double.infinity,
    );
  }
}

/// A color filter.
@internal
final class ColorNode extends OpenNode {
  /// Creates the node.
  ColorNode(ColorFilterLayer super.layer);

  StateChain? _chain;
  StateChain? _chainParent;
  ui.ColorFilter? _read;

  @override
  int saves({required bool flat}) =>
      (layer as ColorFilterLayer).colorFilter == null ? 0 : 1;

  @override
  void enter(SceneOut out, Rect band) {
    final filter = (layer as ColorFilterLayer).colorFilter;
    if (filter == null) return;
    out.settle();
    out.builder.pushColorFilter(filter);
    out.pushes++;
  }

  @override
  bool updateWorld(FormWorld outside) {
    final value = (layer as ColorFilterLayer).colorFilter;
    if (value != _read) {
      edited = true;
      _read = value;
    }
    if (_chain == null ||
        !identical(_chainParent, outside.state) ||
        _chain!.token != value) {
      _chain = value == null ? outside.state : StateChain(outside.state, value);
      _chainParent = outside.state;
    }
    return world.set(
      outside.base,
      outside.dx,
      outside.dy,
      outside.clip,
      _chain!,
      spread: outside.spread,
    );
  }
}

/// A shader mask. A fragment shader keeps its identity while its uniforms
/// change, so it counts as changed every frame.
@internal
final class MaskNode extends OpenNode {
  /// Creates the node.
  MaskNode(ShaderMaskLayer super.layer);

  StateChain? _chain;
  StateChain? _chainParent;
  Object? _shader;
  Rect? _rect;
  BlendMode? _blend;
  Rect _extra = Rect.zero;

  @override
  Rect get extra => _extra;

  @override
  int saves({required bool flat}) {
    final layer = this.layer as ShaderMaskLayer;
    return layer.shader == null ||
            layer.maskRect == null ||
            layer.blendMode == null
        ? 0
        : 1;
  }

  @override
  void enter(SceneOut out, Rect band) {
    final layer = this.layer as ShaderMaskLayer;
    final shader = layer.shader;
    final rect = layer.maskRect;
    final blend = layer.blendMode;
    if (shader == null || rect == null || blend == null) return;
    out.settle();
    out.builder.pushShaderMask(shader, rect, blend);
    out.pushes++;
  }

  @override
  bool updateWorld(FormWorld outside) {
    final layer = this.layer as ShaderMaskLayer;
    final shader = layer.shader;
    final rect = layer.maskRect;
    final blend = layer.blendMode;
    if (shader is ui.FragmentShader ||
        !identical(_shader, shader) ||
        _rect != rect ||
        _blend != blend) {
      edited = true;
    }
    if (shader == null || rect == null || blend == null) {
      _shader = shader;
      _rect = rect;
      _blend = blend;
      return world.inherit(outside);
    }
    if (_chain == null ||
        shader is ui.FragmentShader ||
        !identical(_chainParent, outside.state) ||
        !identical(_shader, shader) ||
        _rect != rect ||
        _blend != blend) {
      _chain = StateChain(
        StateChain(outside.state, rect),
        shader is ui.FragmentShader ? Object() : shader,
      );
      _chainParent = outside.state;
      _shader = shader;
      _rect = rect;
      _blend = blend;
      _extra = outside.reaching(rect);
    }
    return world.set(
      outside.base,
      outside.dx,
      outside.dy,
      outside.clip,
      _chain!,
      spread: outside.spread,
    );
  }
}

/// A clip of any shape.
@internal
final class ClipNode extends OpenNode {
  /// Creates the node.
  ClipNode(super.layer);

  Object? _geometry;
  Clip? _behavior;
  Rect? _clip;
  StateChain? _chain;
  StateChain? _chainParent;
  int _seen = 0;

  static final _pathBounds = Expando<Rect>();

  (Object?, Clip) _read() => switch (layer) {
    ClipRectLayer(:final clipRect, :final clipBehavior) => (
      clipRect,
      clipBehavior,
    ),
    ClipRRectLayer(:final clipRRect, :final clipBehavior) => (
      clipRRect,
      clipBehavior,
    ),
    ClipRSuperellipseLayer(:final clipRSuperellipse, :final clipBehavior) => (
      clipRSuperellipse,
      clipBehavior,
    ),
    ClipPathLayer(:final clipPath, :final clipBehavior) => (
      clipPath,
      clipBehavior,
    ),
    NativeClipLayer(:final enabled, :final geometry, :final clipBehavior) => (
      enabled ? geometry : null,
      clipBehavior,
    ),
    _ => (null, Clip.none),
  };

  static Rect _boundsOf(Object geometry) => switch (geometry) {
    final Rect rect => rect,
    final RRect rect => rect.outerRect,
    final RSuperellipse rect => rect.outerRect,
    final Path path => _pathBounds[path] ??= path.getBounds(),
    _ => Rect.largest,
  };

  @override
  int saves({required bool flat}) =>
      _geometry != null && _behavior == Clip.antiAliasWithSaveLayer ? 1 : 0;

  @override
  void enter(SceneOut out, Rect band) {
    final (geometry, behavior) = _read();
    if (geometry == null || behavior == Clip.none) return;
    // A rect that cuts nothing of the read costs a layer for nothing.
    if (geometry is Rect &&
        behavior != Clip.antiAliasWithSaveLayer &&
        world.spread == 0 &&
        _clip != null &&
        _clip!.left <= band.left &&
        _clip!.top <= band.top &&
        _clip!.right >= band.right &&
        _clip!.bottom >= band.bottom) {
      return;
    }
    out.settle();
    final builder = out.builder;
    switch (geometry) {
      case final Rect rect:
        builder.pushClipRect(rect, clipBehavior: behavior);
      case final RRect rect:
        builder.pushClipRRect(rect, clipBehavior: behavior);
      case final RSuperellipse rect:
        builder.pushClipRSuperellipse(rect, clipBehavior: behavior);
      case final Path path:
        builder.pushClipPath(path, clipBehavior: behavior);
      default:
        return;
    }
    out.pushes++;
  }

  @override
  bool updateWorld(FormWorld outside) {
    final (geometry, behavior) = _read();
    final same =
        _behavior == behavior &&
        (identical(_geometry, geometry) || _geometry == geometry);
    if (!same) {
      edited = true;
      _geometry = geometry;
      _behavior = behavior;
    }
    if (geometry == null || behavior == Clip.none) {
      return world.inherit(outside);
    }
    if (_chain == null ||
        !same ||
        _seen != outside.stamp ||
        !identical(_chainParent, outside.state)) {
      _seen = outside.stamp;
      _clip = outside.reaching(_boundsOf(geometry));
      _chain = StateChain(StateChain(outside.state, geometry), behavior);
      _chainParent = outside.state;
    }
    return world.set(
      outside.base,
      outside.dx,
      outside.dy,
      _clip,
      _chain!,
      spread: outside.spread,
    );
  }
}

/// A layer type registered with [LiquidGlassUnderlay].
@internal
final class EffectsNode extends OpenNode with _Matrix {
  /// Creates the node.
  EffectsNode(super.layer);

  // How many sigmas a Gaussian blur spreads what it blurs: Impeller's kernel
  // ends at three, and a downsampled blur reads a little past it.
  static const double _blurReach = 4;

  // The most [matrix] stretches a length in the plane.
  static double _stretch(Matrix4 matrix) {
    final m = matrix.storage;
    return sqrt(max(m[0] * m[0] + m[1] * m[1], m[4] * m[4] + m[5] * m[5]));
  }

  StateChain? _chain;
  StateChain? _chainParent;
  Object? _token;
  bool _hidden = false;

  @override
  bool get shows => !_hidden;

  // A blur is its layer and two passes of its own; an opacity over it is
  // the same layer's.
  @override
  int saves({required bool flat}) {
    if (_token case (_, final int? alpha, final double blur)) {
      if (blur > 0 && !flat) return 3;
      return leaves > 1 && alpha != null && alpha != 255 ? 1 : 0;
    }
    return 0;
  }

  @override
  bool get savesByKind => switch (_token) {
    (_, _, final double blur) => blur > 0,
    _ => false,
  };

  @override
  void enter(SceneOut out, Rect band) {
    final effects = underlayEffectsOf(layer)!;
    out.transform(effects.transform);
    final builder = out.builder;
    if (effects.clip case final rounded?) {
      out.settle();
      builder.pushClipRRect(rounded, clipBehavior: _roundedClip);
      out.pushes++;
    }
    if (effects.alpha case final alpha? when alpha != 255) {
      out.settleMatrix();
      builder.pushOpacity(alpha, offset: out.at);
      out.at = Offset.zero;
      out.pushes++;
    }
    // Under glass that frosts all it shows the blur is left out. NEAR: what
    // blurs in under frosted glass is drawn there as sharp as the frost
    // leaves it, in a copy of a sixteenth of its pixels.
    if (effects.blur > 0 && !out.flat) {
      if (!kReleaseMode) GlassWork.filters++;
      out.settleMatrix();
      builder.pushImageFilter(
        ui.ImageFilter.blur(sigmaX: effects.blur, sigmaY: effects.blur),
        offset: out.at,
      );
      out.at = Offset.zero;
      out.pushes++;
    }
  }

  @override
  bool updateWorld(FormWorld outside) {
    final effects = underlayEffectsOf(layer)!;
    _hidden = effects.alpha == 0;
    final token = (effects.clip, effects.alpha, effects.blur);
    if (_token != token) edited = true;
    if (_chain == null ||
        !identical(_chainParent, outside.state) ||
        _token != token) {
      final adds =
          effects.clip != null || effects.alpha != null || effects.blur > 0;
      _chain = adds ? StateChain(outside.state, token) : outside.state;
      _chainParent = outside.state;
      _token = token;
    }
    final own = effects.transform;
    var clip = outside.clip;
    if (effects.clip case final rounded?) {
      final bounds = MatrixUtils.transformRect(
        _resolve(outside, own),
        rounded.outerRect,
      );
      clip = clip == null ? bounds : clip.intersect(bounds);
    }
    final blurred = effects.blur > 0;
    return _placeUnder(
      outside,
      own,
      blurred ? null : clip,
      _chain!,
      spread: blurred
          ? outside.spread +
                _blurReach *
                    effects.blur *
                    _stretch(outside.base) *
                    _stretch(own)
          : outside.spread,
    );
  }
}

// The native scene builder's default. The web's has none and requires the
// argument, and a constant equal to the native default is reported as
// redundant, so it is not one.
Clip get _roundedClip => Clip.antiAlias;
