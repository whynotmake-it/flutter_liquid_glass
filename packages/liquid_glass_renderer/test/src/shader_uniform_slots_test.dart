import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The uniform declarations, samplers aside, of [file] and what it includes
/// from its own directory, whichever branch of an `#if` they sit in.
int _uniformDeclarations(File file) {
  var count = 0;
  for (final line in file.readAsLinesSync()) {
    final include = RegExp('^#include "(.+)"').firstMatch(line);
    if (include != null) {
      final included = File('${file.parent.path}/${include.group(1)}');
      if (included.existsSync()) count += _uniformDeclarations(included);
    } else if (RegExp('^uniform (?!sampler)').hasMatch(line)) {
      count++;
    }
  }
  return count;
}

void main() {
  test('every runtime shader fits the 31 buffers a Metal stage has', () {
    // Impeller's Metal backend binds each uniform declaration of a runtime
    // effect to a buffer of its own, and the library fails to build past
    // buffer 30: on Metal the shader then draws nothing.
    final shaders = Directory('lib/assets/shaders')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.frag'));
    expect(shaders, isNotEmpty);
    for (final shader in shaders) {
      expect(
        _uniformDeclarations(shader),
        lessThanOrEqualTo(31),
        reason: shader.path,
      );
    }
  });
}
