import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/rendering/consolidated_fake_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

import 'shared.dart';
import 'submitted_scene_binding.dart';

void main() => runIndependentOpacityPaintOrderTests(SubmittedSceneBinding());

void runIndependentOpacityPaintOrderTests(SubmittedSceneCapture binding) {
  if (const bool.fromEnvironment('PROBE_OUTER_OPTICS')) {
    _outerOpticsTests(binding);
    return;
  }
  const halfAppearance = bool.fromEnvironment('PROBE_HALF_APPEARANCE');
  for (final fake in [true, false]) {
    for (final (fadeEarlier, interleaved, sharedFade, localFade, reorder, blend)
        in [
          (true, false, false, false, false, false),
          (false, false, false, false, false, false),
          (true, true, false, false, false, false),
          (true, false, true, false, false, false),
          (true, false, true, true, false, false),
          (true, false, false, false, true, false),
          (true, false, false, false, true, true),
        ]) {
      testWidgets(
        'contained paint order ${fake ? "fake" : "real"} '
        'fadeEarlier=$fadeEarlier interleaved=$interleaved '
        'shared=$sharedFade local=$localFade reorder=$reorder blend=$blend',
        (tester) async {
          final oldSize = (binding.captureWidth, binding.captureHeight);
          binding
            ..captureNextScene = false
            ..captured = null
            ..captureWidth = 240
            ..captureHeight = 200;
          tester.view
            ..physicalSize = const Size(240, 200)
            ..devicePixelRatio = 1;
          addTearDown(() {
            tester.view.reset();
            binding
              ..captureNextScene = false
              ..captured = null
              ..captureWidth = oldSize.$1
              ..captureHeight = oldSize.$2;
          });
          final red = AnimationController(vsync: tester, value: 1);
          final green = AnimationController(vsync: tester, value: 1);
          final fading = fadeEarlier ? red : green;
          addTearDown(red.dispose);
          addTearDown(green.dispose);
          Widget reorderedScene(int frame, {required bool glass}) => _scene(
            glass: glass,
            interleaved: interleaved,
            sharedFade: sharedFade,
            localFade: localFade,
            fake: fake,
            red: red,
            green: green,
            reverseOrder: frame >= 2 && frame <= 4,
            blend: blend,
          );
          await tester.runAsync(
            () => MultiShaderBuilder.precacheShaders([
              ShaderKeys.fakeGlassSurface,
              ShaderKeys.liquidGlassRender,
              ShaderKeys.liquidGlassMaterialRender,
              ShaderKeys.liquidGlassTintRender,
            ]),
          );

          Future<Uint8List> capture() async {
            binding
              ..captured = null
              ..captureNextScene = true
              ..scheduleFrame();
            await tester.pump();
            expect(binding.captureNextScene, isFalse);
            expect(binding.captured, isNotNull);
            final image = (await tester.runAsync(() => binding.captured!))!;
            try {
              expect((image.width, image.height), (240, 200));
              final bytes = (await tester.runAsync(image.toByteData))!;
              return Uint8List.fromList(
                bytes.buffer.asUint8List(
                  bytes.offsetInBytes,
                  bytes.lengthInBytes,
                ),
              );
            } finally {
              image.dispose();
              binding.captured = null;
            }
          }

          // Native foreground oracle has no material, holder routing or scope
          // selector. The central marker overlap is far inside both flat glass
          // surfaces. Refraction, tint, blur and lighting cannot justify moving
          // an earlier foreground source over an opaque later source there.
          final alphas = [
            1.0,
            .5,
            if (reorder)
              1.0
            else if (const bool.fromEnvironment('PROBE_NEAR_OPAQUE'))
              .99931
            else
              254 / 255,
            .5,
            0.0,
            1.0,
            if (!reorder) ...[.5, 1.0, .5],
          ];
          await tester.pumpWidget(
            _scene(
              glass: false,
              blend: blend,
              interleaved: interleaved,
              sharedFade: sharedFade,
              localFade: localFade,
              fake: fake,
              red: red,
              green: green,
            ),
          );
          final references = <Uint8List>[];
          for (var i = 0; i < alphas.length; i++) {
            fading.value = alphas[i];
            if (reorder) {
              await tester.pumpWidget(reorderedScene(i, glass: false));
            }
            references.add(await capture());
          }
          const overlap = Rect.fromLTRB(104, 88, 136, 120);
          const redOnly = Rect.fromLTRB(48, 90, 56, 110);
          const greenOnly = Rect.fromLTRB(184, 90, 192, 110);
          if (!halfAppearance) {
            _expectSolid(references.first, overlap, [0, 255, 0, 255]);
            _expectSolid(references.first, redOnly, [255, 0, 0, 255]);
            _expectSolid(references.first, greenOnly, [0, 255, 0, 255]);
          }
          if (!halfAppearance && fadeEarlier && !sharedFade && !reorder) {
            for (final reference in references) {
              _expectSolid(reference, overlap, [0, 255, 0, 255]);
            }
          } else if (!halfAppearance && !sharedFade && !reorder) {
            _expectSolid(references[4], overlap, [255, 0, 0, 255]);
          }
          // The fading source is genuinely visible in its non-overlap region.
          expect(
            _region(references[0], fadeEarlier ? redOnly : greenOnly),
            isNot(
              orderedEquals(
                _region(references[4], fadeEarlier ? redOnly : greenOnly),
              ),
            ),
          );

          await tester.pumpWidget(const SizedBox.shrink());
          fading.value = 1;
          await tester.pumpWidget(
            _scene(
              glass: true,
              blend: blend,
              interleaved: interleaved,
              sharedFade: sharedFade,
              localFade: localFade,
              fake: fake,
              red: red,
              green: green,
            ),
          );
          if (!fake) {
            await pumpUntilGlassReady(tester);
            for (var frame = 0; frame < 60; frame++) {
              final scopes = tester.widgetList<LiquidGlassRenderScope>(
                find.byType(LiquidGlassRenderScope),
              );
              if (scopes.length == 1 &&
                  !scopes.single.consolidatesFakeBackdrop) {
                break;
              }
              await tester.pump(const Duration(milliseconds: 16));
            }
            final scope = tester.widget<LiquidGlassRenderScope>(
              find.byType(LiquidGlassRenderScope),
            );
            expect(scope.useFake, isFalse);
            expect(scope.consolidatesFakeBackdrop, isFalse);
          }
          final realOwner = fake
              ? null
              : tester.allRenderObjects
                    .whereType<RenderLiquidGlassLayer>()
                    .toSet()
                    .single;
          final fakeOwner = fake
              ? tester.allRenderObjects
                    .whereType<RenderConsolidatedFakeGlassLayer>()
                    .toSet()
                    .single
              : null;
          if (!fake) expect(realOwner!.gpuGeometryRenderer, isNotNull);
          int work() =>
              fakeOwner?.debugIndependentPassRecordCount ??
              FlutterGpuGeometryRenderer.debugTotalRenderCount;
          int paints() =>
              fakeOwner?.debugPaintCount ?? realOwner!.debugPaintCount;
          final failures = <String>[];
          final redObject = tester.renderObject(
            find.byKey(const ValueKey('red-source')),
          );
          final greenObject = tester.renderObject(
            find.byKey(const ValueKey('green-source')),
          );
          final originalWork = work();
          int? warmedWork;
          int? warmedPaints;
          for (var i = 0; i < alphas.length; i++) {
            fading.value = alphas[i];
            if (reorder) {
              await tester.pumpWidget(reorderedScene(i, glass: true));
            }
            expect(
              tester.renderObject(find.byKey(const ValueKey('red-source'))),
              same(redObject),
            );
            expect(
              tester.renderObject(find.byKey(const ValueKey('green-source'))),
              same(greenObject),
            );
            final first = await capture();
            final stable = await capture();
            if (sharedFade && !localFade) {
              expect(
                work(),
                originalWork,
                reason: 'Shared-only fade must reuse the original geometry',
              );
            }
            for (final (label, region) in [
              ('overlap', overlap),
              ('red only', redOnly),
              ('green only', greenOnly),
            ]) {
              _compareRegion(
                first,
                references[i],
                region,
                'alpha=${alphas[i]} first $label',
                failures,
              );
              _compareRegion(
                stable,
                references[i],
                region,
                'alpha=${alphas[i]} stable $label',
                failures,
              );
            }
            // Prove the actual opaque glass oracle is a visible, unambiguous
            // marker, not a blank/transparent scene that could pass accidentally.
            if (i == 0 && !halfAppearance) {
              _expectSolid(first, overlap, [0, 255, 0, 255]);
              _expectSolid(first, redOnly, [255, 0, 0, 255]);
            }
            if (i == 1) {
              // Warm-up construction is allowed. Only subsequent nonzero
              // fractional ticks must retain recordings/SDF and owner painting.
              warmedWork = work();
              warmedPaints = paints();
            } else if (!reorder && (i == 2 || i == 3)) {
              if (work() != warmedWork || paints() != warmedPaints) {
                failures.add(
                  'alpha=${alphas[i]} warm-cache churn: '
                  'work ${work()} vs $warmedWork, '
                  'paints ${paints()} vs $warmedPaints.',
                );
              }
            }
          }
          expect(failures, isEmpty, reason: failures.join('\n'));
        },
        skip: !fake && skipProperGlassTests,
      );
    }
  }
}

