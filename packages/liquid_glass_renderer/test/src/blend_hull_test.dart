import 'dart:math' as math;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';

const _width = 256;
const _height = 128;
const _centerY = 64.0;
const _blend = 40.0;
const _expectFallback = bool.fromEnvironment('EXPECT_FLUTTER_GPU_FALLBACK');

/// A primitive in matte pixels, axis-aligned and centered at ([x], [_centerY]
/// + [dy]).
class _Shape {
  const _Shape.rect(this.x, this.width, this.height, this.radius, {this.dy = 0})
    : type = 3;
  const _Shape.circle(this.x, double diameter)
    : type = 2,
      dy = 0,
      width = diameter,
      height = diameter,
      radius = 0;

  final double type;
  final double x;
  final double dy;
  final double width;
  final double height;
  final double radius;

  double get top => _centerY + dy - height / 2;
  double get bottom => _centerY + dy + height / 2;
  double get left => x - width / 2;
  double get right => x + width / 2;

  double distance(double px, double py) {
    final qx = (px - x).abs();
    final qy = (py - _centerY - dy).abs();
    if (type == 2) return math.sqrt(qx * qx + qy * qy) - width / 2;
    final r = math.min(radius, math.min(width, height) / 2);
    final ox = qx - width / 2 + r;
    final oy = qy - height / 2 + r;
    final outside = math.sqrt(
      math.pow(math.max(ox, 0), 2) + math.pow(math.max(oy, 0), 2),
    );
    return math.min(math.max(ox, oy), 0) + outside - r;
  }
}

