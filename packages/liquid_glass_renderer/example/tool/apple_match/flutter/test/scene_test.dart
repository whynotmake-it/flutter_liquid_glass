import 'dart:convert';
import 'dart:io';

import 'package:apple_match_flutter/scene.dart';
import 'package:apple_match_flutter/scene_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

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

  testWidgets('loupe scenes magnify before the glass layer', (tester) async {
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
    expect(find.byType(RawMagnifier), findsOneWidget);
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
    final settings = matchGlassSettings(const {
      'blur': 9.0,
      'thickness': 12.0,
      'lightIntensity': 0.4,
      'edgeAlpha': 0.2,
      'edgeWidth': 1.0,
      'contourTransmissionRatio': 0.75,
      'contourOffset': 0.5,
      'curvatureLighting': 0.4,
      'innerShadowStrength': 0.025,
      'innerShadowDepth': 12.0,
      'exteriorShadowSizeResponse': 0.8,
      'refractiveIndex': 1.15,
      'saturation': 1.2,
    });
    expect(settings.frost, 9);
    expect(settings.thickness, 12);
    expect(settings.highlight, 0.4);
    expect(settings.contourStrength, 0.2);
    expect(settings.contourWidth, 1.0);
    expect(settings.contourTransmittance, 0.75);
    expect(settings.contourOffset, 0.5);
    expect(settings.curvatureLighting, 0.4);
    expect(settings.bevelShadowStrength, 0.025);
    expect(settings.bevelShadowDepth, 12.0);
    expect(settings.exteriorShadowSizeResponse, 0.8);
    expect(settings.edgeRefraction, closeTo(54.5, 0.1));
    expect(settings.saturation, 1.2);
  });
}
