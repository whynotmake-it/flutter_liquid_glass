import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:apple_match_flutter/scene.dart';
import 'package:apple_match_flutter/scene_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

// Temporary fitting helper: renders many settings vectors against one scene in
// a single `flutter test` process, so parameter scans do not pay the host
// capture startup cost per candidate. Enabled only when HOST_CAPTURE_SWEEP is
// set; the regular single-capture test is unchanged.
const _scenePath = String.fromEnvironment('HOST_CAPTURE_SCENE');
const _sweepPath = String.fromEnvironment('HOST_CAPTURE_SWEEP');
const _outputPath = String.fromEnvironment('HOST_CAPTURE_OUT');
const _probeList = String.fromEnvironment('HOST_CAPTURE_PROBES');
const _dprOverride = String.fromEnvironment('HOST_CAPTURE_DPR');
const _captureFake = bool.fromEnvironment('HOST_CAPTURE_FAKE');

void main() {
  final configurationMissing =
      _scenePath.isEmpty ||
      _sweepPath.isEmpty ||
      _outputPath.isEmpty ||
      _probeList.isEmpty;

  testWidgets(
    'captures a sweep of settings vectors',
    (tester) async {
      expect(ui.ImageFilter.isShaderFilterSupported, isTrue);

      final sceneFile = File(_scenePath).absolute;
      final sweepFile = File(_sweepPath).absolute;
      final output = Directory(_outputPath).absolute
        ..createSync(recursive: true);
      final scene = MatchScene.fromBase64(
        base64Encode(utf8.encode(sceneFile.readAsStringSync())),
      );
      final sweep = jsonDecode(sweepFile.readAsStringSync())! as List<Object?>;
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

      final shadowsWereDisabled = debugDisableShadows;
      debugDisableShadows = false;
      try {
        for (final entry in sweep) {
          final map = entry! as Map<String, Object?>;
          final name = map['name']! as String;
          final settings = map['settings']! as Map<String, Object?>;
          final candidate = Directory('${output.path}/$name')
            ..createSync(recursive: true);
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
              matchesGoldenFile(Uri.file('${candidate.path}/$probe.png')),
            );
          }
          File('${candidate.path}/settings.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(settings),
          );
        }
      } finally {
        debugDisableShadows = shadowsWereDisabled;
      }
    },
    skip: configurationMissing,
    tags: 'golden',
  );
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
  fail('glass did not become ready within 60 frames');
}
