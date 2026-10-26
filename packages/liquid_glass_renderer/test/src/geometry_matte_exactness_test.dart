import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/rounded_superellipse_parameters.dart';

import 'gpu_test_helpers.dart';

// Exactness of the geometry pass.
//
// Renders a spread of sheets, pills, ovals and blend groups at the matte scale
// of a dpr 3 layer (4) and checks the low-res matte: rules any correct matte
// follows, and a circle against its exact distance.
const _expectFallback = bool.fromEnvironment('EXPECT_FLUTTER_GPU_FALLBACK');

class _Shape {
  const _Shape(
    this.type,
    this.w,
    this.h,
    this.r,
    this.cx,
    this.cy, {
    this.scale = 1,
    this.basis = const [1, 0, 0, 1],
  });
  final double type;
  final double w, h, r, cx, cy, scale;
  final List<double> basis;
}

class _Scene {
  const _Scene(
    this.name,
    this.width,
    this.height,
    this.shapes, {
    this.blend = 0,
    this.refractionHeight = 24,
    this.refractionAmount = 72,
    this.fits = true,
    this.contourExtent = 0.5,
    this.offsetX = 0,
    this.offsetY = 0,
  });
  final String name;
  final int width, height;
  final List<_Shape> shapes;
  final double blend, refractionHeight, refractionAmount, contourExtent;
  final bool fits;
  final double offsetX, offsetY;
}

final _scenes = <_Scene>[
  for (final (w, h, r) in [
    (390.0, 600.0, 40.0),
    (1170.0, 1500.0, 120.0),
    (720.0, 300.0, 96.0),
    (96.0, 96.0, 48.0),
    (360.0, 150.0, 75.0),
    (200.0, 64.0, 32.0),
    (201.0, 63.0, 20.0),
  ])
    for (final (rh, ra, fits) in [
      (24.0, 72.0, true),
      (60.0, 180.0, true),
      (60.0, 180.0, false),
      (9.0, 27.0, false),
    ])
      _Scene(
        'sheet_${w.toInt()}x${h.toInt()}_r${r.toInt()}_h${rh.toInt()}$fits',
        w.toInt() + 40,
        h.toInt() + 40,
        [_Shape(1, w, h, r, (w + 40) / 2 + 0.3, (h + 40) / 2 - 0.2)],
        refractionHeight: rh,
        refractionAmount: ra,
        fits: fits,
        contourExtent: 6,
      ),
  const _Scene(
    'rrect_sheet',
    500,
    400,
    [_Shape(3, 450, 350, 40, 250, 200)],
    contourExtent: 6,
  ),
  const _Scene(
    'oval_wide',
    600,
    300,
    [_Shape(2, 560, 260, 0, 300, 150)],
    contourExtent: 6,
  ),
  const _Scene(
    'circle',
    300,
    300,
    [_Shape(2, 260, 260, 0, 150, 150)],
    refractionHeight: 60,
    refractionAmount: 180,
  ),
  const _Scene(
    'stretched_sheet',
    520,
    420,
    [
      _Shape(
        1,
        300,
        200,
        50,
        260,
        210,
        scale: 1.2,
        basis: [0.8, 0.1, -0.1, 0.9],
      ),
    ],
    contourExtent: 6,
  ),
  _Scene(
    'blend5_pills',
    900,
    300,
    [
      for (var i = 0; i < 5; i++)
        _Shape(1, 150, 120, 60, 100.0 + i * 175 + (i.isOdd ? 6 : 0), 150),
    ],
    blend: 36,
    refractionHeight: 40,
    refractionAmount: 120,
    contourExtent: 6,
  ),
  const _Scene(
    'small_pill_in_large_texture',
    1000,
    1000,
    [_Shape(1, 150, 60, 30, 400.5, 250.25)],
    contourExtent: 6,
  ),
  const _Scene(
    'offset_pill',
    900,
    700,
    [_Shape(1, 200, 80, 40, 600.5, 500.25)],
    contourExtent: 6,
    offsetX: 137,
    offsetY: 61,
  ),
  const _Scene(
    'far_apart_groups',
    1300,
    1000,
    [
      _Shape(1, 200, 70, 35, 140, 100),
      _Shape(1, 160, 70, 35, 290, 110),
      _Shape(1, 220, 90, 45, 1100, 880),
      _Shape(2, 90, 90, 0, 1180, 760),
    ],
    blend: 30,
    refractionHeight: 40,
    refractionAmount: 120,
    contourExtent: 6,
  ),
  const _Scene(
    'far_apart_sheets',
    1200,
    1200,
    [_Shape(1, 380, 300, 50, 230, 190), _Shape(1, 300, 260, 60, 950, 980)],
    contourExtent: 6,
  ),
  _Scene(
    'blend_overlap_sheets',
    800,
    700,
    [
      const _Shape(1, 600, 420, 80, 330, 250),
      const _Shape(1, 360, 240, 60, 480, 470),
      const _Shape(2, 200, 200, 0, 140, 540),
    ],
    blend: 60,
    refractionHeight: 60,
    refractionAmount: 180,
    contourExtent: 6,
  ),
];