void _outerOpticsTests(SubmittedSceneCapture binding) {
  for (final fake in [true, false]) {
    for (final clipped in [false, true]) {
      testWidgets('outer optical fade fake=$fake clipped=$clipped', (
        tester,
      ) async {
        final oldSize = (binding.captureWidth, binding.captureHeight);
        binding
          ..captureWidth = 240
          ..captureHeight = 200;
        tester.view
          ..physicalSize = const Size(240, 200)
          ..devicePixelRatio = 1;
        addTearDown(() {
          tester.view.reset();
          binding
            ..captureNextScene = false
            ..captured = null
            ..captureWidth = oldSize.$1
            ..captureHeight = oldSize.$2;
        });
        final alpha = AnimationController(vsync: tester, value: 1);
        addTearDown(alpha.dispose);
        final activeAlpha = const bool.fromEnvironment('PROBE_ACTIVE_OUTER')
            ? _ActiveOpacity(alpha)
            : null;
        addTearDown(() => activeAlpha?.parent = null);
        await tester.runAsync(
          () => MultiShaderBuilder.precacheShaders([
            ShaderKeys.fakeGlassSurface,
            ShaderKeys.liquidGlassRender,
            ShaderKeys.liquidGlassMaterialRender,
            ShaderKeys.liquidGlassTintRender,
          ]),
        );
        const localOptics = bool.fromEnvironment('PROBE_LOCAL_OPTICS');
        const keyedOptics = bool.fromEnvironment('PROBE_OPTICAL_BACKDROP_KEY');
        // Move the material across a capture bucket boundary without moving
        // its owner. This distinguishes input-surface and output-clip origins.
        const opticalShiftX = int.fromEnvironment('PROBE_OPTICAL_SHIFT_X');
        const fullOptics = bool.fromEnvironment('PROBE_FULL_OPTICS');
        const staticOuter = bool.fromEnvironment('PROBE_STATIC_OUTER');
        assert(
          !staticOuter || !localOptics,
          'Select one outer fade mechanism.',
        );
        const opticalShape = LiquidGlass.grouped(
          shape: LiquidRoundedRectangle(borderRadius: 20),
          child: SizedBox(width: 120, height: 120),
        );
        final opticalAppearance = switch (const String.fromEnvironment(
          'PROBE_OPTICAL_APPEARANCE',
          defaultValue: 'neutral',
        )) {
          'toolbar-light' => const LiquidGlassAppearance.ios27ToolbarLight(),
          'toolbar-dark' => const LiquidGlassAppearance.ios27ToolbarDark(),
          'regular-light' => const LiquidGlassAppearance.ios27RegularLight(),
          'regular-dark' => const LiquidGlassAppearance.ios27RegularDark(),
          'neutral' => const LiquidGlassAppearance(),
          final unknown => throw ArgumentError(
            'Unknown optical appearance: $unknown',
          ),
        };
        Widget layer = LiquidGlassLayer(
          fake: fake,
          backdropKey: keyedOptics ? BackdropKey() : null,
          defaultAppearance:
              const bool.fromEnvironment('PROBE_OPTICAL_LINEAR_TRANSMISSION')
              ? opticalAppearance.copyWith(transmissionGamma: 1)
              : opticalAppearance,
          settings: fullOptics
              ? const LiquidGlassSettings(frost: 8)
              : const LiquidGlassSettings(
                  frost: 8,
                  edgeRefraction: 0,
                  highlight: 0,
                  chromaticAberration: 0,
                ),
          child: Stack(
            children: [
              Positioned(
                left: 60.0 + opticalShiftX,
                top: 40,
                child: localOptics
                    ? FadeTransition(
                        opacity: activeAlpha ?? alpha,
                        child: opticalShape,
                      )
                    : opticalShape,
              ),
            ],
          ),
        );
        const nested = bool.fromEnvironment('PROBE_OUTER_NESTED');
        const betweenFade = bool.fromEnvironment('PROBE_BETWEEN_FADE');
        assert(!betweenFade || nested, 'Between-owner fade requires nesting.');
        assert(
          !localOptics || !betweenFade,
          'Select one optical fade placement.',
        );
        if (nested) {
          layer = LiquidGlassLayer(
            fake: fake,
            defaultAppearance: const LiquidGlassAppearance(),
            settings: const LiquidGlassSettings(
              frost: 0,
              edgeRefraction: 0,
              highlight: 0,
              chromaticAberration: 0,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const Positioned(
                  left: 2,
                  top: 2,
                  child: LiquidGlass.grouped(
                    shape: LiquidRoundedRectangle(borderRadius: 2),
                    child: SizedBox(width: 8, height: 8),
                  ),
                ),
                if (betweenFade)
                  if (const bool.fromEnvironment('PROBE_STATIC_BETWEEN'))
                    AnimatedBuilder(
                      animation: alpha,
                      child: layer,
                      builder: (_, child) =>
                          Opacity(opacity: alpha.value, child: child),
                    )
                  else
                    FadeTransition(opacity: activeAlpha ?? alpha, child: layer)
                else
                  layer,
              ],
            ),
          );
        }
        if (const bool.fromEnvironment('PROBE_OPTICAL_SCALE')) {
          layer = Transform.scale(
            scale: 1.1,
            alignment: Alignment.topLeft,
            child: layer,
          );
        }
        if (const bool.fromEnvironment('PROBE_OPTICAL_ROTATION')) {
          layer = Transform.rotate(
            angle: .08,
            alignment: Alignment.topLeft,
            child: layer,
          );
        }
        const smallOwner = bool.fromEnvironment('PROBE_OPTICAL_SMALL_OWNER');
        if (smallOwner) {
          layer = Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(width: 180, height: 160, child: layer),
          );
        }
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(size: Size(240, 200)),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const CustomPaint(painter: _OpticalBackground()),
                  if (staticOuter)
                    AnimatedBuilder(
                      animation: alpha,
                      child: clipped ? _opticalAncestorClip(layer) : layer,
                      builder: (_, child) =>
                          Opacity(opacity: alpha.value, child: child),
                    )
                  else
                    FadeTransition(
                      opacity: localOptics
                          ? const AlwaysStoppedAnimation<double>(1)
                          : activeAlpha ?? alpha,
                      child: clipped ? _opticalAncestorClip(layer) : layer,
                    ),
                ],
              ),
            ),
          ),
        );
        if (!fake) {
          await pumpUntilGlassReady(tester);
          for (var frame = 0; frame < 60; frame++) {
            final scopes = tester.widgetList<LiquidGlassRenderScope>(
              find.byType(LiquidGlassRenderScope),
            );
            if (scopes.length == (nested ? 2 : 1) &&
                scopes.every((scope) => !scope.consolidatesFakeBackdrop)) {
              break;
            }
            await tester.pump(const Duration(milliseconds: 16));
          }
          final scopes = tester.widgetList<LiquidGlassRenderScope>(
            find.byType(LiquidGlassRenderScope),
          );
          expect(scopes, hasLength(nested ? 2 : 1));
          expect(
            scopes.every((scope) => !scope.consolidatesFakeBackdrop),
            isTrue,
          );
        }
        Future<Uint8List> capture(double opacity) async {
          alpha.value = opacity;
          binding
            ..captured = null
            ..captureNextScene = true
            ..scheduleFrame();
          await tester.pump();
          final image = (await tester.runAsync(() => binding.captured!))!;
          try {
            final nativeAlpha = Color.getAlphaFromOpacity(opacity);
            if (keyedOptics && !fake && nativeAlpha > 0 && nativeAlpha < 255) {
              final captureKeys = [
                for (final owner
                    in tester.allRenderObjects
                        .whereType<RenderLiquidGlassLayer>())
                  ...owner.debugIndependentCaptureBackdropKeys,
              ];
              expect(captureKeys, isNotEmpty);
              expect(
                captureKeys,
                everyElement(isNull),
                reason:
                    'Fresh and recovered captures must read sequential '
                    'input, not inherit the original pass backdrop key.',
              );
            }
            if (const bool.fromEnvironment('PROBE_SAVE_OPTICAL_SCENES') &&
                fullOptics &&
                !fake &&
                clipped) {
              await tester.runAsync(() async {
                final png = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File(
                  '${Directory.systemTemp.path}/glass-clipped-${Color.getAlphaFromOpacity(opacity)}.png',
                );
                await file.writeAsBytes(png!.buffer.asUint8List());
                debugPrint('OPTICS_CAPTURE ${file.path}');
              });
            }
            final bytes = (await tester.runAsync(image.toByteData))!;
            return Uint8List.fromList(
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            );
          } finally {
            image.dispose();
            binding.captured = null;
          }
        }

        final full = await capture(1);
        final background = await capture(0);
        const baseRegion = fullOptics
            ? Rect.fromLTRB(62, 42, 178, 158)
            : Rect.fromLTRB(92, 88, 148, 120);
        // A nonzero define deliberately tests a different capture origin.
        final region = baseRegion.shift(
          // ignore: use_named_constants
          const Offset(
            opticalShiftX * 1.0 + (smallOwner ? 60 : 0),
            smallOwner ? 40 : 0,
          ),
        );
        final opaquePixels = _region(full, region);
        final backgroundPixels = _region(background, region);
        expect(
          opaquePixels.where((v) => v > 40 && v < 215).length,
          greaterThan(500),
          reason: 'Opaque glass must visibly blur the black/white checker.',
        );
        expect(opaquePixels, isNot(orderedEquals(backgroundPixels)));
        final failures = <String>[];
        final originalWork = FlutterGpuGeometryRenderer.debugTotalRenderCount;
        for (final opacity in [
          254 / 255,
          .99931,
          128 / 255,
          32 / 255,
          0.0,
          1.0,
          128 / 255,
        ]) {
          final value = Color.getAlphaFromOpacity(opacity);
          // This witness contains only the inner layer's neutral blur. Two
          // enclosing native scopes therefore apply their alphas once each.
          final coverage = betweenFade ? value * value / 255 : value.toDouble();
          final expected = Uint8List.fromList([
            for (var i = 0; i < full.length; i++)
              ((full[i] * coverage + background[i] * (255 - coverage)) / 255)
                  .round(),
          ]);
          Uint8List? firstActual;
          for (final frame in ['first', 'stable']) {
            final actual = await capture(opacity);
            if (firstActual == null) {
              firstActual = actual;
            } else {
              expect(
                actual,
                orderedEquals(firstActual),
                reason:
                    'The first submitted fade frame must match its '
                    'settled frame without delayed glass updates.',
              );
            }
            _compareRegion(
              actual,
              expected,
              region,
              '$opacity $frame',
              failures,
            );
            _compareRegion(
              actual,
              background,
              const Rect.fromLTRB(24, 88, 48, 120),
              '$opacity $frame outside shape',
              failures,
            );
          }
          if (!fake) {
            expect(
              FlutterGpuGeometryRenderer.debugTotalRenderCount,
              originalWork,
              reason: 'Outer fade must reuse its full geometry matte.',
            );
          }
        }
        if (!fake && activeAlpha != null) {
          await capture(.5);
          final warmedPasses = {
            for (final owner
                in tester.allRenderObjects.whereType<RenderLiquidGlassLayer>())
              if (owner.debugIndependentPassCount > 0)
                owner: owner.debugIndependentPassCount,
          };
          expect(warmedPasses, isNotEmpty);
          final beforeRepaint =
              FlutterGpuGeometryRenderer.debugTotalRenderCount;
          for (final owner in warmedPasses.keys) {
            owner.markNeedsPaint();
          }
          await capture(.5);
          expect(
            FlutterGpuGeometryRenderer.debugTotalRenderCount,
            beforeRepaint,
            reason: 'Transient repaint detachment must not rebuild geometry.',
          );
          for (final entry in warmedPasses.entries) {
            expect(entry.key.debugIndependentPassCount, entry.value);
          }
          await capture(1);
          expect(activeAlpha.status.isAnimating, isTrue);
          for (final entry in warmedPasses.entries) {
            expect(
              entry.key.debugIndependentPassCount,
              staticOuter ? 0 : entry.value,
              reason: staticOuter
                  ? 'Static opaque ancestry must release temporary passes.'
                  : 'Active external animation must retain warm passes at 1.',
            );
          }
          await capture(.5);
          expect(
            FlutterGpuGeometryRenderer.debugTotalRenderCount,
            originalWork,
          );
          activeAlpha.active = false;
          await capture(1);
          for (final owner in warmedPasses.keys) {
            expect(
              owner.debugIndependentPassCount,
              0,
              reason: 'Settled ancestry must release temporary fade passes.',
            );
          }
          // A dismissed fade can remain mounted indefinitely. It must not
          // retain the temporary passes merely because it never returns to 1.
          activeAlpha.active = true;
          await capture(.5);
          final hiddenOwners = [
            for (final owner
                in tester.allRenderObjects.whereType<RenderLiquidGlassLayer>())
              if (owner.debugIndependentPassCount > 0) owner,
          ];
          expect(hiddenOwners, isNotEmpty);
          activeAlpha.active = false;
          await capture(0);
          for (final owner in hiddenOwners) {
            expect(
              owner.debugIndependentPassCount,
              0,
              reason: 'Dismissed ancestry must release temporary fade passes.',
            );
          }
          activeAlpha.active = true;
          final restored = await capture(128 / 255);
          final restoredWork = FlutterGpuGeometryRenderer.debugTotalRenderCount;
          final stableRestored = await capture(128 / 255);
          expect(
            FlutterGpuGeometryRenderer.debugTotalRenderCount,
            restoredWork,
            reason: 'A new fade after dismissal must reuse its warmed matte.',
          );
          const restoredCoverage = betweenFade ? 128 * 128 / 255 : 128.0;
          final restoredExpected = Uint8List.fromList([
            for (var i = 0; i < full.length; i++)
              ((full[i] * restoredCoverage +
                          background[i] * (255 - restoredCoverage)) /
                      255)
                  .round(),
          ]);
          for (final pixels in [restored, stableRestored]) {
            _compareRegion(
              pixels,
              restoredExpected,
              region,
              'fade in after dismissed cleanup',
              failures,
            );
          }
        }
        // Report pixel errors after exercising cleanup as well, so a small
        // optical residual cannot hide a resource-lifetime regression.
        expect(failures, isEmpty, reason: failures.join('\n'));
      }, skip: !fake && skipProperGlassTests);
    }
  }
}

