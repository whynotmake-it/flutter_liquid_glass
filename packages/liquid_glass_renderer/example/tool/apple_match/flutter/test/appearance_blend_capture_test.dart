import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

const _outputPath = String.fromEnvironment('APPEARANCE_BLEND_CAPTURE_OUT');

/// The grid shows refraction; turn it off to measure color steps alone.
const _grid = bool.fromEnvironment('APPEARANCE_BLEND_GRID', defaultValue: true);

/// Captures the example playground's Colors scene: light, dark, clear and
/// tinted glass merged in one blend group, where appearances must blend
/// across the smooth union instead of switching at a seam.
void main() {
  for (final fake in [false, true]) {
    for (final dpr in [2.0, 3.0]) {
      testWidgets('captures merged appearances fake=$fake dpr=$dpr', (
        tester,
      ) async {
        if (!fake) {
          expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
        }
        final output = Directory(_outputPath)..createSync(recursive: true);
        tester.view
          ..devicePixelRatio = dpr
          ..physicalSize = const Size(360, 360) * dpr;
        addTearDown(tester.view.reset);
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: RepaintBoundary(
              key: captureKey,
              child: _ColorsScene(fake: fake),
            ),
          ),
        );
        for (var frame = 0; frame < 30; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: dpr);
        final kind = fake ? 'fake' : 'real';
        await expectLater(
          image,
          matchesGoldenFile(
            Uri.file('${output.path}/colors-$kind-dpr${dpr.round()}.png'),
          ),
        );
      }, skip: _outputPath.isEmpty);
    }
  }
}

class _ColorsScene extends StatelessWidget {
  const _ColorsScene({required this.fake});

  final bool fake;

  static const _swatches = [
    (Offset(-50, -50), LiquidGlassAppearance.ios27RegularLight()),
    (Offset(50, -50), LiquidGlassAppearance.ios27RegularDark()),
    (Offset(-50, 50), LiquidGlassAppearance.ios27Clear()),
    (
      Offset(50, 50),
      LiquidGlassAppearance.ios27RegularLight(tint: Color(0xFF0A84FF)),
    ),
  ];

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF7B733), Color(0xFFE8612C)],
          ),
        ),
      ),
      if (_grid)
        const GridPaper(
          color: Color(0x33000000),
          interval: 60,
          divisions: 1,
          subdivisions: 1,
        ),
      LiquidGlassLayer(
        fake: fake,
        settings: LiquidGlassSettings.ios27Toolbar(brightness: Brightness.dark),
        child: LiquidGlassBlendGroup(
          blend: 24,
          child: Stack(
            children: [
              for (final (offset, appearance) in _swatches)
                Positioned(
                  left: 180 + offset.dx - 54,
                  top: 180 + offset.dy - 54,
                  child: LiquidGlass.grouped(
                    appearance: appearance,
                    shape: const LiquidOval(),
                    child: const SizedBox.square(dimension: 108),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}
