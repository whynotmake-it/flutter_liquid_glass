import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

void main() {
  group('LiquidGlass', () {
    testWidgets('fake layer retains its painted subtree', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LiquidGlassLayer(
            fake: true,
            child: LiquidGlass(
              shape: LiquidOval(),
              child: SizedBox.square(dimension: 80),
            ),
          ),
        ),
      );

      final scope = tester.element(find.byType(LiquidGlassRenderScope));
      Element? parent;
      scope.visitAncestorElements((ancestor) {
        parent = ancestor;
        return false;
      });

      expect(parent!.widget, isA<RepaintBoundary>());
    });

    testWidgets(
      'standalone shapes share a layer without a dummy blend group',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: LiquidGlassLayer(
              child: Row(
                children: [
                  LiquidGlass(
                    shape: LiquidOval(),
                    child: SizedBox.square(dimension: 80),
                  ),
                  LiquidGlass(
                    shape: LiquidOval(),
                    child: SizedBox.square(dimension: 80),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byType(LiquidGlassLayer), findsOneWidget);
        expect(find.byType(LiquidGlassBlendGroup), findsNothing);
      },
    );

    testWidgets(
      'withOwnLayer does not wrap a blend group',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: LiquidGlass.withOwnLayer(
              shape: LiquidOval(),
              child: SizedBox.square(dimension: 80),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byType(LiquidGlassLayer), findsOneWidget);
        expect(find.byType(LiquidGlassBlendGroup), findsNothing);
      },
    );

    test('can be used', () async {
      expect(
        const LiquidGlass(shape: LiquidOval(), child: SizedBox()),
        isA<Widget>(),
      );
    });

    testWidgets(
      'initializes Flutter GPU asynchronously after the first surface frame',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: LiquidGlassLayer(
              child: LiquidGlass(
                shape: LiquidOval(),
                child: SizedBox.square(dimension: 100),
              ),
            ),
          ),
        );

        final initialScope = tester.widget<LiquidGlassRenderScope>(
          find.byType(LiquidGlassRenderScope),
        );
        if (initialScope.useFake) {
          // Shader-bundle I/O completes on the host event loop rather than the
          // fake clock advanced by pump durations. A warm cache may already
          // have selected the real renderer during pumpWidget.
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(seconds: 1)),
          );
          await tester.pump();
        }

        expect(
          tester
              .widget<LiquidGlassRenderScope>(
                find.byType(LiquidGlassRenderScope),
              )
              .useFake,
          isFalse,
        );
      },
      skip: expectFlutterGpuFallback,
    );

    testWidgets(
      'reuses real textures and releases them when switching to fake',
      (tester) async {
        final fake = ValueNotifier(false);
        final revision = ValueNotifier(0);
        addTearDown(fake.dispose);
        addTearDown(revision.dispose);
        final initialRenderers =
            FlutterGpuGeometryRenderer.debugActiveRendererCount;
        final initialGeometryTextures =
            FlutterGpuGeometryRenderer.debugActiveGeometryTextureCount;
        final initialCoordinateTextures =
            FlutterGpuGeometryRenderer.debugActiveCoordinateTextureCount;

        Widget app() => MaterialApp(
          home: AnimatedBuilder(
            animation: Listenable.merge([fake, revision]),
            builder: (_, __) => LiquidGlassLayer(
              fake: fake.value,
              child: const LiquidGlass(
                shape: LiquidOval(),
                child: SizedBox.square(dimension: 100),
              ),
            ),
          ),
        );

        await tester.pumpWidget(app());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 1)),
        );
        await tester.pump();
        await tester.pump();

        final renderObject = tester.allRenderObjects
            .whereType<RenderLiquidGlassLayer>()
            .last;
        final renderer = renderObject.gpuGeometryRenderer!;
        final renderShader = renderObject.renderShader;
        final renderCount = renderer.debugRenderCount;
        expect(
          FlutterGpuGeometryRenderer.debugActiveRendererCount,
          initialRenderers + 1,
        );
        expect(
          FlutterGpuGeometryRenderer.debugActiveGeometryTextureCount,
          initialGeometryTextures + 1,
        );
        expect(
          FlutterGpuGeometryRenderer.debugActiveCoordinateTextureCount,
          initialCoordinateTextures + 1,
        );

        // An unchanged real layer keeps both persistent textures and does not
        // submit another geometry pass. Rebuilding with an equivalent shader
        // asset list must also retain the same shader instance.
        revision.value++;
        await tester.pump();
        expect(renderer.debugRenderCount, renderCount);
        expect(renderObject.renderShader, same(renderShader));
        expect(renderShader.debugDisposed, isFalse);
        expect(
          FlutterGpuGeometryRenderer.debugActiveGeometryTextureCount,
          initialGeometryTextures + 1,
        );

        fake.value = true;
        await tester.pump();
        await tester.pump();
        expect(renderer.debugDisposed, isTrue);
        expect(renderShader.debugDisposed, isTrue);
        expect(
          FlutterGpuGeometryRenderer.debugActiveRendererCount,
          initialRenderers,
        );
        expect(
          FlutterGpuGeometryRenderer.debugActiveGeometryTextureCount,
          initialGeometryTextures,
        );
        expect(
          FlutterGpuGeometryRenderer.debugActiveCoordinateTextureCount,
          initialCoordinateTextures,
        );

        // A later real selection gets a fresh owner; fake mode never keeps the
        // retired real texture around merely to make this transition cheaper.
        fake.value = false;
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 1)),
        );
        await tester.pump();
        await tester.pump();
        final replacementRenderObject = tester.allRenderObjects
            .whereType<RenderLiquidGlassLayer>()
            .last;
        final replacement = replacementRenderObject.gpuGeometryRenderer!;
        final replacementShader = replacementRenderObject.renderShader;
        expect(replacement, isNot(same(renderer)));

        await tester.pumpWidget(const SizedBox());
        expect(replacement.debugDisposed, isTrue);
        expect(replacementShader.debugDisposed, isTrue);
        expect(
          FlutterGpuGeometryRenderer.debugActiveRendererCount,
          initialRenderers,
        );
        expect(
          FlutterGpuGeometryRenderer.debugActiveGeometryTextureCount,
          initialGeometryTextures,
        );
        expect(
          FlutterGpuGeometryRenderer.debugActiveCoordinateTextureCount,
          initialCoordinateTextures,
        );
      },
      skip: expectFlutterGpuFallback,
    );

    group('LiquidRoundedSuperellipse', () {
      goldenTest(
        'should render a rounded superellipse with different thickness',
        skip: skipGoldenTests,
        fileName: 'rounded_superellipse_thicknesses',
        pumpBeforeTest: pumpOnce,
        builder: () => GoldenTestGroup(
          scenarioConstraints: testScenarioConstraints,
          children: [
            for (final thickness in [0.0, 5, 10, 15, 20, 40, 100])
              GoldenTestScenario(
                name: 'thickness ${thickness.toStringAsFixed(0)}px',
                child: buildWithGridPaper(
                  LiquidGlass.withOwnLayer(
                    settings: settingsWithoutLighting.copyWith(
                      thickness: thickness.toDouble(),
                    ),
                    shape: const LiquidRoundedSuperellipse(
                      borderRadius: 100,
                    ),
                    child: const SizedBox.square(
                      dimension: 400,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

      goldenTest(
        'should render a rounded superellipse with different radii',
        skip: skipGoldenTests,
        fileName: 'rounded_superellipse_radii',
        pumpBeforeTest: pumpOnce,
        builder: () {
          final radii = [0.0, 50.0, 100.0, 200.0];
          return GoldenTestGroup(
            scenarioConstraints: testScenarioConstraints,
            children: [
              for (final radius in radii)
                GoldenTestScenario(
                  name: 'square shape radius ${radius.toStringAsFixed(0)}px',
                  child: buildWithGridPaper(
                    LiquidGlass.withOwnLayer(
                      settings: settingsWithoutLighting.copyWith(
                        thickness: 2,
                        tint: Colors.blue.withValues(alpha: 0.5),
                      ),
                      glassContainsChild: true,
                      shape: LiquidRoundedSuperellipse(
                        borderRadius: radius,
                      ),
                      child: SizedBox.square(
                        dimension: 400,
                        child: Container(
                          decoration: ShapeDecoration(
                            color: Colors.red.withValues(alpha: 0.5),
                            shape: RoundedSuperellipseBorder(
                              borderRadius: BorderRadius.circular(radius),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              for (final radius in radii)
                GoldenTestScenario(
                  name: 'wide shape radius ${radius.toStringAsFixed(0)}px',
                  child: buildWithGridPaper(
                    LiquidGlassLayer(
                      settings: settingsWithoutLighting.copyWith(
                        thickness: 2,
                        tint: Colors.blue.withValues(alpha: 0.5),
                      ),
                      child: LiquidGlassBlendGroup(
                        child: LiquidGlass.grouped(
                          glassContainsChild: true,
                          shape: LiquidRoundedSuperellipse(
                            borderRadius: radius,
                          ),
                          child: SizedBox.fromSize(
                            size: const Size(400, 200),
                            child: Container(
                              decoration: ShapeDecoration(
                                color: Colors.red.withValues(alpha: 0.5),
                                shape: RoundedSuperellipseBorder(
                                  borderRadius: BorderRadius.circular(radius),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
    });

    group('merging', () {
      goldenTest(
        'cut-out individual shadows paint below blended shading',
        skip: skipGoldenTests,
        fileName: 'layer_owned_cutout_blend_shadows',
        pumpBeforeTest: pumpOnce,
        builder: () => GoldenTestGroup(
          scenarioConstraints: testScenarioConstraints,
          children: [
            for (final enabled in [false, true])
              for (final background in [Colors.black, Colors.white])
                GoldenTestScenario(
                  name:
                      '${enabled ? 'cutout shadow' : 'no shadow'} · '
                      '${background == Colors.black ? 'black' : 'white'}',
                  child: ColoredBox(
                    color: background,
                    child: Center(
                      child: SizedBox(
                        width: 340,
                        height: 220,
                        child: LiquidGlassLayer(
                          settings: const LiquidGlassSettings.ios27ToolbarLight(
                            frost: 0,
                          ),
                          child: LiquidGlassBlendGroup(
                            blend: 36,
                            child: Stack(
                              children: [
                                Positioned(
                                  left: 36,
                                  top: 72,
                                  child: LiquidGlass.grouped(
                                    shadows: enabled
                                        ? const [
                                            BoxShadow(
                                              color: Color(0x08000000),
                                              offset: Offset(0, 4),
                                              blurRadius: 8,
                                              spreadRadius: -1,
                                            ),
                                          ]
                                        : const [],
                                    shape: const LiquidOval(),
                                    child: const SizedBox(
                                      width: 140,
                                      height: 100,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 138,
                                  top: 42,
                                  child: LiquidGlass.grouped(
                                    shadows: enabled
                                        ? const [
                                            BoxShadow(
                                              color: Color(0x08000000),
                                              offset: Offset(0, 4),
                                              blurRadius: 8,
                                              spreadRadius: -1,
                                            ),
                                          ]
                                        : const [],
                                    shape: const LiquidRoundedSuperellipse(
                                      borderRadius: 38,
                                    ),
                                    child: const SizedBox(
                                      width: 150,
                                      height: 120,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      );

      goldenTest(
        'directional bevel follows smooth-union geometry',
        skip: skipGoldenTests,
        fileName: 'directional_bevel_blend_group',
        pumpBeforeTest: pumpOnce,
        builder: () => GoldenTestGroup(
          scenarioConstraints: testScenarioConstraints,
          children: [
            for (final directionality in [0.0, 1.0])
              for (final background in [Colors.black, Colors.white])
                GoldenTestScenario(
                  name:
                      'directionality ${directionality.toStringAsFixed(0)} · '
                      '${background == Colors.black ? 'black' : 'white'}',
                  child: ColoredBox(
                    color: background,
                    child: Center(
                      child: SizedBox(
                        width: 340,
                        height: 220,
                        child: LiquidGlassLayer(
                          // Deliberately exaggerated, isolated material so the
                          // golden proves that the directional bevel follows
                          // the smooth-union SDF instead of a shape bounds box.
                          settings:
                              const LiquidGlassSettings.ios27ToolbarLight(
                                frost: 0,
                              ).copyWith(
                                highlight: 0,
                                contourStrength: 0,
                                bevelShadowStrength: .12,
                                bevelShadowDepth: 12,
                                bevelShadowDirectionality: directionality,
                                bevelShadowSizeResponse: 0,
                              ),
                          child: const LiquidGlassBlendGroup(
                            blend: 36,
                            child: Stack(
                              children: [
                                Positioned(
                                  left: 36,
                                  top: 72,
                                  child: LiquidGlass.grouped(
                                    shape: LiquidOval(),
                                    child: SizedBox(width: 140, height: 100),
                                  ),
                                ),
                                Positioned(
                                  left: 138,
                                  top: 42,
                                  child: LiquidGlass.grouped(
                                    shape: LiquidRoundedSuperellipse(
                                      borderRadius: 38,
                                    ),
                                    child: SizedBox(width: 160, height: 130),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      );

      goldenTest(
        'shapes merge with different blend values',
        skip: skipGoldenTests,
        fileName: 'merging_blend_values',
        pumpBeforeTest: pumpOnce,
        builder: () => GoldenTestGroup(
          scenarioConstraints: testScenarioConstraints,
          children: [
            for (final blend in [0.0, 40.0, 80.0, 100.0])
              GoldenTestScenario(
                name: 'blend $blend',
                child: buildWithGridPaper(
                  LiquidGlassLayer(
                    settings: settingsWithoutLighting.copyWith(
                      tint: Colors.red.withValues(alpha: 0.5),
                    ),
                    child: LiquidGlassBlendGroup(
                      blend: blend,

                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          LiquidGlass.grouped(
                            shape: LiquidOval(),
                            child: SizedBox.square(dimension: 100),
                          ),
                          LiquidGlass.grouped(
                            shape: LiquidRoundedRectangle(
                              borderRadius: 20,
                            ),
                            child: SizedBox.square(dimension: 100),
                          ),
                          LiquidGlass.grouped(
                            shape: LiquidRoundedSuperellipse(
                              borderRadius: 20,
                            ),
                            child: SizedBox.square(dimension: 100),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });

    group('transforms', () {
      goldenTest(
        'keeps composed blur sampling aligned away from the surface origin',
        skip: skipGoldenTests,
        fileName: 'liquid_glass_composed_filter_coordinates',
        pumpBeforeTest: _pumpAtDpr2,
        builder: () => GoldenTestGroup(
          scenarioConstraints: BoxConstraints.tight(const Size(900, 600)),
          children: [
            GoldenTestScenario(
              name: 'translated high-distortion glass with blur',
              child: _coordinateRegressionScene(),
            ),
          ],
        ),
      );

      goldenTest(
        'keeps stretched blend-group geometry aligned at DPR 2',
        skip: skipGoldenTests,
        fileName: 'liquid_glass_blend_group_stretch_dpr2',
        pumpBeforeTest: _pumpAtDpr2,
        builder: () => GoldenTestGroup(
          scenarioConstraints: testScenarioConstraints,
          children: [
            GoldenTestScenario(
              name: 'non-uniform stretch and rotation are applied once',
              child: buildWithGridPaper(
                LiquidGlassLayer(
                  settings: settingsWithoutLighting.copyWith(
                    thickness: 18,
                    tint: Colors.cyan.withValues(alpha: .25),
                  ),
                  child: LiquidGlassBlendGroup(
                    child: Center(
                      child: RawLiquidStretch(
                        stretchPixels: const Offset(70, 0),
                        child: Transform.rotate(
                          angle: .3,
                          child: LiquidGlass.grouped(
                            glassContainsChild: true,
                            shape: const LiquidRoundedRectangle(
                              borderRadius: 28,
                            ),
                            child: Container(
                              width: 220,
                              height: 140,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.red,
                                  width: 3,
                                ),
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

      goldenTest(
        'keeps optical displacement in logical pixels at DPR 2',
        skip: skipGoldenTests,
        fileName: 'liquid_glass_optics_dpr2',
        pumpBeforeTest: _pumpAtDpr2,
        builder: () => GoldenTestGroup(
          scenarioConstraints: testScenarioConstraints,
          children: [
            GoldenTestScenario(
              name: 'refraction and dispersion retain their logical strength',
              child: _dprOpticsRegressionScene(),
            ),
          ],
        ),
      );

      goldenTest(
        'keeps the effect aligned with scaled content at DPR 2',
        skip: skipGoldenTests,
        fileName: 'liquid_glass_transform_dpr2',
        pumpBeforeTest: _pumpAtDpr2,
        builder: () => GoldenTestGroup(
          scenarioConstraints: testScenarioConstraints,
          children: [
            GoldenTestScenario(
              name: 'scaled content and matte share logical coordinates',
              child: buildWithGridPaper(
                Transform.scale(
                  scale: 1.45,
                  child: LiquidGlass.withOwnLayer(
                    settings: settingsWithoutLighting.copyWith(
                      thickness: 18,
                      tint: Colors.cyan.withValues(alpha: .25),
                    ),
                    glassContainsChild: true,
                    shape: const LiquidRoundedRectangle(borderRadius: 28),
                    child: Container(
                      width: 220,
                      height: 140,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.red, width: 3),
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

      goldenTest(
        'keeps geometry aligned through affine and clipped transforms',
        skip: skipGoldenTests,
        fileName: 'liquid_glass_transform_matrix',
        pumpBeforeTest: pumpOnce,
        builder: () => GoldenTestGroup(
          scenarioConstraints: testScenarioConstraints,
          children: [
            GoldenTestScenario(
              name: 'translated',
              child: buildWithGridPaper(
                Transform.translate(
                  offset: const Offset(90, -55),
                  child: _transformGlass(),
                ),
              ),
            ),
            GoldenTestScenario(
              name: 'non-uniform scale',
              child: buildWithGridPaper(
                Transform.scale(
                  scaleX: 1.55,
                  scaleY: .65,
                  child: _transformGlass(),
                ),
              ),
            ),
            GoldenTestScenario(
              name: 'rotation',
              child: buildWithGridPaper(
                Transform.rotate(angle: .55, child: _transformGlass()),
              ),
            ),
            GoldenTestScenario(
              name: 'nested affine transform',
              child: buildWithGridPaper(
                Transform.translate(
                  offset: const Offset(-70, 45),
                  child: Transform.rotate(
                    angle: -.35,
                    child: Transform.scale(
                      scaleX: .75,
                      scaleY: 1.3,
                      child: _transformGlass(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

      testWidgets(
        'layer-owned shadow paint bounds retain the Gaussian tail',
        (tester) async {
          await tester.pumpWidget(
            const MaterialApp(
              home: Center(
                child: LiquidGlassLayer(
                  settings: settingsWithoutLighting,
                  child: LiquidGlassBlendGroup(
                    blend: 0,
                    child: LiquidGlass.grouped(
                      shadows: [
                        BoxShadow(
                          offset: Offset(0, 4),
                          blurRadius: 12,
                          spreadRadius: -1,
                        ),
                      ],
                      shape: LiquidOval(),
                      child: SizedBox.square(dimension: 100),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          final renderObject = tester.allRenderObjects
              .whereType<RenderLiquidGlassLayer>()
              .where((renderObject) => renderObject.paintBounds != Rect.zero)
              .last;
          final support = Shadow.convertRadiusToSigma(12) * 3 - 1;
          expect(
            renderObject.paintBounds,
            Rect.fromLTRB(-support, 4 - support, 100 + support, 104 + support),
          );
          final filterBounds = renderObject.debugFilterBounds!;
          expect(filterBounds.left, greaterThan(renderObject.paintBounds.left));
          expect(filterBounds.top, greaterThan(renderObject.paintBounds.top));
          expect(filterBounds.right, lessThan(renderObject.paintBounds.right));
          expect(
            filterBounds.bottom,
            lessThan(renderObject.paintBounds.bottom),
          );
        },
        skip: expectFlutterGpuFallback,
      );

      testWidgets(
        'updates layer paint bounds when an ancestor moves',
        (
          tester,
        ) async {
          final offset = ValueNotifier(Offset.zero);
          addTearDown(offset.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: ValueListenableBuilder<Offset>(
                valueListenable: offset,
                builder: (_, value, __) => Transform.translate(
                  offset: value,
                  child: _transformGlass(),
                ),
              ),
            ),
          );
          await tester.pump();
          final renderObject = tester.allRenderObjects
              .whereType<RenderLiquidGlassLayer>()
              .where((renderObject) => renderObject.paintBounds != Rect.zero)
              .last;
          final initialBounds = MatrixUtils.transformRect(
            renderObject.getTransformTo(null),
            renderObject.paintBounds,
          );

          offset.value = const Offset(80, 45);
          await tester.pump();
          await tester.pump();
          final movedBounds = MatrixUtils.transformRect(
            renderObject.getTransformTo(null),
            renderObject.paintBounds,
          );

          expect(
            movedBounds.topLeft - initialBounds.topLeft,
            const Offset(80, 45),
          );
          expect(movedBounds.size, initialBounds.size);
        },
        skip: expectFlutterGpuFallback,
      );

      testWidgets(
        'reuses geometry when the complete layer moves',
        (tester) async {
          final offset = ValueNotifier(Offset.zero);
          addTearDown(offset.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: ValueListenableBuilder<Offset>(
                valueListenable: offset,
                builder: (_, value, __) => Transform.translate(
                  offset: value,
                  child: _transformGlass(),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump();
          final renderObject = tester.allRenderObjects
              .whereType<RenderLiquidGlassLayer>()
              .where((renderObject) => renderObject.gpuGeometryRenderer != null)
              .last;
          final renderer = renderObject.gpuGeometryRenderer!;
          final initialRenderCount = renderer.debugRenderCount;
          final initialPaintCount = renderObject.debugPaintCount;
          final geometry = tester.allRenderObjects
              .whereType<RenderLiquidGlassGeometry>()
              .last;
          expect(geometry.geometryState, LiquidGlassGeometryState.updated);

          offset.value = const Offset(80, 45);
          await tester.pump();
          await tester.pump();

          expect(renderer.debugRenderCount, initialRenderCount);
          expect(renderObject.debugPaintCount, initialPaintCount);
          expect(geometry.geometryState, LiquidGlassGeometryState.updated);
        },
        skip: expectFlutterGpuFallback,
      );

      testWidgets(
        'rebuilds geometry when a shape moves inside the layer',
        (tester) async {
          final offset = ValueNotifier(Offset.zero);
          addTearDown(offset.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: ValueListenableBuilder<Offset>(
                valueListenable: offset,
                builder: (_, value, __) => LiquidGlassLayer(
                  settings: settingsWithoutLighting.copyWith(
                    thickness: 18,
                    tint: Colors.cyan.withValues(alpha: .25),
                  ),
                  child: Transform.translate(
                    offset: value,
                    child: const LiquidGlass(
                      shape: LiquidRoundedRectangle(borderRadius: 28),
                      child: SizedBox(width: 240, height: 150),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump();
          final renderObject = tester.allRenderObjects
              .whereType<RenderLiquidGlassLayer>()
              .where((renderObject) => renderObject.gpuGeometryRenderer != null)
              .last;
          final renderer = renderObject.gpuGeometryRenderer!;
          final initialRenderCount = renderer.debugRenderCount;

          offset.value = const Offset(80, 45);
          await tester.pump();
          await tester.pump();

          expect(renderer.debugRenderCount, greaterThan(initialRenderCount));
        },
        skip: expectFlutterGpuFallback,
      );

      testWidgets(
        'only rebuilds geometry when settings change geometry inputs',
        (tester) async {
          final settings = ValueNotifier(
            settingsWithoutLighting.copyWith(thickness: 18),
          );
          addTearDown(settings.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: ValueListenableBuilder<LiquidGlassSettings>(
                valueListenable: settings,
                builder: (_, value, __) => LiquidGlass.withOwnLayer(
                  settings: value,
                  shape: const LiquidRoundedRectangle(borderRadius: 28),
                  child: const SizedBox(width: 240, height: 150),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump();
          final renderObject = tester.allRenderObjects
              .whereType<RenderLiquidGlassLayer>()
              .where((renderObject) => renderObject.gpuGeometryRenderer != null)
              .last;
          final renderer = renderObject.gpuGeometryRenderer!;
          final initialRenderCount = renderer.debugRenderCount;

          settings.value = settings.value.copyWith(tint: Colors.cyan);
          await tester.pump();
          expect(renderer.debugRenderCount, initialRenderCount);

          settings.value = settings.value.copyWith(backdropScale: .8);
          await tester.pump();
          expect(
            renderer.debugRenderCount,
            initialRenderCount,
            reason: 'backdrop scaling belongs to the final material pass',
          );

          settings.value = settings.value.copyWith(thickness: 24);
          await tester.pump();
          expect(renderer.debugRenderCount, initialRenderCount + 1);
        },
        skip: expectFlutterGpuFallback,
      );
    });
  });
}

Future<void> _pumpAtDpr2(WidgetTester tester) async {
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetDevicePixelRatio);
  await pumpOnce(tester);
}

Widget _transformGlass() => LiquidGlass.withOwnLayer(
  settings: settingsWithoutLighting.copyWith(
    thickness: 18,
    tint: Colors.cyan.withValues(alpha: .25),
  ),
  shape: const LiquidRoundedRectangle(borderRadius: 28),
  child: const SizedBox(width: 240, height: 150),
);

Widget _dprOpticsRegressionScene() => Directionality(
  textDirection: TextDirection.ltr,
  child: DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Colors.black,
          Colors.white,
          Colors.red,
          Colors.green,
          Colors.blue,
          Colors.white,
          Colors.black,
        ],
      ),
    ),
    child: Center(
      child: LiquidGlass.withOwnLayer(
        settings: settingsWithoutLighting.copyWith(
          thickness: 24,
          edgeRefraction: 64,
          chromaticAberration: .5,
          saturation: 1,
          tint: Colors.transparent,
        ),
        shape: const LiquidRoundedSuperellipse(borderRadius: 80),
        child: const SizedBox(width: 400, height: 220),
      ),
    ),
  ),
);

Widget _coordinateRegressionScene() => Stack(
  children: [
    const SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xffff595e),
              Color(0xff8ac926),
              Color(0xff1982c4),
              Color(0xffc77dff),
              Color(0xffffca3a),
            ],
          ),
        ),
      ),
    ),
    const Positioned.fill(
      child: GridPaper(
        color: Colors.black,
        interval: 40,
        subdivisions: 1,
      ),
    ),
    Positioned(
      left: 390,
      top: 250,
      child: LiquidGlass.withOwnLayer(
        settings: settingsWithoutLighting.copyWith(
          frost: 5,
          thickness: 60,
          tint: Colors.white.withValues(alpha: .08),
        ),
        shape: const LiquidRoundedRectangle(borderRadius: 48),
        child: const SizedBox(width: 390, height: 220),
      ),
    ),
  ],
);
