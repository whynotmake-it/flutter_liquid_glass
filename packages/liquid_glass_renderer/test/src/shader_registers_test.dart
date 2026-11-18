// The work registers each shader takes on a Mali-G78 and on a Mali-G52, and
// the bytes it spills to the stack, as Arm's offline compiler counts them,
// against test/shader_registers.txt.
//
// A shader that needs more than 32 runs half as many fragments at once on
// those GPUs, one that spills reads and writes memory for every fragment,
// and an edit to a file several shaders include can take one over without
// any picture changing. The numbers are reviewed like an API: a change
// shows up here as a diff of the file. After reading it:
// flutter test --dart-define=UPDATE_SHADER_REGISTERS=true
//   test/src/shader_registers_test.dart
//
// A line reads: the shader, its registers on the Mali-G78, those on the
// Mali-G52, and the most bytes it spills on either. The Mali-G52 takes
// more than 32 for most glass shaders: the count there is held so that it
// does not grow unseen, not because it was brought under the limit.
//
// Needs `malioc` (Arm Performance Studio) on the path, and skips without it.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

const _update = bool.fromEnvironment('UPDATE_SHADER_REGISTERS');
const _reviewed = 'test/shader_registers.txt';
const _shaders = 'lib/assets/shaders';

// The engine's shader compiler lies beside the tester that runs this.
final _engine = File(Platform.resolvedExecutable).parent;
final _impellerc = File('${_engine.path}/impellerc');

bool get _hasMalioc {
  try {
    return Process.runSync('malioc', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void _compile(List<String> arguments) {
  final result = Process.runSync(_impellerc.path, [
    ...arguments,
    '--include=${_engine.path}/shader_lib',
    '--include=$_shaders',
    '--include=$_shaders/gpu',
  ]);
  if (result.exitCode != 0) {
    fail('impellerc ${arguments.join(' ')}:\n${result.stderr}');
  }
}

// The SPIR-V a runtime-effect library holds for Vulkan: the module begins at
// its magic number, and its byte length is the word before it. Some
// versions of the compiler write the module alone.
Uint8List _spirvOf(Uint8List library) {
  const magic = [0x03, 0x02, 0x23, 0x07];
  for (var i = 0; i + 4 <= library.length; i++) {
    if (library[i] == magic[0] &&
        library[i + 1] == magic[1] &&
        library[i + 2] == magic[2] &&
        library[i + 3] == magic[3]) {
      if (i < 4) return library;
      final length = ByteData.sublistView(
        library,
        i - 4,
        i,
      ).getUint32(0, Endian.little);
      return Uint8List.sublistView(library, i, i + length);
    }
  }
  fail('No SPIR-V in the library.');
}

// The cores measured: the Mali-G78, whose count leads each line, and the
// Mali-G52, an older core on which the same shader can take more.
const _cores = ['Mali-G78', 'Mali-G52'];

// The work registers [spirv] takes on [core], and the bytes it spills to
// the stack there.
(int, int) _measure(String spirv, String core) {
  final result = Process.runSync('malioc', [
    '--core',
    core,
    '--fragment',
    '--vulkan',
    '--format',
    'json',
    spirv,
  ]);
  final report = jsonDecode(result.stdout as String) as Map<String, Object?>;
  final shader = (report['shaders']! as List<Object?>).first! as Map;
  final variant = (shader['variants'] as List<Object?>).first! as Map;
  int? registers;
  int? spilled;
  for (final property in variant['properties'] as List<Object?>) {
    switch (property) {
      case {'name': 'work_registers_used', 'value': final int value}:
        registers = value;
      case {'name': 'stack_spill_bytes', 'value': final int value}:
        spilled = value;
    }
  }
  if (registers == null || spilled == null) {
    fail('malioc reported no registers for $spirv on $core:\n${result.stdout}');
  }
  return (registers, spilled);
}

// A line of the reviewed file: the registers on the Mali-G78, those on the
// Mali-G52, and the most bytes either spills.
String _lineOf(String name, String spirv) {
  final [(g78, spill78), (g52, spill52)] = [
    for (final core in _cores) _measure(spirv, core),
  ];
  final spill = spill78 > spill52 ? spill78 : spill52;
  return '$name $g78 g52=$g52 spill=$spill';
}

void main() {
  test(
    'the shaders take the work registers that were reviewed',
    () {
      final out = Directory.systemTemp.createTempSync('shader_registers');
      addTearDown(() => out.deleteSync(recursive: true));
      final lines = <String>[];

      // The runtime effects: what a glass filter or a frost runs.
      final effects = [
        for (final file in Directory(_shaders).listSync())
          if (file.path.endsWith('.frag')) file.uri.pathSegments.last,
      ]..sort();
      for (final name in effects) {
        final library = '${out.path}/$name.iplr';
        _compile([
          '--runtime-stage-vulkan',
          '--input=$_shaders/$name',
          '--sl=$library',
          '--spirv=${out.path}/$name.spv',
        ]);
        final spirv = File('${out.path}/$name.vulkan.spv')
          ..writeAsBytesSync(_spirvOf(File(library).readAsBytesSync()));
        lines.add(_lineOf(name, spirv.path));
      }

      // The passes that draw a geometry atlas.
      final passes = [
        for (final file in Directory('$_shaders/gpu').listSync())
          if (file.path.endsWith('_fragment.glsl')) file.uri.pathSegments.last,
      ]..sort();
      for (final name in passes) {
        final spirv = '${out.path}/$name.spv';
        _compile([
          '--vulkan',
          '--input-type=frag',
          '--input=$_shaders/gpu/$name',
          '--sl=${out.path}/$name.sl',
          '--spirv=$spirv',
        ]);
        lines.add(_lineOf('gpu/$name', spirv));
      }

      final measured = '${lines.join('\n')}\n';
      final reviewed = File(_reviewed);
      if (_update) {
        reviewed.writeAsStringSync(measured);
        return;
      }
      expect(
        measured,
        reviewed.readAsStringSync(),
        reason:
            'A shader takes other work registers or spills another amount '
            'than was reviewed. Read the diff, then run with '
            '--dart-define=UPDATE_SHADER_REGISTERS=true.',
      );
    },
    skip: !_impellerc.existsSync()
        ? 'no impellerc beside the tester'
        : !_hasMalioc
        ? 'malioc is not on the path'
        : false,
  );
}
