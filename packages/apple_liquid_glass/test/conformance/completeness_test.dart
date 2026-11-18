import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'checks.dart';
import 'harness.dart';
import 'known.dart';
import 'registry.dart';

const _widgetBases = {
  'Widget',
  'StatelessWidget',
  'StatefulWidget',
  'InheritedWidget',
  'InheritedNotifier',
  'InheritedModel',
  'ProxyWidget',
  'ParentDataWidget',
  'RenderObjectWidget',
  'LeafRenderObjectWidget',
  'SingleChildRenderObjectWidget',
  'MultiChildRenderObjectWidget',
  'PresentationPageRoute',
  'PageRoute',
  'ModalRoute',
};

final _classLine = RegExp(
  r'^(?:(?:abstract|base|final|sealed|interface|mixin)\s+)*class\s+(\w+)'
  r'(?:<[^>]*>)?(?:\s+extends\s+(\w+))?',
);

final _inputMember = RegExp(
  r'^  final (?:bool enabled|void Function\([^)]*\)\?? on\w+)$',
);

final _function = RegExp(r'^\S.*?\b(show\w+)(?:<\w+>)?\($');

/// The package's own public names that take input: widget and route
/// classes, the entries of bars and menus, classes that carry a callback or
/// an enabled flag, and the `show` functions.
Set<String> _interactiveApi() {
  final lines = File('test/api/public_api.txt').readAsLinesSync();
  final supers = <String, String?>{};
  final input = <String>{};
  final functions = <String>{};
  var own = false;
  String? current;
  for (final line in lines) {
    if (line.startsWith('# package:')) {
      own = line.startsWith('# package:apple_liquid_glass/');
      current = null;
      continue;
    }
    if (line.startsWith('re-exported from')) own = false;
    if (!own) continue;
    final declared = _classLine.firstMatch(line);
    if (declared != null && !line.contains('(see package:')) {
      current = declared.group(1);
      supers[current!] = declared.group(2);
      continue;
    }
    if (!line.startsWith(' ')) current = null;
    if (current != null && _inputMember.hasMatch(line)) input.add(current);
    final function = _function.firstMatch(line);
    if (function != null) functions.add(function.group(1)!);
  }
  bool widgetish(String name) {
    final seen = <String>{};
    String? at = name;
    while (at != null && seen.add(at)) {
      final parent = supers[at];
      if (parent == null) return false;
      if (_widgetBases.contains(parent) ||
          parent == 'GlassBarEntry' ||
          parent == 'GlassMenuEntry') {
        return true;
      }
      at = parent;
    }
    return false;
  }

  return {
    for (final name in supers.keys)
      if (widgetish(name) || input.contains(name)) name,
    ...functions,
  };
}

Set<String> _publicNames() => {
  for (final line in File('test/api/public_names.txt').readAsLinesSync())
    if (line.trim().isNotEmpty) line.trim(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final covered = {for (final entry in registry) ...entry.covers};

  test('every public widget is in the registry or listed as taking no '
      'input', () {
    final missing = _interactiveApi()
        .difference(covered)
        .difference(nonInteractive.keys.toSet());
    expect(
      missing,
      isEmpty,
      reason:
          'add an Entry to test/conformance/registry.dart, or a line with '
          'the reason to nonInteractive',
    );
  });

  test('the registry names only public names', () {
    final names = _publicNames();
    expect(covered.difference(names), isEmpty);
    expect(nonInteractive.keys.toSet().difference(names), isEmpty);
    expect(covered.intersection(nonInteractive.keys.toSet()), isEmpty);
  });

  test('entry names are unique', () {
    final ids = [for (final entry in registry) entry.id];
    expect(ids.toSet().length, ids.length);
  });

  test('every known failure names an entry and a check that applies', () {
    final pairs = {
      for (final entry in registry) ...[
        pairKey(entry.id, leakCheck),
        for (final check in checks)
          if (check.applies(entry)) pairKey(entry.id, check.name),
      ],
    };
    expect(readKnown().keys.toSet().difference(pairs), isEmpty);
  });

  test('the known failures are sorted', () {
    final keys = readKnown().keys.toList();
    final sorted = [...keys];
    sorted.sort();
    expect(keys, sorted);
  });

  test('every exemption and every failure a reference declares names a '
      'check that applies', () {
    final stray = [
      for (final entry in registry)
        for (final check in {...entry.exempt.keys, ...entry.fails.keys})
          if (!_applies(check, entry)) pairKey(entry.id, check),
    ];
    expect(stray, isEmpty);
  });

  test('only a bad reference declares failures, only a control is exempt, '
      'and every exemption says why', () {
    for (final entry in registry) {
      final bad = entry.id.startsWith('reference.bad.');
      final reference = entry.id.startsWith('reference.');
      expect(entry.fails.isNotEmpty, bad, reason: entry.id);
      if (reference) expect(entry.exempt, isEmpty, reason: entry.id);
      for (final MapEntry(:key, :value) in entry.exempt.entries) {
        expect(
          value.because.trim(),
          isNotEmpty,
          reason: pairKey(entry.id, key),
        );
      }
    }
  });

  test('the defects name no reference and nothing an entry declares', () {
    final declared = {
      for (final entry in registry)
        for (final check in {...entry.exempt.keys, ...entry.fails.keys})
          pairKey(entry.id, check),
    };
    final keys = readKnown().keys;
    expect(keys.where((key) => key.startsWith('reference.')), isEmpty);
    expect(keys.where(declared.contains), isEmpty);
  });

  test('the reference controls calibrate every check: a good one passes, '
      'a bad one declares it fails', () {
    final unseen = <String>[];
    for (final check in [...checks.map((c) => c.name), leakCheck]) {
      final failing = registry.where(
        (entry) =>
            entry.id.startsWith('reference.bad.') &&
            entry.fails.containsKey(check),
      );
      final passing = registry.where(
        (entry) =>
            entry.id.startsWith('reference.good.') && _applies(check, entry),
      );
      if (failing.isEmpty) unseen.add('$check: no bad reference fails it');
      if (passing.isEmpty) unseen.add('$check: no good reference meets it');
    }
    expect(unseen, isEmpty);
  });
}

bool _applies(String check, Entry entry) =>
    check == leakCheck ||
    checks.any((c) => c.name == check && c.applies(entry));
