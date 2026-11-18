import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';

import 'src/shared.dart';

void main() {
  for (final MapEntry(key: name, value: text) in generatedShaderFiles.entries) {
    test('$name is written from the table', () {
      expectGeneratedFile('lib/assets/shaders/$name', text);
    });
  }

  test('no other shader defines a name or holds a value of the table', () {
    final names = {
      for (final match in RegExp(
        r'^(?:#define|const \w+) (\w+)',
        multiLine: true,
      ).allMatches(generatedShaderFiles['shader_constants.glsl']!))
        match[1]!,
    };
    final values = [
      lumaWeights.$1,
      lumaWeights.$2,
      lumaWeights.$3,
      partingMirror.$1.abs(),
      partingMirror.$2,
      GlassGlint.peak,
      GlassGlint.directVibrancy,
    ];
    final found = <String>[];
    for (final file in Directory('lib/assets/shaders').listSync(
      recursive: true,
    )) {
      final name = file.uri.pathSegments.last;
      if (file is! File || generatedShaderFiles.containsKey(name)) continue;
      if (!name.endsWith('.glsl') && !name.endsWith('.frag')) continue;
      final text = file.readAsStringSync();
      for (final match in RegExp(
        r'^\s*(?:#define|const \w+) (\w+)',
        multiLine: true,
      ).allMatches(text)) {
        if (names.contains(match[1])) found.add('${file.path}: ${match[1]}');
      }
      for (final value in values) {
        final pattern = '(?<![\\d.])${RegExp.escape('$value')}(?!\\d)';
        if (RegExp(pattern).hasMatch(text)) found.add('${file.path}: $value');
      }
    }
    expect(found, isEmpty, reason: 'Take these from shader_constants.glsl.');
  });
}
