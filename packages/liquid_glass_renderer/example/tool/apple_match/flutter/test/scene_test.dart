import 'dart:convert';
import 'dart:io';

import 'package:apple_match_flutter/scene.dart';
import 'package:apple_match_flutter/scene_view.dart';
import 'package:flutter_test/flutter_test.dart';

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
  });

  test('maps core optical settings', () {
    final settings = matchGlassSettings(const {
      'blur': 9.0,
      'thickness': 12.0,
      'lightIntensity': 0.4,
      'refractiveIndex': 1.15,
      'saturation': 1.2,
    });
    expect(settings.blur, 9);
    expect(settings.thickness, 12);
    expect(settings.lightIntensity, 0.4);
    expect(settings.refractiveIndex, 1.15);
    expect(settings.saturation, 1.2);
  });
}