// Nonmonotonic animation can attain value1 while its controller keeps running.
// Keep value notifications deterministic without pumping elapsed-time frames.
class _ActiveOpacity extends ProxyAnimation {
  _ActiveOpacity(super.animation);
  bool active = true;

  @override
  AnimationStatus get status => active ? AnimationStatus.forward : super.status;
}

class _OpticalBackground extends CustomPainter {
  const _OpticalBackground();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final (first, second) = switch (const String.fromEnvironment(
      'PROBE_OPTICAL_PALETTE',
      defaultValue: 'gray',
    )) {
      'gray' => (const Color(0xFF000000), const Color(0xFFFFFFFF)),
      'purple' => (const Color(0xFF1740B8), const Color(0xFFAD2080)),
      'green' => (const Color(0xFF18782C), const Color(0xFF90D020)),
      'dark' => (const Color(0xFF080810), const Color(0xFF303048)),
      'light' => (const Color(0xFFB8CCD8), const Color(0xFFF8F4E8)),
      final unknown => throw ArgumentError('Unknown optical palette: $unknown'),
    };
    for (var y = 0; y < size.height; y += 8) {
      for (var x = 0; x < size.width; x += 8) {
        paint.color = (x ~/ 8 + y ~/ 8).isEven ? first : second;
        canvas.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 8, 8), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_OpticalBackground oldDelegate) => false;
}

