import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/rendering/paint_fake_glass_surface.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_programs.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';

/// One way a glass shape moves what is drawn over it away from its rim:
/// by [amount] at the rim, falling along a quarter circle to nothing
/// [height] deep, as a lifted iOS lens does with what it selects.
@immutable
final class LiquidGlassContentBend {
  /// A bend of [amount] at the rim that reaches [height] deep, both in
  /// logical pixels.
  const LiquidGlassContentBend({required this.amount, required this.height});

  /// How far from its place the rim shows the content, in logical pixels.
  final double amount;

  /// How deep from the rim the bend reaches, in logical pixels.
  final double height;

  /// How deep from the rim lies what shows [depth] from it.
  double shownDepth(double depth) {
    if (depth < 0 || depth >= height) return depth;
    final x = 1 - depth / height;
    return depth + amount * (1 - math.sqrt(1 - x * x));
  }

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassContentBend &&
      other.amount == amount &&
      other.height == height;

  @override
  int get hashCode => Object.hash(amount, height);
}

/// Paints content over a glass shape the way the shape shows it at its
/// rim: every point shows what lies deeper under the rim by the shape's
/// bends, its colors parted the way the glass parts what lies under it, and
/// from where both end everything shows in place.
///
/// The content is drawn once into a picture the size of the shape, which
/// costs one offscreen pass of that size per paint and no filter. The
/// picture lies on the pixels the content would be drawn on, so what the
/// bends and the parting do not reach shows pixel for pixel.
///
/// The middle of the shape, which the bends and the parting leave in place,
/// is the picture drawn as it is, on whole device pixels: a third of a tab
/// bar's lifted lens. Around it, without a parting, the picture is drawn as
/// one mesh whose rings lie at most a logical pixel apart and read it where
/// the bends say. With one a shader draws it twice, first what the content
/// takes of what lies under it and then the content, so each color covers
/// by what its own reads hold, as if the content and what lies under it
/// were parted together. Inside a layer that holds nothing under the
/// content the two draws leave the content covering by its widest color.
/// The shader takes 32 work registers on a Mali, and every pixel it draws
/// seven reads of the picture in each draw. NEAR: a read beside a point
/// follows the outline through the point, a circle or a straight side, and
/// not the one through itself; around a corner of 35 a host capture stays
/// within 12 of 255 of the outline worked out for every read.
///
/// The parting needs its program, which `LiquidGlass.precache` loads; a
/// paint before it has loaded asks for it and parts nothing. It takes at
/// most two bends. The depth is the distance to an outline with circular
/// corners. Keep one of these per shape, paint through it each frame the
/// shape bends its content, and [dispose] it with the shape.
final class LiquidGlassBentContent {
  ui.Image? _image;
  ui.ImageShader? _shader;
  ui.Vertices? _vertices;
  ui.FragmentShader? _parting;

  /// Releases the picture and the mesh of the last paint.
  void dispose() {
    _vertices?.dispose();
    _shader?.dispose();
    _image?.dispose();
    _parting?.dispose();
    _vertices = null;
    _shader = null;
    _image = null;
    _parting = null;
  }

  // A load that fails reports its error, which one paint after another
  // must not repeat.
  static bool _asked = false;

  // Rings near the rim lie closer: a bend is steepest there.
  static const List<double> _rimDepths = [0, 0.1, 0.25, 0.5, 0.75, 1, 1.5, 2];

