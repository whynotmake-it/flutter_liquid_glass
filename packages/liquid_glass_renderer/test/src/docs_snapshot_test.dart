import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:snaptest/snaptest.dart';

import 'shared.dart';

void main() {
  _docsSnapshot(
    testName: 'renderer showcase',
    snapshotName: 'renderer-showcase',
    size: const Size(1200, 540),
    child: const _Hero(),
  );
  _docsSnapshot(
    testName: 'renderer optics',
    snapshotName: 'renderer-optics',
    size: const Size(1000, 500),
    child: const _Optics(),
  );
  _docsSnapshot(
    testName: 'renderer blended geometry',
    snapshotName: 'renderer-blending',
    size: const Size(1000, 500),
    child: const _Blending(),
  );
  _docsSnapshot(
    testName: 'renderer fallback',
    snapshotName: 'renderer-fallback',
    size: const Size(1000, 500),
    child: const _Fallback(),
  );
}

void _docsSnapshot({
  required String testName,
  required String snapshotName,
  required Size size,
  required Widget child,
}) {
  final snapshotKey = ValueKey(snapshotName);
  snapTest(
    testName,
    (tester) async {
      final previousDisableShadows = debugDisableShadows;
      debugDisableShadows = false;

      tester.view
        ..physicalSize = size * 2
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: RepaintBoundary(
              key: snapshotKey,
              child: SizedBox.fromSize(
                size: size * 2,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Transform.scale(
                    scale: 2,
                    alignment: Alignment.topLeft,
                    child: SizedBox.fromSize(size: size, child: child),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await pumpUntilGlassReady(tester);
      await tester.pump();
      await snap(name: snapshotName, from: find.byKey(snapshotKey));
      debugDisableShadows = previousDisableShadows;
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

const _clearGlass = LiquidGlassSettings.ios27ToolbarLight(frost: 0);
const _softGlass = LiquidGlassSettings.ios27ToolbarLight(frost: 8);
const _exampleShadow = BoxShadow(
  color: Color.from(alpha: 0.03, red: 0, green: 0, blue: 0),
  offset: Offset(0, 6),
  blurRadius: 12,
  spreadRadius: -1,
);

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) => const _LoupeGrid(
    child: Center(
      child: LiquidGlass.withOwnLayer(
        settings: _clearGlass,
        shadows: [_exampleShadow],
        shape: LiquidRoundedSuperellipse(borderRadius: 82),
        child: SizedBox(width: 680, height: 164),
      ),
    ),
  );
}

class _Optics extends StatelessWidget {
  const _Optics();

  @override
  Widget build(BuildContext context) => const _LoupeGrid(
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        LiquidGlass.withOwnLayer(
          settings: _clearGlass,
          shadows: [_exampleShadow],
          shape: LiquidRoundedSuperellipse(borderRadius: 58),
          child: SizedBox(width: 310, height: 180),
        ),
        SizedBox(width: 72),
        LiquidGlass.withOwnLayer(
          settings: _softGlass,
          shadows: [_exampleShadow],
          shape: LiquidRoundedSuperellipse(borderRadius: 58),
          child: SizedBox(width: 310, height: 180),
        ),
      ],
    ),
  );
}

class _Blending extends StatelessWidget {
  const _Blending();

  @override
  Widget build(BuildContext context) => const _LoupeGrid(
    child: Center(
      child: SizedBox(
        width: 560,
        height: 260,
        child: LiquidGlassLayer(
          settings: _clearGlass,
          child: LiquidGlassBlendGroup(
            blend: 42,
            child: Stack(
              children: [
                Positioned(
                  left: 42,
                  top: 18,
                  child: LiquidGlass.grouped(
                    shadows: [_exampleShadow],
                    shape: LiquidOval(),
                    child: SizedBox.square(dimension: 190),
                  ),
                ),
                Positioned(
                  right: 36,
                  bottom: 18,
                  child: LiquidGlass.grouped(
                    shadows: [_exampleShadow],
                    shape: LiquidRoundedSuperellipse(borderRadius: 64),
                    child: SizedBox(width: 350, height: 156),
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

class _Fallback extends StatelessWidget {
  const _Fallback();

  @override
  Widget build(BuildContext context) => const _LoupeGrid(
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        LiquidGlass.withOwnLayer(
          settings: _softGlass,
          shadows: [_exampleShadow],
          shape: LiquidRoundedSuperellipse(borderRadius: 58),
          child: SizedBox(width: 310, height: 180),
        ),
        SizedBox(width: 72),
        FakeGlass(
          settings: _softGlass,
          shadows: [_exampleShadow],
          shape: LiquidRoundedSuperellipse(borderRadius: 58),
          child: SizedBox(width: 310, height: 180),
        ),
      ],
    ),
  );
}

class _LoupeGrid extends StatelessWidget {
  const _LoupeGrid({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Positioned.fill(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFCEC5B4), Color(0xFFF2F0EA)],
            ),
          ),
          child: GridPaper(
            color: const Color(0xFF0F0B0A).withValues(alpha: .2),
          ),
        ),
      ),
      child,
    ],
  );
}
