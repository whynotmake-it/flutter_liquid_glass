import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/painting/glass_work.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_shadow.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';
import 'package:liquid_glass_renderer/src/plan/rects.dart';
import 'package:liquid_glass_renderer/src/rendering/frame_shapes.dart';
import 'package:liquid_glass_renderer/src/rendering/retained_glass_clip.dart';

/// The exterior shadows of the shapes a glass layer's committed frame draws,
/// drawn and kept in a layer of their own.
@internal
final class GlassShadowRecorder {
  /// Creates a recorder of the shadows of the shapes [_frame] draws, each
  /// kept inside the individual ancestor clips [_clips] hold for its render
  /// object, cast by the edge of the field [_field] gives where it gives
  /// one.
  GlassShadowRecorder(this._frame, this._clips, this._field);

  final FrameShapes _frame;
  final RetainedGlassClip _clips;
  final LiquidGlassField? Function() _field;

  final _slot = LayerHandle<ContainerLayer>();
  final _picture = LayerHandle<PictureLayer>();

  bool get _hasShadows =>
      _frame.drawn.any((drawn) => drawn.shape.shadows.isNotEmpty);

  /// The layer [begin] last handed out, or null.
  ContainerLayer? get slot => _slot.layer;

  /// The picture [record] last recorded, wherever it lies now.
  PictureLayer? get picture => _picture.layer;

  /// Forgets what it knew of the committed shapes: they changed.
  void shapesCommitted() => _fading = null;

  // Asked several times a frame; the committed shapes change only where
  // [shapesCommitted] is called.
  bool? _fading;

  /// Whether a drawn shape is partly visible.
  bool get fading => _fading ??= _frame.drawn.any(
    (drawn) => drawn.shape.appearance.visibility < 1,
  );

  List<_Body> _bodies(LiquidGlassField? field) {
    if (field != null) {
      for (final drawn in _frame.drawn) {
        if (drawn.shape.shadows.isEmpty) continue;
        return [_EdgeBody(drawn, field.edge)];
      }
      return const [];
    }
    return [
      for (final drawn in _frame.drawn)
        if (drawn.shape.shadows.isNotEmpty) _ShapeBody(drawn),
    ];
  }

  /// Grows [bounds] to include the shadows of the drawn shapes.
  Rect expand(Rect bounds) => _bodies(
    _field(),
  ).fold(bounds, (bounds, body) => bounds.expandToInclude(body.shadowBounds));

  /// Draws the drawn shapes' exterior shadows into [canvas] at [offset],
  /// kept outside every drawn shape's silhouette, or whole with [under].
  void draw(
    Canvas canvas,
    Offset offset, {
    required bool under,
    required Offset translation,
    required Rect bounds,
    required double devicePixelRatio,
  }) {
    final field = _field();
    final bodies = _bodies(field);
    if (bodies.isEmpty) return;
    final drawn = _frame.drawn.singleOrNull;
    final lone =
        bodies.length == 1 &&
        (field != null ||
            drawn != null &&
                identical(drawn.committed.source, drawn.shape.renderObject));
    canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    switch (GlassShadowCut.of(
      lone: lone,
      shadows: lone ? bodies.single.shadows : const [],
      fading: fading,
      under: under,
    )) {
      case GlassShadowCut.outer:
        _cast(canvas, translation, bodies, outer: true);
      case GlassShadowCut.none:
        _cast(canvas, translation, bodies, outer: false);
      case GlassShadowCut.fraction:
        _castCutOffscreen(
          canvas,
          translation,
          bodies,
          field,
          bounds,
          devicePixelRatio,
        );
      case GlassShadowCut.clip:
        final silhouettes = _currentSilhouettes(field);
        for (final (:bounds, :group) in _shadowGroups(bodies)) {
          canvas.save();
          _clipOutsideSilhouettes(canvas, bounds, silhouettes);
          _cast(canvas, translation, group, outer: false);
          canvas.restore();
        }
    }
    canvas.restore();
  }

  void _cast(
    Canvas canvas,
    Offset translation,
    Iterable<_Body> bodies, {
    required bool outer,
  }) {
    for (final body in bodies) {
      _clips.paintWithIndividualClips(
        canvas,
        body.drawn.shape.renderObject,
        translation,
        () => body.cast(canvas, outer: outer),
      );
    }
  }

