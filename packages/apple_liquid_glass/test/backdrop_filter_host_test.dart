@Tags(['macos_pixels'])
library;

// Run with `flutter test --enable-impeller --enable-flutter-gpu`: without
// Impeller there is no glass to read.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/rendering.dart';

const _viewSize = Size(300, 600);
const _dpr = 2.0;

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

Widget _row(int index) => SizedBox(
  height: 100,
  child: ColoredBox(
    color: index.isEven ? const Color(0xFF00C000) : const Color(0xFF0000C0),
    child: Center(
      child: SizedBox(
        width: 200,
        height: 60,
        child: LiquidGlassLayer(
          // Another glint strength keeps each in a read of its own.
          settings:
              const LiquidGlassSettings.ios27Regular(
                brightness: Brightness.light,
              ).copyWith(
                glintStrength: 0.1 + index / 100,
              ),
          child: const LiquidGlass(
            shape: LiquidRoundedSuperellipse(radius: 20),
            child: SizedBox.expand(),
          ),
        ),
      ),
    ),
  ),
);

Widget _list(_CapturingView view, ScrollController controller) => View(
  view: view,
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: ListView.builder(
      controller: controller,
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: 40,
      itemBuilder: (_, index) => RepaintBoundary(child: _row(index)),
    ),
  ),
);

Future<void> _loaded(WidgetTester tester) => tester.runAsync(
  () => Future<void>.delayed(const Duration(milliseconds: 200)),
);

// Flutter_tester's software Vulkan crashes under frames drawn back to back.
Future<void> _frame(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
}

// The switch asks for no frame by itself.
Future<void> _readCopies(WidgetTester tester, bool copies) async {
  glassReadsCopies = copies;
  tester.binding.scheduleFrame();
  await _frame(tester);
  await _frame(tester);
}

Future<Uint8List> _pixels(WidgetTester tester, _CapturingView view) async {
  final data = (await tester.runAsync(view.last!.toByteData))!;
  return data.buffer.asUint8List();
}

// Whether glass is drawn over the middle of the fourth row, a blue one, of a
// list scrolled by [scrolled]: glass lightens the row under it.
bool _glassOverFourthRow(Uint8List pixels, {required double scrolled}) {
  final x = (_viewSize.width / 2 * _dpr).round();
  final y = ((350 - scrolled) * _dpr).round();
  final at = (y * (_viewSize.width * _dpr).round() + x) * 4;
  return pixels[at] > 40 && pixels[at + 1] > 40;
}

void main() {
  setUp(() => glassReadsCopies = true);
  tearDown(() => glassReadsCopies = false);

  testWidgets('glass scrolled over a copy builds no backdrop filter', (
    tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    final view = _CapturingView(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_list(view, controller), wrapWithView: false);
    await _loaded(tester);
    await _frame(tester);

    GlassFrameReport? last;
    void listener(GlassFrameReport report) => last = report;
    GlassFrameReports.addListener(listener);
    addTearDown(() => GlassFrameReports.removeListener(listener));
    var offset = 0.0;
    for (var i = 0; i < 8; i++) {
      offset += 7;
      controller.jumpTo(offset);
      await _frame(tester);
    }
    final report = last!;
    final glass = report.reads.fold(0, (sum, read) => sum + read.glassCount);
    expect(glass, greaterThanOrEqualTo(5));
    expect(
      report.reads.map((r) => r.source),
      isNot(contains(GlassReadSource.backdrop)),
    );
    // Each read's own filter, which follows the glass, and no more.
    expect(report.filtersBuilt, lessThanOrEqualTo(2 * report.reads.length));
  });

  testWidgets(
    'the backdrop filter follows glass scrolled while it read a copy',
    (
      tester,
    ) async {
      if (!ui.ImageFilter.isShaderFilterSupported) return;
      final view = _CapturingView(tester);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_list(view, controller), wrapWithView: false);
      await _loaded(tester);
      await _frame(tester);
      // The glass reads its backdrop at rest, so its filter is bound there,
      // then a copy while it scrolls, then its backdrop again.
      await _readCopies(tester, false);
      await _readCopies(tester, true);
      for (var offset = 7.0; offset < 60; offset += 7) {
        controller.jumpTo(offset);
        await _frame(tester);
      }
      await _readCopies(tester, false);
      final moved = await _pixels(tester, view);

      // A view keeps what it holds by a global key: only an empty view
      // between the two lists makes the second one new.
      await tester.pumpWidget(
        View(view: view, child: const SizedBox()),
        wrapWithView: false,
      );
      final fresh = ScrollController(initialScrollOffset: 56);
      addTearDown(fresh.dispose);
      await tester.pumpWidget(_list(view, fresh), wrapWithView: false);
      await _loaded(tester);
      await _frame(tester);
      await _frame(tester);
      final direct = await _pixels(tester, view);
      expect(_glassOverFourthRow(direct, scrolled: 56), isTrue);

      var off = 0;
      for (var i = 0; i < moved.length; i += 4) {
        if ((moved[i + 1] - direct[i + 1]).abs() > 12 ||
            (moved[i + 2] - direct[i + 2]).abs() > 12) {
          off++;
        }
      }
      expect(off / (moved.length / 4), lessThan(0.002));
    },
  );
}
