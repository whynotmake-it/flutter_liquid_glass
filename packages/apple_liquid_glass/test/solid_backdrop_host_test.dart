@Tags(['macos_pixels'])
library;

// Run with `flutter test --enable-impeller --enable-flutter-gpu`: without
// Impeller there is no glass to read.
//
// Glass on a section's card reads the card's color, not the screen.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';

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

Widget _button() => GlassButton(
  onPressed: () {},
  child: const SizedBox(width: 120, height: 20),
);

Widget _row({required bool reads}) => GlassListRow(
  trailing: reads
      ? GlassSolidBackdrop(color: null, child: _button())
      : _button(),
  child: const SizedBox(),
);

// Paints what a photo would, in the card's own layer.
Widget _photo() => SizedBox(
  height: 100,
  child: ColoredBox(
    color: _photoColor,
    child: Center(child: _button()),
  ),
);

Widget _highlightingRow() => GlassListRow(
  onPressed: () {},
  trailing: _button(),
  child: const SizedBox(),
);

Widget _page(_CapturingView view, Widget content) {
  return View(
    view: view,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: _viewSize, devicePixelRatio: _dpr),
        child: GlassScope(
          renderer: const LiquidGlassRenderer(),
          child: ColoredBox(
            color: const Color(0xFFD02020),
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 60),
                child: GlassListSection(
                  style: const GlassListStyle(
                    backgroundColor: WidgetStatePropertyAll(
                      Color(0xFF2C2C2E),
                    ),
                  ),
                  children: [content],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<(Uint8List, GlassFrameReport)> _draw(
  WidgetTester tester,
  _CapturingView view,
  Widget content,
) async {
  GlassFrameReport? last;
  void listener(GlassFrameReport report) => last = report;
  GlassFrameReports.addListener(listener);
  addTearDown(() => GlassFrameReports.removeListener(listener));
  // A view keeps what it holds by a global key: only an empty view before
  // a page makes it new.
  await tester.pumpWidget(
    View(view: view, child: const SizedBox()),
    wrapWithView: false,
  );
  await tester.pumpWidget(_page(view, content), wrapWithView: false);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump(const Duration(milliseconds: 16));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pump(const Duration(milliseconds: 16));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  final data = (await tester.runAsync(view.last!.toByteData))!;
  return (data.buffer.asUint8List(), last!);
}

const _photoColor = Color(0xFF20D040);

void main() {
  setUp(() => glassReadsCopies = true);
  tearDown(() => glassReadsCopies = false);

  testWidgets('a control on a row reads nothing and looks the same', (
    tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    await tester.runAsync(precacheGlass);
    final view = _CapturingView(tester);
    final (read, readReport) = await _draw(tester, view, _row(reads: true));
    final (solid, solidReport) = await _draw(tester, view, _row(reads: false));
    expect(readReport.reads, isNotEmpty);
    expect(solidReport.reads, isEmpty);

    var sum = 0;
    var max = 0;
    var inside = 0;
    final width = (_viewSize.width * _dpr).toInt();
    for (var y = 60 * 3; y < 240 * 3; y++) {
      for (var x = 40 * 3; x < 362 * 3; x++) {
        final at = (y * width + x) * 4;
        for (var c = 0; c < 3; c++) {
          final d = (read[at + c] - solid[at + c]).abs();
          sum += d;
          if (d > max) max = d;
        }
        inside++;
      }
    }
    expect(max, lessThan(40));
    expect(sum / (inside * 3), lessThan(2));
  });

  testWidgets('glass over a picture on a card reads the picture', (
    tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    await tester.runAsync(precacheGlass);
    final view = _CapturingView(tester);
    final (pixels, report) = await _draw(tester, view, _photo());
    expect(report.reads, isNotEmpty);

    final width = (_viewSize.width * _dpr).toInt();
    final at = (((60 + 50) * _dpr).toInt() * width + width ~/ 2) * 4;
    expect(pixels[at + 1], greaterThan(pixels[at] + 40));
  });

  testWidgets('a control on a row that highlights reads', (tester) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    await tester.runAsync(precacheGlass);
    final view = _CapturingView(tester);
    final (_, report) = await _draw(tester, view, _highlightingRow());
    expect(report.reads, isNotEmpty);
  });
}