List<int> _region(Uint8List pixels, Rect rect) => [
  for (var y = rect.top.toInt(); y < rect.bottom; y++)
    for (var x = rect.left.toInt(); x < rect.right; x++)
      for (var channel = 0; channel < 4; channel++)
        pixels[(y * 240 + x) * 4 + channel],
];

void _expectSolid(Uint8List pixels, Rect rect, List<int> rgba) {
  final values = _region(pixels, rect);
  var bad = 0;
  for (var i = 0; i < values.length; i++) {
    if ((values[i] - rgba[i % 4]).abs() > 3) bad++;
  }
  expect(
    bad,
    0,
    reason:
        'Expected solid $rgba throughout $rect; '
        'first actual pixel ${values.take(4).toList()}',
  );
}

void _compareRegion(
  Uint8List actual,
  Uint8List expected,
  Rect region,
  String label,
  List<String> failures,
) {
  final a = _region(actual, region);
  final b = _region(expected, region);
  var bad = 0;
  var maximum = 0;
  for (var i = 0; i < a.length; i++) {
    final error = (a[i] - b[i]).abs();
    if (error > 3) bad++;
    if (error > maximum) maximum = error;
  }
  if (bad > 0) failures.add('$label: $bad RGBA channels >3; max $maximum.');
}

