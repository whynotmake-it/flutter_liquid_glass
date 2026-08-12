import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

void main() {
  group('LiquidGlass', () {
    test('can be used', () async {
      expect(
        const LiquidGlass(shape: LiquidOval(), child: SizedBox()),
        isA<Widget>(),
      );
    });

    testWidgets(
      'initializes Flutter GPU after the first surface frame',
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

        expect(
          tester
              .widget<LiquidGlassRenderScope>(
                find.byType(LiquidGlassRenderScope),
              )
              .useFake,
          isTrue,
        );

        await tester.pump();

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

    group('LiquidRoundedSuperellipse', () {
      goldenTest(
        'should render a rounded superellipse with different thickness',
        skip: skipProperGlassTests,
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
        skip: skipProperGlassTests,
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
                        glassColor: Colors.blue.withValues(alpha: 0.5),
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
                        glassColor: Colors.blue.withValues(alpha: 0.5),
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
        'shapes merge with different blend values',
        skip: skipProperGlassTests,
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
                      glassColor: Colors.red.withValues(alpha: 0.5),
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
        skip: skipProperGlassTests,
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
        skip: skipProperGlassTests,
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
                    glassColor: Colors.cyan.withValues(alpha: .25),
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
        'keeps the effect aligned with scaled content at DPR 2',
        skip: skipProperGlassTests,
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
                      glassColor: Colors.cyan.withValues(alpha: .25),
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
        skip: skipProperGlassTests,
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
          final initialUploads = renderer.debugCoordinateUploadCount;
          final blendGroup = tester.allRenderObjects
              .whereType<RenderLiquidGlassBlendGroup>()
              .last;
          expect(blendGroup.geometryState, LiquidGlassGeometryState.updated);

          offset.value = const Offset(80, 45);
          await tester.pump();
          await tester.pump();

          expect(renderer.debugRenderCount, initialRenderCount);
          expect(renderObject.debugPaintCount, initialPaintCount);
          expect(blendGroup.geometryState, LiquidGlassGeometryState.updated);
          expect(
            renderer.debugCoordinateUploadCount,
            greaterThan(initialUploads),
          );
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
                    glassColor: Colors.cyan.withValues(alpha: .25),
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

          settings.value = settings.value.copyWith(glassColor: Colors.cyan);
          await tester.pump();
          expect(renderer.debugRenderCount, initialRenderCount);

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
    glassColor: Colors.cyan.withValues(alpha: .25),
  ),
  shape: const LiquidRoundedRectangle(borderRadius: 28),
  child: const SizedBox(width: 240, height: 150),
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
          blur: 5,
          thickness: 60,
          glassColor: Colors.white.withValues(alpha: .08),
        ),
        shape: const LiquidRoundedRectangle(borderRadius: 48),
        child: const SizedBox(width: 390, height: 220),
      ),
    ),
  ],
);
