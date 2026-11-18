// Unpacks a family of native recordings into a folder of files, and packs
// such a folder back into the one gzipped file the replay tests read
// (test/support/fixtures.dart).
//
//   dart run tool/fixtures.dart unpack test/fixtures/ios27-device/menu
//   dart run tool/fixtures.dart pack test/fixtures/ios27-device/menu
//
// pack writes keys sorted and no timestamp, so the same recordings give the
// same bytes and an unchanged family shows no diff.
import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  if (arguments.length != 2 || !{'pack', 'unpack'}.contains(arguments[0])) {
    stderr.writeln('usage: dart run tool/fixtures.dart pack|unpack <family>');
    exitCode = 64;
    return;
  }
  final family = arguments[1].replaceAll(RegExp(r'/+$'), '');
  final archive = File('$family.json.gz');
  final folder = Directory(family);
  if (arguments[0] == 'unpack') {
    final recordings = (jsonDecode(
      utf8.decode(gzip.decode(archive.readAsBytesSync())),
    ) as Map<String, Object?>).cast<String, String>();
    folder.createSync(recursive: true);
    for (final MapEntry(:key, :value) in recordings.entries) {
      File('${folder.path}/$key').writeAsStringSync(value);
    }
    stdout.writeln('${recordings.length} recordings in ${folder.path}');
    return;
  }
  final files = folder.listSync().whereType<File>().toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  final recordings = <String, String>{
    for (final file in files)
      file.uri.pathSegments.last: file.readAsStringSync(),
  };
  final bytes = GZipCodec(level: 9).encode(
    utf8.encode(jsonEncode(recordings)),
  );
  archive.writeAsBytesSync(bytes);
  folder.deleteSync(recursive: true);
  stdout.writeln('${recordings.length} recordings in ${archive.path}');
}
