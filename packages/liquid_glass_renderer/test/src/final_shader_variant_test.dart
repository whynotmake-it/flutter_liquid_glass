import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

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
          settings: LiquidGlassSettings.ios27RegularLight(),
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
                    shape: const LiquidRoundedSuperellipse(borderRadius: 30),
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
  test('every kind but the material map has a variant per model family', () {
    final names = {for (final v in FinalShaderVariant.all) v.name};
    expect(names, hasLength(FinalShaderVariant.all.length));
    expect(FinalShaderVariant.all, hasLength(10));
    final material =
        FinalShaderVariant.all[FinalShaderVariant.indexOf(
          FinalShaderKind.material,
          FinalShaderModels.direct,
        )];
    expect(material.models, FinalShaderModels.all);
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

  final direct = const LiquidGlassAppearance.ios27RegularLight().copyWith(
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
          layer.renderShader,
          layer.finalShaders[FinalShaderVariant.indexOf(kind, models)],
        ),
        isTrue,
      );
      final variant = await _capture(tester);

      var largest = 0;
      for (var i = 0; i < general.length; i++) {
        final d = (general[i] - variant[i]).abs();
        if (d > largest) largest = d;
      }
      expect(largest, lessThanOrEqualTo(1));
    }, skip: skipProperGlassTests);
  }
}
