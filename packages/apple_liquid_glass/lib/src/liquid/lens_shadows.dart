import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// The shadows iOS 27 gives a lifted lens: a ring shadow and a weak inner
/// shadow, and no drop shadow.
///
/// Read from UIKit's lifted lenses on iOS 27.2 (tab bar, segmented control,
/// switch, slider; notes private); the lengths are the same on all four.
///
/// The ring shadow is black over the lens's glass and around it. It is a
/// band [ringWidth] wide just inside the lens's outline moved [ringDrop]
/// down, with a Gaussian edge of [sigma]: 2 pt inside the moved outline it
/// reaches 0.495 of its opacity. So it darkens the lens 10 pt under its top
/// and the page 6 pt under its bottom. Its opacity is [largeRing] on a
/// selection, and on a knob or thumb [smallRingDark] in dark mode and
/// [smallRingLight] in light mode. On the iPhone 16 Pro references a
/// slider's thumb over black shows 20 of 255 under the ring and 25 beside
/// it, and this law gives 20.4.
///
/// The inner shadow is black at [inner] inside the lens: the shadow the
/// lens's surroundings cast onto it from [innerDrop] above, with a Gaussian
/// edge of [sigma]. A selection bends it at the rim with what it selects
/// ([contentBend]), which leaves a crescent under the top that peaks 4 pt
/// deep at 0.028. UIKit gives its opacity, blur and offset; the shape it is
/// cast from is our reading of them.
///
/// Both follow the lens's glass as it appears.
///
/// Fidelity. Both are near UIKit's, not identical. They shade by the
/// distance to an outline with circular corners, as UIKit does, between
/// points at most 1 pt apart in depth. UIKit draws the ring under what a
/// selection selects and under the rim light; here it lies over the glass,
/// which changes the rim by less than a level of 255. Approximation: UIKit
/// keeps a light bar over a white page brighter than white, so its shadows
/// change nothing there; here they darken it by up to 5 %.
@internal
abstract final class LensShadowLaw {
  /// How far down the outline the ring shadow follows is moved.
  static const double ringDrop = 8;

  /// The width of the ring shadow's band inside the moved outline.
  static const double ringWidth = 4;

  /// The Gaussian sigma of both shadows' edges.
  static const double sigma = 3;

  /// The ring shadow's opacity on a large lens, a selection.
  static const double largeRing = 0.1;

  /// The ring shadow's opacity on a small lens in dark mode.
  static const double smallRingDark = 0.4;

  /// The ring shadow's opacity on a small lens in light mode.
  static const double smallRingLight = 0.15;

  /// The inner shadow's opacity.
  static const double inner = 0.06;

  /// How far down the inner shadow is cast.
  static const double innerDrop = 7;

  /// The ring shadow's opacity on a lens that is [small] in [brightness].
  static double ringOpacity({
    required bool small,
    required Brightness brightness,
  }) => !small
      ? largeRing
      : brightness == Brightness.dark
      ? smallRingDark
      : smallRingLight;

  /// How much of the ring shadow's opacity shows [depth] inside the moved
  /// outline (negative outside it).
  static double ringAt(double depth) =>
      _phi(depth / sigma) - _phi((depth - ringWidth) / sigma);

  /// How much of the inner shadow's opacity shows where the lens's outline
  /// moved down by [innerDrop] is [depth] inside (negative outside).
  static double innerAt(double depth) => _phi(-depth / sigma);

  /// How a lens of [height] across its short side, lifted by [lift], bends
  /// what it selects. A small lens bends none.
  static LiquidGlassContentBend contentBend(
    double height, {
    required bool small,
    double lift = 1,
  }) => small
      ? const LiquidGlassContentBend(amount: 0, height: 0)
      : LiquidGlassContentBend(
          amount: 0.2 * height * lift,
          height: 0.16 * height,
        );
}

// The standard normal distribution function, by Abramowitz and Stegun's
// formula 7.1.26 for the error function (error under 1.5e-7).
double _phi(double x) {
  final z = x.abs() / math.sqrt2;
  final t = 1 / (1 + 0.3275911 * z);
  final poly =
      t *
      (0.254829592 +
          t *
              (-0.284496736 +
                  t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))));
  final erf = 1 - poly * math.exp(-z * z);
  return x >= 0 ? 0.5 * (1 + erf) : 0.5 * (1 - erf);
}

// How deep [point] lies inside a box of [size] at the origin with circular
// corners of [radius]; negative outside.
double _depthIn(Size size, double radius, Offset point) {
  final qx = (point.dx - size.width / 2).abs() - size.width / 2 + radius;
  final qy = (point.dy - size.height / 2).abs() - size.height / 2 + radius;
  final outside = Offset(math.max(qx, 0), math.max(qy, 0)).distance;
  return radius - outside - math.min(math.max(qx, qy), 0);
}