Widget _scene({
  required bool glass,
  required bool interleaved,
  required bool sharedFade,
  required bool localFade,
  required bool fake,
  required Animation<double> red,
  required Animation<double> green,
  bool reverseOrder = false,
  bool blend = false,
}) {
  Widget source(Color color, Size size) {
    final marker = SizedBox.fromSize(
      size: size,
      child: Center(
        child: ColoredBox(
          color: color,
          child: const SizedBox(width: 120, height: 108),
        ),
      ),
    );
    return glass
        ? LiquidGlass.grouped(
            appearance: const LiquidGlassAppearance(
              // Diagnostic varies the existing materialization API.
              // ignore: avoid_redundant_argument_values
              visibility: bool.fromEnvironment('PROBE_HALF_APPEARANCE')
                  ? .5
                  : 1,
            ),
            shape: const LiquidRoundedRectangle(borderRadius: 12),
            child: marker,
          )
        : const bool.fromEnvironment('PROBE_HALF_APPEARANCE')
        ? Opacity(opacity: .5, child: marker)
        : marker;
  }

  final sources = <Widget>[
    if (interleaved)
      Positioned(
        left: 20,
        top: 24,
        child: source(const Color(0xFF0000FF), const Size(160, 152)),
      ),
    Positioned(
      key: const ValueKey('red-source'),
      left: 20,
      top: 24,
      child: FadeTransition(
        opacity: sharedFade && !localFade
            ? const AlwaysStoppedAnimation<double>(1)
            : red,
        child: source(const Color(0xFFFF0000), const Size(160, 152)),
      ),
    ),
    Positioned(
      key: const ValueKey('green-source'),
      left: 60,
      top: 44,
      child: FadeTransition(
        opacity: green,
        child: source(const Color(0xFF00FF00), const Size(160, 136)),
      ),
    ),
  ];
  final children = Stack(
    children: reverseOrder ? sources.reversed.toList() : sources,
  );
  final contents = blend && glass
      ? LiquidGlassBlendGroup(blend: 0, child: children)
      : children;
  const outerFade = bool.fromEnvironment('PROBE_OUTER_FADE');
  Widget sharedTransition(Widget child) => FadeTransition(
    opacity: red,
    child: outerFade && const bool.fromEnvironment('PROBE_OUTER_CLIP')
        ? ClipRect(clipper: const _OffsetClip(), child: child)
        : child,
  );
  Widget glassLayer() {
    final layer = LiquidGlassLayer(
      fake: fake,
      settings: const LiquidGlassSettings(
        edgeRefraction: 0,
        frost: 0,
        highlight: 0,
        chromaticAberration: 0,
      ),
      child: sharedFade && !outerFade
          ? FadeTransition(opacity: red, child: contents)
          : contents,
    );
    return sharedFade && outerFade ? sharedTransition(layer) : layer;
  }

  return MediaQuery(
    data: const MediaQueryData(size: Size(240, 200)),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFFE0D8C8)),
            if (glass)
              glassLayer()
            else if (sharedFade)
              sharedTransition(contents)
            else
              contents,
          ],
        ),
      ),
    ),
  );
}