  // A clip cuts a silhouette whole, but a fading glass lets as much of the
  // shadow under it show as it has yet to fade in. Only an offscreen layer
  // cuts by a fraction; fades are brief, so only they pay for one.
  void _castCutOffscreen(
    Canvas canvas,
    Offset translation,
    List<_Body> bodies,
    LiquidGlassField? field,
    Rect bounds,
    double devicePixelRatio,
  ) {
    // Bounds only: growing them to pixel buckets changes no pixel, and an
    // animated shape does not get a render target of a new size each frame.
    canvas.saveLayer(
      ViewPixels(devicePixelRatio).bucket(bounds),
      Paint(),
    );
    _cast(canvas, translation, bodies, outer: false);
    if (field != null) {
      final body = bodies.single;
      body.silhouette.cutOut(canvas, body.visibility);
    } else {
      for (final drawn in _frame.drawn) {
        final shape = drawn.shape;
        canvas
          ..save()
          ..transform(drawn.toLayer.storage);
        LiquidGlassSilhouette.shape(
          shape.shape,
          Offset.zero & shape.renderObject.paintSize,
        ).cutOut(canvas, shape.appearance.visibility);
        canvas.restore();
      }
    }
    canvas.restore();
  }

  List<({Rect bounds, List<_Body> group})> _shadowGroups(List<_Body> bodies) {
    final groups = <({Rect bounds, List<_Body> group})>[];
    for (final body in bodies) {
      var bounds = body.shadowBounds;
      final group = [body];
      for (var i = groups.length - 1; i >= 0; i--) {
        final (bounds: other, group: otherGroup) = groups[i];
        if (!meets(other, bounds)) continue;
        bounds = bounds.expandToInclude(other);
        group.addAll(otherGroup);
        groups.removeAt(i);
        i = groups.length;
      }
      groups.add((bounds: bounds, group: group));
    }
    return groups;
  }

  // The last draw's silhouettes, matched to shapes by position: an entry is
  // reused while its shape, size and transform stay the same, and only
  // re-mapped when just the transform changed. A size within a hair of the
  // last counts as the same: a moving shape's size, taken as the difference
  // of its moved edges, changes in its last bits from frame to frame.
  List<_Silhouette> _silhouettes = const [];

  static const double _sameSize = 1e-6;

  List<_Silhouette> _currentSilhouettes(LiquidGlassField? field) {
    if (field != null) {
      if (_silhouettes.singleOrNull case final _EdgeSilhouette old
          when identical(old.cut, field.edge)) {
        return _silhouettes;
      }
      return _silhouettes = [
        _EdgeSilhouette(LiquidGlassSilhouette.path(field.edge)),
      ];
    }
    final previous = _silhouettes;
    final next = <_Silhouette>[];
    for (final drawn in _frame.drawn) {
      final shape = drawn.shape;
      final transform = drawn.toLayer;
      final size = shape.renderObject.paintSize;
      final old = next.length < previous.length ? previous[next.length] : null;
      final sameOutline =
          old is _ShapeSilhouette &&
          old.shape == shape.shape &&
          (old.size.width - size.width).abs() < _sameSize &&
          (old.size.height - size.height).abs() < _sameSize;
      if (sameOutline && MatrixUtils.matrixEquals(old.transform, transform)) {
        next.add(old);
        continue;
      }
      next.add(
        _ShapeSilhouette(
          shape.shape,
          sameOutline ? old.size : size,
          transform,
          cut: sameOutline ? old.cut : null,
        ),
      );
    }
    return _silhouettes = next;
  }

  /// Clips [canvas] to [bounds] less each of [all] whose bounds meet it,
  /// without a path operation where it can.
  void _clipOutsideSilhouettes(
    Canvas canvas,
    Rect bounds,
    List<_Silhouette> all,
  ) {
    final silhouettes = [
      for (final silhouette in all)
        if (meets(silhouette.bounds, bounds)) silhouette,
    ];
    var apart = silhouettes.every((silhouette) => silhouette.cutsUnderEvenOdd);
    for (var i = 0; i < silhouettes.length && apart; i++) {
      for (var j = i + 1; j < silhouettes.length; j++) {
        if (meets(silhouettes[i].bounds, silhouettes[j].bounds)) {
          apart = false;
          break;
        }
      }
    }
    if (apart) {
      final path = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(bounds);
      for (final silhouette in silhouettes) {
        path.addPath(silhouette.cut, Offset.zero, matrix4: silhouette._toLayer);
      }
      canvas.clipPath(path);
      return;
    }
    for (final silhouette in silhouettes) {
      canvas.clipPath(silhouette.outside(bounds));
    }
  }

