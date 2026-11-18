import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('delays are seconds: no Duration delay parameter in lib', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      if (RegExp(r'Duration\??\s+delay\b').hasMatch(source)) {
        offenders.add(file.path);
      }
    }
    expect(offenders, isEmpty);
  });
}
