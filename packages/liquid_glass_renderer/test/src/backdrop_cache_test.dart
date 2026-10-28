import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/backdrop_seed.dart';

import 'backdrop_cache_scene.dart';
import 'shared.dart';

void main() {
  testWidgets('glass over its cached backdrop draws what reading it draws, '
      'and never over an older page', (tester) async {
    // No frost: the copy is the raw page.
    final settings = LiquidGlassSettings.ios27RegularLight().copyWith(
      frost: 0,
    );
    final (reading, cached) = await renderBothWays(tester, settings);
    expect(cacheDifference(reading, cached), lessThanOrEqualTo(1));

    // A page that changes under the glass is read, not the old copy.
    final cache = LiquidGlassBackdropCache(source: () => cachePage(tester));
    addTearDown(cache.dispose);
    await tester.pumpWidget(cacheScene(cache: cache, settings: settings));
    for (var i = 0; i < 3; i++) {
      tester.binding.scheduleFrame();
      await tester.pump();
    }
    expect(cacheLayer(tester).debugDrewOverCopy, isTrue);
    await tester.pumpWidget(
      cacheScene(cache: cache, settings: settings, shift: 0.3),
    );
    expect(cacheLayer(tester).debugDrewOverCopy, isFalse);
  }, skip: skipProperGlassTests);

  testWidgets('glass reads its backdrop in the frame its page moves', (
    tester,
  ) async {
    final settings = LiquidGlassSettings.ios27RegularLight();
    final cache = LiquidGlassBackdropCache(source: () => cachePage(tester));
    addTearDown(cache.dispose);
    await tester.pumpWidget(cacheScene(cache: cache, settings: settings));
    for (var i = 0; i < 3; i++) {
      tester.binding.scheduleFrame();
      await tester.pump();
    }
    expect(cacheLayer(tester).debugDrewOverCopy, isTrue);
    // Only the page moves off the screen's origin; the glass does not
    // repaint in this frame.
    await tester.pumpWidget(
      cacheScene(
        cache: cache,
        settings: settings,
        pageOffset: const Offset(0, 8),
      ),
    );
    expect(cacheLayer(tester).debugDrewOverCopy, isFalse);
  }, skip: skipProperGlassTests);

  testWidgets('a cache without a source leaves the glass reading', (
    tester,
  ) async {
    final cache = LiquidGlassBackdropCache(source: () => null);
    addTearDown(cache.dispose);
    await tester.pumpWidget(
      cacheScene(
        cache: cache,
        settings: LiquidGlassSettings.ios27RegularLight(),
      ),
    );
    await tester.pump();
    expect(cacheLayer(tester).debugCachesBackdrop, isFalse);
    expect(cache.debugCaptures, 0);
  }, skip: skipProperGlassTests);

  testWidgets('a page with seeded glass of its own is copied', (tester) async {
    final override = SeededBackdropPassLayer.debugModeOverride;
    SeededBackdropPassLayer.debugModeOverride = BackdropSeed.blur;
    addTearDown(() => SeededBackdropPassLayer.debugModeOverride = override);
    final cache = LiquidGlassBackdropCache(source: () => cachePage(tester));
    addTearDown(cache.dispose);
    await tester.pumpWidget(
      cacheScene(
        cache: cache,
        settings: LiquidGlassSettings.ios27RegularLight(),
        page: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFF1E3A8A))),
            Positioned.fill(
              child: LiquidGlassLayer(
                settings: const LiquidGlassSettings(frost: 8),
                child: Stack(
                  children: [
                    Positioned.fromRect(
                      rect: const Rect.fromLTWH(20, 140, 220, 44),
                      child: const LiquidGlass(
                        shape: LiquidRoundedSuperellipse(borderRadius: 22),
                        child: SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      tester.binding.scheduleFrame();
      await tester.pump();
    }
    final pass = tester.layers.whereType<SeededBackdropPassLayer>().single;
    expect(pass.nativeSeed, isNot(BackdropSeed.none));
    expect(cacheLayer(tester).debugDrewOverCopy, isTrue);
  }, skip: skipProperGlassTests);

  testWidgets('a page under an opacity is read, not copied', (tester) async {
    final cache = LiquidGlassBackdropCache(source: () => cachePage(tester));
    addTearDown(cache.dispose);
    await tester.pumpWidget(
      cacheScene(
        cache: cache,
        settings: LiquidGlassSettings.ios27RegularLight(),
        pageOpacity: 0.5,
      ),
    );
    for (var i = 0; i < 3; i++) {
      tester.binding.scheduleFrame();
      await tester.pump();
    }
    expect(cache.ready, isFalse);
    expect(cacheLayer(tester).debugDrewOverCopy, isFalse);
  }, skip: skipProperGlassTests);

  testWidgets('glass reads its backdrop when a filter in the page reads far '
      'from the glass, and what it reads changes', (tester) async {
    tester.view
      ..physicalSize = const Size(260, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cache = LiquidGlassBackdropCache(source: () => cachePage(tester));
    addTearDown(cache.dispose);
    Widget scene(Color far) => cacheScene(
      cache: cache,
      settings: LiquidGlassSettings.ios27RegularLight(),
      page: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Color(0xFF1E3A8A))),
          Positioned(
            left: 0,
            top: 460,
            width: 260,
            height: 100,
            // Its own picture, outside the band the copy is checked over.
            child: RepaintBoundary(child: ColoredBox(color: far)),
          ),
          // Draws, under the glass, what lies 400 px lower.
          Positioned(
            left: 0,
            top: 40,
            width: 260,
            height: 140,
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.matrix(
                  Matrix4.translationValues(0, -400, 0).storage,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpWidget(scene(const Color(0xFFF59E0B)));
    for (var i = 0; i < 3; i++) {
      tester.binding.scheduleFrame();
      await tester.pump();
    }
    expect(cacheLayer(tester).debugDrewOverCopy, isTrue);
    await tester.pumpWidget(scene(const Color(0xFF10B981)));
    expect(cacheLayer(tester).debugDrewOverCopy, isFalse);
  }, skip: skipProperGlassTests);
}
