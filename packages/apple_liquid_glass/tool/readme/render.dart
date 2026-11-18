// Renders the README animations into doc/readme/<scene>.webp.
//
//   dart run tool/readme/render.dart              every scene
//   dart run tool/readme/render.dart switch menu  only these
//   dart run tool/readme/render.dart --encode     encode the frames on disk
//                                                 again, without recording
//
// Each scene runs as a widget test with Impeller (tool/readme/capture.dart),
// which writes its frames to build/readme/<scene>/. When the tester process
// dies partway, the scene starts again from the first missing frame.
// img2webp from libwebp (`brew install webp`) joins the frames into an
// animated WebP.
import 'dart:io';

const _fps = 30;
const _quality = 80;

/// The view heights the retries take in turn; see capture.dart.
const _views = [1600, 1700, 1500, 1800, 1400, 1900, 1650, 1550];

Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent.parent;
  final capture = File('${root.path}/tool/readme/capture.dart');
  final scenes = [
    for (final match in RegExp(
      r"^    name: '(\w+)',$",
      multiLine: true,
    ).allMatches(capture.readAsStringSync()))
      match[1]!,
  ];
  final encodeOnly = arguments.contains('--encode');
  final names = [
    for (final argument in arguments)
      if (argument != '--encode') argument,
  ];
  final unknown = names.where((name) => !scenes.contains(name)).toList();
  if (unknown.isNotEmpty) {
    stderr.writeln('unknown scenes: ${unknown.join(', ')}');
    stderr.writeln('scenes: ${scenes.join(', ')}');
    exitCode = 64;
    return;
  }
  if (!await _has('img2webp')) {
    stderr.writeln('img2webp is missing; install libwebp (brew install webp)');
    exitCode = 69;
    return;
  }

  final frames = Directory('${root.path}/build/readme');
  final output = Directory('${root.path}/doc/readme');
  output.createSync(recursive: true);
  for (final scene in names.isEmpty ? scenes : names) {
    final dir = Directory('${frames.path}/$scene');
    if (encodeOnly) {
      if (!dir.existsSync()) {
        stderr.writeln('$scene: no frames in ${dir.path}');
        exitCode = 1;
        continue;
      }
    } else {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      if (!await _record(root, scene, frames, dir)) {
        exitCode = 1;
        continue;
      }
    }
    final pictures = [
      for (final file in dir.listSync().whereType<File>())
        if (file.path.endsWith('.png')) file.path,
    ];
    pictures.sort();
    final webp = '${output.path}/$scene.webp';
    final encode = await Process.run('img2webp', [
      '-loop',
      '0',
      '-lossy',
      '-q',
      '$_quality',
      '-m',
      '6',
      '-d',
      '${1000 ~/ _fps}',
      ...pictures,
      '-o',
      webp,
    ]);
    if (encode.exitCode != 0) {
      stderr.write(encode.stderr);
      exitCode = 1;
      continue;
    }
    final size = File(webp).lengthSync() ~/ 1024;
    stdout.writeln('$scene: ${pictures.length} frames, $size KB');
  }
}

/// Runs the scene's test until every frame is on disk, starting each retry
/// from the first missing frame.
Future<bool> _record(
  Directory root,
  String scene,
  Directory frames,
  Directory dir,
) async {
  var from = 0;
  for (final view in _views) {
    final run = await Process.run('flutter', [
      'test',
      '--enable-impeller',
      '--enable-flutter-gpu',
      '--dart-define=README_FRAMES=${frames.path}',
      '--dart-define=README_FONTS=${root.path}/tool/readme/fonts',
      '--dart-define=README_SCENE=$scene',
      '--dart-define=README_FROM=$from',
      '--dart-define=README_FPS=$_fps',
      '--dart-define=README_VIEW=$view',
      'tool/readme/capture.dart',
    ], workingDirectory: root.path);
    final count = File('${dir.path}/count');
    if (!count.existsSync()) {
      stderr.write(run.stdout);
      continue;
    }
    final total = int.parse(count.readAsStringSync());
    var next = from;
    while (File(_frame(dir, next)).existsSync()) {
      next++;
    }
    if (next >= total) return true;
    if (run.exitCode == 0) {
      stderr.write(run.stdout);
      return false;
    }
    stdout.writeln('$scene: the tester stopped at frame $next of $total');
    from = next;
  }
  stderr.writeln('$scene: gave up after ${_views.length} runs');
  return false;
}

String _frame(Directory dir, int index) =>
    '${dir.path}/${index.toString().padLeft(4, '0')}.png';

Future<bool> _has(String tool) async {
  try {
    await Process.run(tool, ['-version']);
    return true;
  } on ProcessException {
    return false;
  }
}