  /// Paints what [content] paints as a shape that fills [rect] with corners
  /// of [radius] shows it through [bends], applied in order from the one
  /// nearest the eye, inside [clip], the shape's outline.
  ///
  /// With an [aberration] the colors of what the bends show part by it at
  /// the rim, fading to nothing [aberrationDepth] deep, along the way
  /// `LiquidGlassSettings.aberration` describes; both are in logical
  /// pixels.
  ///
  /// [rect] and [clip] are in the coordinates [content] paints in when it
  /// is given [offset], and [content] is drawn at [devicePixelRatio]. With
  /// no bend and no parting the content is painted as it is.
  void paint(
    PaintingContext context,
    Offset offset, {
    required Rect rect,
    required double radius,
    required Path clip,
    required List<LiquidGlassContentBend> bends,
    required double devicePixelRatio,
    required PaintingContextCallback content,
    double aberration = 0,
    double aberrationDepth = 0,
  }) {
    final half = rect.shortestSide / 2;
    var reach = 0.0;
    for (final bend in bends) {
      if (bend.amount != 0) reach = math.max(reach, bend.height);
    }
    reach = math.min(reach, half);
    ui.FragmentProgram? program;
    if (aberration > 0 && aberrationDepth > 0 && bends.length <= 2) {
      program = GlassShaderPrograms.cached(ShaderKeys.bentContent);
      if (program == null && !_asked) {
        _asked = true;
        unawaited(GlassShaderPrograms.precacheShader(ShaderKeys.bentContent));
      }
    }
    if ((reach <= 0 && program == null) ||
        rect.isEmpty ||
        devicePixelRatio <= 0) {
      return content(context, offset);
    }
    dispose();
    // On the pixels of the layer the content is drawn in, so the picture
    // is read texel for pixel wherever nothing bends.
    final bounds = Rect.fromLTRB(
      (rect.left * devicePixelRatio).floorToDouble() / devicePixelRatio,
      (rect.top * devicePixelRatio).floorToDouble() / devicePixelRatio,
      (rect.right * devicePixelRatio).ceilToDouble() / devicePixelRatio,
      (rect.bottom * devicePixelRatio).ceilToDouble() / devicePixelRatio,
    );
    final layer = OffsetLayer();
    final offscreen = _Offscreen(layer, bounds);
    content(offscreen, offset);
    offscreen.finish();
    final image = _image = layer.toImageSync(
      bounds,
      pixelRatio: devicePixelRatio,
    );
    layer.dispose();
    // Where the picture lies: as many logical pixels wide as it holds
    // device pixels, which the layer can round up by one past [bounds].
    final picture =
        bounds.topLeft &
        Size(image.width / devicePixelRatio, image.height / devicePixelRatio);
    final corners = radius.clamp(0.0, half);
    if (program != null) {
      _paintParted(
        context.canvas,
        program,
        image,
        rect: rect,
        picture: picture,
        radius: corners,
        clip: clip,
        bends: bends,
        aberration: aberration,
        aberrationDepth: aberrationDepth,
        devicePixelRatio: devicePixelRatio,
      );
    } else {
      _paintMesh(
        context.canvas,
        image,
        rect: rect,
        picture: picture,
        radius: corners,
        clip: clip,
        bends: bends,
        reach: reach,
        devicePixelRatio: devicePixelRatio,
      );
    }
  }

  void _paintParted(
    Canvas canvas,
    ui.FragmentProgram program,
    ui.Image image, {
    required Rect rect,
    required Rect picture,
    required double radius,
    required Path clip,
    required List<LiquidGlassContentBend> bends,
    required double aberration,
    required double aberrationDepth,
    required double devicePixelRatio,
  }) {
    final shader = _parting = program.fragmentShader()
      ..setImageSampler(0, image, filterQuality: FilterQuality.low);
    final origin = picture.topLeft - rect.topLeft;
    final first = bends.isNotEmpty ? bends[0] : null;
    final second = bends.length > 1 ? bends[1] : null;
    canvas
      ..save()
      ..clipPath(clip)
      ..translate(rect.left, rect.top);
    var still = aberrationDepth;
    for (final bend in bends) {
      if (bend.amount != 0) still = math.max(still, bend.height);
    }
    final middle = _onPixels(
      _middle(rect.size, radius, still),
      canvas.getTransform(),
    );
    // The shader draws the picture as it is from [still] deep on.
    _paintMiddle(canvas, image, picture.shift(-rect.topLeft), middle);
    final quad = fakeGlassSurfaceQuad(
      Offset.zero & rect.size,
      canvas.getTransform(),
    );
    // What the content takes of what lies under it, then the content.
    for (final (pass, blend) in const [
      (0.0, BlendMode.modulate),
      (1.0, BlendMode.plus),
    ]) {
      final uniforms = <double>[
        rect.width,
        rect.height,
        radius,
        pass,
        origin.dx,
        origin.dy,
        1 / picture.width,
        1 / picture.height,
        first?.amount ?? 0,
        first?.height ?? 0,
        second?.amount ?? 0,
        second?.height ?? 0,
        aberration,
        aberrationDepth,
        1 / devicePixelRatio,
        0,
      ];
      for (var i = 0; i < uniforms.length; i++) {
        shader.setFloat(i, uniforms[i]);
      }
      canvas.drawRect(
        quad,
        Paint()
          ..shader = shader
          ..blendMode = blend,
      );
    }
    canvas.restore();
  }

