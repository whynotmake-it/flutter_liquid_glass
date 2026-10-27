import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/backdrop_seed.dart';
import 'package:liquid_glass_renderer/src/internal/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/internal/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

// What seeded passes (SeededBackdropPassLayer) put in the layer tree: when a
// glass gets a pass, how the pass is sized, and which seeds share a backdrop
// key.
// How they render is native_seed_parity_test.dart.
const _pill = LiquidRoundedSuperellipse(borderRadius: 32);

const _settings = LiquidGlassSettings(frost: 8, refractionAmount: 24);
const _noBlur = LiquidGlassSettings(frost: 0, refractionAmount: 24);

Widget _glass({
  bool fake = false,
  LiquidGlassSettings settings = _settings,
  BackdropKey? key,
  LiquidGlassAppearance? appearance,
}) => LiquidGlass.withOwnLayer(
  fake: fake,
  settings: settings,
  backdropKey: key,
  appearance: appearance,
  shape: _pill,
  child: const SizedBox(width: 200, height: 64),
);

Widget _scene(List<Widget> children) => Directionality(
  textDirection: TextDirection.ltr,
  child: Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: Color(0xFF204060)),
      ...children,
    ],
  ),
);

Widget _at(double left, double top, Widget child) =>
    Positioned(left: left, top: top, child: child);

List<SeededBackdropPassLayer> _passes(WidgetTester tester) {
  final passes = tester.binding.renderViews.single.debugLayer!
      .depthFirstIterateChildren()
      .whereType<SeededBackdropPassLayer>()
      .toList();
  // In paint order, which is top to bottom in these scenes.
  return passes
    ..sort((a, b) => a.plan.globalRect!.top.compareTo(b.plan.globalRect!.top));
}

/// Backdrop filters in the layer tree, not counting the composition probe's.
List<BackdropFilterLayer> _filters(WidgetTester tester) => tester
    .binding
    .renderViews
    .single
    .debugLayer!
    .depthFirstIterateChildren()
    .whereType<BackdropFilterLayer>()
    .where((layer) => layer is! OpacitySeedLayer)
    .toList();

Future<void> _pump(WidgetTester tester, Widget scene) async {
  await tester.pumpWidget(const SizedBox());
  tester.view
    ..physicalSize = const Size(800, 1600)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(scene);
  await tester.pump();
  await tester.pump();
}

double _sigmaOf(ui.ImageFilter filter) {
  final match = RegExp(
    r'ImageFilter\.blur\(([\d.]+), ',
  ).firstMatch(filter.toString());
  return double.parse(match!.group(1)!);
}

