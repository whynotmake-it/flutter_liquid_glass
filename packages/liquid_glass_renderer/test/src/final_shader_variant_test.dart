import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/plan/plan.dart';
import 'package:liquid_glass_renderer/src/rendering/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('variant');
const _view = Size(300, 200);
const _gray = Color(0xFF7A8290);

Widget _scene(List<LiquidGlassAppearance?> appearances) => Directionality(
  textDirection: TextDirection.ltr,
  child: RepaintBoundary(
    key: _key,
    child: SizedBox.fromSize(
      size: _view,
      child: ColoredBox(
        color: _gray,
        child: LiquidGlassLayer(
          settings: const LiquidGlassSettings.ios27Regular(
            brightness: Brightness.light,
          ),
          // A paint over a solid color, not a backdrop filter: flutter_tester
          // renders only a process's first backdrop filter reliably.
          backdrop: const LiquidGlassBackdrop.solid(_gray),
          child: Stack(
            children: [
              for (final (i, appearance) in appearances.indexed)
                Positioned(
                  left: 20.0 + i * 140,
                  top: 50,
                  width: 120,
                  height: 90,
                  child: LiquidGlass(
                    shape: const LiquidRoundedSuperellipse(radius: 30),
                    appearance: appearance,
                    child: const SizedBox.expand(),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  ),
);

Future<Uint8List> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(boundary.toImage))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

RenderLiquidGlassLayer _layer(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().toSet().single;

void main() {
  test('every kind but material has a variant per model family', () {
    final names = {for (final v in FinalShaderVariant.all) v.name};
    expect(names, hasLength(FinalShaderVariant.all.length));
    expect(FinalShaderVariant.all, hasLength(13));
    final material =
        FinalShaderVariant.all[FinalShaderVariant.indexOf(
          FinalShaderKind.material,
          FinalShaderModels.direct,
        )];
    expect(material.models, FinalShaderModels.all);
  });

  test('a variant that cannot frost has a frosted twin', () {
    for (final kind in FinalShaderKind.values) {
      for (final models in FinalShaderModels.values) {
        final plain =
            FinalShaderVariant.all[FinalShaderVariant.indexOf(kind, models)];
        final frosted =
            FinalShaderVariant.all[FinalShaderVariant.indexOf(
              kind,
              models,
              frost: true,
            )];
        expect(plain.frost, isFalse);
        expect((frosted.kind, frosted.models), (plain.kind, plain.models));
      }
    }
    expect(
      FinalShaderVariant.all.where((v) => v.frost && !v.band && !v.shape),
      hasLength(1),
    );
    expect(
      FinalShaderVariant.all.where((v) => v.band && !v.shape),
      hasLength(1),
    );
  });

  test('every variant of one appearance has one for one shape', () {
    final atlas = FinalShaderVariant.all.where(
      (v) => v.kind == FinalShaderKind.single && !v.shape,
    );
    final shape = FinalShaderVariant.all.where((v) => v.shape);
    expect(
      {for (final v in shape) (v.kind, v.models, v.band)},
      {for (final v in atlas) (v.kind, v.models, v.band)},
    );
    for (final v in atlas) {
      final index = v.band
          ? FinalShaderVariant.bandIndexOf(
              v.kind,
              v.models,
              frost: v.frost,
              shape: true,
            )!
          : FinalShaderVariant.indexOf(
              v.kind,
              v.models,
              frost: v.frost,
              shape: true,
            );
      final twin = FinalShaderVariant.all[index];
      expect((twin.shape, twin.models, twin.band), (true, v.models, v.band));
    }
  });

  test('glass that frosts its copy draws a band wherever a variant does', () {
    for (final kind in FinalShaderKind.values) {
      for (final models in FinalShaderModels.values) {
        for (final shape in [false, if (kind == FinalShaderKind.single) true]) {
          final drawn = FinalShaderVariant.all.any(
            (v) =>
                v.band &&
                v.kind == kind &&
                v.models == models &&
                v.shape == shape,
          );
          for (final frost in [false, true]) {
            final index = FinalShaderVariant.bandIndexOf(
              kind,
              models,
              frost: frost,
              shape: shape,
            );
            expect(index != null, drawn && frost, reason: '$kind $models');
            if (index != null) {
              expect(FinalShaderVariant.all[index].band, isTrue);
            }
          }
        }
      }
    }
  });

  test('the build hook compiles each variant: one '
      'liquid_glass_final_render*.frag per variant', () {
    final files = {
      for (final file in Directory('lib/assets/shaders').listSync())
        if (file.uri.pathSegments.last case final name
            when name.startsWith('liquid_glass_final_render') &&
                name.endsWith('.frag'))
          name.substring(0, name.length - '.frag'.length),
    };
    expect(files, {for (final v in FinalShaderVariant.all) v.name});
  });

  test('each variant file is its source, and the core defines what the '
      'variants name', () {
    final core = File(
      'lib/assets/shaders/liquid_glass_final_render_core.glsl',
    ).readAsStringSync();
    for (final v in FinalShaderVariant.all) {
      expectGeneratedFile('lib/assets/shaders/${v.name}.frag', v.source);
      for (final value in v.defines.values) {
        if (int.tryParse(value) == null) {
          expect(core, contains('#define $value '), reason: v.name);
        }
      }
    }
  });

  final direct =
      const LiquidGlassAppearance.ios27Regular(brightness: Brightness.light)
          .copyWith(
            colorModel: const LiquidGlassColorModel.direct(),
          );
  for (final (name, appearances, models) in [
    ('one iOS 27 model', [null, null], FinalShaderModels.ios27),
    ('the direct model', [direct, direct], FinalShaderModels.direct),
    ('mixed models', [null, direct], FinalShaderModels.all),
  ]) {
    testWidgets('a layer of $name draws with its variant what the general '
        'shader draws', (tester) async {
      tester.view
        ..physicalSize = _view
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => RenderLiquidGlassLayer.debugShaderVariants = true);

      RenderLiquidGlassLayer.debugShaderVariants = false;
      await tester.pumpWidget(_scene(appearances));
      await tester.pump();
      final general = await _capture(tester);

      RenderLiquidGlassLayer.debugShaderVariants = true;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_scene(appearances));
      await tester.pump();
      final layer = _layer(tester);
      final kind = appearances.toSet().length > 1
          ? FinalShaderKind.material
          : FinalShaderKind.single;
      expect(
        identical(
          layer.debugBackdropShader,
          // The scene's glass is frosted, so it draws with a variant that
          // can frost a copy.
          layer.finalShaders[FinalShaderVariant.indexOf(
            kind,
            models,
            frost: true,
          )],
        ),
        isTrue,
      );
      final variant = await _capture(tester);

      debugGlassPolicy = const PlanPolicy(shaderFrost: false);
      addTearDown(() => debugGlassPolicy = const PlanPolicy());
      expect(
        identical(
          layer.debugBackdropShader,
          layer.finalShaders[FinalShaderVariant.indexOf(kind, models)],
        ),
        isTrue,
      );

      var largest = 0;
      for (var i = 0; i < general.length; i++) {
        final d = (general[i] - variant[i]).abs();
        if (d > largest) largest = d;
      }
      expect(largest, lessThanOrEqualTo(1));
    }, skip: skipProperGlassTests);
  }
}
