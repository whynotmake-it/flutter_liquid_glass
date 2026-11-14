import 'dart:io';

import 'package:layer_rules/layer_rules.dart';
import 'package:layer_rules/src/source.dart';
import 'package:test/test.dart';

const _rules = LayerRules(
  package: 'sample',
  libraries: {
    'base': {},
    'top': {'base'},
  },
  umbrella: 'sample',
  umbrellaReexports: {'package:flutter/widgets.dart'},
  unchecked: {'testing'},
  packages: {'flutter'},
  forbidden: {
    'base': ['package:flutter/widgets.dart'],
  },
  bans: [
    Ban('dynamic', r'\bdynamic\b', allowedIn: {'lib/src/top/t.dart'}),
    Ban('ignore', r'//\s*ignore:', code: false),
  ],
);

void main() {
  final fixture = Directory('test/fixtures/sample');

  test('rule 1 and the table fail without debt', () {
    expect(checkLayers(fixture, _rules).structure, [
      'lib/src/orphan/ has no library file lib/orphan.dart',
      'lib/src/orphan/ is not in the table',
      'lib/src/stray.dart sits directly in lib/src/',
      'lib/top.dart names src/base/a.dart, outside lib/src/top/',
      'the umbrella lib/sample.dart does not export top',
    ]);
  });

  test('rules 2 to 5 are counted per rule and file', () {
    expect(checkLayers(fixture, _rules).violations.map((v) => '$v'), [
      '2:same-library-style lib/src/base/a.dart 1',
      '2:through-library lib/src/base/b.dart 1',
      '2:through-library lib/src/top/t.dart 1',
      '3:not-allowed lib/src/base/a.dart 1',
      '3:not-allowed lib/src/top/t.dart 1',
      '4:forbidden lib/src/base/a.dart 1',
      '4:package lib/src/base/a.dart 1',
      '5:dynamic lib/src/base/a.dart 2',
      '5:ignore lib/src/base/a.dart 1',
    ]);
  });

  test('the umbrella may re-export only the packages it names', () {
    const strict = LayerRules(
      package: 'sample',
      libraries: {
        'base': {},
        'top': {'base'},
      },
      umbrella: 'sample',
    );
    expect(
      checkLayers(fixture, strict).structure,
      contains(
        'the umbrella lib/sample.dart names package:flutter/widgets.dart',
      ),
    );
  });

  test('an umbrella exports the libraries it lists, and only them', () {
    LayerRules listing(Set<String> libraries) => LayerRules(
      package: 'sample',
      libraries: const {
        'base': {},
        'top': {'base'},
      },
      umbrella: 'sample',
      umbrellaLibraries: libraries,
      umbrellaReexports: const {'package:flutter/widgets.dart'},
    );
    bool aboutUmbrella(String error) => error.startsWith('the umbrella');

    expect(
      checkLayers(fixture, listing({'base'})).structure.where(aboutUmbrella),
      isEmpty,
    );
    expect(
      checkLayers(
        fixture,
        listing({'top', 'gone'}),
      ).structure.where(aboutUmbrella),
      unorderedEquals([
        'the umbrella is to export gone, no library',
        'the umbrella lib/sample.dart does not export top',
        'the umbrella lib/sample.dart exports base, which it does not list',
      ]),
    );
  });

  test('a ban allows a folder by a path ending in a slash', () {
    const folder = LayerRules(
      package: 'sample',
      libraries: {
        'base': {},
        'top': {'base'},
      },
      bans: [
        Ban('dynamic', r'\bdynamic\b', allowedIn: {'lib/src/base/'}),
      ],
    );
    expect(
      checkLayers(fixture, folder).violations.map((v) => '$v'),
      contains('5:dynamic lib/src/top/t.dart 1'),
    );
    expect(
      checkLayers(fixture, folder).violations.map((v) => '$v'),
      isNot(contains('5:dynamic lib/src/base/a.dart 2')),
    );
  });

  test('a comment above an occurrence allows it by its reason', () {
    LayerRules withPrint(String? allowedWith) => LayerRules(
      package: 'sample',
      libraries: const {
        'base': {},
        'top': {'base'},
      },
      bans: [Ban('print', r'\bprint\(', allowedWith: allowedWith)],
    );
    expect(
      checkLayers(fixture, withPrint(null)).violations.map((v) => '$v'),
      contains('5:print lib/src/top/t.dart 3'),
    );
    expect(
      checkLayers(fixture, withPrint('Must show:')).violations.map((v) => '$v'),
      contains('5:print lib/src/top/t.dart 2'),
    );
  });

  test('a cycle in the table fails', () {
    const cyclic = LayerRules(
      package: 'sample',
      libraries: {
        'base': {'top'},
        'top': {'base'},
        'orphan': {'nowhere'},
      },
    );
    expect(
      checkLayers(fixture, cyclic).structure,
      containsAll([
        'the table has a cycle: base -> top -> base',
        'the table lets orphan import nowhere, no library',
      ]),
    );
  });

  test('comments and strings are blanked, interpolations kept', () {
    const source = r'''
a /* b /* c */ d */ e // f
r'g\' "h$i" 'j${k + 'l'}m' """n
o""" p''';
    final blanked = blank(source, strings: true);
    expect(blanked.length, source.length);
    expect(blanked.split('\n').map((line) => line.length), [
      for (final line in source.split('\n')) line.length,
    ]);
    expect(blanked.replaceAll(RegExp(r'\s+'), ' ').trim(), 'a e k + p');
    expect(blank('x // y'), 'x     ');
  });

  test('directives list every URI, conditional ones included', () {
    expect(
      directives('''
library;
// import 'commented.dart';
import 'a.dart' show A;
import 'b.dart'
    if (dart.library.io) 'c.dart';
export 'package:d/d.dart' hide D;
part of 'e.dart';
void f(Object part) {
  part is! String || g('h.dart');
}
'''),
      [
        ['a.dart'],
        ['b.dart', 'c.dart'],
        ['package:d/d.dart'],
      ],
    );
  });

  group('debt', () {
    late Directory temp;
    late File file;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('layer_rules_');
      file = File('${temp.path}/rules/debt.txt');
    });

    tearDown(() => temp.deleteSync(recursive: true));

    const a = Violation(notAllowed, 'lib/src/a/a.dart', 2);
    const b = Violation('5:dynamic', 'lib/src/b/b.dart', 1);

    test('a missing file is written, sorted and readable', () {
      expect(holdDebt(file, [b, a], update: true), isNull);
      expect(
        file.readAsStringSync(),
        endsWith(
          '\n'
          '3:not-allowed  lib/src/a/a.dart  2\n'
          '5:dynamic      lib/src/b/b.dart  1\n',
        ),
      );
      expect(readDebt(file.readAsStringSync()), {
        '3:not-allowed lib/src/a/a.dart': 2,
        '5:dynamic lib/src/b/b.dart': 1,
      });
      expect(holdDebt(file, [a, b], update: false), isNull);
    });

    test('a new or grown entry fails, and an update refuses it', () {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(writeDebt([a]));
      const grown = Violation(notAllowed, 'lib/src/a/a.dart', 3);
      final failure = holdDebt(file, [grown, b], update: false);
      expect(
        failure,
        contains('  3:not-allowed lib/src/a/a.dart 3 (listed: 2)'),
      );
      expect(failure, contains('  5:dynamic lib/src/b/b.dart 1 (listed: 0)'));
      final before = file.readAsStringSync();
      expect(holdDebt(file, [grown], update: true), isNotNull);
      expect(file.readAsStringSync(), before);
    });

    test('a stale entry fails, and an update shrinks the file', () {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(writeDebt([a, b]));
      const fewer = Violation(notAllowed, 'lib/src/a/a.dart', 1);
      final failure = holdDebt(file, [fewer], update: false);
      expect(
        failure,
        contains('  3:not-allowed lib/src/a/a.dart 2 (found: 1)'),
      );
      expect(failure, contains('  5:dynamic lib/src/b/b.dart 1 (found: 0)'));
      expect(holdDebt(file, [fewer], update: true), isNull);
      expect(readDebt(file.readAsStringSync()), {
        '3:not-allowed lib/src/a/a.dart': 1,
      });
    });
  });
}
