import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

const _outputPath = String.fromEnvironment('PER_SHAPE_CAPTURE_OUT');

void main() {
  testWidgets(
    'captures the compact per-shape appearance atlas with real Impeller glass',
    (tester) async {
      expect(
        ui.ImageFilter.isShaderFilterSupported,
        isTrue,
        reason: 'this atlas must never capture the FakeGlass fallback',
      );

      final output = Directory(_outputPath)..createSync(recursive: true);
      tester.view
        ..devicePixelRatio = 2
        ..physicalSize = const Size(1200, 900);
      addTearDown(tester.view.reset);

      const captures = <(String, Widget)>[
        ('default-light', _DefaultAppearance(brightness: Brightness.light)),
        ('default-dark', _DefaultAppearance(brightness: Brightness.dark)),
        ('color-response', _ColorAxes()),
        ('merged-visibility', _MergedAppearance()),
      ];
      final shadowsWereDisabled = debugDisableShadows;
      debugDisableShadows = false;
      try {
        for (final (name, child) in captures) {
          final captureKey = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              home: RepaintBoundary(
                key: captureKey,
                child: SizedBox(
                  width: 600,
                  height: 450,
                  child: ColoredBox(
                    color: const Color(0xFF111318),
                    child: child,
                  ),
                ),
              ),
            ),
          );
          await _pumpUntilRealGlass(tester);
          await tester.pump();

          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          await expectLater(
            image,
            matchesGoldenFile(Uri.file('${output.path}/$name.png')),
          );
        }
      } finally {
        debugDisableShadows = shadowsWereDisabled;
      }
    },
    skip: _outputPath.isEmpty,
  );
}

Future<void> _pumpUntilRealGlass(WidgetTester tester) async {
  for (var frame = 0; frame < 60; frame++) {
    if (find.byType(LiquidGlassLayer).evaluate().isNotEmpty &&
        find.byType(FakeGlass).evaluate().isEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  fail('real Flutter GPU glass did not become ready within 60 frames');
}

class _DefaultAppearance extends StatelessWidget {
  const _DefaultAppearance({required this.brightness});

  final Brightness brightness;

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(platformBrightness: brightness),
    child: _Backdrop(
      dark: brightness == Brightness.dark,
      child: LiquidGlassLayer(
        settings: LiquidGlassSettings.ios27Toolbar(brightness: brightness),
        child: const Center(
          child: LiquidGlass(
            shape: LiquidRoundedSuperellipse(borderRadius: 42),
            shadows: [
              BoxShadow(
                color: Color(0x33000000),
                offset: Offset(0, 6),
                blurRadius: 14,
                spreadRadius: -2,
              ),
            ],
            child: SizedBox(width: 300, height: 132),
          ),
        ),
      ),
    ),
  );
}

class _ColorAxes extends StatelessWidget {
  const _ColorAxes();

  @override
  Widget build(BuildContext context) => _Backdrop(
    child: LiquidGlassLayer(
      settings: const LiquidGlassSettings.ios27ToolbarLight(frost: 0),
      child: Center(
        child: Wrap(
          spacing: 18,
          runSpacing: 18,
          children: const [
            _AppearanceChip(
              appearance: LiquidGlassAppearance(tint: Color(0x994C8DFF)),
            ),
            _AppearanceChip(appearance: LiquidGlassAppearance(saturation: 2.4)),
            _AppearanceChip(
              appearance: LiquidGlassAppearance(transmissionGamma: .62),
            ),
            _AppearanceChip(appearance: LiquidGlassAppearance(vibrancy: .4)),
          ],
        ),
      ),
    ),
  );
}

class _AppearanceChip extends StatelessWidget {
  const _AppearanceChip({required this.appearance});

  final LiquidGlassAppearance appearance;

  @override
  Widget build(BuildContext context) => LiquidGlass(
    appearance: appearance,
    shape: const LiquidRoundedSuperellipse(borderRadius: 24),
    child: const SizedBox(width: 210, height: 110),
  );
}

class _MergedAppearance extends StatelessWidget {
  const _MergedAppearance();

  @override
  Widget build(BuildContext context) => _Backdrop(
    child: LiquidGlassLayer(
      settings: const LiquidGlassSettings.ios27ToolbarLight(frost: 0),
      child: Center(
        child: LiquidGlassBlendGroup(
          blend: 38,
          child: SizedBox(
            width: 440,
            height: 270,
            child: Stack(
              children: const [
                Positioned(
                  left: 38,
                  top: 48,
                  child: LiquidGlass.grouped(
                    appearance: LiquidGlassAppearance(
                      tint: Color(0xA8FFFFFF),
                      saturation: .8,
                    ),
                    shape: LiquidRoundedSuperellipse(borderRadius: 34),
                    child: SizedBox(width: 220, height: 120),
                  ),
                ),
                Positioned(
                  left: 192,
                  top: 48,
                  child: LiquidGlass.grouped(
                    appearance: LiquidGlassAppearance(
                      tint: Color(0xA52B7CFF),
                      saturation: 1.8,
                      transmissionGamma: .78,
                      vibrancy: .2,
                    ),
                    shape: LiquidRoundedSuperellipse(borderRadius: 34),
                    child: SizedBox(width: 220, height: 120),
                  ),
                ),
                Positioned(
                  left: 136,
                  top: 142,
                  child: LiquidGlass.grouped(
                    appearance: LiquidGlassAppearance(
                      tint: Color(0xA8FF6D58),
                      visibility: .5,
                    ),
                    shape: LiquidOval(),
                    child: SizedBox(width: 170, height: 100),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 4,
                  child: LiquidGlass.grouped(
                    appearance: LiquidGlassAppearance(visibility: 0),
                    shape: LiquidOval(),
                    child: SizedBox.square(dimension: 72),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.child, this.dark = false});

  final Widget child;
  final bool dark;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? const [Color(0xFF07101F), Color(0xFF54275F)]
                : const [Color(0xFFE6F5FF), Color(0xFFFFD55C)],
          ),
        ),
      ),
      const GridPaper(
        color: Color(0x66000000),
        interval: 40,
        divisions: 2,
        subdivisions: 1,
      ),
      child,
    ],
  );
}
