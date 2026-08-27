import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:snaptest/snaptest.dart';

import 'shared.dart';

const _docsSnapshot = Key('docs-snapshot');

void main() {
  snapTest(
    'renderer showcase',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 680)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(body: Center(child: _Showcase())),
        ),
      );
      await pumpUntilGlassReady(tester);
      await tester.pump();
      await snap(name: 'renderer-showcase', from: find.byKey(_docsSnapshot));
    },
    settings: const SnaptestSettings(
      blockText: false,
      renderImages: true,
      renderShadows: true,
      pathPrefix: '.snaptest/docs/',
    ),
    skip: skipGoldenTests,
  );
}

class _Showcase extends StatelessWidget {
  const _Showcase();

  static const settings = LiquidGlassSettings.ios27ToolbarLight(frost: 5);
  static const shadow = BoxShadow(
    color: Color(0x3300081A),
    offset: Offset(0, 12),
    blurRadius: 28,
    spreadRadius: -4,
  );

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: _docsSnapshot,
    child: SizedBox(
      width: 1200,
      height: 680,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xff071426), Color(0xff146B82), Color(0xffEBB86A)],
            stops: [0, .58, 1],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              left: -110,
              top: -170,
              child: _Glow(color: Color(0x998B5CF6), diameter: 520),
            ),
            const Positioned(
              right: -80,
              bottom: -220,
              child: _Glow(color: Color(0xB3FFE08A), diameter: 600),
            ),
            Padding(
              padding: const EdgeInsets.all(64),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Liquid Glass Renderer',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 46,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Refraction, blended geometry, and a portable fallback',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .72),
                      fontSize: 20,
                    ),
                  ),
                  const Spacer(),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _SingleMaterial(),
                      _BlendedMaterial(),
                      _FakeMaterial(),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SingleMaterial extends StatelessWidget {
  const _SingleMaterial();

  @override
  Widget build(BuildContext context) => const LiquidGlass.withOwnLayer(
    settings: _Showcase.settings,
    shadows: [_Showcase.shadow],
    shape: LiquidRoundedSuperellipse(borderRadius: 56),
    child: SizedBox(
      width: 280,
      height: 210,
      child: _MaterialLabel(title: 'REFRACTION', subtitle: 'Full renderer'),
    ),
  );
}

class _BlendedMaterial extends StatelessWidget {
  const _BlendedMaterial();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 300,
    height: 250,
    child: LiquidGlassLayer(
      settings: _Showcase.settings,
      child: LiquidGlassBlendGroup(
        blend: 36,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 12,
              child: LiquidGlass.grouped(
                shadows: [_Showcase.shadow],
                shape: LiquidOval(),
                child: SizedBox.square(dimension: 176),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: LiquidGlass.grouped(
                shadows: [_Showcase.shadow],
                shape: LiquidRoundedSuperellipse(borderRadius: 48),
                child: SizedBox(
                  width: 214,
                  height: 136,
                  child: _MaterialLabel(
                    title: 'BLENDED',
                    subtitle: 'Shared layer',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _FakeMaterial extends StatelessWidget {
  const _FakeMaterial();

  @override
  Widget build(BuildContext context) => const FakeGlass(
    settings: _Showcase.settings,
    shadows: [_Showcase.shadow],
    shape: LiquidRoundedSuperellipse(borderRadius: 56),
    child: SizedBox(
      width: 280,
      height: 210,
      child: _MaterialLabel(title: 'PORTABLE', subtitle: 'FakeGlass fallback'),
    ),
  );
}

class _MaterialLabel extends StatelessWidget {
  const _MaterialLabel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(color: Colors.white.withValues(alpha: .68)),
        ),
      ],
    ),
  );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.diameter});

  final Color color;
  final double diameter;

  @override
  Widget build(BuildContext context) => Container(
    width: diameter,
    height: diameter,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}
