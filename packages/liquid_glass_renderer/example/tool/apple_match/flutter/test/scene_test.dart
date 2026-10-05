import 'dart:convert';
import 'dart:io';

import 'package:apple_match_flutter/scene.dart';
import 'package:apple_match_flutter/scene_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/loupe/liquid_glass_loupe.dart';

void main() {
  test('loads the shared deterministic scene', () {
    final file = File('../scenes/toolbar_capsule.json');
    final encoded = base64Encode(utf8.encode(file.readAsStringSync()));
    final scene = MatchScene.fromBase64(encoded);
    expect(scene.width, 402);
    expect(scene.height, 874);
    expect(scene.scale, 3);
    expect(scene.probes.keys, orderedEquals(['A', 'B', 'C', 'D']));
    expect(scene.shapeRect.width, closeTo(225.333, 0.0001));
    expect(scene.shapeKind, 'capsule');
    expect(scene.profile, 'toolbar_capsule');
  });

  test('shared material scenes select shape from scene geometry', () {
    final expected = <String, Type>{
      'material_capsule': LiquidRoundedRectangle,
      'material_circle': LiquidOval,
      'material_card': LiquidRoundedSuperellipse,
    };
    for (final entry in expected.entries) {
      final file = File('../scenes/${entry.key}.json');
      final scene = MatchScene.fromBase64(
        base64Encode(utf8.encode(file.readAsStringSync())),
      );
      final shape = matchGlassShape(
        const {},
        scene.shapeKind,
        scene.cornerRadius,
      );
      expect(shape.runtimeType, entry.value, reason: entry.key);
    }
  });

  testWidgets('tile-grid probes use the deterministic tile painter', (
    tester,
  ) async {
    final file = File('../scenes/material_capsule.json');
    final scene = MatchScene.fromBase64(
      base64Encode(utf8.encode(file.readAsStringSync())),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MatchSceneView(scene: scene, probe: 'A', settings: const {}),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is TileGridPainter,
      ),
      findsOneWidget,
    );
  });

  testWidgets('loupe scenes use the full-resolution liquid glass loupe', (
    tester,
  ) async {
    final file = File('../scenes/loupe.json');
    final scene = MatchScene.fromBase64(
      base64Encode(utf8.encode(file.readAsStringSync())),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MatchSceneView(scene: scene, probe: 'A', settings: const {}),
      ),
    );

    expect(scene.profile, 'loupe');
    expect(find.byType(LiquidGlassLoupe), findsOneWidget);
    expect(find.byType(LiquidGlassLoupeSource), findsOneWidget);
  });

  testWidgets('tab holdout includes deterministic foreground content', (
    tester,
  ) async {
    final file = File('../scenes/tab_bar_holdout.json');
    final scene = MatchScene.fromBase64(
      base64Encode(utf8.encode(file.readAsStringSync())),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MatchSceneView(scene: scene, probe: 'A', settings: const {}),
      ),
    );

    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Third'), findsOneWidget);
  });

  test('maps core optical settings', () {
    const values = <String, Object?>{
      'frost': 9.0,
      'refractionHeight': 12.0,
      'refractionAmount': 54.5,
      'backdropShrink': 0.1,
      'dispersion': -0.06,
      'highlight': 0.4,
      'contourStrength': 0.2,
      'bevelShadowStrength': 0.025,
      'saturation': 1.2,
    };
    final settings = matchGlassSettings(values);
    final appearance = matchGlassAppearance(values);
    expect(settings.frost, 9);
    expect(settings.refractionHeight, 12);
    expect(settings.highlight, 0.4);
    expect(settings.contourStrength, 0.2);
    expect(settings.bevelShadowStrength, 0.025);
    expect(settings.refractionAmount, 54.5);
    expect(settings.backdropShrink, 0.1);
    expect(settings.dispersion, -0.06);
    expect(appearance.saturation, 1.2);
  });

  MatchScene loadScene(String id) => MatchScene.fromJson(
    jsonDecode(File('../scenes/$id.json').readAsStringSync())!
        as Map<String, Object?>,
  );

  test('settings keys match settings/contract.json', () {
    final contract =
        jsonDecode(File('../settings/contract.json').readAsStringSync())!
            as Map<String, Object?>;
    final keys = {
      for (final entry in contract.entries)
        if (entry.key != r'$comment') ...(entry.value! as List).cast<String>(),
    };
    expect(matchSettingsKeys, keys);
  });

  test('rejects settings the renderer does not read', () {
    expect(
      () => checkMatchSettings({'frost': 1, 'contourWidth': 1}),
      throwsArgumentError,
    );
    checkMatchSettings({'frost': 1, 'blend': 30});
  });

  testWidgets('merge scenes blend both shapes in one group', (tester) async {
    final scene = loadScene('merge_rect_circle');
    expect(scene.mergeShape!.kind, 'circle');
    expect(scene.mergeShape!.rect, const Rect.fromLTWH(236, 402, 70, 70));
    expect(scene.containerSpacing, 40);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MatchSceneView(scene: scene, probe: 'A', settings: const {}),
      ),
    );
    final group = tester.widget<LiquidGlassBlendGroup>(
      find.byType(LiquidGlassBlendGroup),
    );
    expect(group.blend, 40);
    final shapes = tester
        .widgetList<LiquidGlass>(find.byType(LiquidGlass))
        .map((glass) => glass.shape.runtimeType)
        .toList();
    expect(shapes, [LiquidRoundedSuperellipse, LiquidOval]);
  });

  test('clear and tinted scenes default their appearance from the scene', () {
    final clear = loadScene('material_card_clear');
    expect(clear.glassVariant, 'clear');
    expect(
      matchGlassAppearance(const {}, clear).colorModel,
      const LiquidGlassColorModel.ios27Clear(),
    );
    expect(
      () => matchGlassAppearance(const {'colorModel': 'ios27Light'}, clear),
      throwsArgumentError,
    );

    final tinted = loadScene('material_tint_blue');
    expect(tinted.glassTint, const Color(0xFF007AFF));
    expect(
      matchGlassAppearance(const {}, tinted).tint,
      const Color(0xFF007AFF),
    );
    expect(
      matchGlassAppearance(const {'tintAlpha': 0.4}, tinted).tint,
      const Color(0xFF007AFF).withValues(alpha: 0.4),
    );
    expect(
      () => matchGlassAppearance(const {'tintRed': 255}, tinted),
      throwsArgumentError,
    );
  });
}
