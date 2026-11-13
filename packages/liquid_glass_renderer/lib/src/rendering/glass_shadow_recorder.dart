import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_shadow.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_shape_helpers.dart';
import 'package:liquid_glass_renderer/src/rendering/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/rendering/retained_glass_clip.dart';
import 'package:liquid_glass_renderer/src/rendering/snap_rect_to_pixels.dart';

/// The exterior shadows of a glass layer's committed shapes, drawn and kept
/// in a layer of their own.
///
/// The layer that owns it hands it its committed shapes and its retained
/// ancestor clips once; it reads them as they are whenever it draws.
@internal
final class GlassShadowRecorder {
  /// Creates a recorder of the shadows of the committed shapes it is given,
  /// each kept inside the individual ancestor clips the given clips hold for
  /// its render object.
  GlassShadowRecorder(this._shapes, this._clips);

  final List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> _shapes;
  final RetainedGlassClip _clips;

  final _slot = LayerHandle<ContainerLayer>();
  final _picture = LayerHandle<PictureLayer>();

  bool get _hasShadows => _shapes.any(
    (entry) => entry.$2.shapes.any((shape) => shape.shadows.isNotEmpty),
  );

  /// The layer [begin] last handed out, or null.
  ContainerLayer? get slot => _slot.layer;

  /// The picture [record] last recorded, wherever it lies now.
  PictureLayer? get picture => _picture.layer;

  /// Forgets what it knew of the committed shapes: they changed.
  void shapesCommitted() => _fading = null;

  // Asked several times a frame; the committed shapes change only where
  // [shapesCommitted] is called.
  bool? _fading;

  /// Whether a committed shape is partly visible.
  bool get fading => _fading ??= _shapes.any(
    (entry) => entry.$2.shapes.any(
      (shape) =>
          shape.appearance.visibility > 0 && shape.appearance.visibility < 1,
    ),
  );

  /// Draws every committed shape's exterior shadows into [canvas] at
  /// [offset], kept outside the silhouette of every shape above zero
  /// visibility, or whole with [under]. [translation] is the compositor's
  /// translation of the retained effect, [bounds] the effect's paint
  /// bounds.
  void draw(
    Canvas canvas,
    Offset offset, {
    required bool under,
    required Offset translation,
    required Rect bounds,
    required double devicePixelRatio,
  }) {
    if (!_hasShadows) return;
    final entry = _shapes.singleOrNull;
    final shape = entry?.$2.shapes.singleOrNull;
    final useNativeOuterBlur =
        shape != null &&
        identical(entry!.$1, shape.renderObject) &&
        shape.shadows.every(
          (shadow) => shadow.offset == Offset.zero && shadow.spreadRadius >= 0,
        );
    canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    if (useNativeOuterBlur) {
      _paintShadows(canvas, translation, (_) => true, outer: true);
    } else if (fading) {
      _paintShadowsCutOffscreen(canvas, translation, bounds, devicePixelRatio);
    } else if (under) {
      _paintShadows(canvas, translation, (_) => true, outer: false);
    } else {
      // A clip, not an offscreen layer. Shadows whose bounds meet are
      // grouped, and each group is clipped to its own bounds less the
      // silhouettes, so glass scattered over a large layer clips only around
      // each group, not the whole layer.
      final silhouettes = _currentSilhouettes();
      for (final (:bounds, shapes: group) in _shadowGroups()) {
        canvas.save();
        _clipOutsideSilhouettes(canvas, bounds, silhouettes);
        _paintShadows(canvas, translation, group.contains, outer: false);
        canvas.restore();
      }
    }
    canvas.restore();
  }

  void _paintShadows(
    Canvas canvas,
    Offset translation,
    bool Function(ShapeGeometry shape) include, {
    required bool outer,
  }) {
    for (final (_, geometry, geometryToLayer) in _shapes) {
      for (final shape in geometry.shapes) {
        final shapeVisibility = shape.appearance.visibility.clamp(0.0, 1.0);
        if (shape.shadows.isEmpty || shapeVisibility <= 0) continue;
        if (!include(shape)) continue;
        _clips.paintWithIndividualClips(
          canvas,
          shape.renderObject,
          translation,
          () {
            canvas
              ..save()
              ..transform(geometryToLayer.storage);
            if (shape.shapeToGeometry case final transform?) {
              canvas.transform(transform.storage);
            }
            final rect = Offset.zero & shape.renderObject.paintSize;
            for (final shadow in shape.shadows) {
              final paint = shadow
                  .copyWith(
                    color: shadow.color.withValues(
                      alpha: shadow.color.a * shapeVisibility,
                    ),
                    blurRadius: shadow.blurRadius * shapeVisibility,
                    blurStyle: outer ? BlurStyle.outer : BlurStyle.normal,
                  )
                  .toPaint();
              drawGlassShape(
                canvas,
                shape.shape,
                rect.shift(shadow.offset).inflate(shadow.spreadRadius),
                paint,
              );
            }
            canvas.restore();
          },
        );
      }
    }
  }

