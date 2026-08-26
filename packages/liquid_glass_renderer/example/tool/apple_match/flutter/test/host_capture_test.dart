import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:apple_match_flutter/scene.dart';
import 'package:apple_match_flutter/scene_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

const _scenePath = String.fromEnvironment('HOST_CAPTURE_SCENE');
const _settingsPath = String.fromEnvironment('HOST_CAPTURE_SETTINGS');
const _outputPath = String.fromEnvironment('HOST_CAPTURE_OUT');
const _probe = String.fromEnvironment('HOST_CAPTURE_PROBE');

void main() {
  final configurationMissing =
      _scenePath.isEmpty ||
      _settingsPath.isEmpty ||
      _outputPath.isEmpty ||
      !const {'A', 'B', 'C', 'D'}.contains(_probe);

  testWidgets('captures the requested probe with the macOS Impeller renderer', (
    tester,
  ) async {
    expect(
      ui.ImageFilter.isShaderFilterSupported,
      isTrue,
      reason: 'host fitting must exercise the real shader-filter path',
    );

    final sceneFile = File(_scenePath).absolute;
    final settingsFile = File(_settingsPath).absolute;
    final output = Directory(_outputPath).absolute..createSync(recursive: true);
    final scene = MatchScene.fromBase64(
      base64Encode(utf8.encode(sceneFile.readAsStringSync())),
    );
    final settings =
        jsonDecode(settingsFile.readAsStringSync())! as Map<String, Object?>;

    tester.view
      ..devicePixelRatio = scene.scale.toDouble()
      ..physicalSize = Size(
        scene.width * scene.scale,
        scene.height * scene.scale,
      );
    addTearDown(tester.view.reset);

    final captureKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: captureKey,
          child: MatchSceneView(
            scene: scene,
            probe: _probe,
            settings: settings,
          ),
        ),
      ),
    );
    await _pumpUntilGlassReady(tester);
    await tester.pump();

    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await expectLater(
      boundary.toImage(pixelRatio: scene.scale.toDouble()),
      matchesGoldenFile(Uri.file('${output.path}/$_probe.png')),
    );

    settingsFile.copySync('${output.path}/settings.json');
  }, skip: configurationMissing);
}

Future<void> _pumpUntilGlassReady(WidgetTester tester) async {
  for (var frame = 0; frame < 60; frame++) {
    if (find.byType(LiquidGlassLayer).evaluate().isNotEmpty &&
        find.byType(FakeGlass).evaluate().isEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  fail('Flutter GPU LiquidGlassLayer did not become ready within 60 frames');
}
