import 'dart:io';

import 'package:layer_rules/src/check.dart';

/// Whether the environment asks the debt file to be rewritten:
/// `UPDATE_DEBT=1`.
bool get updateDebtRequested => Platform.environment['UPDATE_DEBT'] == '1';

const _update = 'UPDATE_DEBT=1';

const _header = '''
# Breaks of the layer rules that the code has today, as rule, file, count.
# The list only shrinks: a new break fails the test, and so does a line
# that lists more than the code has. After fixing one, rewrite this file
# with UPDATE_DEBT=1 (it never grows an entry).
''';

/// Holds [found] to the debt listed in [file].
///
/// Returns null when they agree, or a message naming each new break and each
/// listed entry the code no longer has as often. With [update] it rewrites
/// [file] to [found] instead, unless that grows an entry: then it returns
/// the message and leaves the file. A missing file is written from [found].
String? holdDebt(File file, List<Violation> found, {required bool update}) {
  final existing = file.existsSync();
  final listed = existing ? readDebt(file.readAsStringSync()) : <String, int>{};
  final actual = {for (final violation in found) violation.key: violation};
  final grown = [
    for (final violation in actual.values)
      if (violation.count > (listed[violation.key] ?? 0))
        '  $violation (listed: ${listed[violation.key] ?? 0})',
  ];
  final stale = [
    for (final MapEntry(:key, :value) in listed.entries)
      if (value > (actual[key]?.count ?? 0))
        '  $key $value (found: ${actual[key]?.count ?? 0})',
  ];
  grown.sort();
  stale.sort();
  if (update && (grown.isEmpty || !existing)) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(writeDebt(found));
    return null;
  }
  if (grown.isEmpty && stale.isEmpty) return null;
  final message = <String>[
    if (grown.isNotEmpty) ...[
      'New breaks of the layer rules; fix them, the debt list never grows:',
      ...grown,
    ],
    if (stale.isNotEmpty && !update) ...[
      '${file.path} lists more than the code has; rewrite it with $_update:',
      ...stale,
    ],
  ];
  return message.join('\n');
}

/// The entries of a debt file's [text], by rule and file.
Map<String, int> readDebt(String text) => {
  for (final line in text.split('\n'))
    if (line.trim().isNotEmpty && !line.trimLeft().startsWith('#'))
      if (line.trim().split(RegExp(r'\s+')) case [
        final rule,
        final path,
        final count,
      ])
        '$rule $path': int.parse(count),
};

/// The text of a debt file listing [violations], sorted, in aligned columns.
String writeDebt(List<Violation> violations) {
  final sorted = [...violations];
  sorted.sort();
  final ruleWidth = sorted.fold(
    0,
    (width, v) => v.rule.length > width ? v.rule.length : width,
  );
  final fileWidth = sorted.fold(
    0,
    (width, v) => v.file.length > width ? v.file.length : width,
  );
  final out = StringBuffer(_header);
  if (sorted.isNotEmpty) out.writeln();
  for (final violation in sorted) {
    out.writeln(
      '${violation.rule.padRight(ruleWidth)}  '
      '${violation.file.padRight(fileWidth)}  ${violation.count}',
    );
  }
  return out.toString();
}