  /// Draws [image], which lies over [picture], as it is inside [middle],
  /// and leaves [canvas] clipped to the rest. On whole pixels the two clips
  /// split no pixel between them.
  static void _paintMiddle(
    Canvas canvas,
    ui.Image image,
    Rect picture,
    Rect middle,
  ) {
    if (middle.isEmpty) return;
    canvas
      ..save()
      ..clipRect(middle, doAntiAlias: false)
      ..drawImageRect(
        image,
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
        picture,
        Paint()..filterQuality = FilterQuality.low,
      )
      ..restore()
      ..clipRect(middle, clipOp: ui.ClipOp.difference, doAntiAlias: false);
  }

  /// The largest rect, centered in a box of [size] with corners of
  /// [radius], whose every point lies at least [depth] inside the box's
  /// outline; empty where that is under a tenth of the box, which a clip
  /// of its own would not repay.
  static Rect _middle(Size size, double radius, double depth) {
    final halfWidth = size.width / 2 - depth;
    final halfHeight = size.height / 2 - depth;
    if (halfWidth <= 0 || halfHeight <= 0) return Rect.zero;
    // The points that deep fill a box with corners of what is left of
    // the radius; the rect touches one of those corners.
    final round = math.max(radius - depth, 0).toDouble();
    var width = 0.0;
    var height = 0.0;
    for (var step = 0; step <= 8; step++) {
      final angle = step * math.pi / 16;
      final x = halfWidth - round + round * math.cos(angle);
      final y = halfHeight - round + round * math.sin(angle);
      if (x * y > width * height) {
        width = x;
        height = y;
      }
    }
    if (width * height * 4 < size.width * size.height / 10) return Rect.zero;
    return Rect.fromCenter(
      center: size.center(Offset.zero),
      width: width * 2,
      height: height * 2,
    );
  }

  /// [rect] shrunk to the whole device pixels inside it under
  /// [transform], or empty where the transform turns or skews it.
  static Rect _onPixels(Rect rect, Float64List transform) {
    if (rect.isEmpty ||
        transform[1] != 0 ||
        transform[4] != 0 ||
        transform[3] != 0 ||
        transform[7] != 0 ||
        transform[15] != 1 ||
        transform[0] <= 0 ||
        transform[5] <= 0) {
      return Rect.zero;
    }
    final scaleX = transform[0];
    final scaleY = transform[5];
    final dx = transform[12];
    final dy = transform[13];
    final snapped = Rect.fromLTRB(
      ((rect.left * scaleX + dx).ceilToDouble() - dx) / scaleX,
      ((rect.top * scaleY + dy).ceilToDouble() - dy) / scaleY,
      ((rect.right * scaleX + dx).floorToDouble() - dx) / scaleX,
      ((rect.bottom * scaleY + dy).floorToDouble() - dy) / scaleY,
    );
    return snapped.isEmpty ? Rect.zero : snapped;
  }

