// Shared scenes for the LiquidGlassCapture pixel tests.
//
// flutter_tester (Impeller) renders only the FIRST identity-backdrop subpass
// of a process correctly; every later one comes out black, while real GPUs
// (macOS Metal, Android Vulkan) render all of them. `flutter test` starts one
// process per test file, so each pixel scene lives in its own
// `liquid_glass_capture_<scene>_test.dart` that renders the uncaptured
// reference first and the captured scene exactly once. The macOS integration
// test `example/integration_test/liquid_glass_capture_test.dart` runs all
// scenes, including dispose and recreate, on a real GPU.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';

import 'shared.dart';

/// Every scene the capture is locked down for. Names are golden file names.
const captureScenes = <CaptureScene>[
  CaptureScene('bar', shadow: true),
  CaptureScene('bar_edge', shadow: true, edge: true),
  CaptureScene('indicator', indicator: true),
  CaptureScene('indicator_edge', indicator: true, edge: true),
  CaptureScene(
    'opacity',
    shadow: true,
    fade: CaptureFade.opacity,
    fakeReferenceOnHost: false,
  ),
  CaptureScene(
    'fade_transition',
    shadow: true,
    fade: CaptureFade.transition,
    fakeReferenceOnHost: false,
  ),
  CaptureScene('blend_group', blend: true, shadow: true),
  CaptureScene('dpr2', shadow: true, indicator: true, dpr: 2),
];

/// Renders [scene] with and without a capture, requires the two to match to
/// within blur-resampling noise, and locks the captured image with a golden
/// when [golden] is set. Must be the first thing a flutter_tester process
/// renders; call it at most once per process. [compareReference] forces the
/// reference comparison for scenes flutter_tester cannot render twice; the
/// device integration test sets it.
Future<void> expectCaptureKeepsTheLook(
  WidgetTester tester,
  CaptureScene scene, {
  required bool fake,
  bool golden = true,
  bool compareReference = false,
  int maxChannelDiff = 4,
}) async {
  final name = '${fake ? "fake" : "real"}_${scene.name}';
  final controller = AnimationController(vsync: tester, value: 0.5);
  addTearDown(controller.dispose);

  Future<Uint8List> render({required bool capture}) async {
    await pumpCaptureScene(
      tester,
      scene,
      fake: fake,
      capture: capture,
      controller: controller,
    );
    final image = await captureSceneImage(tester);
    final rgba = (await tester.runAsync(image.toByteData))!;
    if (const bool.fromEnvironment('LGR_CAPTURE_DUMP')) {
      await tester.runAsync(() async {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${Directory.systemTemp.path}/lgr_capture_${name}_'
          '${capture ? "capture" : "plain"}.png',
        ).writeAsBytes(png!.buffer.asUint8List());
      });
    }
    if (capture && golden) {
      final png = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      ))!;
      await tester.runAsync(
        () => expectLater(
          png.buffer.asUint8List(),
          matchesGoldenFile('goldens/liquid_glass_capture_$name.png'),
        ),
      );
    }
    image.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    return rgba.buffer.asUint8List();
  }

  // The captured render must be the first BackdropFilter this process
  // draws; see the file comment. The reference has no identity subpass and
  // renders fine afterwards.
  final captured = await render(capture: true);
  if (fake && !scene.fakeReferenceOnHost && !compareReference) return;
  final reference = await render(capture: false);
  expectSameLook(
    captured,
    reference,
    width: (320 * scene.dpr).round(),
    maxChannelDiff: maxChannelDiff,
  );
}

/// Requires two RGBA buffers to show the same picture: no pixel may differ by
/// more than [maxChannelDiff] codes and the mean difference must stay tiny.
///
/// Blur resampling at a different pass origin moves individual codes; a
/// clipped halo, a black pass or a shifted matte moves whole regions by
/// 100+ codes. [width] lets the failure message locate the differences.
void expectSameLook(
  Uint8List captured,
  Uint8List reference, {
  required int width,
  int maxChannelDiff = 4,
}) {
  expect(captured.length, reference.length);
  var maxDiff = 0;
  var sum = 0;
  var over = 0;
  int? minX;
  int? minY;
  int? maxX;
  int? maxY;
  for (var i = 0; i < reference.length; i++) {
    final d = (captured[i] - reference[i]).abs();
    if (d > maxDiff) maxDiff = d;
    sum += d;
    if (d > maxChannelDiff) {
      over++;
      final px = i ~/ 4;
      final x = px % width;
      final y = px ~/ width;
      minX = minX == null ? x : (x < minX ? x : minX);
      maxX = maxX == null ? x : (x > maxX ? x : maxX);
      minY = minY == null ? y : (y < minY ? y : minY);
      maxY = maxY == null ? y : (y > maxY ? y : maxY);
    }
  }
  final mean = sum / reference.length;
  expect(
    maxDiff,
    lessThanOrEqualTo(maxChannelDiff),
    reason:
        'max channel diff $maxDiff, mean $mean, $over channel samples over '
        '$maxChannelDiff inside x $minX..$maxX y $minY..$maxY (width $width)',
  );
  expect(mean, lessThan(0.5));
}

enum CaptureFade { none, opacity, transition }

