import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// Renders the glass of the cover of `docs/liquid-glass-rewrite.md` over the
/// background drawn by `tool/blog_cover.py`; see that file for the steps. The
/// test only runs when both paths are set.
const _out = String.fromEnvironment('BLOG_COVER_OUT');
const _background = String.fromEnvironment('BLOG_COVER_BACKGROUND');

const _size = Size(1200, 630);
const _scale = 2.0;

class _Cover extends StatelessWidget {
  const _Cover({required this.background});

  final ui.Image background;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: RawImage(image: background, fit: BoxFit.fill),
        ),
        LiquidGlassLayer(
          settings: LiquidGlassSettings.ios27Clear(frost: 0),
          defaultAppearance: const LiquidGlassAppearance.ios27Clear(),
          child: LiquidGlassBlendGroup(
            blend: 40,
            child: Stack(
              children: [
                _glass(
                  left: 600,
                  top: 186,
                  width: 300,
                  height: 128,
                  shape: const LiquidRoundedSuperellipse(borderRadius: 64),
                ),
                _glass(
                  left: 883,
                  top: 250,
                  width: 170,
                  height: 170,
                  shape: const LiquidOval(),
                ),
                _glass(
                  left: 994,
                  top: 166,
                  width: 92,
                  height: 92,
                  shape: const LiquidOval(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _glass({
    required double left,
    required double top,
    required double width,
    required double height,
    required LiquidShape shape,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: LiquidGlass.grouped(
        shape: shape,
        shadows: const [
          BoxShadow(
            color: Color(0x2E0B1F4D),
            blurRadius: 36,
            offset: Offset(0, 14),
          ),
        ],
        child: SizedBox(width: width, height: height),
      ),
    );
  }
}

void main() {
  testWidgets(
    'captures the blog cover',
    (tester) async {
      final shadowsWereDisabled = debugDisableShadows;
      debugDisableShadows = false;
      try {
        tester.view
          ..physicalSize = _size * _scale
          ..devicePixelRatio = _scale;
        addTearDown(tester.view.reset);

        final background = (await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(
            File(_background).readAsBytesSync(),
          );
          return (await codec.getNextFrame()).image;
        }))!;
        addTearDown(background.dispose);
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: _Cover(background: background),
            ),
          ),
        );
        for (var frame = 0; frame < 120; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: _scale);
        await tester.runAsync(() async {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File(_out)
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(png!.buffer.asUint8List());
        });
        image.dispose();
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      } finally {
        debugDisableShadows = shadowsWereDisabled;
      }
    },
    skip: _out.isEmpty || _background.isEmpty,
    tags: 'golden',
  );
}
