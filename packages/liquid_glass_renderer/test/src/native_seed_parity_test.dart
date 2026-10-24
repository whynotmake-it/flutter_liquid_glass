import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/backdrop_seed.dart';

import 'shared.dart';
import 'submitted_scene_binding.dart';

// Native seeds (liquidGlassNativeSeed) against the plain native path (`none`),
// for real and fake glass.
//
// A seed puts the glass in a small pass that Impeller seeds from the backdrop,
// so its blur only covers the pass. The result must be the glass the plain
// path draws, up to antialiasing and blur-quality noise: the budget below is
// what the measured differences allow. Seeds that share a backdrop key read
// the backdrop as it was at the first of them, so a seed shares one only with
// seeds nothing can change what it reads in between: the scenes that put
// something in between check that they are kept apart.
late final SubmittedSceneCapture binding;

const _logical = Size(400, 400);

/// What a seed may differ from the plain path by: the largest per-channel
/// level anywhere, and the mean over the whole image.
///
/// Real glass differs by quantization only (at most 3 levels). Fake glass
/// differs where a clip path is antialiased: its pass cuts the effect to the
/// outline by clearing what lies outside it, and on the long, nearly flat
/// stretches of an outline a few dozen edge pixels land a coverage step
/// (quarter sample) away from where the clip puts them, up to ~80 levels in
/// the worst of them. So the budget for fake glass allows those edge pixels
/// and holds the rest to blur-quality noise through the mean and the count of
/// pixels over 8.
const _realMax = 8;
const _realMean = 0.1;
const _fakeMax = 96;
const _fakeMean = 0.35;
const _fakeOver8Fraction = 0.002;

void main() {
  runNativeSeedParityTests(SubmittedSceneBinding());
}