Widget _opticalAncestorClip(Widget child) =>
    const String.fromEnvironment('PROBE_OPTICAL_CLIP_KIND') == 'oval'
    ? ClipOval(clipper: const _OffsetClip(), child: child)
    : const String.fromEnvironment('PROBE_OPTICAL_CLIP_KIND') == 'superellipse'
    ? ClipRSuperellipse(clipper: const _OffsetSuperellipseClip(), child: child)
    : const bool.fromEnvironment('PROBE_OPTICAL_PATH_CLIP')
    ? ClipPath(clipper: const _OffsetPathClip(), child: child)
    : const bool.fromEnvironment('PROBE_OPTICAL_ROUNDED_CLIP')
    ? ClipRRect(clipper: const _OffsetRoundedClip(), child: child)
    : ClipRect(clipper: const _OffsetClip(), child: child);

class _OffsetSuperellipseClip extends CustomClipper<RSuperellipse> {
  const _OffsetSuperellipseClip();

  @override
  RSuperellipse getClip(Size size) => const BorderRadius.all(
    Radius.circular(12),
  ).toRSuperellipse(const Rect.fromLTRB(16, 64, 224, 144));

  @override
  bool shouldReclip(_OffsetSuperellipseClip oldClipper) => false;
}

class _OffsetPathClip extends CustomClipper<Path> {
  const _OffsetPathClip();

  @override
  Path getClip(Size size) =>
      Path()..addRRect(const _OffsetRoundedClip().getClip(size));

  @override
  bool shouldReclip(_OffsetPathClip oldClipper) => false;
}

class _OffsetRoundedClip extends CustomClipper<RRect> {
  const _OffsetRoundedClip();

  @override
  RRect getClip(Size size) => RRect.fromRectAndRadius(
    const Rect.fromLTRB(16, 64, 224, 144),
    const Radius.circular(12),
  );

  @override
  bool shouldReclip(_OffsetRoundedClip oldClipper) => false;
}

class _OffsetClip extends CustomClipper<Rect> {
  const _OffsetClip();

  @override
  Rect getClip(Size size) => const Rect.fromLTWH(16, 64, 208, 80);

  @override
  bool shouldReclip(_OffsetClip oldClipper) => false;
}