class CaptureScene {
  const CaptureScene(
    this.name, {
    this.edge = false,
    this.indicator = false,
    this.blend = false,
    this.shadow = false,
    this.fade = CaptureFade.none,
    this.dpr = 1,
    this.fakeReferenceOnHost = true,
  });

  final String name;
  final bool edge;
  final bool indicator;
  final bool blend;
  final bool shadow;
  final CaptureFade fade;
  final double dpr;

  /// Whether flutter_tester can render the uncaptured fake reference after
  /// the captured scene. A fake layer under `Opacity` is itself a blur
  /// inside a subpass, which flutter_tester paints black as the second one
  /// in a process; the macOS integration test compares those on a real GPU.
  final bool fakeReferenceOnHost;
}

Iterable<LiquidGlassLayerRenderObject> glassLayersBelow(RenderObject node) {
  final result = <LiquidGlassLayerRenderObject>[];
  void visit(RenderObject n) {
    if (n is LiquidGlassLayerRenderObject) {
      result.add(n as LiquidGlassLayerRenderObject);
    }
    n.visitChildren(visit);
  }

  visit(node);
  return result;
}

Future<void> pumpCaptureScene(
  WidgetTester tester,
  CaptureScene scene, {
  required bool fake,
  required bool capture,
  AnimationController? controller,
}) async {
  final width = (320 * scene.dpr).round();
  final height = (240 * scene.dpr).round();
  tester.view
    ..physicalSize = Size(width.toDouble(), height.toDouble())
    ..devicePixelRatio = scene.dpr;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    captureSceneWidget(
      scene,
      fake: fake,
      capture: capture,
      controller: controller,
    ),
  );
  if (!fake) await pumpUntilGlassReady(tester);
  // Let the asynchronous shaders and the first geometry pass settle.
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Rasterizes the whole scene at the view's device pixel ratio.
Future<ui.Image> captureSceneImage(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(captureSceneBoundaryKey),
  );
  return (await tester.runAsync(
    () => boundary.toImage(pixelRatio: tester.view.devicePixelRatio),
  ))!;
}

/// Key of the [RepaintBoundary] that [captureSceneWidget] wraps the scene in.
const captureSceneBoundaryKey = ValueKey('capture-scene');

Widget captureSceneWidget(
  CaptureScene scene, {
  required bool fake,
  bool capture = true,
  EdgeInsets? bleed,
  AnimationController? controller,
}) {
  const settings = LiquidGlassSettings(
    frost: 6,
    edgeRefraction: 30,
    highlight: 0.5,
    chromaticAberration: 0,
  );
  final shadows = scene.shadow
      ? const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ]
      : const <BoxShadow>[];
  const barShape = LiquidRoundedRectangle(borderRadius: 20);
  Widget bar;
  if (scene.blend) {
    bar = LiquidGlassLayer(
      fake: fake,
      settings: settings,
      child: LiquidGlassBlendGroup(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LiquidGlass.grouped(
              shape: barShape,
              shadows: shadows,
              child: const SizedBox(width: 90, height: 40),
            ),
            const SizedBox(width: 8),
            LiquidGlass.grouped(
              shape: barShape,
              shadows: shadows,
              child: const SizedBox(width: 60, height: 40),
            ),
          ],
        ),
      ),
    );
  } else {
    bar = LiquidGlassLayer(
      fake: fake,
      settings: settings,
      child: LiquidGlass(
        shape: barShape,
        shadows: shadows,
        child: SizedBox(
          width: 160,
          height: 40,
          child: scene.indicator
              ? Align(
                  alignment: const Alignment(0.6, 0),
                  child: LiquidGlassLayer(
                    fake: fake,
                    settings: const LiquidGlassSettings(
                      frost: 0,
                      edgeRefraction: 24,
                      backdropScale: 0.92,
                      highlight: 0.4,
                      chromaticAberration: 0,
                    ),
                    child: const LiquidGlass(
                      shape: LiquidRoundedRectangle(borderRadius: 14),
                      child: SizedBox(width: 44, height: 30),
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
  var chrome = capture ? LiquidGlassCapture(bleed: bleed, child: bar) : bar;
  if (controller != null) {
    chrome = switch (scene.fade) {
      CaptureFade.none => chrome,
      CaptureFade.opacity => Opacity(opacity: controller.value, child: chrome),
      CaptureFade.transition => FadeTransition(
        opacity: controller,
        child: chrome,
      ),
    };
  }
  return Directionality(
    textDirection: TextDirection.ltr,
    child: RepaintBoundary(
      key: captureSceneBoundaryKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: CaptureBackdrop()),
          Align(
            alignment: scene.edge ? Alignment.bottomLeft : Alignment.center,
            child: chrome,
          ),
        ],
      ),
    ),
  );
}

/// Stripes over a diagonal gradient: blur, refraction and shadow are all
/// visible against it.
class CaptureBackdrop extends CustomPainter {
  const CaptureBackdrop();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, size.height),
          const [Color(0xFF1E3A8A), Color(0xFFF59E0B)],
        ),
    );
    final paint = Paint()
      ..isAntiAlias = false
      ..color = const Color(0xCCFFFFFF);
    for (var x = 0.0; x < size.width; x += 12) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 4, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(CaptureBackdrop oldDelegate) => false;
}