/// Shared host/device workload; the device binding must capture submitted
/// scenes (see [SubmittedSceneCapture]).
void runNativeSeedParityTests(TestWidgetsFlutterBinding testBinding) {
  binding = testBinding as SubmittedSceneCapture;
  late LiquidGlassNativeSeed originalSeed;
  setUp(() => originalSeed = liquidGlassNativeSeed);
  tearDown(() => liquidGlassNativeSeed = originalSeed);

  /// Renders [scene] with seeds off and with [mode], and requires the seeded
  /// frames to match the plain ones within the budget of real or fake glass.
  Future<({_Run plain, _Run seeded, _Diff worst})> compare(
    WidgetTester tester,
    Widget Function(ValueNotifier<int> tick) scene, {
    required LiquidGlassNativeSeed mode,
    required bool fake,
    double dpr = 2,
    Size logical = _logical,
    int frames = 1,
  }) async {
    final plain = await _run(
      tester,
      scene,
      seed: LiquidGlassNativeSeed.none,
      dpr: dpr,
      logical: logical,
      frames: frames,
    );
    final seeded = await _run(
      tester,
      scene,
      seed: mode,
      dpr: dpr,
      logical: logical,
      frames: frames,
    );
    final worst = _Diff.worst(plain, seeded);
    expect(worst.alphaMax, 0, reason: 'the scene is opaque');
    expect(worst.max, lessThanOrEqualTo(fake ? _fakeMax : _realMax));
    expect(worst.mean, lessThan(fake ? _fakeMean : _realMean));
    final over8 = worst.over8;
    if (fake) {
      expect(
        over8,
        lessThan(plain.frames.first.length / 4 * 3 * _fakeOver8Fraction),
      );
    } else {
      expect(over8, 0);
    }
    return (plain: plain, seeded: seeded, worst: worst);
  }

  const modes = [LiquidGlassNativeSeed.identity, LiquidGlassNativeSeed.blur];

  for (final scene in _Scene.values) {
    for (final fake in [false, true]) {
      for (final dpr in [2.0, 2.625]) {
        // Without a blur there is nothing to seed: one scene shows that.
        for (final frost in scene == _Scene.pill ? [0.0, 8.0] : [8.0]) {
          for (final mode in modes) {
            testWidgets(
              '${scene.name} ${fake ? 'fake' : 'real'} dpr=$dpr '
              'frost=$frost ${mode.name}',
              (tester) async {
                final result = await compare(
                  tester,
                  (_) => _glassScene(scene, fake: fake, frost: frost),
                  mode: mode,
                  fake: fake,
                  dpr: dpr,
                );
                final expectSeeds = frost > 0;
                expect(
                  result.seeded.seeded,
                  expectSeeds ? scene.seeds : 0,
                  reason: 'seeded passes of ${result.seeded.passes}',
                );
                if (!expectSeeds) {
                  expect(result.worst.max, 0, reason: 'nothing to seed');
                }
                // Seeds that cannot see each other's glass share one key.
                expect(
                  result.seeded.distinctKeys,
                  expectSeeds ? scene.keys : 0,
                  reason: 'distinct seed keys of ${result.seeded.passes}',
                );
              },
              skip: skipProperGlassTests,
            );
          }
        }
      }
    }
  }

  // The backdrop changes under glass whose pass the compositor retains
  // between frames: the seed must read the fresh backdrop each time.
  for (final fake in [false, true]) {
    for (final mode in modes) {
      testWidgets(
        'a seed follows a changing backdrop frame by frame '
        '(${fake ? 'fake' : 'real'}, ${mode.name})',
        (tester) async {
          final result = await compare(
            tester,
            (tick) => Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(child: CustomPaint(painter: _Moving(tick))),
                _glassScene(_Scene.pill, fake: fake, frost: 8),
              ],
            ),
            mode: mode,
            fake: fake,
            dpr: 2.625,
            frames: 4,
          );
          // The frames themselves differ from each other.
          expect(
            _Diff.of(
              result.plain.frames.first,
              result.plain.frames.last,
            ).max,
            greaterThan(40),
          );
        },
        skip: !fake && skipProperGlassTests,
      );
    }
  }

  // Real glass placed at a fractional device-pixel offset must match the plain
  // render at antialiasing level. An offset of exactly half a device pixel on
  // an axis puts every fragment centre on a texel boundary of the nearest-
  // sampled glass matte; the renderer biases the matte mapping by a fixed
  // sub-texel amount so those ties resolve the same way in the root pass and
  // in a seeded pass.
  for (final dpr in [2.0, 2.625]) {
    for (final pill in [true, false]) {
      for (final (fx, fy) in [(0.0, 0.0), (0.5, 0.0), (0.0, 0.5), (0.5, 0.5)]) {
        testWidgets(
          '${pill ? 'pill' : 'rrect'} at a fractional offset dpr=$dpr '
          'fx=$fx fy=$fy',
          (tester) async {
            final result = await compare(
              tester,
              (tick) => Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(painter: _Background(tick)),
                  ),
                  Positioned(
                    // Device pixels, so the offsets are fractions of one.
                    left: (100 + fx) / dpr,
                    top: (300 + fy) / dpr,
                    child: LiquidGlassLayer(
                      settings: const LiquidGlassSettings(
                        frost: 6,
                        refractionAmount: 20,
                      ),
                      child: LiquidGlass(
                        shape: LiquidRoundedRectangle(
                          borderRadius: pill ? 32 : 14,
                        ),
                        child: const SizedBox(width: 200, height: 64),
                      ),
                    ),
                  ),
                ],
              ),
              mode: LiquidGlassNativeSeed.blur,
              fake: false,
              dpr: dpr,
              logical: const Size(400, 300),
              frames: 4,
            );
            expect(result.seeded.seeded, 1, reason: 'the glass is seeded');
            expect(result.worst.mean, lessThan(0.05));
          },
          skip: skipProperGlassTests,
        );
      }
    }
  }

  // What a seed assumes about the layer tree around it: its pass is planned
  // from the transforms above it, and those can change in a single frame.
  group('transforms that change in a single frame', () {
    const glass = LiquidGlassLayer(
      fake: true,
      settings: LiquidGlassSettings(frost: 6),
      child: LiquidGlass(
        shape: LiquidRoundedSuperellipse(borderRadius: 20),
        child: SizedBox(width: 60, height: 50),
      ),
    );

    Widget red(double width, double height) => RepaintBoundary(
      child: SizedBox(
        width: width,
        height: height,
        child: const ColoredBox(color: Color(0xFFFF0000)),
      ),
    );

    testWidgets('a TransformLayer matrix', (tester) async {
      final result = await compare(
        tester,
        (tick) => Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFFFFFFFF)),
            Positioned(
              left: 0,
              top: 0,
              child: ValueListenableBuilder<int>(
                valueListenable: tick,
                builder: (_, step, _) => Transform.scale(
                  scale: step == 0 ? 1.5 : 2.5,
                  alignment: Alignment.topLeft,
                  child: red(60, 80),
                ),
              ),
            ),
            const Positioned(left: 100, top: 80, child: glass),
          ],
        ),
        mode: LiquidGlassNativeSeed.blur,
        fake: true,
        dpr: 1,
        logical: const Size(500, 320),
      );
      expect(result.seeded.seeded, 1);
    });

    testWidgets('a TransformLayer above the glass', (tester) async {
      final result = await compare(
        tester,
        (tick) => ValueListenableBuilder<int>(
          valueListenable: tick,
          builder: (_, step, _) => Transform.scale(
            scale: step == 0 ? 1 : 2,
            alignment: Alignment.topLeft,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: ColoredBox(color: Color(0xFFFFFFFF)),
                ),
                Positioned(left: 90, top: 70, child: red(80, 40)),
                const Positioned(left: 100, top: 80, child: glass),
              ],
            ),
          ),
        ),
        mode: LiquidGlassNativeSeed.blur,
        fake: true,
        dpr: 1,
        logical: const Size(500, 320),
      );
      expect(result.seeded.seeded, 1);
    });
  });

  // Seeds share one backdrop read, so a seed must not join one when something
  // painted after the first seed changes what it reads. The box paints well
  // past its 20 px bounds, over the second glass.
  group('content painted between two seeds', () {
    Widget pill(double left, double top) => Positioned(
      left: left,
      top: top,
      child: const LiquidGlass.withOwnLayer(
        fake: true,
        settings: LiquidGlassSettings(frost: 8, refractionAmount: 24),
        shape: _pill,
        child: SizedBox(width: 200, height: 64),
      ),
    );

    const overflowing = Positioned(
      left: 380,
      top: 234,
      child: RepaintBoundary(
        child: SizedBox(
          width: 20,
          height: 20,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -260,
                top: 0,
                width: 40,
                height: 40,
                child: ColoredBox(color: Color(0xFFFF0000)),
              ),
            ],
          ),
        ),
      ),
    );

    testWidgets(
      'keeps their seeds apart, and the glass draws what the plain path does',
      (tester) async {
        final result = await compare(
          tester,
          (_) => Stack(
            fit: StackFit.expand,
            children: [pill(70, 60), overflowing, pill(100, 234)],
          ),
          mode: LiquidGlassNativeSeed.blur,
          fake: true,
        );
        expect(result.seeded.seeded, 2);
        expect(result.seeded.distinctKeys, 2);
      },
    );
  });

  // Glass that declares one backdrop key (a BackdropGroup or a shared
  // backdropKey) keeps it for its seed. flutter_tester renders any pass nested
  // in a keyed backdrop filter wrongly, so the pixels are compared on a device
  // only.
  for (final variant in ['BackdropGroup', 'BackdropKey']) {
    testWidgets(
      'two glass layers sharing a $variant draw what the plain path draws',
      (tester) async {
        final key = BackdropKey();
        Widget layer(double left, double top) => Positioned(
          left: left,
          top: top,
          child: LiquidGlassLayer(
            fake: true,
            useBackdropGroup: variant == 'BackdropGroup',
            backdropKey: variant == 'BackdropKey' ? key : null,
            settings: const LiquidGlassSettings(frost: 6),
            child: const LiquidGlass(
              shape: LiquidRoundedSuperellipse(borderRadius: 20),
              child: SizedBox(width: 60, height: 50),
            ),
          ),
        );
        final result = await compare(
          tester,
          (_) => Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFFFF0040),
                      Color(0xFF00D060),
                      Color(0xFF0060FF),
                    ],
                  ),
                ),
              ),
              if (variant == 'BackdropGroup')
                BackdropGroup(
                  child: Stack(children: [layer(10, 20), layer(240, 200)]),
                )
              else
                Stack(children: [layer(10, 20), layer(240, 200)]),
            ],
          ),
          mode: LiquidGlassNativeSeed.blur,
          fake: true,
        );
        expect(result.seeded.seeded, 2);
        expect(result.seeded.distinctKeys, 1);
      },
      skip: binding.isFlutterTester,
    );
  }

  // A native filter of the same key (a BackdropFilter.grouped in the key's
  // BackdropGroup) shares the glass's key too: the seed keeps it.
  for (final nativeSharer in [true, false]) {
    testWidgets(
      'a seed keeps the key of its glass '
      '(a native filter shares it: $nativeSharer)',
      (tester) async {
        final key = BackdropKey();
        final result = await compare(
          tester,
          (_) => Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: 90,
                top: 70,
                child: Container(
                  width: 80,
                  height: 40,
                  color: const Color(0xFFFF0000),
                ),
              ),
              Positioned(
                left: 100,
                top: 80,
                child: LiquidGlassLayer(
                  fake: true,
                  useBackdropGroup: true,
                  backdropKey: key,
                  settings: const LiquidGlassSettings(frost: 6),
                  child: const LiquidGlass(
                    shape: LiquidRoundedSuperellipse(borderRadius: 20),
                    child: SizedBox(width: 60, height: 50),
                  ),
                ),
              ),
              if (nativeSharer)
                Positioned(
                  left: 300,
                  top: 150,
                  width: 60,
                  height: 40,
                  child: BackdropGroup(
                    backdropKey: key,
                    child: ClipRect(
                      child: BackdropFilter.grouped(
                        filter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          mode: LiquidGlassNativeSeed.blur,
          fake: true,
          dpr: 1,
        );
        expect(result.seeded.seeded, 1);
        expect(result.seeded.distinctKeys, 1);
      },
    );
  }
}

enum _Scene {
  pill(1, 1),
  blendGroup(1, 1),
  // Clear of each other: one backdrop read.
  apart(2, 1),
  // Their halos overlap, or one is on the other: one read each.
  near(2, 2),
  overlapping(2, 2),
  fading(1, 1),
  // A glass without a blur on a blurred one is not seeded, and reads the
  // seeded glass.
  indicator(1, 1);

  const _Scene(this.seeds, this.keys);

  /// How many seeded passes the scene has with a blur.
  final int seeds;

  /// How many distinct backdrop keys those passes are pushed with.
  final int keys;
}

const _pill = LiquidRoundedSuperellipse(borderRadius: 32);

Widget _glassScene(
  _Scene scene, {
  required bool fake,
  required double frost,
}) {
  final settings = LiquidGlassSettings(
    frost: frost,
    refractionAmount: 24,
  );
  Widget own(double left, double top) => Positioned(
    left: left,
    top: top,
    child: LiquidGlass.withOwnLayer(
      fake: fake,
      settings: settings,
      shape: _pill,
      child: const SizedBox(width: 200, height: 64),
    ),
  );
  switch (scene) {
    case _Scene.pill:
      return Center(
        child: LiquidGlassLayer(
          fake: fake,
          settings: settings,
          child: const LiquidGlass(
            shape: _pill,
            child: SizedBox(width: 220, height: 64),
          ),
        ),
      );
    case _Scene.fading:
      return Center(
        child: LiquidGlassVisibility(
          visibility: 0.5,
          child: LiquidGlassLayer(
            fake: fake,
            settings: settings,
            child: const LiquidGlass(
              shape: _pill,
              child: SizedBox(width: 220, height: 64),
            ),
          ),
        ),
      );
    case _Scene.blendGroup:
      return Center(
        child: LiquidGlassLayer(
          fake: fake,
          settings: settings,
          child: LiquidGlassBlendGroup(
            blend: 28,
            child: SizedBox(
              width: 340,
              height: 120,
              child: Stack(
                children: [
                  for (var i = 0; i < 5; i++)
                    Positioned(
                      left: i * 62.0,
                      top: i.isEven ? 8 : 44,
                      child: LiquidGlass.grouped(
                        shape: i.isEven
                            ? const LiquidOval()
                            : const LiquidRoundedSuperellipse(borderRadius: 22),
                        child: const SizedBox(width: 84, height: 64),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    case _Scene.apart:
      return Stack(children: [own(70, 60), own(100, 234)]);
    case _Scene.indicator:
      return Center(
        child: LiquidGlassLayer(
          fake: fake,
          settings: settings,
          child: LiquidGlass(
            shape: _pill,
            child: SizedBox(
              width: 220,
              height: 64,
              child: Align(
                alignment: const Alignment(0.6, 0),
                child: LiquidGlassLayer(
                  fake: fake,
                  settings: const LiquidGlassSettings(
                    frost: 0,
                    refractionAmount: 24,
                    backdropShrink: 0.08,
                    highlight: 0.4,
                  ),
                  child: const LiquidGlass(
                    shape: LiquidRoundedSuperellipse(borderRadius: 22),
                    child: SizedBox(width: 70, height: 44),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    case _Scene.near:
    case _Scene.overlapping:
      // The glass is 64 high, and its blur reaches 25 past it: `near` leaves
      // the shapes apart but their halos overlapping, `overlapping` stacks
      // the second on the first. The second reads the first's glass, so it
      // cannot share the first's backdrop read.
      return Stack(
        children: [
          own(70, 60),
          if (scene == _Scene.near) own(100, 136) else own(130, 104),
        ],
      );
  }
}

class _Run {
  _Run(
    this.frames,
    this.width, {
    required this.passes,
    required this.seeded,
    required this.distinctKeys,
  });

  /// The captured RGBA frames.
  final List<Uint8List> frames;
  final int width;

  /// Of the last frame: the pass layers, the seeded ones, and the distinct
  /// backdrop keys the seeds are pushed with.
  final int passes;
  final int seeded;
  final int distinctKeys;
}

/// Renders [scene] with [seed] and captures [frames] frames, setting the
/// scene's tick to the frame's number before each.
Future<_Run> _run(
  WidgetTester tester,
  Widget Function(ValueNotifier<int> tick) scene, {
  required LiquidGlassNativeSeed seed,
  required double dpr,
  required Size logical,
  required int frames,
}) async {
  liquidGlassNativeSeed = seed;
  final w = (logical.width * dpr).round();
  final h = (logical.height * dpr).round();
  binding
    ..captureWidth = w
    ..captureHeight = h;
  tester.view
    ..physicalSize = Size(w.toDouble(), h.toDouble())
    ..devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  final tick = ValueNotifier<int>(0);
  addTearDown(tick.dispose);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(child: CustomPaint(painter: _Detail())),
          scene(tick),
        ],
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  final images = <Uint8List>[];
  for (var i = 1; i <= frames; i++) {
    binding
      ..captured = null
      ..captureNextScene = true
      ..scheduleFrame();
    tick.value = i;
    await tester.pump();
    final image = (await tester.runAsync(() => binding.captured!))!;
    final bytes = (await tester.runAsync(image.toByteData))!;
    images.add(Uint8List.fromList(bytes.buffer.asUint8List()));
    image.dispose();
  }
  final passes = tester.binding.renderViews.single.debugLayer!
      .depthFirstIterateChildren()
      .whereType<SeededBackdropPassLayer>()
      .toList();
  final seeded = passes.where(
    (p) => p.nativeSeed != LiquidGlassNativeSeed.none,
  );
  return _Run(
    images,
    w,
    passes: passes.length,
    seeded: seeded.length,
    distinctKeys: {
      for (final p in seeded)
        if (p.debugSeedKey != null) p.debugSeedKey,
    }.length,
  );
}

class _Moving extends CustomPainter {
  _Moving(this.tick) : super(repaint: tick);
  final ValueNotifier<int> tick;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF2EFE6),
    );
    final shift = tick.value * 37.0;
    final stripe = Paint()..color = const Color(0xFF1F3A93);
    for (var x = -size.height + shift; x < size.width; x += 26) {
      canvas.drawPath(
        Path()
          ..moveTo(x, 0)
          ..lineTo(x + 10, 0)
          ..lineTo(x + 10 + size.height, size.height)
          ..lineTo(x + size.height, size.height)
          ..close(),
        stripe,
      );
    }
    canvas.drawCircle(
      Offset(60.0 + shift * 2, size.height * 0.5),
      70,
      Paint()..color = const Color(0xFFE63946),
    );
  }

  @override
  bool shouldRepaint(_Moving oldDelegate) => true;
}

/// Stripes and bars that shift a little between the first frames, over a
/// gradient.
class _Background extends CustomPainter {
  _Background(this.tick) : super(repaint: tick);
  final ValueNotifier<int> tick;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, size.height),
          const [Color(0xFF1E3A8A), Color(0xFFF59E0B)],
        ),
    );
    final paint = Paint()
      ..isAntiAlias = false
      ..color = const Color(0xCCFFFFFF);
    final shift = (math.min(tick.value, 2) * 3) % 24.0;
    for (var x = shift - 24; x < size.width; x += 24) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 6, size.height), paint);
    }
    final dark = Paint()
      ..isAntiAlias = false
      ..color = const Color(0x99000000);
    for (var y = shift * 0.5; y < size.height; y += 20) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 3), dark);
    }
  }

  @override
  bool shouldRepaint(_Background oldDelegate) => true;
}

class _Diff {
  _Diff(this.max, this.mean, this.over8, this.alphaMax);

  /// The largest difference in any frame, the largest per-frame mean, and the
  /// largest per-frame count of channels over 8 levels.
  factory _Diff.worst(_Run a, _Run b) {
    var max = 0;
    var mean = 0.0;
    var over8 = 0;
    var alphaMax = 0;
    for (var i = 0; i < a.frames.length; i++) {
      final d = _Diff.of(a.frames[i], b.frames[i]);
      max = math.max(max, d.max);
      mean = math.max(mean, d.mean);
      over8 = math.max(over8, d.over8);
      alphaMax = math.max(alphaMax, d.alphaMax);
    }
    return _Diff(max, mean, over8, alphaMax);
  }

  factory _Diff.of(Uint8List a, Uint8List b) {
    var max = 0;
    var over8 = 0;
    var sum = 0;
    var alphaMax = 0;
    for (var i = 0; i < a.length; i += 4) {
      alphaMax = math.max(alphaMax, (a[i + 3] - b[i + 3]).abs());
      for (var c = 0; c < 3; c++) {
        final d = (a[i + c] - b[i + c]).abs();
        sum += d;
        max = math.max(max, d);
        if (d > 8) over8++;
      }
    }
    return _Diff(max, sum / (a.length / 4 * 3), over8, alphaMax);
  }

  final int max;
  final double mean;
  final int over8;

  /// The largest difference in alpha: a seed that cleared the backdrop around
  /// the glass shows here, and not in the colour channels of an opaque scene.
  final int alphaMax;
}

/// Static detail under the glass: stripes, a disc and small text, so blur and
/// refraction differences show.
class _Detail extends CustomPainter {
  const _Detail();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF2EFE6),
    );
    final stripe = Paint()..color = const Color(0xFF1F3A93);
    for (var x = -size.height; x < size.width; x += 14) {
      canvas.drawPath(
        Path()
          ..moveTo(x, 0)
          ..lineTo(x + 6, 0)
          ..lineTo(x + 6 + size.height, size.height)
          ..lineTo(x + size.height, size.height)
          ..close(),
        stripe,
      );
    }
    canvas.drawCircle(
      Offset(size.width * 0.3, size.height * 0.4),
      60,
      Paint()..color = const Color(0xFFE63946),
    );
    for (var y = 6.0; y < size.height; y += 16) {
      TextPainter(
          text: TextSpan(
            text: 'Liquid glass native seed detail $y  The quick brown fox',
            style: const TextStyle(
              color: Color(0xFF111111),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )
        ..layout()
        ..paint(canvas, Offset(4, y));
    }
  }

  @override
  bool shouldRepaint(_Detail oldDelegate) => false;
}
