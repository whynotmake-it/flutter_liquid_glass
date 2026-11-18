import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// What reads a backdrop or takes a copy of the screen. The renderer reads
// the backdrop for every surface, through the view's composer
// (LiquidGlassBackdropFilterLayer for a filter of the widget layer's own).
final _read = RegExp(
  r'toImageSync\(|pushBackdropFilter\(|(?<![\w.])(?:BackdropFilterLayer|'
  r'BackdropFilter|BackdropKey|BackdropGroup)\(',
);

// Code the stack replaced, with the files that still hold it. A listed file
// that stops offending fails too, so the list only shrinks.
final _bans = <String, (RegExp, Set<String>)>{
  'a release velocity comes from InputRegion': (
    RegExp(r'\bVelocityTracker\b'),
    {},
  ),
  // A motion keeps its time on its Motion's cursor and asks its parts
  // whether they rest.
  'a motion keeps no clock of its own': (RegExp(r'\bdouble _now\b'), {}),
  'rest tolerances are MotionRest': (RegExp(r'\bGlassRest\b'), {}),
  // A renderer reads a body's field when it draws one (GlassOutline).
  'no widget asks which renderer draws it': (
    RegExp(r'(?<!other )\bis!? (?:Flat|Liquid|Adaptive)GlassRenderer\b'),
    {},
  ),
  'a press is a GlassPress': (RegExp(r'\bFlexInteraction\('), {}),
  // Every const Object() is one object, so two such slots of a motion
  // would replace each other's reactions.
  'a reaction slot is a symbol': (
    RegExp(r'static const _\w+ = Object\(\);'),
    {},
  ),
};

void main() {
  for (final MapEntry(key: rule, value: (pattern, allowed)) in _bans.entries) {
    test('lib: $rule', () {
      final found = <String>{};
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      for (final file in files) {
        final code = file.readAsLinesSync().where(
          (line) => !line.trimLeft().startsWith('//'),
        );
        if (code.any(pattern.hasMatch)) found.add(file.path);
      }
      expect(found.difference(allowed), isEmpty, reason: 'new offenders');
      expect(allowed.difference(found), isEmpty, reason: 'drop from the list');
    });
  }

  test('no backdrop read outside the renderer', () {
    final found = <String, int>{};
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      var count = 0;
      for (final line in file.readAsLinesSync()) {
        if (line.trimLeft().startsWith('//')) continue;
        count += _read.allMatches(line).length;
      }
      if (count > 0) found[file.path] = count;
    }
    expect(found, isEmpty);
  });

  group('public libraries', () {
    final export = RegExp(
      r'''export\s+'([^']+)'\s*(show\s+([^;]*))?;''',
      multiLine: true,
    );
    final libraries = Directory(
      'lib',
    ).listSync().whereType<File>().where((file) => file.path.endsWith('.dart'));

    test('export their own files by show lists only', () {
      final offenders = <String>[];
      for (final library in libraries) {
        for (final match in export.allMatches(library.readAsStringSync())) {
          final uri = match.group(1)!;
          if (uri.startsWith('package:kinesis/')) continue;
          final whole = !uri.startsWith('src/') && !uri.startsWith('package:');
          if (whole) continue;
          // The controls take the renderer's shapes and fields.
          final foreign =
              uri.startsWith('package:') &&
              uri != 'package:liquid_glass_renderer/painting.dart';
          if (foreign || match.group(2) == null) {
            offenders.add('${library.path}: $uri');
          }
        }
      }
      expect(offenders, isEmpty);
    });

    test('show no internal name', () {
      final offenders = <String>[];
      for (final library in libraries) {
        for (final match in export.allMatches(library.readAsStringSync())) {
          final names = match.group(3);
          if (names == null || match.group(1)!.startsWith('package:')) continue;
          final source = File('lib/${match.group(1)}').readAsStringSync();
          for (final name in names.split(',').map((name) => name.trim())) {
            final declared = RegExp(
              r'((?:^@\w+(?:\([^)]*\))?\n)*)^[^\n/]*?'
              '(?:class|enum|typedef|mixin|extension)\\s+$name\\b',
              multiLine: true,
            ).firstMatch(source);
            if (declared?.group(1)?.contains('@internal') ?? false) {
              offenders.add('${library.path}: $name');
            }
          }
        }
      }
      expect(offenders, isEmpty);
    });
  });
}