void main() {
  late BackdropSeed? originalOverride;
  setUp(() {
    originalOverride = SeededBackdropPassLayer.debugModeOverride;
    SeededBackdropPassLayer.debugModeOverride = BackdropSeed.none;
  });
  tearDown(() {
    SeededBackdropPassLayer.debugModeOverride = originalOverride;
    BackdropPassSizing.debugStabilizeLargePasses = true;
  });

  test('shared seeds differ by more than the engine tolerates as equal', () {
    // DlBlurImageFilter::equals_ compares sigmas within kEhCloseEnough (1e-3):
    // closer filters are equal, and Impeller then runs one of them over the
    // whole texture with no coverage hint.
    expect(SeededBackdropPassLayer.seedSigmaStep, greaterThan(1e-3 * 2));
    // A color matrix is compared bit for bit, so any step differs; it must
    // leave every 8 bit value alone: it adds under half a level to a full one.
    expect(SeededBackdropPassLayer.seedMatrixStep * 255, lessThan(0.5));
  });

  group('seeds', () {
    testWidgets('none adds no pass', (tester) async {
      await _pump(tester, _scene([_at(100, 300, _glass())]));
      expect(_passes(tester), isEmpty);
    }, skip: skipProperGlassTests);

    for (final fake in [false, true]) {
      testWidgets(
        'glass inside a LiquidGlassCapture reads the capture without a pass '
        '(${fake ? 'fake' : 'real'})',
        (tester) async {
          SeededBackdropPassLayer.debugModeOverride = BackdropSeed.blur;
          await _pump(
            tester,
            _scene([
              _at(100, 100, _glass(fake: fake)),
              _at(100, 400, LiquidGlassCapture(child: _glass(fake: fake))),
            ]),
          );
          // Only the glass outside the capture is seeded.
          expect(
            _passes(tester).where((p) => p.nativeSeed != BackdropSeed.none),
            hasLength(1),
          );
          expect(
            _passes(tester).single.plan.globalRect!.top,
            lessThan(400),
          );
        },
        skip: !fake && skipProperGlassTests,
      );
    }

    testWidgets('fake glass that is only a blur stays native', (tester) async {
      SeededBackdropPassLayer.debugModeOverride = BackdropSeed.identity;
      await _pump(
        tester,
        _scene([
          _at(
            100,
            300,
            _glass(fake: true, appearance: const LiquidGlassAppearance()),
          ),
        ]),
      );
      expect(_passes(tester), isEmpty);
      // Impeller crops a lone blur by itself, so nothing is added around it.
      final filters = _filters(tester);
      expect(filters, hasLength(1));
      expect(filters.single.filter.toString(), startsWith('ImageFilter.blur('));
    });

    test('a neutral fake glass filter is recognised as only a blur', () {
      final neutral = fakeGlassBackdropFilterParts(
        _settings,
        const LiquidGlassAppearance(),
      )!;
      expect(identical(neutral.withoutBlur, fakeGlassIdentityFilter), isTrue);
      final tinted = fakeGlassBackdropFilterParts(
        _settings,
        const LiquidGlassAppearance.ios27RegularLight(),
      )!;
      expect(identical(tinted.withoutBlur, fakeGlassIdentityFilter), isFalse);
    });

    for (final fake in [false, true]) {
      for (final mode in [
        BackdropSeed.identity,
        BackdropSeed.blur,
      ]) {
        testWidgets(
          '${mode.name} seeds a pass '
          '(${fake ? 'fake' : 'real'})',
          (tester) async {
            SeededBackdropPassLayer.debugModeOverride = mode;
            await _pump(
              tester,
              _scene([
                _at(
                  100,
                  300,
                  _glass(
                    fake: fake,
                    appearance: const LiquidGlassAppearance.ios27RegularLight(),
                  ),
                ),
              ]),
            );
            final pass = _passes(tester).single;
            expect(pass.active, isTrue);
            expect(pass.nativeSeed, mode);
            expect(pass.passRect, isNotNull);
            // Inside the pass: no key, and `src` so only the effect is held.
            final filter = _filters(
              tester,
            ).singleWhere((layer) => layer.blendMode == BlendMode.src);
            expect(filter.backdropKey, isNull);
            if (mode == BackdropSeed.identity) {
              // The glass filter keeps its blur.
              expect(filter.filter.toString(), contains('blur'));
              expect(pass.debugSeedFilter.toString(), contains('ColorFilter'));
            } else {
              // The seed is the blur, and the glass filter does none.
              expect(filter.filter.toString(), isNot(contains('blur')));
              expect(
                pass.debugSeedFilter.toString(),
                startsWith('ImageFilter.blur'),
              );
              expect(pass.debugSeedFilter.toString(), contains('mirror'));
            }
          },
          skip: !fake && skipProperGlassTests,
        );
      }
    }

    testWidgets('a pass in effect maps shader coordinates to its origin', (
      tester,
    ) async {
      Future<RenderLiquidGlassLayer> layerFor(
        BackdropSeed mode,
      ) async {
        SeededBackdropPassLayer.debugModeOverride = mode;
        await _pump(tester, _scene([_at(100, 300, _glass())]));
        return tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().last;
      }

      var layer = await layerFor(BackdropSeed.none);
      expect(layer.debugBackdropPassPlan.globalOrigin, isNull);
      for (final mode in [
        BackdropSeed.identity,
        BackdropSeed.blur,
      ]) {
        layer = await layerFor(mode);
        final pass = _passes(tester).single;
        final origin = layer.debugBackdropPassPlan.globalOrigin;
        expect(origin, isNotNull, reason: '$mode');
        expect(origin, pass.plan.globalRect!.topLeft);
        // The mapping the shader got is relative to that origin: moving the
        // pass origin moves the matte position it computes.
        expect(
          layer.shaderCoordinateTransform.getTranslation().x,
          closeTo(
            layer.getTransformTo(null).getTranslation().x - origin!.dx,
            1e-6,
          ),
        );
      }
    }, skip: skipProperGlassTests);

    testWidgets('a blur Impeller would not crop is seeded by identity', (
      tester,
    ) async {
      SeededBackdropPassLayer.debugModeOverride = BackdropSeed.blur;
      // At the left edge of the screen (the pass is cut there, so its padded
      // hint leaves the texture), and clear of every edge.
      await _pump(
        tester,
        _scene([
          _at(0, 100, _glass(fake: true)),
          _at(100, 500, _glass(fake: true)),
        ]),
      );
      final passes = _passes(tester);
      expect(passes[0].nativeSeed, BackdropSeed.identity);
      expect(passes[1].nativeSeed, BackdropSeed.blur);
    });

    testWidgets('a pass inside another pass is not assumed to crop', (
      tester,
    ) async {
      SeededBackdropPassLayer.debugModeOverride = BackdropSeed.blur;
      await _pump(
        tester,
        _scene([
          _at(
            100,
            300,
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAliasWithSaveLayer,
              child: _glass(fake: true),
            ),
          ),
        ]),
      );
      expect(_passes(tester).single.nativeSeed, BackdropSeed.identity);
    });

    testWidgets('a pass is seeded whatever backdrop filter paints before it', (
      tester,
    ) async {
      SeededBackdropPassLayer.debugModeOverride = BackdropSeed.identity;
      await _pump(
        tester,
        _scene([
          Positioned(
            left: 0,
            top: 280,
            width: 500,
            height: 120,
            child: ClipRect(
              child: BackdropFilter(
                filter: ColorFilter.mode(
                  Colors.red.withAlpha(40),
                  BlendMode.srcOver,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          _at(100, 300, _glass(fake: true)),
        ]),
      );
      expect(_passes(tester).single.nativeSeed, BackdropSeed.identity);
    });
  });

  // Glass that needs no backdrop must not get one from the seeds: each scene
  // is built with the seeds off (the plain path) and on, and a seed may only
  // replace a backdrop filter that was already there, never add one.
  group('fast paths', () {
    const hidden = LiquidGlassAppearance(visibility: 0);
    const neutral = LiquidGlassAppearance();

    Widget layer({
      required bool fake,
      required LiquidGlassSettings settings,
      LiquidGlassAppearance? appearance,
      bool group = false,
    }) {
      const child = SizedBox(width: 200, height: 64);
      final shape = group
          ? LiquidGlass.grouped(
              shape: _pill,
              appearance: appearance,
              child: child,
            )
          : LiquidGlass(shape: _pill, appearance: appearance, child: child);
      return _scene([
        _at(
          100,
          300,
          LiquidGlassLayer(
            fake: fake,
            settings: settings,
            defaultAppearance: neutral,
            child: group ? LiquidGlassBlendGroup(child: shape) : shape,
          ),
        ),
      ]);
    }

    Future<int> filtersWith(
      WidgetTester tester,
      Widget scene,
      BackdropSeed seed,
    ) async {
      SeededBackdropPassLayer.debugModeOverride = seed;
      await _pump(tester, scene);
      if (seed == BackdropSeed.none) {
        expect(_passes(tester), isEmpty);
      }
      return _filters(tester).length;
    }

    for (final fake in [true, false]) {
      for (final group in [false, true]) {
        final name = '${fake ? 'fake' : 'real'}, group=$group';
        testWidgets(
          'glass without a blur or an appearance needs no backdrop ($name)',
          (tester) async {
            final scene = layer(fake: fake, settings: _noBlur, group: group);
            final plain = await filtersWith(
              tester,
              scene,
              BackdropSeed.none,
            );
            final seeded = await filtersWith(
              tester,
              scene,
              BackdropSeed.blur,
            );
            // Real glass keeps the filter it always had and gets no pass;
            // fake glass has no backdrop work at all then.
            expect(seeded, plain);
            if (fake) expect(seeded, 0);
            expect(_passes(tester), isEmpty);
          },
          skip: !fake && skipProperGlassTests,
        );
        testWidgets(
          'invisible glass gets no pass ($name)',
          (tester) async {
            final scene = layer(
              fake: fake,
              settings: _settings,
              appearance: hidden,
              group: group,
            );
            final plain = await filtersWith(
              tester,
              scene,
              BackdropSeed.none,
            );
            final seeded = await filtersWith(
              tester,
              scene,
              BackdropSeed.blur,
            );
            expect(seeded, lessThanOrEqualTo(plain));
            expect(
              _passes(tester).where((p) => p.nativeSeed != BackdropSeed.none),
              isEmpty,
            );
            if (fake) expect(seeded, 0);
          },
          skip: !fake && skipProperGlassTests,
        );
        testWidgets(
          'blurred glass never gets more backdrop filters ($name)',
          (tester) async {
            final scene = layer(
              fake: fake,
              settings: _settings,
              appearance: const LiquidGlassAppearance.ios27RegularLight(),
              group: group,
            );
            final plain = await filtersWith(
              tester,
              scene,
              BackdropSeed.none,
            );
            final seeded = await filtersWith(
              tester,
              scene,
              BackdropSeed.blur,
            );
            expect(seeded, lessThanOrEqualTo(plain));
            expect(
              _passes(tester).where((p) => p.nativeSeed != BackdropSeed.none),
              hasLength(1),
            );
          },
          skip: !fake && skipProperGlassTests,
        );
      }
    }

    testWidgets('standalone fake glass that is invisible or a lone blur', (
      tester,
    ) async {
      for (final appearance in [hidden, neutral]) {
        final scene = _scene([
          _at(
            100,
            300,
            _glass(
              fake: true,
              settings: appearance == hidden ? _settings : _noBlur,
              appearance: appearance,
            ),
          ),
        ]);
        expect(
          await filtersWith(tester, scene, BackdropSeed.blur),
          0,
        );
        expect(_passes(tester), isEmpty);
      }
    });

    testWidgets('static glass keeps its cached geometry with seeds on', (
      tester,
    ) async {
      SeededBackdropPassLayer.debugModeOverride = BackdropSeed.blur;
      final repaint = ValueNotifier<int>(0);
      addTearDown(repaint.dispose);
      tester.view
        ..physicalSize = const Size(800, 1600)
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _scene([
          ValueListenableBuilder<int>(
            valueListenable: repaint,
            builder: (_, value, _) => Positioned.fill(
              child: ColoredBox(color: Color(0xFF204060 + value)),
            ),
          ),
          _at(100, 300, _glass()),
        ]),
      );
      await tester.pump();
      final renderer = tester.allRenderObjects
          .whereType<RenderLiquidGlassLayer>()
          .last
          .gpuGeometryRenderer!;
      final renders = renderer.debugRenderCount;
      for (var i = 1; i <= 5; i++) {
        repaint.value = i;
        await tester.pump();
      }
      expect(
        renderer.debugRenderCount,
        renders,
        reason: 'Foreground repaints must not draw the geometry again.',
      );
      expect(_passes(tester), isNotEmpty, reason: 'the seeds are on');
    }, skip: skipProperGlassTests);
  });

  // A seed reads the backdrop for itself unless the glass was given a key: then
  // Impeller reads it once for all the filters of that key.
  group('backdrop keys', () {
    for (final fake in [false, true]) {
      testWidgets(
        'seeds without a key of their own read the backdrop each '
        '(${fake ? 'fake' : 'real'})',
        (tester) async {
          SeededBackdropPassLayer.debugModeOverride = BackdropSeed.blur;
          await _pump(
            tester,
            _scene([
              _at(100, 100, _glass(fake: fake)),
              _at(100, 350, _glass(fake: fake)),
            ]),
          );
          final passes = _passes(tester);
          expect(passes, hasLength(2));
          expect(passes.every((p) => !p.debugSeedShared), isTrue);
          if (fake) {
            // Each fake glass layer keys its own filters.
            expect(passes[0].debugSeedKey, isNotNull);
            expect(passes[1].debugSeedKey, isNot(passes[0].debugSeedKey));
          } else {
            expect(passes.map((p) => p.debugSeedKey), everyElement(isNull));
          }
        },
        skip: !fake && skipProperGlassTests,
      );
    }

    for (final fake in [false, true]) {
      for (final mode in [
        BackdropSeed.identity,
        BackdropSeed.blur,
      ]) {
        testWidgets(
          "the caller's own key is used, with alternating filters "
          '(${fake ? 'fake' : 'real'}, ${mode.name})',
          (tester) async {
            SeededBackdropPassLayer.debugModeOverride = mode;
            final key = BackdropKey();
            await _pump(
              tester,
              _scene([
                _at(100, 100, _glass(fake: fake, key: key)),
                _at(100, 350, _glass(fake: fake, key: key)),
                _at(100, 600, _glass(fake: fake, key: key)),
              ]),
            );
            final passes = _passes(tester);
            expect(passes, hasLength(3));
            expect(passes.map((p) => p.debugSeedKey), everyElement(same(key)));
            expect(passes.every((p) => p.debugSeedShared), isTrue);
            // Impeller runs a key's filter once over the whole texture when
            // all of them are equal, so neighbours differ.
            final filters = [for (final p in passes) p.debugSeedFilter!];
            for (var i = 1; i < filters.length; i++) {
              if (mode == BackdropSeed.blur) {
                expect(
                  (_sigmaOf(filters[i]) - _sigmaOf(filters[i - 1])).abs(),
                  greaterThan(1e-3),
                );
              } else {
                expect(filters[i].toString(), isNot(filters[i - 1].toString()));
              }
            }
            // Beyond two, the pattern alternates, so no neighbours are equal.
            expect(filters[0].toString(), filters[2].toString());
          },
          skip: !fake && skipProperGlassTests,
        );
      }
    }

    testWidgets('a BackdropGroup shares the key of its seeds', (tester) async {
      SeededBackdropPassLayer.debugModeOverride = BackdropSeed.blur;
      Widget grouped(double top) => _at(
        100,
        top,
        const LiquidGlassLayer(
          fake: true,
          useBackdropGroup: true,
          settings: _settings,
          child: LiquidGlass(
            shape: _pill,
            child: SizedBox(width: 200, height: 64),
          ),
        ),
      );
      await _pump(
        tester,
        _scene([
          BackdropGroup(
            child: Stack(
              children: [grouped(100), grouped(300), grouped(500)],
            ),
          ),
        ]),
      );
      final passes = _passes(tester);
      expect(passes, hasLength(3));
      expect({for (final p in passes) p.debugSeedKey}, hasLength(1));
      expect(passes.first.debugSeedKey, isNotNull);
      expect(passes.every((p) => p.debugSeedShared), isTrue);
    });

    testWidgets('with seeds off no pass exists and keys are untouched', (
      tester,
    ) async {
      final key = BackdropKey();
      await _pump(
        tester,
        _scene([
          _at(100, 100, _glass(fake: true)),
          _at(100, 300, _glass(fake: true, key: key)),
        ]),
      );
      expect(_passes(tester), isEmpty);
      expect(
        _filters(tester).map((f) => f.backdropKey),
        unorderedEquals([isNotNull, same(key)]),
        reason: 'the fake layer keeps its own key, the glass its own',
      );
    });
  });

  group('while the size changes', () {
    Widget sized(double width, {bool fake = true}) => LiquidGlass.withOwnLayer(
      fake: fake,
      settings: _settings,
      shape: _pill,
      child: SizedBox(width: width, height: 64),
    );

    Widget moving(double offset, double width, {bool fake = true}) => _scene([
      Positioned(
        left: 0,
        top: offset,
        width: 800,
        height: 200,
        child: const ColoredBox(color: Color(0xFF802040)),
      ),
      _at(100, 500, sized(width, fake: fake)),
    ]);

    testWidgets('a resizing real glass pass is not seeded, and is again once '
        'it settles', (tester) async {
      SeededBackdropPassLayer.debugModeOverride = BackdropSeed.blur;
      await _pump(tester, moving(0, 200, fake: false));
      expect(_passes(tester).single.nativeSeed, BackdropSeed.blur);
      for (var i = 1; i <= 20; i++) {
        await tester.pumpWidget(moving(0, 200 + i * 20.0, fake: false));
        // The size change is noticed once the pass has grown past a bucket.
        if (i < 3) continue;
        expect(_passes(tester).single.plan.resizing, isTrue);
        expect(
          _passes(tester).single.nativeSeed,
          BackdropSeed.none,
          reason: 'frame $i',
        );
      }
      for (var i = 0; i < BackdropPassSizing.stableFrames + 2; i++) {
        await tester.pumpWidget(moving(0, 200, fake: false));
      }
      expect(_passes(tester).single.nativeSeed, BackdropSeed.blur);
    }, skip: skipProperGlassTests);

    testWidgets('a resizing FakeGlass pass stays seeded', (tester) async {
      SeededBackdropPassLayer.debugModeOverride = BackdropSeed.blur;
      await _pump(tester, moving(0, 200));
      for (var i = 1; i <= 20; i++) {
        await tester.pumpWidget(moving(0, 100 + i * 5.0));
        expect(_passes(tester).single.plan.resizing, isTrue);
        expect(
          _passes(tester).single.nativeSeed,
          BackdropSeed.blur,
          reason: 'frame $i',
        );
      }
    });

    testWidgets('a pass of fixed size over moving content stays seeded', (
      tester,
    ) async {
      SeededBackdropPassLayer.debugModeOverride = BackdropSeed.blur;
      Widget scene(double offset) => _scene([
        Positioned(
          left: 0,
          top: offset,
          width: 800,
          height: 100,
          child: const ColoredBox(color: Color(0xFF802040)),
        ),
        _at(100, 350, sized(200)),
        _at(100, 600, sized(200)),
      ]);
      await _pump(tester, scene(0));
      for (var i = 1; i <= 40; i++) {
        await tester.pumpWidget(scene(i * 7.0));
        final passes = _passes(tester);
        expect(passes, hasLength(2));
        for (final pass in passes) {
          expect(pass.plan.resizing, isFalse);
          expect(pass.nativeSeed, BackdropSeed.blur, reason: 'frame $i');
        }
      }
    });
  });

  // Impeller reuses an offscreen render target only at an identical size, so
  // the pass a glass is seeded in must keep its size (and everything sized from
  // it) while the glass merely moves, and change it only on bucket steps while
  // the glass resizes.
  group('pass sizing', () {
    const dpr = 2.625;
    const physical = Size(1080, 2424);

    // Wide enough that nothing below reaches a screen edge.
    const wide = Size(1440, 2424);

    const backdrop = Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFFF0040),
              Color(0xFF00D060),
              Color(0xFF0060FF),
              Color(0xFFC000FF),
            ],
          ),
        ),
      ),
    );

    Size device(Rect r) => Size(
      (r.width * dpr).roundToDouble(),
      (r.height * dpr).roundToDouble(),
    );

    void configureView(WidgetTester tester, [Size size = physical]) {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
    }

    /// The bounds of the clip the pass puts around its filter.
    Rect? clipBounds(SeededBackdropPassLayer pass) => switch (pass.firstChild) {
      ClipRectLayer(:final clipRect) => clipRect,
      ClipPathLayer(:final clipPath) => clipPath?.getBounds(),
      _ => null,
    };

    Widget pill({
      required bool fake,
      required double left,
      required double top,
      required double width,
      required double height,
    }) => Positioned(
      left: left,
      top: top,
      child: LiquidGlassLayer(
        fake: fake,
        settings: const LiquidGlassSettings(frost: 6),
        child: LiquidGlass(
          shape: LiquidRoundedSuperellipse(borderRadius: height / 2),
          child: SizedBox(width: width, height: height),
        ),
      ),
    );

    test('small passes use fine buckets and large ones coarse buckets', () {
      expect(BackdropPassSizing.bucketFor(100, 40), PixelBuckets.fine);
      expect(
        BackdropPassSizing.bucketFor(
          BackdropPassSizing.smallMaxSide.toDouble(),
          10,
        ),
        PixelBuckets.fine,
      );
      expect(
        BackdropPassSizing.bucketFor(BackdropPassSizing.smallMaxSide + 1.0, 10),
        PixelBuckets.standard,
      );
      expect(BackdropPassSizing.bucketFor(10, 900), PixelBuckets.standard);
      expect(
        BackdropPassSizing.bucketFor(1080, 900, large: true),
        PixelBuckets.coarse,
      );
    });

    testWidgets('large pass sizing grows at once, and shrinks only after the '
        'needed size was stable', (tester) async {
      configureView(tester);
      await tester.pumpWidget(const SizedBox());
      final sizing = BackdropPassSizing();
      const width = 411.0;
      Rect need(double height) => Rect.fromLTWH(0, 923 - height, width, height);
      Future<bool> frame(double wanted) async {
        tester.binding.scheduleFrame();
        await tester.pump();
        return sizing.decideLarge(width, wanted, dpr);
      }

      expect(await frame(500), isFalse, reason: 'unchanged is not resizing');
      expect(await frame(520), isTrue, reason: 'a large pass changed size');
      expect(sizing.stabilize(need(512)), need(512));

      expect(await frame(600), isTrue);
      final grown = sizing.stabilize(need(768));
      expect(grown, need(768), reason: 'it grows at once');

      expect(await frame(520), isTrue);
      expect(
        sizing.stabilize(need(512)),
        grown,
        reason: 'and does not shrink with the need',
      );
      // The wanted size keeps moving, but the bucket it needs does not.
      for (var i = 1; i < BackdropPassSizing.stableFrames; i++) {
        expect(await frame(i.isEven ? 520 : 530), isTrue);
        expect(sizing.stabilize(need(512)), grown, reason: 'frame $i');
      }
      expect(await frame(520), isTrue);
      expect(
        sizing.stabilize(need(512)),
        need(512),
        reason: 'stable for $BackdropPassSizing.stableFrames frames: shrinks',
      );
      // A pass that stops changing size returns to fine buckets.
      for (var i = 0; i < BackdropPassSizing.stableFrames; i++) {
        await frame(580);
      }
      expect(await frame(580), isFalse);
    });

    for (final fake in [true, false]) {
      testWidgets(
        'translating 300 px in 1 px steps keeps one pass size '
        '(${fake ? 'fake' : 'real'})',
        (tester) async {
          SeededBackdropPassLayer.debugModeOverride = BackdropSeed.blur;
          configureView(tester, wide);
          final x = ValueNotifier<double>(50);
          addTearDown(x.dispose);
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  backdrop,
                  ValueListenableBuilder<double>(
                    valueListenable: x,
                    builder: (context, value, _) => pill(
                      fake: fake,
                      left: value,
                      top: 400.3,
                      width: 60,
                      height: 56,
                    ),
                  ),
                ],
              ),
            ),
          );
          final plan = <Size>{};
          final layer = <Size>{};
          final clip = <Size>{};
          for (var i = 0; i < 300; i++) {
            x.value += 1;
            await tester.pump();
            final pass = _passes(tester).single;
            expect(pass.active, isTrue, reason: 'frame $i');
            plan.add(device(pass.plan.globalRect!));
            layer.add(device(pass.passRect!));
            if (clipBounds(pass) case final bounds?) clip.add(device(bounds));
          }
          expect(plan, hasLength(1), reason: '$plan');
          expect(layer, hasLength(1), reason: '$layer');
          expect(clip.length, lessThanOrEqualTo(1), reason: '$clip');
        },
        skip: !fake && skipProperGlassTests,
      );
    }

    group('a fake glass pill that resizes', () {
      Future<void> pump(WidgetTester tester, Widget scene) async {
        tester.view
          ..physicalSize = const Size(400, 400)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(debugShowCheckedModeBanner: false, home: scene),
        );
        await tester.pumpAndSettle();
      }

      setUp(
        () => SeededBackdropPassLayer.debugModeOverride = BackdropSeed.blur,
      );

      testWidgets('keeps one pass rect while it animates inside a bucket', (
        tester,
      ) async {
        final rects = <Rect>[];
        for (final width in [96.0, 98.0, 100.0, 103.0, 105.0]) {
          await pump(
            tester,
            Stack(
              children: [
                backdrop,
                pill(fake: true, left: 100, top: 120, width: width, height: 40),
              ],
            ),
          );
          final pass = _passes(tester).single;
          expect(pass.active, isTrue);
          rects.add(pass.passRect!);
        }
        // The first frame is placed before the pass is known to be resizing
        // (it is sized by its own extent); once it resizes it keeps one rect.
        expect(rects.skip(1).toSet(), hasLength(1), reason: '$rects');
        final rect = rects.last;
        // Device pixels at a pixel ratio of 1: whole, on the small bucket grid.
        final global = rect.shift(const Offset(100, 120));
        for (final v in [global.left, global.top, rect.width, rect.height]) {
          expect(v, equals(v.roundToDouble()));
          expect(v % PixelBuckets.fine, 0);
        }
        // It still covers the glass and its blur reach.
        expect(rect.contains(Offset.zero), isTrue);
        expect(rect.contains(const Offset(105, 40)), isTrue);
      });

      testWidgets('the filter clip is the pass rect and the pass cuts the '
          'outline', (tester) async {
        await pump(
          tester,
          Stack(
            children: [
              backdrop,
              pill(fake: true, left: 100, top: 120, width: 100, height: 40),
            ],
          ),
        );
        final pass = _passes(tester).single;
        expect(pass.active, isTrue);
        final clip = pass.firstChild! as ClipPathLayer;
        expect(clip.clipPath!.getBounds(), pass.passRect);
        final outline = pass.silhouette!.getBounds();
        expect(outline.width, closeTo(100, 1));
        expect(outline.height, closeTo(40, 1));
      });
    });

    group('a fake glass sheet that grows from the bottom of the screen', () {
      // A full-width sheet on a 1080x2424 phone, growing a few logical pixels
      // per frame. Every distinct size is a render-target allocation.
      final screen = Offset.zero & (physical / dpr);

      Future<({int pass, int clip, int planSizes, List<bool> active})> resize(
        WidgetTester tester,
      ) async {
        configureView(tester);
        final height = ValueNotifier<double>(screen.height * 0.45);
        addTearDown(height.dispose);
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              fit: StackFit.expand,
              children: [
                backdrop,
                ValueListenableBuilder<double>(
                  valueListenable: height,
                  builder: (context, value, _) => Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: value,
                    child: const LiquidGlassLayer(
                      fake: true,
                      settings: LiquidGlassSettings(frost: 6),
                      child: LiquidGlass(
                        shape: LiquidRoundedSuperellipse(borderRadius: 40),
                        child: SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        await tester.pump();
        final passSizes = <Size>[];
        final clipSizes = <Size>[];
        final planSizes = <Size>{};
        final active = <bool>[];
        for (var frame = 0; frame < 120; frame++) {
          height.value += 2;
          await tester.pump();
          final pass = _passes(tester).single;
          active.add(pass.active);
          final planned = pass.plan.globalRect;
          if (planned != null) planSizes.add(device(planned));
          final toGlobal = pass.plan.layerToGlobal;
          if (!pass.active || toGlobal == null) continue;
          Rect global(Rect r) =>
              MatrixUtils.transformRect(toGlobal, r).intersect(screen);
          passSizes.add(device(global(pass.passRect!)));
          clipSizes.add(device(global(clipBounds(pass)!)));
        }
        int changes(List<Size> sizes) {
          var n = 0;
          for (var i = 1; i < sizes.length; i++) {
            if (sizes[i] != sizes[i - 1]) n++;
          }
          return n;
        }

        return (
          pass: changes(passSizes),
          clip: changes(clipSizes),
          planSizes: planSizes.length,
          active: active,
        );
      }

      setUp(
        () => SeededBackdropPassLayer.debugModeOverride = BackdropSeed.blur,
      );

      testWidgets('the pass rect and the filter clip change size only on '
          'bucket boundaries', (tester) async {
        // About 630 device px/s at 120 Hz, as the sheet of the app.
        final result = await resize(tester);
        expect(result.active, everyElement(isTrue));
        expect(result.pass, lessThanOrEqualTo(16));
        expect(result.clip, lessThanOrEqualTo(16));
        expect(result.pass, greaterThan(1), reason: 'the sheet really grows');
      });

      testWidgets('large-pass sizing takes far fewer distinct pass sizes than '
          'fine buckets', (tester) async {
        BackdropPassSizing.debugStabilizeLargePasses = false;
        final before = await resize(tester);
        await tester.pumpWidget(const SizedBox());
        BackdropPassSizing.debugStabilizeLargePasses = true;
        final after = await resize(tester);
        expect(after.planSizes, lessThan(before.planSizes));
        expect(after.planSizes * 3, lessThanOrEqualTo(before.planSizes * 2));
        expect(after.active, everyElement(isTrue));
      });
    });
  });
}
