@Tags(['macos_pixels'])
library;

// Run with `flutter test --enable-impeller --enable-flutter-gpu`: without
// Impeller there is no glass to plan.
//
// A focused or hovered glass body costs its glass nothing: the ring and the
// wash are plain painting over it, so the frame issues the same offscreen
// targets and reads as with neither.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _viewSize = Size(402, 400);
const _dpr = 3.0;

class _CapturingView extends TestFlutterView {
  _CapturingView(WidgetTester tester)
    : super(
        view: tester.view,
        platformDispatcher: tester.platformDispatcher,
        display: tester.view.display,
      ) {
    physicalSize = _viewSize * _dpr;
    devicePixelRatio = _dpr;
  }

  ui.Image? last;

  @override
  void render(ui.Scene scene, {Size? size}) {
    last?.dispose();
    last = scene.toImageSync(
      (_viewSize.width * _dpr).toInt(),
      (_viewSize.height * _dpr).toInt(),
    );
  }
}

Widget _scene(WidgetStatesController states, {required bool grouped}) {
  Widget body(int i) => SizedBox(
    width: 120,
    height: 44,
    child: GlassSurface.live(
      frame: MotionSelection(() => const GlassFrame()),
      states: i == 0 ? states : null,
      child: const Center(child: Text('Go')),
    ),
  );
  final bodies = Row(
    mainAxisSize: MainAxisSize.min,
    children: [body(0), const SizedBox(width: 24), body(1)],
  );
  return MediaQuery(
    data: const MediaQueryData(size: _viewSize, devicePixelRatio: _dpr),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: GlassScope(
        renderer: const LiquidGlassRenderer(),
        child: Stack(
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  for (var i = 0; i < 12; i++)
                    Expanded(
                      child: ColoredBox(
                        color: i.isEven
                            ? const Color(0xFF20C040)
                            : const Color(0xFFE0A020),
                      ),
                    ),
                ],
              ),
            ),
            Center(child: grouped ? GlassGroup(child: bodies) : bodies),
          ],
        ),
      ),
    ),
  );
}

Future<void> _frame(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 16));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
}

/// What the scene built fresh with [states] costs: the targets, reads,
/// filters and pictures of its first frame, and its pixels.
Future<((int, int, int, int), Uint8List)> _cost(
  WidgetTester tester,
  _CapturingView view,
  Set<WidgetState> states, {
  required bool grouped,
}) async {
  final controller = WidgetStatesController(states);
  GlassFrameReport? last;
  void listener(GlassFrameReport report) {
    if (report.planned) last ??= report;
  }

  GlassFrameReports.addListener(listener);
  try {
    await tester.pumpWidget(
      View(
        view: view,
        child: _scene(controller, grouped: grouped),
      ),
      wrapWithView: false,
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    for (var i = 0; i < 4; i++) {
      await _frame(tester);
    }
  } finally {
    GlassFrameReports.removeListener(listener);
  }
  final data = (await tester.runAsync(view.last!.toByteData))!;
  await tester.pumpWidget(
    View(view: view, child: const SizedBox()),
    wrapWithView: false,
  );
  controller.dispose();
  final report = last!;
  return (
    (
      report.targetCount,
      report.reads.length,
      report.filtersBuilt,
      report.picturesRecorded,
    ),
    data.buffer.asUint8List(),
  );
}

/// Whether the pixel at the logical point [at] of the view is bluish.
bool _blue(Uint8List pixels, Offset at) {
  final x = (at.dx * _dpr).round();
  final y = (at.dy * _dpr).round();
  final i = (y * (_viewSize.width * _dpr).round() + x) * 4;
  return pixels[i + 2] - pixels[i] > 40;
}

void main() {
  // The first body's right edge sits 12 points left of the view's middle.
  final ring = Offset(_viewSize.width / 2 - 12 + 1.75, _viewSize.height / 2);

  for (final grouped in [false, true]) {
    testWidgets('a focused or hovered body issues the targets of a plain '
        'one${grouped ? ' in a group' : ''}', (tester) async {
      if (!ui.ImageFilter.isShaderFilterSupported) return;
      final view = _CapturingView(tester);
      final (plain, pixels) = await _cost(tester, view, {}, grouped: grouped);
      expect(plain.$3, greaterThan(0));
      expect(_blue(pixels, ring), isFalse);
      final (focused, lit) = await _cost(
        tester,
        view,
        {WidgetState.focused},
        grouped: grouped,
      );
      expect(focused, plain);
      expect(_blue(lit, ring), isTrue);
      final (hovered, _) = await _cost(
        tester,
        view,
        {WidgetState.focused, WidgetState.hovered},
        grouped: grouped,
      );
      expect(hovered, plain);
    });
  }
}
