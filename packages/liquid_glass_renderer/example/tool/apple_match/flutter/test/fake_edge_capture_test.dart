import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

const _outputPath = String.fromEnvironment('FAKE_EDGE_CAPTURE_OUT');

/// Drops blur and color transfer, leaving FakeGlass without a backdrop
/// filter, to separate the backdrop clip from the analytic surface.
const _noBackdrop = bool.fromEnvironment('FAKE_EDGE_NO_BACKDROP');

/// A flat backdrop, so only the silhouette varies along an edge.
const _flat = bool.fromEnvironment('FAKE_EDGE_FLAT');

/// Captures FakeGlass pills, capsules and cards on a busy backdrop so the
/// silhouette's anti-aliasing can be judged at several device pixel ratios.
void main() {
  for (final fake in [true, false]) {
    for (final brightness in Brightness.values) {
      for (final dpr in [1.0, 2.0, 3.0]) {
        final kind = fake ? 'fake' : 'real';
        final name = '$kind-${brightness.name}-dpr${dpr.round()}';
        testWidgets('captures glass edges $name', (tester) async {
          final output = Directory(_outputPath)..createSync(recursive: true);
          tester.view
            ..devicePixelRatio = dpr
            ..physicalSize = const Size(360, 300) * dpr;
          addTearDown(tester.view.reset);
          final captureKey = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              home: RepaintBoundary(
                key: captureKey,
                child: _Shapes(fake: fake, brightness: brightness),
              ),
            ),
          );
          for (var frame = 0; frame < 20; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: dpr);
          await expectLater(
            image,
            matchesGoldenFile(Uri.file('${output.path}/$name.png')),
          );
        }, skip: _outputPath.isEmpty, tags: 'golden');
      }
    }
  }
}

class _Shapes extends StatelessWidget {
  const _Shapes({required this.fake, required this.brightness});

  final bool fake;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (_flat)
        const ColoredBox(color: Color(0xFF2A9D8F))
      else ...[
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1B8A6B), Color(0xFFF2C94C), Color(0xFFD9485F)],
            ),
          ),
        ),
        const GridPaper(
          color: Color(0x55000000),
          interval: 24,
          divisions: 1,
          subdivisions: 1,
        ),
      ],
      LiquidGlassLayer(
        fake: fake,
        settings: _noBackdrop
            ? const LiquidGlassSettings(frost: 0)
            : LiquidGlassSettings.ios27Toolbar(brightness: brightness),
        defaultAppearance: _noBackdrop
            ? const LiquidGlassAppearance(tint: Color(0x66FFFFFF))
            : LiquidGlassAppearance.ios27Toolbar(brightness: brightness),
        child: Stack(
          children: [
            // Pill button (the example's GlassButton).
            const Positioned(
              left: 20,
              top: 20,
              child: LiquidGlass(
                shape: LiquidRoundedSuperellipse(borderRadius: 9000),
                child: SizedBox(width: 120, height: 44),
              ),
            ),
            // Bottom-bar capsule.
            const Positioned(
              left: 20,
              top: 90,
              child: LiquidGlass(
                shape: LiquidRoundedSuperellipse(borderRadius: 32),
                child: SizedBox(width: 320, height: 64),
              ),
            ),
            // Card.
            const Positioned(
              left: 20,
              top: 180,
              child: LiquidGlass(
                shape: LiquidRoundedSuperellipse(borderRadius: 24),
                child: SizedBox(width: 200, height: 100),
              ),
            ),
            // Circle icon button.
            const Positioned(
              left: 250,
              top: 190,
              child: LiquidGlass(
                shape: LiquidOval(),
                child: SizedBox.square(dimension: 52),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