/// Draws the shadows of the lifted lens that [frame] describes over its
/// glass ([LensShadowLaw]). It paints nothing at rest.
@internal
class LensShadows extends LeafRenderObjectWidget {
  /// Creates the shadows of a lens that is [small] in [brightness].
  const LensShadows({
    required this.frame,
    required this.small,
    required this.brightness,
    super.key,
  });

  /// The lens's frame.
  final ValueListenable<GlassFrame> frame;

  /// Whether the lens is a knob or thumb, not a selection.
  final bool small;

  /// The appearance the lens is drawn in.
  final Brightness brightness;

  @override
  RenderLensShadows createRenderObject(BuildContext context) =>
      RenderLensShadows(frame, small: small, brightness: brightness);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLensShadows renderObject,
  ) {
    renderObject.frame = frame;
    renderObject.small = small;
    renderObject.brightness = brightness;
  }
}

/// Paints [LensShadows].
@internal
class RenderLensShadows extends RenderBox with ListenableFollower {
  /// Creates the render object of [LensShadows].
  RenderLensShadows(
    this._frame, {
    required this._small,
    required this._brightness,
  });

  ValueListenable<GlassFrame> _frame;

  /// The lens's frame.
  ValueListenable<GlassFrame> get frame => _frame;
  set frame(ValueListenable<GlassFrame> value) {
    if (identical(value, _frame)) return;
    refollow(() => _frame = value);
    markNeedsPaint();
  }

  bool _small;

  /// Whether the lens is a knob or thumb.
  bool get small => _small;
  set small(bool value) {
    if (value == _small) return;
    _small = value;
    // The inner shadow's bend is the one input its mesh does not key on.
    _inner?.dispose();
    _inner = null;
    markNeedsPaint();
  }

  Brightness _brightness;

  /// The appearance the lens is drawn in.
  Brightness get brightness => _brightness;
  set brightness(Brightness value) {
    if (value == _brightness) return;
    _brightness = value;
    markNeedsPaint();
  }

  @override
  List<(Listenable, VoidCallback)> get followed => [(_frame, _changed)];

  bool _painted = false;
  _Shade? _ring;
  _Shade? _inner;

  static double _shownOf(GlassFrame frame) => frame.outline != null
      ? 0
      : GlassFrame.glassnessAt(frame.lift) * frame.opacity.clamp(0.0, 1.0);

  void _changed() {
    if (_painted || _shownOf(_frame.value) > 0) markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  // Three sigma past the band on either side: under 0.2 % of the opacity.
  static const double _ringOutside = 3 * LensShadowLaw.sigma;
  static const double _ringInside =
      LensShadowLaw.ringWidth + 3 * LensShadowLaw.sigma;

  @override
  Rect get paintBounds {
    final bounds = Offset.zero & size;
    final frame = _frame.value;
    if (_shownOf(frame) <= 0) return bounds;
    return bounds.expandToInclude(
      frame
          .bodyIn(size)
          .drawnRect
          .shift(const Offset(0, LensShadowLaw.ringDrop))
          .inflate(_ringOutside),
    );
  }

  @override
  void dispose() {
    _ring?.dispose();
    _inner?.dispose();
    _ring = _inner = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final frame = _frame.value;
    final shown = _shownOf(frame);
    _painted = shown > 0;
    if (!_painted) return;
    final placed = frame.bodyIn(size);
    final body = placed.drawnRect;
    if (body.isEmpty) return;
    final box = body.size;
    final half = box.shortestSide / 2;
    final radius = placed.drawnRadius;
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);

    final ringOpacity =
        LensShadowLaw.ringOpacity(small: _small, brightness: _brightness) *
        shown;
    var ring = _ring;
    if (ring == null || !ring.fits(box, radius, ringOpacity)) {
      ring?.dispose();
      ring = _ring = _Shade(
        box,
        radius,
        opacity: ringOpacity,
        depths: [
          for (var d = -_ringOutside; d < _ringInside && d < half; d++) d,
          math.min(_ringInside, half),
        ],
        at: (point, depth, normal) => LensShadowLaw.ringAt(depth),
      );
    }
    ring.paint(canvas, body.topLeft + const Offset(0, LensShadowLaw.ringDrop));

    final innerOpacity = LensShadowLaw.inner * shown;
    var inner = _inner;
    if (inner == null || !inner.fits(box, radius, innerOpacity)) {
      inner?.dispose();
      final bend = LensShadowLaw.contentBend(box.shortestSide, small: _small);
      final deepest = math.min(
        half,
        math.max(
          LensShadowLaw.innerDrop + 3 * LensShadowLaw.sigma,
          bend.height,
        ),
      );
      const drop = Offset(0, LensShadowLaw.innerDrop);
      inner = _inner = _Shade(
        box,
        radius,
        opacity: innerOpacity,
        depths: [
          // One ring outside, so the clip and not the mesh draws the edge.
          -1,
          // The bend is steep at the rim.
          for (var d = 0.0; d < 3 && d < deepest; d += 0.5) d,
          for (var d = 3.0; d < deepest; d++) d,
          deepest,
        ],
        at: (point, depth, normal) {
          final bent = bend.shownDepth(math.max(depth, 0));
          final source = point - normal * (bent - math.max(depth, 0));
          return LensShadowLaw.innerAt(_depthIn(box, radius, source - drop));
        },
      );
    }
    canvas.clipPath(placed.edgeInBox);
    inner.paint(canvas, body.topLeft);
    canvas.restore();
  }
}