  /// Empties the layer the shadows are recorded into and returns it, or
  /// clears it and returns null when no committed shape casts a shadow.
  ContainerLayer? begin() {
    if (!_hasShadows) {
      clear();
      return null;
    }
    final slot = (_slot.layer ??= ContainerLayer())..removeAllChildren();
    _picture.layer = null;
    return slot;
  }

  /// Records into [slot], which [begin] returned, what [draw] draws at
  /// [offset], in [bounds] shifted by it.
  void record(
    ContainerLayer slot,
    Offset offset, {
    required bool under,
    required Offset translation,
    required Rect bounds,
    required double devicePixelRatio,
  }) {
    if (!kReleaseMode) GlassWork.pictures++;
    final recorder = ui.PictureRecorder();
    draw(
      Canvas(recorder),
      offset,
      under: under,
      translation: translation,
      bounds: bounds,
      devicePixelRatio: devicePixelRatio,
    );
    final picture = PictureLayer(bounds.shift(offset))
      ..picture = recorder.endRecording();
    slot.append(picture);
    _picture.layer = picture;
  }

  /// Drops the recorded layer.
  void clear() {
    _slot.layer = null;
    _picture.layer = null;
  }

  /// Drops the recorded layer and the silhouettes it kept.
  void dispose() {
    _silhouettes = const [];
    clear();
  }
}

sealed class _Body {
  _Body(this.drawn, this.silhouette);

  final FrameShape drawn;
  final LiquidGlassSilhouette silhouette;

  List<BoxShadow> get shadows => drawn.shape.shadows;

  double get visibility => drawn.shape.appearance.visibility;

  Rect get _ownShadowBounds =>
      glassShadowBounds(silhouette.bounds, shadows, visibility);

  Rect get shadowBounds;

  void cast(Canvas canvas, {required bool outer});
}

final class _ShapeBody extends _Body {
  _ShapeBody(FrameShape drawn)
    : super(
        drawn,
        LiquidGlassSilhouette.shape(
          drawn.shape.shape,
          Offset.zero & drawn.shape.renderObject.paintSize,
        ),
      );

  @override
  Rect get shadowBounds =>
      MatrixUtils.transformRect(drawn.toLayer, _ownShadowBounds);

  @override
  void cast(Canvas canvas, {required bool outer}) {
    canvas
      ..save()
      ..transform(drawn.toLayer.storage);
    silhouette.cast(canvas, shadows, visibility, outer: outer);
    canvas.restore();
  }
}

final class _EdgeBody extends _Body {
  _EdgeBody(FrameShape drawn, Path edge)
    : super(drawn, LiquidGlassSilhouette.path(edge));

  @override
  Rect get shadowBounds => _ownShadowBounds;

  @override
  void cast(Canvas canvas, {required bool outer}) =>
      silhouette.cast(canvas, shadows, visibility, outer: outer);
}

sealed class _Silhouette {
  _Silhouette(this.cut, {required this.cutsUnderEvenOdd, required this.bounds});

  final Path cut;
  final bool cutsUnderEvenOdd;
  final Rect bounds;

  Float64List? get _toLayer;

  Rect? _outsideOf;
  Path? _outside;

  Path outside(Rect bounds) {
    if (bounds != _outsideOf || _outside == null) {
      _outsideOf = bounds;
      _outside = pathOutside(
        cut,
        bounds,
        cutsUnderEvenOdd: cutsUnderEvenOdd,
        transform: _toLayer,
      );
    }
    return _outside!;
  }
}

final class _ShapeSilhouette extends _Silhouette {
  _ShapeSilhouette(
    LiquidShape shape,
    Size size,
    Matrix4 transform, {
    Path? cut,
  }) : this._(
         LiquidGlassSilhouette.shape(shape, Offset.zero & size),
         shape,
         size,
         transform,
         cut,
       );

  _ShapeSilhouette._(
    LiquidGlassSilhouette silhouette,
    this.shape,
    this.size,
    this.transform,
    Path? cut,
  ) : super(
        cut ?? silhouette.cut,
        cutsUnderEvenOdd: silhouette.cutsUnderEvenOdd,
        bounds: MatrixUtils.transformRect(transform, silhouette.cutRect),
      );

  final LiquidShape shape;
  final Size size;
  final Matrix4 transform;

  @override
  Float64List get _toLayer => transform.storage;
}

final class _EdgeSilhouette extends _Silhouette {
  _EdgeSilhouette(LiquidGlassSilhouette edge)
    : super(
        edge.cut,
        cutsUnderEvenOdd: edge.cutsUnderEvenOdd,
        bounds: edge.bounds,
      );

  @override
  Float64List? get _toLayer => null;
}
