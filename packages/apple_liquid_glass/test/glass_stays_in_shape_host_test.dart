import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = Size(420, 240);
const _dpr = 2.625;
const _background = Color(0xFF2080D0);

class _CapturingView extends TestFlutterView {
  _CapturingView(WidgetTester tester)
    : super(
        view: tester.view,
        platformDispatcher: tester.platformDispatcher,
        display: tester.view.display,
      ) {
    physicalSize = _size * _dpr;
    devicePixelRatio = _dpr;
  }

  ui.Image? last;

  @override
  void render(ui.Scene scene, {Size? size}) {
    last?.dispose();
    last = scene.toImageSync(
      (_size.width * _dpr).toInt(),
      (_size.height * _dpr).toInt(),
    );
  }
}

Widget _scene(_CapturingView view, Widget child) => View(
  view: view,
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: _size, devicePixelRatio: _dpr),
      child: GlassScope(
        renderer: const LiquidGlassRenderer(),
        child: ColoredBox(color: _background, child: child),
      ),
    ),
  ),
);

Widget _page(_CapturingView view, List<Rect> rects) => _scene(
  view,
  Stack(
    children: [
      for (final rect in rects)
        Positioned.fromRect(
          rect: rect,
          child: const GlassSurface(
            shape: LiquidRoundedSuperellipse(radius: 16),
            glass: Glass.clear(),
            child: SizedBox.expand(),
          ),
        ),
    ],
  ),
);

int _strayPixels(Uint8List pixels, List<Rect> glass) {
  final width = (_size.width * _dpr).toInt();
  final height = (_size.height * _dpr).toInt();
  final outside = [for (final rect in glass) rect.inflate(4)];
  var strays = 0;
  for (var y = 0; y < height; y += 3) {
    for (var x = 0; x < width; x += 3) {
      final point = Offset(x / _dpr, y / _dpr);
      if (outside.any((rect) => rect.contains(point))) continue;
      final at = (y * width + x) * 4;
      final off =
          (pixels[at] - 0x20).abs() +
          (pixels[at + 1] - 0x80).abs() +
          (pixels[at + 2] - 0xD0).abs();
      if (off > 30) strays++;
    }
  }
  return strays;
}

void main() {
  // A shape that resizes takes textures its earlier sizes drew into. What they
  // held must not reach the screen, as streaks past the shape.
  testWidgets('glass that resizes draws nothing past its shape', (
    tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    await tester.runAsync(precacheGlass);
    final view = _CapturingView(tester);
    for (var w = 60.0; w <= 380; w += 27.4) {
      for (var h = 40.0; h <= 170; h += 7.3) {
        final rect = Rect.fromLTWH(20, 30, w, h);
        await tester.pumpWidget(_page(view, [rect]), wrapWithView: false);
        await tester.pump();
        await tester.pump();
        final data = (await tester.runAsync(view.last!.toByteData))!;
        expect(
          _strayPixels(data.buffer.asUint8List(), [rect]),
          0,
          reason: 'glass at $rect',
        );
      }
    }
  });
  testWidgets('glass that jumps around draws nothing past its shapes', (
    tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    await tester.runAsync(precacheGlass);
    final view = _CapturingView(tester);
    final random = Random(7);
    Rect anywhere() {
      final width = 30 + random.nextDouble() * 200;
      final height = 30 + random.nextDouble() * 120;
      return Rect.fromLTWH(
        random.nextDouble() * (_size.width - width),
        random.nextDouble() * (_size.height - height),
        width,
        height,
      );
    }

    for (var frame = 0; frame < 80; frame++) {
      final rects = [
        for (var i = 0; i < 1 + random.nextInt(4); i++) anywhere(),
      ];
      await tester.pumpWidget(_page(view, rects), wrapWithView: false);
      await tester.pump();
      final data = (await tester.runAsync(view.last!.toByteData))!;
      expect(
        _strayPixels(data.buffer.asUint8List(), rects),
        0,
        reason: 'frame $frame, glass at $rects',
      );
    }
  });

  // The glass and the box of a tile move in one layout: the body stays where
  // it is drawn while the box lands elsewhere, not at the box with its old
  // size.
  testWidgets('glass following a layout moves with its box', (tester) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    await tester.runAsync(precacheGlass);
    final view = _CapturingView(tester);
    final layout = LayoutMotion();
    const id = ValueKey('tile');
    final frame = layout.select((motion) {
      const shape = LiquidRoundedSuperellipse(radius: 16);
      final box = motion.laidOut(id);
      if (box == null) return const GlassFrame(shape: shape);
      return GlassFrame(
        shape: shape,
        rect: motion.itemAt(id).rect.shift(-box.topLeft),
      );
    });
    Widget page({required bool far}) => _scene(
      view,
      MotionLayout(
        motion: layout,
        layoutBuilder: (context, children) => Align(
          alignment: far ? Alignment.bottomRight : Alignment.topLeft,
          child: children.single,
        ),
        children: [
          SizedBox(
            key: id,
            width: 120,
            height: 60,
            child: Builder(
              builder: (context) {
                MotionLayout.adoptItem(context);
                return GlassSurface.live(
                  frame: frame,
                  glass: const Glass.clear(),
                  child: const SizedBox.expand(),
                );
              },
            ),
          ),
        ],
      ),
    );

    await tester.pumpWidget(page(far: false), wrapWithView: false);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    withSpring(Spring.snappy, () {});
    await tester.pumpWidget(page(far: true), wrapWithView: false);
    final data = (await tester.runAsync(view.last!.toByteData))!;
    expect(
      _strayPixels(data.buffer.asUint8List(), const [
        Rect.fromLTWH(0, 0, 130, 70),
      ]),
      0,
    );
  });
}