/// A black shade over rings at fixed depths from the outline of a rounded
/// box, as one mesh colored at its vertices: no blur and no layer.
final class _Shade {
  /// The shade of a box of [size] with circular corners of [radius], whose
  /// share of [opacity] is [at] a point of the box's own coordinates, given
  /// with its depth inside the outline (negative outside) and the outward
  /// normal of the outline nearest to it. It is sampled on rings at
  /// [depths], which rise and stay within half the box's short side.
  factory _Shade(
    Size size,
    double radius, {
    required double opacity,
    required List<double> depths,
    required double Function(Offset point, double depth, Offset normal) at,
  }) {
    final w = size.width;
    final h = size.height;
    // The outline's columns, clockwise from the left end of the top left
    // corner: where each crosses the outline, its outward normal, and the
    // way a ring deeper than the corners' centers is drawn back along it.
    final edge = <Offset>[];
    final normals = <Offset>[];
    final miters = <Offset>[];
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

    for (var k = 0; k < 4; k++) {
      final center = centers[k];
      final start = math.pi + k * math.pi / 2;
      final diagonal = diagonalOf(k);
      for (var i = 0; i <= perCorner; i++) {
        final angle = start + i * math.pi / 2 / perCorner;
        final normal = Offset(math.cos(angle), math.sin(angle));
        edge.add(center + normal * radius);
        normals.add(normal);
        miters.add(diagonal);
      }
      final from = edge.last;
      final normal = normals.last;
      final to = centers[(k + 1) % 4] + normal * radius;
      final pieces = ((to - from).distance / edgeStep).ceil();
      for (var i = 1; i < pieces; i++) {
        final t = i / pieces;
        edge.add(Offset.lerp(from, to, t)!);
        normals.add(normal);
        miters.add(Offset.lerp(diagonal, diagonalOf(k + 1), t)!);
      }
    }

    final columns = edge.length;
    final rings = depths.length;
    final positions = Float32List(columns * rings * 2);
    final colors = Int32List(columns * rings);
    for (var ring = 0; ring < rings; ring++) {
      final depth = depths[ring];
      for (var c = 0; c < columns; c++) {
        final normal = normals[c];
        // Deeper than the corners' centers a ring is the box drawn in by
        // the depth, whose corners lie on the diagonals.
        final point = depth <= radius
            ? edge[c] - normal * depth
            : edge[c] - normal * radius - miters[c] * (depth - radius);
        final vertex = ring * columns + c;
        positions[vertex * 2] = point.dx;
        positions[vertex * 2 + 1] = point.dy;
        final alpha = (at(point, depth, normal) * opacity).clamp(0.0, 1.0);
        colors[vertex] = (alpha * 255).round() << 24;
      }
    }
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
    return _Shade._(
      size,
      radius,
      opacity,
      ui.Vertices.raw(
        ui.VertexMode.triangles,
        positions,
        colors: colors,
        indices: indices,
      ),
    );
  }

  _Shade._(this._size, this._radius, this._opacity, this._vertices);

  final Size _size;
  final double _radius;
  final double _opacity;
  final ui.Vertices _vertices;

  /// Whether this is the shade of a box of [size] with corners of [radius]
  /// at [opacity].
  bool fits(Size size, double radius, double opacity) =>
      size == _size && radius == _radius && opacity == _opacity;

  void dispose() => _vertices.dispose();

  /// Paints the shade of a box whose top left is [origin].
  void paint(Canvas canvas, Offset origin) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.drawVertices(_vertices, BlendMode.dst, Paint());
    canvas.restore();
  }
}