  // A clip cuts a silhouette whole, but a fading glass lets as much of the
  // shadow under it show as it has yet to fade in. Only an offscreen layer
  // cuts by a fraction; fades are brief, so only they pay for one.
  void _paintShadowsCutOffscreen(
    Canvas canvas,
    Offset translation,
    Rect bounds,
    double devicePixelRatio,
  ) {
    // Bounds only: growing them to pixel buckets changes no pixel, and an
    // animated shape does not get a render target of a new size each frame.
    canvas.saveLayer(
      bounds.expandToPixelBuckets(devicePixelRatio),
      Paint(),
    );
    _paintShadows(canvas, translation, (_) => true, outer: false);
    for (final (_, geometry, geometryToLayer) in _shapes) {
      for (final shape in geometry.shapes) {
        final visibility = shape.appearance.visibility.clamp(0.0, 1.0);
        if (visibility <= 0) continue;
        canvas
          ..save()
          ..transform(shapeTransformToLayer(shape, geometryToLayer).storage);
        drawGlassShape(
          canvas,
          shape.shape,
          (Offset.zero & shape.renderObject.paintSize).deflate(.5),
          Paint()
            ..color = Color.fromRGBO(0, 0, 0, visibility)
            ..blendMode = BlendMode.dstOut,
        );
        canvas.restore();
      }
    }
    canvas.restore();
  }

  List<({Rect bounds, Set<ShapeGeometry> shapes})> _shadowGroups() {
    final groups = <({Rect bounds, Set<ShapeGeometry> shapes})>[];
    for (final (_, geometry, geometryToLayer) in _shapes) {
      for (final shape in geometry.shapes) {
        if (shape.shadows.isEmpty || shape.appearance.visibility <= 0) continue;
        var bounds = expandForGlassShadows(
          MatrixUtils.transformRect(
            shapeTransformToLayer(shape, geometryToLayer),
            Offset.zero & shape.renderObject.paintSize,
          ),
          [
            (<ShapeGeometry>[shape], geometryToLayer),
          ],
        );
        // By identity: ShapeGeometry compares by value, so its hash would walk
        // its appearance, shadows and transform on every lookup.
        final members = Set<ShapeGeometry>.identity()..add(shape);
        // Joining a group can make it meet another: merge until none meets.
        for (var i = groups.length - 1; i >= 0; i--) {
          final (bounds: other, shapes: otherMembers) = groups[i];
          if (!other.overlaps(bounds)) continue;
          bounds = bounds.expandToInclude(other);
          members.addAll(otherMembers);
          groups.removeAt(i);
          i = groups.length;
        }
        groups.add((bounds: bounds, shapes: members));
      }
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

  List<_Silhouette> _currentSilhouettes() {
    final previous = _silhouettes;
    final next = <_Silhouette>[];
    for (final (_, geometry, geometryToLayer) in _shapes) {
      for (final shape in geometry.shapes) {
        if (shape.appearance.visibility <= 0) continue;
        // A copy: the silhouette keeps it to compare with the next frame's.
        final transform = Matrix4.copy(
          shapeTransformToLayer(shape, geometryToLayer),
        );
        final size = shape.renderObject.paintSize;
        final old = next.length < previous.length
            ? previous[next.length]
            : null;
        final sameOutline =
            old != null &&
            old.shape == shape.shape &&
            (old.size.width - size.width).abs() < _sameSize &&
            (old.size.height - size.height).abs() < _sameSize;
        if (sameOutline && MatrixUtils.matrixEquals(old.transform, transform)) {
          next.add(old);
          continue;
        }
        // Half a pixel inside the outline, so the shadow reaches into the
        // glass's antialiased edge and no seam shows between them.
        final kept = sameOutline ? old.size : size;
        final outline = (Offset.zero & kept).deflate(.5);
        final local = sameOutline
            ? old.local
            : shape.shape.getOuterPath(outline);
        next.add(
          _Silhouette(
            shape.shape,
            kept,
            local,
            transform,
            // The outline fills its rect up to each side: the rect's bounds
            // are the path's, without asking the engine for them.
            MatrixUtils.transformRect(transform, outline),
          ),
        );
      }
    }
    return _silhouettes = next;
  }

  /// Clips [canvas] to [bounds] less each of [all] whose bounds meet it,
  /// without a path operation. While no two of those silhouettes' bounds
  /// meet, one even-odd path cuts them all as holes; otherwise even-odd would
  /// add back where two overlap, so each clips the bounds less itself and the
  /// clips intersect to the bounds less their union.
  void _clipOutsideSilhouettes(
    Canvas canvas,
    Rect bounds,
    List<_Silhouette> all,
  ) {
    final silhouettes = [
      for (final silhouette in all)
        if (silhouette.bounds.overlaps(bounds)) silhouette,
    ];
    var apart = true;
    for (var i = 0; i < silhouettes.length && apart; i++) {
      for (var j = i + 1; j < silhouettes.length; j++) {
        if (silhouettes[i].bounds.overlaps(silhouettes[j].bounds)) {
          apart = false;
          break;
        }
      }
    }
    Path outside() => Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(bounds);
    if (apart) {
      final path = outside();
      for (final silhouette in silhouettes) {
        silhouette.addTo(path);
      }
      canvas.clipPath(path);
      return;
    }
    for (final silhouette in silhouettes) {
      final path = outside();
      silhouette.addTo(path);
      canvas.clipPath(path);
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

/// A shape's outline at its size ([local]), its [transform] into the layer
/// and its [bounds] there.
class _Silhouette {
  _Silhouette(
    this.shape,
    this.size,
    this.local,
    this.transform,
    this.bounds,
  );

  final LiquidShape shape;
  final Size size;
  final Path local;
  final Matrix4 transform;
  final Rect bounds;

  void addTo(Path path) =>
      path.addPath(local, Offset.zero, matrix4: transform.storage);
}
