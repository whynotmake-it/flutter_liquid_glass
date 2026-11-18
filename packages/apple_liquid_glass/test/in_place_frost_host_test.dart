@Tags(['macos_pixels'])
library;

// Run with `flutter test --enable-impeller --enable-flutter-gpu`: the frost is
// a runtime effect, which only Impeller draws.
//
// Every read of a frame frosts its copy through one shader: each has to keep
// the uniforms of its own copy.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';

const _viewSize = Size(300, 600);
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

  void release() {
    last?.dispose();
    last = null;
  }

  @override
  void render(ui.Scene scene, {Size? size}) {
    last?.dispose();
    last = scene.toImageSync(
      (_viewSize.width * _dpr).toInt(),
      (_viewSize.height * _dpr).toInt(),
    );
  }
}

const _wide = Rect.fromLTWH(20, 60, 260, 60);

Widget _glass(Rect rect) => Positioned.fromRect(
  rect: rect,
  child: LiquidGlassLayer(
    // Other highlights keep each in a read of its own.
    settings:
        const LiquidGlassSettings.ios27Regular(brightness: Brightness.light)
            .copyWith(
              glintStrength: rect.width / 1000,
            ),
    child: const LiquidGlass(
      shape: LiquidRoundedSuperellipse(radius: 20),
      child: SizedBox.expand(),
    ),
  ),
);

// An app's engine keeps its frames at most two ahead of the raster thread;
// pumped frames run ahead without limit, and with several glass layers under
// load that crashes flutter_tester's SwiftShader in Flutter 3.50.
Future<void> _rastered(WidgetTester tester, _CapturingView view) async {
  await tester.runAsync(view.last!.toByteData);
}

Future<Uint8List> _draw(
  WidgetTester tester,
  _CapturingView view,
  List<Rect> rects,
) async {
  await tester.pumpWidget(
    View(view: view, child: const SizedBox()),
    wrapWithView: false,
  );
  await _rastered(tester, view);
  await tester.pumpWidget(
    View(
      view: view,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            const Positioned.fill(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: ColoredBox(color: Color(0xFF00C000))),
                  Expanded(child: ColoredBox(color: Color(0xFF0000C0))),
                ],
              ),
            ),
            for (final rect in rects) _glass(rect),
          ],
        ),
      ),
    ),
    wrapWithView: false,
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  for (var i = 0; i < 2; i++) {
    await _rastered(tester, view);
    await tester.pump(const Duration(milliseconds: 16));
  }
  final data = (await tester.runAsync(view.last!.toByteData))!;
  await tester.pumpWidget(
    View(view: view, child: const SizedBox()),
    wrapWithView: false,
  );
  view.release();
  return data.buffer.asUint8List();
}

void main() {
  setUp(() => glassReadsCopies = true);
  tearDown(() => glassReadsCopies = false);

  testWidgets('glass reads its own copy with other glass in the frame', (
    tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    final view = _CapturingView(tester);
    addTearDown(view.release);
    final pixels = await _draw(tester, view, const [
      _wide,
      Rect.fromLTWH(30, 200, 100, 300),
      Rect.fromLTWH(200, 520, 60, 60),
    ]);
    final width = (_viewSize.width * _dpr).toInt();
    (int, int) greenBlue(double x, double y) {
      final at = ((y * _dpr).toInt() * width + (x * _dpr).toInt()) * 4;
      return (pixels[at + 1], pixels[at + 2]);
    }

    // The copy under the wide glass is green on the left, blue on the right.
    final (leftGreen, leftBlue) = greenBlue(_wide.left + 20, _wide.center.dy);
    final (rightGreen, rightBlue) = greenBlue(
      _wide.right - 20,
      _wide.center.dy,
    );
    expect(leftGreen, greaterThan(leftBlue + 40));
    expect(rightBlue, greaterThan(rightGreen + 40));
  });
}
