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
const _probeList = String.fromEnvironment('HOST_CAPTURE_PROBES');
const _dprOverride = String.fromEnvironment('HOST_CAPTURE_DPR');
const _captureFake = bool.fromEnvironment('HOST_CAPTURE_FAKE');

void main() {
  final configurationMissing =
      _scenePath.isEmpty ||
      _settingsPath.isEmpty ||
      _outputPath.isEmpty ||
      _probeList.isEmpty;

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
    final captureDpr = _dprOverride.isEmpty
        ? scene.scale.toDouble()
        : double.parse(_dprOverride);

    tester.view
      ..devicePixelRatio = captureDpr
      ..physicalSize = Size(
        scene.width * captureDpr,
        scene.height * captureDpr,
      );
    addTearDown(tester.view.reset);

    final probes = _probeList
        .split(RegExp(r'\s+'))
        .where((probe) => probe.isNotEmpty)
        .toList(growable: false);
    expect(probes, isNotEmpty);
    expect(probes, everyElement(isIn(const {'A', 'B', 'C', 'D'})));

    // Widget tests disable MaskFilter shadows globally. This harness is
    // explicitly fitting those pixels, so enable them while the display list
    // is built and rasterized, then restore the debug global before binding
    // invariants run.
    final shadowsWereDisabled = debugDisableShadows;
    debugDisableShadows = false;
    try {
      for (final probe in probes) {
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: RepaintBoundary(
              key: captureKey,
              child: MatchSceneView(
                scene: scene,
                probe: probe,
                settings: settings,
                fake: _captureFake,
              ),
            ),
          ),
        );
        await _pumpUntilGlassReady(tester, fake: _captureFake);
        await tester.pump();

        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: captureDpr);
        await expectLater(
          image,
          matchesGoldenFile(Uri.file('${output.path}/$probe.png')),
        );
      }
    } finally {
      debugDisableShadows = shadowsWereDisabled;
    }

    settingsFile.copySync('${output.path}/settings.json');
  }, skip: configurationMissing);
}

Future<void> _pumpUntilGlassReady(
  WidgetTester tester, {
  required bool fake,
}) async {
  for (var frame = 0; frame < 60; frame++) {
    final ready = fake
        ? find.byType(FakeGlass).evaluate().isNotEmpty
        : find.byType(LiquidGlassLayer).evaluate().isNotEmpty &&
              find.byType(FakeGlass).evaluate().isEmpty;
    if (ready) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  fail(
    '${fake ? 'FakeGlass' : 'Flutter GPU LiquidGlassLayer'} did not become ready within 60 frames',
  );
}