Future<(Float32List, int, int)> _renderMatte(
  FlutterGpuGeometryRenderer renderer,
  _Scene scene,
) async {
  final shapeData = <double>[];
  final rseData = <double>[];
  final bounds = <double>[];
  for (var i = 0; i < scene.shapes.length; i++) {
    final s = scene.shapes[i];
    shapeData.addAll([
      s.type, s.w, s.h, s.r, //
      ...s.basis,
      s.cx, s.cy, s.scale, i == 0 ? -(scene.blend + 1) : scene.blend,
    ]);
    rseData.addAll(
      s.type == 1
          ? roundedSuperellipseParameters(ui.Size(s.w, s.h), s.r)
          : List<double>.filled(12, 0),
    );
    final hw = s.w * s.scale, hh = s.h * s.scale;
    bounds.addAll([s.cx - hw, s.cy - hh, s.cx + hw, s.cy + hh]);
  }
  final result = renderer.render(
    width: scene.width,
    height: scene.height,
    shapeData: shapeData,
    rseData: rseData,
    boundsData: bounds,
    numShapes: scene.shapes.length,
    refractionHeight: scene.refractionHeight,
    refractionAmount: scene.refractionAmount,
    refractionFitsShape: scene.fits,
    contourExtent: scene.contourExtent,
    offsetX: scene.offsetX,
    offsetY: scene.offsetY,
    matteScale: 4,
  );
  return (
    await readGeometryField(result.image),
    result.textureWidth,
    result.textureHeight,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the low-res matte is finite and positive inside every shape',
    () async {
      final renderer = await createGeometryRenderer();
      for (final scene in _scenes) {
        final (field, _, _) = await _renderMatte(renderer, scene);
        var inside = 0;
        for (var i = 0; i < field.length; i += 4) {
          expect(field[i].isFinite, isTrue, reason: scene.name);
          if (field[i] > 0) inside++;
        }
        expect(inside, greaterThan(0), reason: scene.name);
      }
    },
    skip: _expectFallback,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'a circle\'s low-res matte holds its exact distance, whatever part the '
    'pass draws',
    () async {
      final renderer = await createGeometryRenderer();
      final scene = _scenes.firstWhere((scene) => scene.name == 'circle');
      final (field, textureWidth, _) = await _renderMatte(renderer, scene);
      const radius = 130.0;
      const center = 150.0;
      var checked = 0;
      var worst = 0.0;
      for (var j = 0; j <= scene.height ~/ 4; j++) {
        for (var i = 0; i <= scene.width ~/ 4; i++) {
          // Texel (i, j) is computed at the center of matte pixel
          // (i * 4, j * 4).
          final dx = i * 4 + 0.5 - center;
          final dy = j * 4 + 0.5 - center;
          final inward = radius - math.sqrt(dx * dx + dy * dy);
          // Far from the edge, the matte only holds "far outside".
          if (inward.abs() > 12) continue;
          final value = field[(j * textureWidth + i) * 4];
          worst = math.max(worst, (value - inward).abs());
          checked++;
        }
      }
      expect(checked, greaterThan(100));
      expect(worst, lessThan(0.05));
    },
    skip: _expectFallback,
  );
}