/// Coverage of one blend group, read back from the geometry matte: `true`
/// where the pixel center lies inside the merged shape.
typedef _Mask = List<List<bool>>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FlutterGpuGeometryRenderer renderer;

  setUpAll(() async {
    if (_expectFallback) return;
    final library = (await gpu.ShaderLibrary.fromAsset(
      'build/shaderbundles/liquid_glass_renderer.shaderbundle',
    ))!;
    renderer = FlutterGpuGeometryRenderer(
      vertexShader: library['GeometryVertex']!,
      fragmentShader: library['GeometryFragment']!,
    );
  });

  tearDownAll(() {
    if (!_expectFallback) renderer.dispose();
  });

  Future<_Mask> render(List<_Shape> shapes, {double blend = _blend}) async {
    final shapeData = <double>[
      for (final (index, shape) in shapes.indexed) ...[
        shape.type, shape.width, shape.height, shape.radius, //
        1, 0, 0, 1, //
        shape.x,
        _centerY + shape.dy,
        1,
        if (index == 0) -(blend + 1) else blend,
      ],
    ];
    final result = renderer.render(
      width: _width,
      height: _height,
      shapeData: shapeData,
      numShapes: shapes.length,
      boundsData: [
        for (final shape in shapes) ...[
          shape.left, shape.top, shape.right, shape.bottom, //
        ],
      ],
      opticalIndex: 1.2,
      thickness: 10,
      offsetX: 0,
      offsetY: 0,
    );
    final bytes = (await result.image.toByteData())!;
    // Channel B stores the companded signed inward distance around 0.5.
    return [
      for (var y = 0; y < _height; y++)
        [
          for (var x = 0; x < _width; x++)
            bytes.getUint8((y * result.width + x) * 4 + 2) >= 128,
        ],
    ];
  }

  int pixelsWhere(_Mask mask, bool Function(double x, double y) test) {
    var count = 0;
    for (var y = 0; y < _height; y++) {
      for (var x = 0; x < _width; x++) {
        if (mask[y][x] && test(x + 0.5, y + 0.5)) count++;
      }
    }
    return count;
  }

  /// Merged pixels outside the axis-aligned box of the union of [shapes].
  int pixelsOutsideBounds(_Mask mask, List<_Shape> shapes) {
    final top = shapes.map((s) => s.top).reduce(math.min);
    final bottom = shapes.map((s) => s.bottom).reduce(math.max);
    final left = shapes.map((s) => s.left).reduce(math.min);
    final right = shapes.map((s) => s.right).reduce(math.max);
    return pixelsWhere(
      mask,
      (x, y) => y < top || y > bottom || x < left || x > right,
    );
  }

  /// Merged pixels that lie outside every primitive by more than half a
  /// pixel, i.e. material added by the blend.
  int filledPixels(_Mask mask, List<_Shape> shapes) => pixelsWhere(
    mask,
    (x, y) => shapes.every((s) => s.distance(x, y) > 0.5),
  );

  List<_Shape> equalRects(double gap) => [
    _Shape.rect(128 - 30 - gap / 2, 60, 40, 12),
    _Shape.rect(128 + 30 + gap / 2, 60, 40, 12),
  ];

  group('blend group smooth union', skip: _expectFallback, () {
    test('two equal rects merge without bulging past their edges', () async {
      final shapes = equalRects(-16);
      final mask = await render(shapes);

      expect(pixelsOutsideBounds(mask, shapes), 0);
      // The straight top and bottom edges stay straight across the join.
      for (var x = 100; x < 156; x++) {
        expect(mask[44][x], isTrue, reason: 'top row at x=$x');
        expect(mask[83][x], isTrue, reason: 'bottom row at x=$x');
      }
    });

    test('unbounded smooth union would have bulged the same pair', () {
      // Guards the scene above: a plain polynomial smooth minimum lifts the
      // join above the shared edge by up to blend / 4.
      final shapes = equalRects(-16);
      final a = shapes[0];
      final b = shapes[1];
      double smoothMin(double d1, double d2) {
        final e = math.max(_blend - (d1 - d2).abs(), 0);
        return math.min(d1, d2) - e * e * 0.25 / _blend;
      }

      expect(smoothMin(a.distance(128, 40), b.distance(128, 40)), lessThan(0));
    });

    test('separated rects still form a bridge inside their hull', () async {
      final shapes = equalRects(8);
      final mask = await render(shapes);

      expect(mask[64][128], isTrue, reason: 'bridge at the gap center');
      expect(filledPixels(mask, shapes), greaterThan(100));
      expect(pixelsOutsideBounds(mask, shapes), 0);
    });

    test('rect and circle keep a smooth fillet', () async {
      const shapes = [
        _Shape.rect(100, 100, 70, 16),
        _Shape.circle(160, 44),
      ];
      final mask = await render(shapes);

      expect(filledPixels(mask, shapes), greaterThan(40));
      expect(pixelsOutsideBounds(mask, shapes), 0);
    });

    test(
      'top-aligned shapes of different sizes keep the shared edge',
      () async {
        const shapes = [
          _Shape.rect(96, 80, 60, 12),
          _Shape.rect(160, 60, 40, 12, dy: -10),
        ];
        final mask = await render(shapes);

        expect(pixelsOutsideBounds(mask, shapes), 0);
        expect(filledPixels(mask, shapes), greaterThan(20));
      },
    );

    test('animated separation never bulges and releases the bridge', () async {
      var bridgeSeen = false;
      var released = false;
      for (var gap = -40.0; gap <= 40; gap += 4) {
        final shapes = equalRects(gap);
        final mask = await render(shapes);
        expect(
          pixelsOutsideBounds(mask, shapes),
          0,
          reason: 'bulge at gap $gap',
        );
        final bridged = mask[64][128];
        if (gap > 0 && bridged) bridgeSeen = true;
        if (bridgeSeen && !bridged) released = true;
        expect(
          released && bridged,
          isFalse,
          reason: 'bridge must not reappear once released (gap $gap)',
        );
      }
      expect(bridgeSeen, isTrue);
      expect(released, isTrue);
    });

    test('zero blend is a hard union', () async {
      final shapes = equalRects(8);
      final mask = await render(shapes, blend: 0);

      expect(filledPixels(mask, shapes), 0);
    });
  });
}
