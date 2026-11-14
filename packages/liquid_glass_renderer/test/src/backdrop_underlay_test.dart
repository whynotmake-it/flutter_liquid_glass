import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_haze.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('screen');

// Two glass layers, the first in its own boundary so that an image can be
// taken of it alone.
const _shadow = [
  BoxShadow(color: Color(0x40000000), blurRadius: 16, offset: Offset(0, 6)),
];

Widget _pairScene({
  double shift = 0,
  double top = 40,
  double frost = 0,
  bool shadowed = false,
  bool second = true,
  bool between = false,
  bool apart = false,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: RepaintBoundary(
    key: _key,
    child: Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: const [Color(0xFF1E3A8A), Color(0xFFF59E0B)],
                  begin: Alignment(-1 + shift, -1),
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
        ),
        for (final (key, rect) in [
          (_first, Rect.fromLTWH(30, top, 200, 90)),
          if (second) (null, const Rect.fromLTWH(30, 260, 200, 60)),
        ]) ...[
          // Painted after the first glass, in the second's band.
          if (between && key == null)
            const Positioned(
              left: 110,
              top: 326,
              width: 40,
              height: 6,
              child: ColoredBox(color: Color(0xFFFFFFFF)),
            ),
          Positioned.fill(
            child: RepaintBoundary(
              key: key,
              child: LiquidGlassLayer(
                // Glass of one look joins one filter; [apart] gives the
                // second glass a look of its own, so each reads its copy.
                settings: LiquidGlassSettings.ios27RegularLight().copyWith(
                  frost: frost,
                  refractionHeight: apart && key == null ? 12 : null,
                ),
                child: Stack(
                  children: [
                    Positioned.fromRect(
                      rect: rect,
                      child: LiquidGlass(
                        shape: const LiquidRoundedSuperellipse(
                          borderRadius: 28,
                        ),
                        shadows: shadowed ? _shadow : const [],
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  ),
);

const _first = ValueKey('first');

final _leader = LayerLink();

// [child] placed under the leader, where it lies with the leader at its
// first place, when [follows].
Widget _following(bool follows, Widget child) => follows
    ? CompositedTransformFollower(
        link: _leader,
        offset: const Offset(-20, -30),
        child: child,
      )
    : child;

Widget _scene({
  double shift = 0,
  double dot = 0,
  bool platformView = false,
  bool follower = false,
  double leader = 20,
  bool glassFollows = false,
  double opacity = 1,
  bool pair = false,
  bool mask = false,
  bool clipped = false,
  double scaleX = 1,
  double scaleY = 1,
  double frost = 0,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: RepaintBoundary(
    key: _key,
    child: Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: const [
                    Color(0xFF1E3A8A),
                    Color(0xFFF59E0B),
                    Color(0xFF10B981),
                  ],
                  begin: Alignment(-1 + shift, -1),
                  end: Alignment.bottomRight,
                  tileMode: TileMode.mirror,
                ),
              ),
              child: const Center(
                child: Text(
                  'Page under the glass',
                  style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 22),
                ),
              ),
            ),
          ),
        ),
        if (mask)
          Positioned.fill(
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0x00000000), Color(0xFF000000)],
              ).createShader(bounds),
              child: const RepaintBoundary(
                child: ColoredBox(color: Color(0x40FFFFFF)),
              ),
            ),
          ),
        // A list scrolled under a clip whose edge runs through the glass's
        // band: the item above the edge, clipped, is an empty rect lying
        // across that band, beside one the clip shows.
        if (clipped)
          Positioned(
            left: 0,
            right: 0,
            top: 100,
            height: 100,
            child: ClipRect(
              child: Transform.translate(
                offset: const Offset(0, -60),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (color, height) in const [
                      (Color(0xFFEF4444), 60.0),
                      (Color(0xFF22C55E), 40.0),
                    ])
                      RepaintBoundary(
                        child: SizedBox(
                          height: height,
                          width: double.infinity,
                          child: ColoredBox(color: color),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (follower) ...[
          Positioned(
            left: leader,
            top: 30,
            child: CompositedTransformTarget(
              link: _leader,
              child: const SizedBox.square(dimension: 4),
            ),
          ),
          CompositedTransformFollower(
            link: _leader,
            offset: const Offset(20, 20),
            child: const SizedBox(
              width: 60,
              height: 30,
              child: ColoredBox(color: Color(0xFFDB2777)),
            ),
          ),
        ],
        if (platformView)
          Positioned(
            left: 40,
            top: 50,
            width: 20,
            height: 20,
            child: PlatformViewSurface(
              controller: _PlatformView(),
              hitTestBehavior: PlatformViewHitTestBehavior.transparent,
              gestureRecognizers: const {},
            ),
          ),
        Positioned.fill(
          child: Opacity(
            opacity: opacity,
            child: Transform(
              alignment: const Alignment(-0.3, -0.5),
              transform: Matrix4.diagonal3Values(scaleX, scaleY, 1),
              child: _following(
                glassFollows,
                LiquidGlassLayer(
                  settings: LiquidGlassSettings.ios27RegularLight().copyWith(
                    frost: frost,
                  ),
                  child: Stack(
                    children: [
                      Positioned.fromRect(
                        rect: const Rect.fromLTWH(30, 40, 200, 90),
                        child: const LiquidGlass(
                          shape: LiquidRoundedSuperellipse(borderRadius: 28),
                          child: SizedBox.expand(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (pair)
          Positioned.fill(
            child: LiquidGlassLayer(
              settings: LiquidGlassSettings.ios27RegularLight().copyWith(
                frost: 0,
              ),
              child: Stack(
                children: [
                  Positioned.fromRect(
                    rect: const Rect.fromLTWH(30, 260, 200, 60),
                    child: const LiquidGlass(
                      shape: LiquidRoundedSuperellipse(borderRadius: 28),
                      child: SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Something that moves far from the glass, in its own boundary.
        Positioned(
          left: 10 + dot,
          bottom: 6,
          child: const RepaintBoundary(
            child: SizedBox.square(
              dimension: 6,
              child: ColoredBox(color: Color(0xFFFFFFFF)),
            ),
          ),
        ),
      ],
    ),
  ),
);

RenderLiquidGlassLayer _glass(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().toSet().single;

Iterable<BackdropFilterLayer> _liveFilters(WidgetTester tester) => tester.layers
    .whereType<BackdropFilterLayer>()
    .where((layer) => layer is! OpacitySeedLayer || layer.seeded);

Future<Uint8List> _pixels(WidgetTester tester, {double pixelRatio = 1}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: pixelRatio),
  ))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

int _difference(Uint8List a, Uint8List b) {
  var largest = 0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (d > largest) largest = d;
  }
  return largest;
}

Future<void> _settle(WidgetTester tester, {double dot = 0}) async {
  for (var i = 0; i < 4; i++) {
    await tester.pumpWidget(_scene(dot: dot + i));
  }
}

void main() {
  setUp(() {
    debugGlassCopies = true;
    // These hold a copy against the backdrop read live, which draws no
    // haze: liquid_glass_haze_test holds the haze.
    debugGlassHaze = false;
  });
  tearDown(() {
    debugGlassCopies = null;
    debugGlassHaze = null;
  });

  testWidgets('glass over a copy drawn in the very frame what lies under '
      'it changed draws what reading it draws, with no backdrop filter in '
      'the frame', (tester) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // flutter_tester renders only a process's first backdrop filter
    // reliably, so the reference reads the backdrop first.
    debugGlassCopies = false;
    await tester.pumpWidget(_scene());
    await tester.pump();
    final reading = await _pixels(tester);
    expect(_liveFilters(tester), isNotEmpty);

    debugGlassCopies = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_scene(shift: 0.3));
    expect(_glass(tester).debugDrewOverCopy, isTrue);
    await tester.pumpWidget(_scene());
    expect(_glass(tester).debugDrewOverCopy, isTrue);
    expect(_liveFilters(tester), isEmpty);
    expect(_difference(reading, await _pixels(tester)), lessThanOrEqualTo(1));
  }, skip: skipProperGlassTests);

  testWidgets('glass reads its backdrop over a layer the copy cannot draw', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_scene(platformView: true));
    expect(_glass(tester).debugDrewOverCopy, isFalse);
    expect(_liveFilters(tester), isNotEmpty);
  }, skip: skipProperGlassTests);

  testWidgets('glass over what a follower paints draws over its copy, as '
      'reading the backdrop draws it', (tester) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    debugGlassCopies = false;
    await tester.pumpWidget(_scene(follower: true));
    await tester.pump();
    final reading = await _pixels(tester);

    debugGlassCopies = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_scene(follower: true, dot: 1));
    await tester.pumpWidget(_scene(follower: true));
    expect(_glass(tester).debugDrewOverCopy, isTrue);
    expect(_liveFilters(tester), isEmpty);
    expect(_difference(reading, await _pixels(tester)), lessThanOrEqualTo(1));
  }, skip: skipProperGlassTests);

  testWidgets('glass over a follower draws over a copy taken where the '
      'leader is in that frame', (tester) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    debugGlassCopies = false;
    await tester.pumpWidget(_scene(follower: true, leader: 70));
    await tester.pump();
    final reading = await _pixels(tester);

    debugGlassCopies = true;
    await tester.pumpWidget(const SizedBox());
    final watch = PlanWatch();
    await tester.pumpWidget(_scene(follower: true, dot: 1));
    await tester.pumpWidget(_scene(follower: true));
    final captures = watch.changes(_glass(tester));
    // One frame: the leader moves and the copy is taken under the follower
    // where it lands.
    await tester.pumpWidget(_scene(follower: true, leader: 70));
    expect(watch.changes(_glass(tester)), captures + 1);
    expect(_glass(tester).debugDrewOverCopy, isTrue);
    expect(_difference(reading, await _pixels(tester)), lessThanOrEqualTo(1));
  }, skip: skipProperGlassTests);

  testWidgets('glass under a follower draws over a copy taken where it '
      'lands in the frame its leader moves', (tester) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    debugGlassCopies = false;
    await tester.pumpWidget(
      _scene(follower: true, glassFollows: true, leader: 40),
    );
    await tester.pump();
    final reading = await _pixels(tester);

    debugGlassCopies = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_scene(follower: true, glassFollows: true, dot: 1));
    await tester.pumpWidget(_scene(follower: true, glassFollows: true));
    expect(_glass(tester).debugDrewOverCopy, isTrue);
    await tester.pumpWidget(
      _scene(follower: true, glassFollows: true, leader: 40),
    );
    expect(_glass(tester).debugDrewOverCopy, isTrue);
    expect(_difference(reading, await _pixels(tester)), lessThanOrEqualTo(1));
  }, skip: skipProperGlassTests);

  testWidgets('glass in a fading group draws over its copy and leaves the '
      'group unseeded', (tester) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_scene(opacity: 0.6));
    expect(_glass(tester).debugDrewOverCopy, isTrue);
    expect(_liveFilters(tester), isEmpty);

    await tester.pumpWidget(_scene(opacity: 0.6, platformView: true));
    expect(_glass(tester).debugDrewOverCopy, isFalse);
    expect(
      tester.layers.whereType<OpacitySeedLayer>().single.seeded,
      isTrue,
    );
  }, skip: skipProperGlassTests);

  testWidgets('motion away from the glass keeps the copy', (tester) async {
    copyIntoImages();
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final watch = PlanWatch();
    await tester.pumpWidget(_scene());
    await _settle(tester);
    final captures = watch.changes(_glass(tester));
    for (var i = 0; i < 10; i++) {
      await tester.pumpWidget(_scene(dot: 20.0 + i));
      expect(_glass(tester).debugDrewOverCopy, isTrue);
    }
    expect(watch.changes(_glass(tester)), captures);
  }, skip: skipProperGlassTests);

  testWidgets('glass draws over its copy above a shader mask', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_scene(mask: true));
    await tester.pumpWidget(_scene(mask: true, shift: 0.3));
    expect(_glass(tester).debugDrewOverCopy, isTrue);
    expect(_liveFilters(tester), isEmpty);
  }, skip: skipProperGlassTests);

  testWidgets('frosted glass stretched along the axes draws over its copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_scene(frost: 6, scaleX: 1.2, scaleY: 0.8));
    await tester.pumpWidget(
      _scene(frost: 6, scaleX: 1.2, scaleY: 0.8, shift: 0.3),
    );
    expect(_glass(tester).debugDrewOverCopy, isTrue);
    expect(_liveFilters(tester), isEmpty);
  }, skip: skipProperGlassTests);

  testWidgets('mirrored glass reads its backdrop', (tester) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_scene(frost: 6, scaleX: -1));
    await tester.pumpWidget(_scene(frost: 6, scaleX: -1, shift: 0.3));
    expect(_glass(tester).debugDrewOverCopy, isFalse);
    expect(_liveFilters(tester), isNotEmpty);
  }, skip: skipProperGlassTests);

  testWidgets('content clipped away at the edge of the band is left out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_scene(clipped: true));
    await tester.pumpWidget(_scene(clipped: true, shift: 0.3));
    expect(_glass(tester).debugDrewOverCopy, isTrue);
    expect(_liveFilters(tester), isEmpty);
  }, skip: skipProperGlassTests);

  testWidgets('glass outside its clip reads no backdrop', (tester) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: 60,
              height: 60,
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 200,
                      top: 20,
                      width: 50,
                      height: 40,
                      child: LiquidGlassLayer(
                        settings: LiquidGlassSettings.ios27RegularLight(),
                        child: const LiquidGlass(
                          shape: LiquidRoundedSuperellipse(borderRadius: 20),
                          child: SizedBox.expand(),
                        ),
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
    expect(_glass(tester).debugFate, isA<HiddenFate>());
    expect(_liveFilters(tester), isEmpty);
  }, skip: skipProperGlassTests);

  testWidgets('an image taken between frames leaves the next frame to copy '
      'what it changed', (tester) async {
    tester.view.physicalSize = const Size(260, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final watch = PlanWatch();
    await tester.pumpWidget(_pairScene());
    await tester.pumpWidget(_pairScene());
    RenderLiquidGlassLayer second() => tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .last;
    tester
        .renderObject<RenderRepaintBoundary>(find.byKey(_first))
        .toImageSync()
        .dispose();
    final captures = watch.changes(second());
    // The first glass leaves the screen and copies nothing: the second is
    // the first to copy in the frame.
    await tester.pumpWidget(_pairScene(shift: 0.3, top: -400));
    expect(second().debugDrewOverCopy, isTrue);
    expect(watch.changes(second()), captures + 1);
  }, skip: skipProperGlassTests);

  testWidgets('copies redrawn in one frame share one image', (tester) async {
    copyIntoImages();
    tester.view.physicalSize = const Size(260, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_scene(pair: true, shift: 0.3));
    final drawn = GlassCopies.debugImagesDrawn;
    await tester.pumpWidget(_scene(pair: true));
    expect(GlassCopies.debugImagesDrawn, drawn + 1);
    final glass = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .toList();
    expect(glass, hasLength(2));
    expect(glass.every((g) => g.debugDrewOverCopy), isTrue);
    expect(_liveFilters(tester), isEmpty);
    final [a, b] = [for (final g in glass) g.debugPage!.image];
    expect(a.isCloneOf(b), isTrue);
  }, skip: skipProperGlassTests);

  // Glass over glass is drawn into its page once the page under it is there,
  // so it takes an image of its own.
  for (final (top, images) in [(160.0, 1), (200.0, 2)]) {
    testWidgets('glass beside glass copies in the same image, glass over '
        'glass in one more, drawing that glass in (top $top)', (
      tester,
    ) async {
      copyIntoImages();
      tester.view.physicalSize = const Size(260, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_pairScene(shift: 0.3, top: top));
      final drawn = GlassCopies.debugImagesDrawn;
      await tester.pumpWidget(_pairScene(top: top));
      expect(GlassCopies.debugImagesDrawn, drawn + images);
      final glass = tester.allRenderObjects
          .whereType<RenderLiquidGlassLayer>()
          .toSet();
      expect(glass, hasLength(2));
      expect(glass.every((g) => g.debugDrewOverCopy), isTrue);
    }, skip: skipProperGlassTests);
  }

  testWidgets('a copy over glass whose copy is drawn in the same image '
      'holds what reading the backdrop draws there', (tester) async {
    copyIntoImages();
    tester.view.physicalSize = const Size(260, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // flutter_tester renders only a process's first backdrop filter
    // reliably, so the reference reads the backdrop first: the lower glass
    // alone, as the upper glass's copy should hold it.
    debugGlassCopies = false;
    await tester.pumpWidget(_pairScene(top: 200, second: false));
    final reading = await _pixels(tester);
    debugGlassCopies = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_pairScene(shift: 0.3, top: 200));
    await tester.pumpWidget(_pairScene(top: 200));
    final upper = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .map((g) => g.debugPage!)
        .reduce((a, b) => a.rect.bottom > b.rect.bottom ? a : b);
    final rect = upper.rect;
    final offset = upper.debugOffset;
    final image = upper.image;
    final bytes = (await tester.runAsync(image.toByteData))!.buffer
        .asUint8List();
    var largest = 0;
    for (var y = 0; y < rect.height.round(); y++) {
      for (var x = 0; x < rect.width.round(); x++) {
        final copied =
            ((offset.dy.round() + y) * image.width + offset.dx.round() + x) * 4;
        final read = ((rect.top.round() + y) * 260 + rect.left.round() + x) * 4;
        for (var c = 0; c < 4; c++) {
          final d = (bytes[copied + c] - reading[read + c]).abs();
          if (d > largest) largest = d;
        }
      }
    }
    // Without the lower glass the copy differs by 89 levels.
    expect(largest, lessThanOrEqualTo(4));
  }, skip: skipProperGlassTests);

  testWidgets('a copy drawn in the frame over glass whose copy is an image '
      'loses nothing under it', (
    tester,
  ) async {
    debugGlassCopies = true;
    tester.view.physicalSize = const Size(260, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget layer(LiquidGlassSettings settings, Rect rect) => LiquidGlassLayer(
      settings: settings,
      child: Stack(
        children: [
          Positioned.fromRect(
            rect: rect,
            child: const LiquidGlass(
              shape: LiquidRoundedSuperellipse(borderRadius: 28),
              child: SizedBox.expand(),
            ),
          ),
        ],
      ),
    );

    // Frosted glass stretched past 5 % keeps the blur in its copy, which is
    // an image; unfrosted glass above it copies in the frame.
    Widget scene(Color page) => Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: _key,
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(child: ColoredBox(color: page)),
            ),
            Positioned.fill(
              child: Transform(
                transform: Matrix4.diagonal3Values(1, 1.2, 1),
                child: layer(
                  LiquidGlassSettings.ios27RegularLight().copyWith(frost: 8),
                  const Rect.fromLTWH(30, 40, 200, 90),
                ),
              ),
            ),
            Positioned.fill(
              child: layer(
                LiquidGlassSettings.ios27RegularLight().copyWith(frost: 0),
                const Rect.fromLTWH(80, 60, 100, 60),
              ),
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(scene(const Color(0xFF3B82F6)));
    await tester.pumpWidget(scene(const Color(0xFFF59E0B)));
    final pixels = await _pixels(tester);
    const center = (90 * 260 + 130) * 4;
    expect(pixels[center], greaterThan(150));
    expect(pixels[center + 1], greaterThan(90));
  }, skip: skipProperGlassTests);

  testWidgets('copies of glass side by side share an image and draw what '
      'reading the backdrop draws', (tester) async {
    copyIntoImages();
    tester.view.physicalSize = const Size(260, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<Uint8List> draw() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_pairScene(top: 160, apart: true));
      return _pixels(tester);
    }

    // flutter_tester renders only a process's first backdrop filter
    // reliably, so the reference reads the backdrop first.
    debugGlassCopies = false;
    final reading = await draw();
    debugGlassCopies = true;
    final together = await draw();
    final glass = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .toList();
    expect(glass.every((g) => g.debugDrewOverCopy), isTrue);
    final [a, b] = [for (final g in glass) g.debugPage!.image];
    expect(a.isCloneOf(b), isTrue);
    expect(_difference(reading, together), lessThanOrEqualTo(3));
  }, skip: skipProperGlassTests);

  testWidgets('frosted copies apart are blurred in one layer and draw what '
      'reading the backdrop draws', (tester) async {
    tester.view.physicalSize = const Size(520, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(() => debugGlassCopies = null);
    GlassCopyTuning.debugOverride(shaderFrost: false);
    addTearDown(GlassCopyTuning.debugOverride);

    debugGlassCopies = false;
    await tester.pumpWidget(_pairScene(frost: 6));
    final reading = await _pixels(tester, pixelRatio: 2);
    debugGlassCopies = true;
    await tester.pumpWidget(const SizedBox());
    final layers = GlassCopies.debugBlurLayers;
    await tester.pumpWidget(_pairScene(frost: 6));
    expect(GlassCopies.debugBlurLayers, layers + 1);
    final [a, b] = [
      for (final g
          in tester.allRenderObjects
              .whereType<RenderLiquidGlassLayer>()
              .toSet())
        g.debugPage!.image,
    ];
    expect(a.isCloneOf(b), isTrue);
    expect(
      _difference(reading, await _pixels(tester, pixelRatio: 2)),
      lessThanOrEqualTo(2),
    );
  }, skip: skipProperGlassTests);

  testWidgets('frosted copies the shader frosts take no blur layer and draw '
      'near what reading the backdrop draws', (tester) async {
    tester.view.physicalSize = const Size(520, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(() => debugGlassCopies = null);

    debugGlassCopies = false;
    await tester.pumpWidget(_pairScene(frost: 6));
    final reading = await _pixels(tester, pixelRatio: 2);
    debugGlassCopies = true;
    await tester.pumpWidget(const SizedBox());
    final layers = GlassCopies.debugBlurLayers;
    await tester.pumpWidget(_pairScene(frost: 6));
    expect(GlassCopies.debugBlurLayers, layers);
    expect(
      _difference(reading, await _pixels(tester, pixelRatio: 2)),
      // NEAR, see GlassCopyTuning.shaderFrost.
      lessThanOrEqualTo(24),
    );
  }, skip: skipProperGlassTests);

  testWidgets('glass over its copy lays its shadows under it, whole, and '
      'draws what its shadows cut outside it draw', (tester) async {
    tester.view.physicalSize = const Size(520, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(() => debugGlassCopies = null);
    List<bool> under() => [
      for (final g
          in tester.allRenderObjects
              .whereType<RenderLiquidGlassLayer>()
              .toSet())
        g.debugShadowsUnderGlass,
    ];

    debugGlassCopies = false;
    await tester.pumpWidget(_pairScene(top: 160, shadowed: true));
    expect(under(), [false, false]);
    final cut = await _pixels(tester, pixelRatio: 2);
    debugGlassCopies = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_pairScene(top: 160, shadowed: true));
    expect(under(), [true, true]);
    final whole = await _pixels(tester, pixelRatio: 2);
    // The cut reached half a pixel into the glass's edge: only along the
    // edge do the two differ.
    bool nearEdge(Offset point) =>
        [
          const Rect.fromLTWH(30, 160, 200, 90),
          const Rect.fromLTWH(30, 260, 200, 60),
        ].any((rect) {
          final outer = rect.inflate(1.5);
          if (!outer.contains(point)) return false;
          const radius = 28.0;
          return RSuperellipse.fromRectAndRadius(
                outer,
                const Radius.circular(radius + 1.5),
              ).contains(point) &&
              !RSuperellipse.fromRectAndRadius(
                rect.deflate(1.5),
                const Radius.circular(radius - 1.5),
              ).contains(point);
        });
    var away = 0;
    for (var i = 0; i < cut.length; i++) {
      final pixel = i ~/ 4;
      final point = Offset(pixel % 520 / 2, pixel ~/ 520 / 2);
      final difference = (cut[i] - whole[i]).abs();
      if (difference > away && !nearEdge(point)) away = difference;
    }
    expect(away, lessThanOrEqualTo(3));
  }, skip: skipProperGlassTests);

  testWidgets('an island holds while what lies under it is unchanged and '
      'is recorded again, once, when it changes', (tester) async {
    copyIntoImages();
    tester.view.physicalSize = const Size(260, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugGlassCopies = true;
    addTearDown(() => debugGlassCopies = null);
    List<RenderLiquidGlassLayer> glass() => tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .toList();
    final watch = PlanWatch();
    await tester.pumpWidget(_pairScene(top: 160, apart: true));
    final captures = [for (final g in glass()) watch.changes(g)];
    final drawn = GlassCopies.debugImagesDrawn;

    tester.binding.scheduleFrame();
    await tester.pump();
    expect([for (final g in glass()) watch.changes(g)], captures);
    expect(GlassCopies.debugImagesDrawn, drawn);

    await tester.pumpWidget(_pairScene(top: 160, shift: 0.3, apart: true));
    expect(
      [for (final g in glass()) watch.changes(g)],
      [for (final c in captures) c + 1],
    );
    expect(GlassCopies.debugImagesDrawn, drawn + 1);
    final [a, b] = [for (final g in glass()) g.debugPage!.image];
    expect(a.isCloneOf(b), isTrue);
  }, skip: skipProperGlassTests);

  testWidgets('copies planned as an island hold while what lies under them '
      'is unchanged, when something painted between their glass keeps the '
      'second out of it', (tester) async {
    copyIntoImages();
    tester.view.physicalSize = const Size(260, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugGlassCopies = true;
    addTearDown(() => debugGlassCopies = null);
    List<RenderLiquidGlassLayer> glass() => tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .toList();
    final watch = PlanWatch();
    await tester.pumpWidget(_pairScene(top: 160, between: true));
    expect(glass().every((g) => g.debugDrewOverCopy), isTrue);
    final captures = [for (final g in glass()) watch.changes(g)];
    final drawn = GlassCopies.debugImagesDrawn;

    for (var i = 0; i < 3; i++) {
      tester.binding.scheduleFrame();
      await tester.pump();
    }
    expect([for (final g in glass()) watch.changes(g)], captures);
    expect(GlassCopies.debugImagesDrawn, drawn);
    expect(glass().every((g) => g.debugDrewOverCopy), isTrue);
  }, skip: skipProperGlassTests);

  testWidgets('glass whose shadow paints between it and the next glass '
      'still shares an image with it', (tester) async {
    copyIntoImages();
    tester.view.physicalSize = const Size(260, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugGlassCopies = true;
    addTearDown(() => debugGlassCopies = null);
    final drawn = GlassCopies.debugImagesDrawn;
    await tester.pumpWidget(_pairScene(top: 160, shadowed: true));
    expect(GlassCopies.debugImagesDrawn, drawn + 1);
  }, skip: skipProperGlassTests);
}

class _PlatformView extends PlatformViewController {
  @override
  int get viewId => 1;

  @override
  Future<void> dispatchPointerEvent(PointerEvent event) async {}

  @override
  Future<void> clearFocus() async {}

  @override
  Future<void> dispose() async {}
}
