import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Members of exported classes that may name `Spring`, each with its reason.
const _allowed = {
  // The app's own choice of spring for its theme change.
  'GlassScope.GlassScope',
  'GlassScope.themeSpring',
  // The spring of the app's own `withSpring` around a change of the items,
  // which the selector reads as its layout spring and hands on.
  'LensMotion.reslot',
};

final _classHeader = RegExp(
  r'^(?:(?:abstract|final|sealed|base|interface|mixin)\s+)*'
  r'(?:class|mixin|enum|extension type|extension)\s+(\w+)',
);
final _spring = RegExp(r'\bSpring\b');
final _name = RegExp(r'(\w+)\s*(?:[({=]|$)');

String _memberName(String first, String owner) {
  final head = first
      .replaceAll(RegExp(r'@\w+\s+'), '')
      .replaceAll(RegExp(r'^(?:const|factory)\s+'), '')
      .trim();
  if (head.startsWith('$owner(') || head.startsWith('$owner.')) {
    return RegExp(r'^[\w.]+').firstMatch(head)!.group(0)!;
  }
  return _name.firstMatch(head)?.group(1) ?? head;
}

/// Lists `Class.member` for every member of an exported class in [listing]
/// whose signature names `Spring` and whose first line is not `@internal`.
List<String> springMembers(String listing) {
  final offenders = <String>[];
  String? owner;
  List<String>? member;

  void close() {
    final lines = member;
    member = null;
    if (owner == null || lines == null) return;
    if (!lines.any(_spring.hasMatch)) return;
    if (lines.first.trimLeft().startsWith('@internal')) return;
    offenders.add('$owner.${_memberName(lines.first.trim(), owner)}');
  }

  for (final line in listing.split('\n')) {
    if (line.trim().isEmpty) continue;
    if (!line.startsWith(' ')) {
      close();
      owner = _classHeader.firstMatch(line)?.group(1);
      continue;
    }
    final continues =
        line.startsWith('   ') ||
        line.trimLeft().startsWith('}') ||
        line.trimLeft().startsWith(')');
    if (continues) {
      member?.add(line);
    } else {
      close();
      member = [line];
    }
  }
  close();
  return offenders;
}

void main() {
  test("the exported API names Spring only for the app's own settings", () {
    final listing = File('test/api/public_api.txt').readAsStringSync();
    final offenders = springMembers(
      listing,
    ).where((member) => !_allowed.contains(member)).toList();
    expect(
      offenders,
      isEmpty,
      reason:
          'A law keeps its springs in its @internal tuning class; these '
          'exported members name Spring:\n${offenders.join('\n')}',
    );
  });

  test('the parser finds a spring in a constructor and skips @internal', () {
    const listing = '''
class A extends Motion
  A({
    Spring spring = ...,
  })
  final double x
  @internal static const Spring hidden
  static const Spring shown
function f (see package:x/x.dart)
re-exported from package:kinesis:
  Spring
''';
    expect(springMembers(listing), ['A.A', 'A.shown']);
  });
}
