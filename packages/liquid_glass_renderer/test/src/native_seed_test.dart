import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/backdrop_seed.dart';
import 'package:liquid_glass_renderer/src/internal/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/internal/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

// What native seeds (liquidGlassNativeSeed) put in the layer tree: when a glass
// gets a pass, how the pass is sized, and which seeds share a backdrop key.
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

/// Clips to a [size] square at the top left of its child, so the part of a
/// child that overflows to the left of it is kept only when [size] is large.
class _CornerClipper extends CustomClipper<Rect> {
  const _CornerClipper(this.size);

  final double size;

  @override
  Rect getClip(Size _) => Rect.fromLTWH(-size, 0, size * 2, size);

  @override
  bool shouldReclip(_CornerClipper oldClipper) => oldClipper.size != size;
}

double _sigmaOf(ui.ImageFilter filter) {
  final match = RegExp(
    r'ImageFilter\.blur\(([\d.]+), ',
  ).firstMatch(filter.toString());
  return double.parse(match!.group(1)!);
}

void main() {
  late LiquidGlassNativeSeed originalSeed;
  setUp(() {
    originalSeed = liquidGlassNativeSeed;
    liquidGlassNativeSeed = LiquidGlassNativeSeed.none;
  });
  tearDown(() {
    liquidGlassNativeSeed = originalSeed;
    debugStabilizeLargePasses = true;
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

    testWidgets('fake glass that is only a blur stays native', (tester) async {
      liquidGlassNativeSeed = LiquidGlassNativeSeed.identity;
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
        LiquidGlassNativeSeed.identity,
        LiquidGlassNativeSeed.blur,
      ]) {
        testWidgets(
          '${mode.name} seeds a pass '
          '(${fake ? 'fake' : 'real'})',
          (tester) async {
            liquidGlassNativeSeed = mode;
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
            if (mode == LiquidGlassNativeSeed.identity) {
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
        LiquidGlassNativeSeed mode,
      ) async {
        liquidGlassNativeSeed = mode;
        await _pump(tester, _scene([_at(100, 300, _glass())]));
        return tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().last;
      }

      var layer = await layerFor(LiquidGlassNativeSeed.none);
      expect(layer.debugBackdropPassPlan.globalOrigin, isNull);
      for (final mode in [
        LiquidGlassNativeSeed.identity,
        LiquidGlassNativeSeed.blur,
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
      liquidGlassNativeSeed = LiquidGlassNativeSeed.blur;
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
      expect(passes[0].nativeSeed, LiquidGlassNativeSeed.identity);
      expect(passes[1].nativeSeed, LiquidGlassNativeSeed.blur);
    });

    testWidgets('a pass inside another pass is not assumed to crop', (
      tester,
    ) async {
      liquidGlassNativeSeed = LiquidGlassNativeSeed.blur;
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
      expect(_passes(tester).single.nativeSeed, LiquidGlassNativeSeed.identity);
    });

    testWidgets('a pass is seeded whatever backdrop filter paints before it', (
      tester,
    ) async {
      liquidGlassNativeSeed = LiquidGlassNativeSeed.identity;
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
      expect(_passes(tester).single.nativeSeed, LiquidGlassNativeSeed.identity);
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
      LiquidGlassNativeSeed seed,
    ) async {
      liquidGlassNativeSeed = seed;
      await _pump(tester, scene);
      if (seed == LiquidGlassNativeSeed.none) {
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
              LiquidGlassNativeSeed.none,
            );
            final seeded = await filtersWith(
              tester,
              scene,
              LiquidGlassNativeSeed.blur,
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
              LiquidGlassNativeSeed.none,
            );
            final seeded = await filtersWith(
              tester,
              scene,
              LiquidGlassNativeSeed.blur,
            );
            expect(seeded, lessThanOrEqualTo(plain));
            expect(
              _passes(tester)
                  .where((p) => p.nativeSeed != LiquidGlassNativeSeed.none),
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
              LiquidGlassNativeSeed.none,
            );
            final seeded = await filtersWith(
              tester,
              scene,
              LiquidGlassNativeSeed.blur,
            );
            expect(seeded, lessThanOrEqualTo(plain));
            expect(
              _passes(tester)
                  .where((p) => p.nativeSeed != LiquidGlassNativeSeed.none),
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
          await filtersWith(tester, scene, LiquidGlassNativeSeed.blur),
          0,
        );
        expect(_passes(tester), isEmpty);
      }
    });

    testWidgets('static glass keeps its cached geometry with seeds on', (
      tester,
    ) async {
      liquidGlassNativeSeed = LiquidGlassNativeSeed.blur;
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

  // Impeller reads the backdrop once for all the filters of a key, so seeds
  // share a key when nothing painted after the first one, and before the other,
  // can have changed what the other reads (see `_canShareSeed`).
  group('shared backdrop keys', () {
    for (final fake in [false, true]) {
      for (final mode in [
        LiquidGlassNativeSeed.identity,
        LiquidGlassNativeSeed.blur,
      ]) {
        testWidgets(
          'seeds nothing can have changed in between share one key '
          '(${fake ? 'fake' : 'real'}, ${mode.name})',
          (tester) async {
            liquidGlassNativeSeed = mode;
            await _pump(
              tester,
              _scene([
                _at(100, 100, _glass(fake: fake)),
                _at(100, 350, _glass(fake: fake)),
                _at(100, 600, _glass(fake: fake)),
              ]),
            );
            // The glass painted in between is the glass of the other seeds:
            // it changes only what its own pass does, which is clear of them.
            final passes = _passes(tester);
            expect(passes, hasLength(3));
            final keys = {for (final p in passes) p.debugSeedKey};
            expect(keys, hasLength(1));
            expect(keys.single, isNotNull);
            expect(passes.every((p) => p.debugSeedShared), isTrue);
            // Impeller runs a key's filter once over the whole texture when
            // all of them are equal, so neighbours differ.
            final filters = [for (final p in passes) p.debugSeedFilter!];
            for (var i = 1; i < filters.length; i++) {
              if (mode == LiquidGlassNativeSeed.blur) {
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

    testWidgets('a seed reading what another changed gets a key of its own', (
      tester,
    ) async {
      liquidGlassNativeSeed = LiquidGlassNativeSeed.identity;
      // The second pass reaches into the first glass.
      await _pump(
        tester,
        _scene([
          _at(100, 100, _glass(fake: true)),
          _at(100, 175, _glass(fake: true)),
          _at(100, 700, _glass(fake: true)),
        ]),
      );
      final [first, second, third] = _passes(tester);
      expect(first.debugSeedKey, isNot(second.debugSeedKey));
      // The third is clear of the second but not of the first group's first.
      expect(third.debugSeedKey, first.debugSeedKey);
      expect(second.debugSeedShared, isFalse);
      expect(first.debugSeedShared, isTrue);
    });

    // Painted content has no bounds worth trusting (a shadow or a Clip.none
    // overflow reaches well past them), so any of it between two seeds keeps
    // them apart, unless a real clip layer fences it.
    Widget overflowing({Widget Function(Widget child)? fence}) {
      // A 20 px box whose paint reaches 280 px left of it, over the second
      // glass.
      const box = RepaintBoundary(
        child: SizedBox(
          width: 20,
          height: 20,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -280,
                top: 0,
                width: 40,
                height: 40,
                child: ColoredBox(color: Color(0xFFFF0000)),
              ),
            ],
          ),
        ),
      );
      return _at(380, 380, fence?.call(box) ?? box);
    }

    testWidgets('content painted in between keeps seeds apart, whatever its '
        'bounds say', (tester) async {
      liquidGlassNativeSeed = LiquidGlassNativeSeed.identity;
      await _pump(
        tester,
        _scene([
          _at(100, 100, _glass(fake: true)),
          overflowing(),
          _at(100, 400, _glass(fake: true)),
        ]),
      );
      final [first, second] = _passes(tester);
      expect(first.debugSeedKey, isNot(second.debugSeedKey));
      expect(first.debugSeedShared || second.debugSeedShared, isFalse);
    });

    testWidgets('a clip layer fences content painted in between, to its own '
        'bounds', (tester) async {
      liquidGlassNativeSeed = LiquidGlassNativeSeed.identity;
      Widget scene(double clip) => _scene([
        _at(100, 100, _glass(fake: true)),
        overflowing(
          fence: (box) => SizedBox(
            width: clip,
            height: clip,
            child: ClipRect(clipper: _CornerClipper(clip), child: box),
          ),
        ),
        _at(100, 400, _glass(fake: true)),
      ]);
      // The clip keeps the overflow clear of the second glass.
      await _pump(tester, scene(20));
      var [first, second] = _passes(tester);
      expect(second.debugSeedKey, isNotNull);
      expect(second.debugSeedKey, same(first.debugSeedKey));
      // A clip around the part over the second glass fences nothing off it.
      await _pump(tester, scene(300));
      [first, second] = _passes(tester);
      expect(second.debugSeedKey, isNot(first.debugSeedKey));
    });

    testWidgets('a backdrop read in between keeps seeds apart', (tester) async {
      liquidGlassNativeSeed = LiquidGlassNativeSeed.identity;
      await _pump(
        tester,
        _scene([
          _at(100, 100, _glass(fake: true)),
          Positioned(
            left: 0,
            top: 600,
            width: 100,
            height: 100,
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
          _at(100, 700, _glass(fake: true)),
        ]),
      );
      final [first, second] = _passes(tester);
      expect(first.debugSeedKey, isNot(second.debugSeedKey));
    });

    testWidgets("the caller's own key is used, with alternating filters", (
      tester,
    ) async {
      liquidGlassNativeSeed = LiquidGlassNativeSeed.blur;
      final key = BackdropKey();
      await _pump(
        tester,
        _scene([
          _at(100, 100, _glass(key: key)),
          _at(100, 400, _glass(key: key)),
        ]),
      );
      final passes = _passes(tester);
      expect(passes, hasLength(2));
      expect(passes.map((p) => p.debugSeedKey), everyElement(same(key)));
      expect(passes.every((p) => p.debugSeedShared), isTrue);
      expect(
        (_sigmaOf(passes[0].debugSeedFilter!) -
                _sigmaOf(passes[1].debugSeedFilter!))
            .abs(),
        greaterThan(1e-3),
      );
    }, skip: skipProperGlassTests);

    testWidgets('a BackdropGroup shares the key of its seeds', (tester) async {
      liquidGlassNativeSeed = LiquidGlassNativeSeed.blur;
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

    testWidgets('a pass inside another pass takes no key', (tester) async {
      liquidGlassNativeSeed = LiquidGlassNativeSeed.identity;
      await _pump(
        tester,
        _scene([
          _at(100, 100, _glass(fake: true)),
          _at(
            100,
            500,
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAliasWithSaveLayer,
              child: _glass(fake: true),
            ),
          ),
        ]),
      );
      final [outer, nested] = _passes(tester);
      expect(nested.debugSeedKey, isNull);
      expect(outer.debugSeedShared, isFalse);
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
      liquidGlassNativeSeed = LiquidGlassNativeSeed.blur;
      await _pump(tester, moving(0, 200, fake: false));
      expect(_passes(tester).single.nativeSeed, LiquidGlassNativeSeed.blur);
      for (var i = 1; i <= 20; i++) {
        await tester.pumpWidget(moving(0, 200 + i * 20.0, fake: false));
        // The size change is noticed once the pass has grown past a bucket.
        if (i < 3) continue;
        expect(_passes(tester).single.plan.resizing, isTrue);
        expect(
          _passes(tester).single.nativeSeed,
          LiquidGlassNativeSeed.none,
          reason: 'frame $i',
        );
      }
      for (var i = 0; i < backdropPassShrinkStableFrames + 2; i++) {
        await tester.pumpWidget(moving(0, 200, fake: false));
      }
      expect(_passes(tester).single.nativeSeed, LiquidGlassNativeSeed.blur);
    }, skip: skipProperGlassTests);

    testWidgets('a resizing FakeGlass pass stays seeded', (tester) async {
      liquidGlassNativeSeed = LiquidGlassNativeSeed.blur;
      await _pump(tester, moving(0, 200));
      for (var i = 1; i <= 20; i++) {
        await tester.pumpWidget(moving(0, 100 + i * 5.0));
        expect(_passes(tester).single.plan.resizing, isTrue);
        expect(
          _passes(tester).single.nativeSeed,
          LiquidGlassNativeSeed.blur,
          reason: 'frame $i',
        );
      }
    });

    testWidgets('a pass of fixed size over moving content stays seeded and '
        'keeps sharing its key', (tester) async {
      liquidGlassNativeSeed = LiquidGlassNativeSeed.blur;
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
          expect(pass.nativeSeed, LiquidGlassNativeSeed.blur);
          expect(pass.debugSeedShared, isTrue, reason: 'frame $i');
        }
        expect(passes[0].debugSeedKey, same(passes[1].debugSeedKey));
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
      expect(backdropPassBucketFor(100, 40), backdropPassSmallBucket);
      expect(
        backdropPassBucketFor(backdropPassSmallMaxSide.toDouble(), 10),
        backdropPassSmallBucket,
      );
      expect(
        backdropPassBucketFor(backdropPassSmallMaxSide + 1.0, 10),
        backdropPassLargeBucket,
      );
      expect(backdropPassBucketFor(10, 900), backdropPassLargeBucket);
      expect(
        backdropPassBucketFor(1080, 900, large: true),
        backdropHugePassBucket,
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
      for (var i = 1; i < backdropPassShrinkStableFrames; i++) {
        expect(await frame(i.isEven ? 520 : 530), isTrue);
        expect(sizing.stabilize(need(512)), grown, reason: 'frame $i');
      }
      expect(await frame(520), isTrue);
      expect(
        sizing.stabilize(need(512)),
        need(512),
        reason: 'stable for $backdropPassShrinkStableFrames frames: shrinks',
      );
      // A pass that stops changing size returns to fine buckets.
      for (var i = 0; i < backdropPassShrinkStableFrames; i++) {
        await frame(580);
      }
      expect(await frame(580), isFalse);
    });

    for (final fake in [true, false]) {
      testWidgets(
        'translating 300 px in 1 px steps keeps one pass size '
        '(${fake ? 'fake' : 'real'})',
        (tester) async {
          liquidGlassNativeSeed = LiquidGlassNativeSeed.blur;
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

      setUp(() => liquidGlassNativeSeed = LiquidGlassNativeSeed.blur);

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
          expect(v % backdropPassSmallBucket, 0);
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

      testWidgets('keeps the shared filter object while an animated size does '
          'not change its inputs', (tester) async {
        // Short sides above 118 logical pixels saturate the size progress, and
        // a regular blur's sigma does not depend on size there.
        final filters = <ui.ImageFilter?>[];
        for (final height in [150.0, 160.0, 170.0]) {
          await pump(
            tester,
            Stack(
              children: [
                backdrop,
                pill(fake: true, left: 20, top: 20, width: 200, height: height),
              ],
            ),
          );
          filters.add(_filters(tester).firstOrNull?.filter);
        }
        expect(filters.first, isNotNull);
        expect(filters.every((f) => identical(f, filters.first)), isTrue);
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

      setUp(() => liquidGlassNativeSeed = LiquidGlassNativeSeed.blur);

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
        debugStabilizeLargePasses = false;
        final before = await resize(tester);
        await tester.pumpWidget(const SizedBox());
        debugStabilizeLargePasses = true;
        final after = await resize(tester);
        expect(after.planSizes, lessThan(before.planSizes));
        expect(after.planSizes * 3, lessThanOrEqualTo(before.planSizes * 2));
        expect(after.active, everyElement(isTrue));
      });
    });
  });
}