  void _paintMesh(
    Canvas canvas,
    ui.Image image, {
    required Rect rect,
    required Rect picture,
    required double radius,
    required Path clip,
    required List<LiquidGlassContentBend> bends,
    required double reach,
    required double devicePixelRatio,
  }) {
    final half = rect.shortestSide / 2;
    final depths = <double>[
      // One ring outside, so the clip and not the mesh draws the edge.
      -1,
      for (final depth in _rimDepths)
        if (depth < reach) depth,
      for (var depth = 3.0; depth < reach; depth++) depth,
      reach,
      if (reach < half) half,
    ];
    final outline = _Rings(rect.size, radius);
    final columns = outline.columns;
    final positions = Float32List(columns * depths.length * 2);
    final sources = Float32List(columns * depths.length * 2);
    final texture = rect.topLeft - picture.topLeft;
    for (var ring = 0; ring < depths.length; ring++) {
      final depth = depths[ring];
      var shown = math.max<double>(depth, 0);
      for (final bend in bends) {
        shown = bend.shownDepth(shown);
      }
      shown = math.min(shown, half);
      for (var c = 0; c < columns; c++) {
        final at = (ring * columns + c) * 2;
        final point = rect.topLeft + outline.pointAt(c, depth);
        positions[at] = point.dx;
        positions[at + 1] = point.dy;
        final source = texture + outline.pointAt(c, shown);
        sources[at] = source.dx * devicePixelRatio;
        sources[at + 1] = source.dy * devicePixelRatio;
      }
    }
    final vertices = _vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: sources,
      indices: outline.indices(depths.length),
    );
    final shader = _shader = ui.ImageShader(
      image,
      TileMode.decal,
      TileMode.decal,
      Matrix4.identity().storage,
      filterQuality: FilterQuality.low,
    );
    canvas
      ..save()
      ..clipPath(clip);
    // The mesh reads the picture as it is from [reach] deep on, through
    // triangles a sampler need not read texel for pixel.
    _paintMiddle(
      canvas,
      image,
      picture,
      _onPixels(
        _middle(rect.size, radius, reach).shift(rect.topLeft),
        canvas.getTransform(),
      ),
    );
    canvas
      ..drawVertices(vertices, BlendMode.srcOver, Paint()..shader = shader)
      ..restore();
  }
}

// Records what is painted into a layer of its own, to be drawn as a
// picture.
final class _Offscreen extends PaintingContext {
  _Offscreen(super.containerLayer, super.estimatedBounds);

  void finish() => stopRecordingIfNeeded();
}

// The outline of a box with circular corners as columns that run from it
// toward its middle, so a mesh samples the box on rings at fixed depths:
// twelve columns to a corner and one every 8 logical pixels of a straight
// edge.
final class _Rings {
  _Rings(Size size, this.radius) {
    final w = size.width;
    final h = size.height;
    const perCorner = 12;
    const edgeStep = 8.0;
    final centers = [
      Offset(radius, radius),
      Offset(w - radius, radius),
      Offset(w - radius, h - radius),
      Offset(radius, h - radius),
    ];
    // The outward diagonal of corner k, as long as it is deep per unit of
    // depth along each edge.
    Offset diagonalOf(int k) {
      final angle = math.pi * 5 / 4 + k * math.pi / 2;
      return Offset(math.cos(angle), math.sin(angle)) * math.sqrt2;
    }

    // Clockwise from the left end of the top left corner.
    for (var k = 0; k < 4; k++) {
      final center = centers[k];
      final start = math.pi + k * math.pi / 2;
      final diagonal = diagonalOf(k);
      for (var i = 0; i <= perCorner; i++) {
        final angle = start + i * math.pi / 2 / perCorner;
        final normal = Offset(math.cos(angle), math.sin(angle));
        _edge.add(center + normal * radius);
        _normals.add(normal);
        _miters.add(diagonal);
      }
      final from = _edge.last;
      final normal = _normals.last;
      final to = centers[(k + 1) % 4] + normal * radius;
      final pieces = ((to - from).distance / edgeStep).ceil();
      for (var i = 1; i < pieces; i++) {
        final t = i / pieces;
        _edge.add(Offset.lerp(from, to, t)!);
        _normals.add(normal);
        _miters.add(Offset.lerp(diagonal, diagonalOf(k + 1), t)!);
      }
    }
  }

  final double radius;
  final _edge = <Offset>[];
  final _normals = <Offset>[];
  final _miters = <Offset>[];

  int get columns => _edge.length;

  // Deeper than the corners' centers a ring is the box drawn in by the
  // depth, whose corners lie on the diagonals.
  Offset pointAt(int column, double depth) => depth <= radius
      ? _edge[column] - _normals[column] * depth
      : _edge[column] -
            _normals[column] * radius -
            _miters[column] * (depth - radius);

  Uint16List indices(int rings) {
    final indices = Uint16List(columns * (rings - 1) * 6);
    var next = 0;
    for (var ring = 0; ring < rings - 1; ring++) {
      for (var c = 0; c < columns; c++) {
        final a = ring * columns + c;
        final b = ring * columns + (c + 1) % columns;
        indices[next++] = a;
        indices[next++] = b;
        indices[next++] = b + columns;
        indices[next++] = a;
        indices[next++] = b + columns;
        indices[next++] = a + columns;
      }
    }
    return indices;
  }
}
