import 'dart:io';

import 'package:api_listing/src/diff.dart';

/// Whether the environment asks the snapshot files to be rewritten:
/// `UPDATE_API=1`.
bool get updateRequested => Platform.environment['UPDATE_API'] == '1';

/// The command that rewrites the snapshot files, run from the package root.
const regenerateCommand = 'UPDATE_API=1 flutter test test/public_api_test.dart';

/// Holds [actual] to the reviewed text in [file].
///
/// Returns null when they are equal, or a message with a line diff when they
/// differ. With [update] it writes [actual] to [file] instead and returns
/// null.
String? checkSnapshot(File file, String actual, {required bool update}) {
  if (update) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(actual);
    return null;
  }
  final expected = file.existsSync() ? file.readAsStringSync() : '';
  if (expected == actual) return null;
  return '${file.path} differs from the generated listing '
      '(- reviewed file, + generated now):\n'
      '${lineDiff(expected, actual)}\n'
      'Review the change, then regenerate from the package root:\n'
      '  $regenerateCommand';
}

const _leakHeading =
    'Public signatures name types that no public library exports; export '
    'the type, or mark the member @internal:';

/// Holds [found] to the allowlist in [file], one entry per line.
///
/// Returns null when they hold the same entries, or a message naming the
/// entries [found] adds and the listed entries it no longer has: the list
/// only shrinks, so a fixed entry leaves the file in the same change. With
/// [update] it writes [found] to [file] instead and returns null.
String? checkAllowlist(
  File file,
  List<String> found, {
  required bool update,
}) {
  final sorted = found.toSet().toList();
  sorted.sort();
  if (update) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(sorted.isEmpty ? '' : '${sorted.join('\n')}\n');
    return null;
  }
  final listed = file.existsSync()
      ? {
          for (final line in file.readAsLinesSync())
            if (line.trim().isNotEmpty) line.trim(),
        }
      : <String>{};
  final added = [
    for (final entry in sorted)
      if (!listed.contains(entry)) entry,
  ];
  final fixed = [
    for (final entry in listed)
      if (!sorted.contains(entry)) entry,
  ];
  fixed.sort();
  if (added.isEmpty && fixed.isEmpty) return null;
  return [
    if (added.isNotEmpty) ...[
      _leakHeading,
      for (final entry in added) '  $entry',
    ],
    if (fixed.isNotEmpty) ...[
      'These entries of ${file.path} no longer occur; remove them:',
      for (final entry in fixed) '  $entry',
    ],
  ].join('\n');
}
