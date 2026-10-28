import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

const _key = ValueKey('screen');
const _pageKey = ValueKey('page');

/// The size of the cache scenes' view.
const cacheView = Size(260, 200);

/// The dimming between the page and the glass.
const cacheDim = Color(0x33000000);

Widget _page({required double shift}) => DecoratedBox(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: const [Color(0xFF1E3A8A), Color(0xFFF59E0B), Color(0xFF10B981)],
      begin: Alignment(-1 + shift, -1),
      end: Alignment.bottomRight,
      tileMode: TileMode.mirror,
    ),
  ),
  child: const Center(
    child: Text(
      'Page under the glass',
      textDirection: TextDirection.ltr,
      style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 22),
    ),
  ),
);

/// A page, a dimming over it and glass over both, which reads the page
/// through [cache] when one is given. [page] replaces the default page.
Widget cacheScene({
  required LiquidGlassBackdropCache? cache,
  required LiquidGlassSettings settings,
  double shift = 0,
  Offset pageOffset = Offset.zero,
  double pageOpacity = 1,
  Widget? page,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: RepaintBoundary(
    key: _key,
    child: Stack(
      children: [
        Positioned.fill(
          child: Transform.translate(
            offset: pageOffset,
            child: Opacity(
              opacity: pageOpacity,
              child: RepaintBoundary(
                key: _pageKey,
                child: page ?? _page(shift: shift),
              ),
            ),
          ),
        ),
        const Positioned.fill(child: ColoredBox(color: cacheDim)),
        Positioned.fill(
          child: LiquidGlassLayer(
            settings: settings,
            backdrop: cache == null
                ? const LiquidGlassBackdrop.read()
                : LiquidGlassBackdrop.cached(cache),
            child: Stack(
              children: [
                Positioned.fromRect(
                  rect: const Rect.fromLTWH(30, 50, 200, 110),
                  child: const LiquidGlass(
                    shape: LiquidRoundedSuperellipse(borderRadius: 28),
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

/// The cache scenes' page boundary.
RenderObject cachePage(WidgetTester tester) =>
    tester.renderObject(find.byKey(_pageKey));

/// The scene's pixels, RGBA.
Future<Uint8List> captureCacheScene(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(boundary.toImage))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

/// The scene's glass layer, the one given a cache.
RenderLiquidGlassLayer cacheLayer(WidgetTester tester) => tester
    .allRenderObjects
    .whereType<RenderLiquidGlassLayer>()
    .where((layer) => layer.backdropCache != null)
    .toSet()
    .single;

/// Renders the scene reading its backdrop, then over a copy, and returns
/// both, after checking the copy was taken once and drawn over.
Future<(Uint8List reading, Uint8List cached)> renderBothWays(
  WidgetTester tester,
  LiquidGlassSettings settings,
) async {
  tester.view
    ..physicalSize = cacheView
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  // flutter_tester renders only a process's first backdrop filter
  // reliably, so the reference reads the backdrop first, and a test file
  // calls this once.
  await tester.pumpWidget(cacheScene(cache: null, settings: settings));
  await tester.pump();
  final reading = await captureCacheScene(tester);

  final cache = LiquidGlassBackdropCache(source: () => cachePage(tester))
    ..overlay = cacheDim;
  addTearDown(cache.dispose);
  await tester.pumpWidget(cacheScene(cache: cache, settings: settings));
  final layer = cacheLayer(tester);
  expect(layer.debugCachesBackdrop, isTrue);
  // The first frames read the backdrop: the page has to hold still for a
  // frame before it is copied. The cache schedules no frame of its own (it
  // copies in a post-frame callback), so scheduleFrame stands in for content
  // animating on the glass.
  expect(layer.debugDrewOverCopy, isFalse);
  for (var i = 0; i < 3; i++) {
    tester.binding.scheduleFrame();
    await tester.pump();
  }
  expect(cache.debugCaptures, 1);
  expect(layer.debugDrewOverCopy, isTrue);
  return (reading, await captureCacheScene(tester));
}

/// The largest channel difference between [a] and [b].
int cacheDifference(Uint8List a, Uint8List b) {
  var largest = 0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (d > largest) largest = d;
  }
  return largest;
}
