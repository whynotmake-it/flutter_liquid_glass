import 'dart:convert';
import 'dart:io';

/// The recordings of native iOS behaviour the replay tests hold the widgets
/// to.
///
/// Each family of recordings is one gzipped JSON object under
/// `test/fixtures/<source>/<family>.json.gz` that maps a recording's file
/// name to its text: a few hundred recordings stay a few files in the
/// repository and in a review. A recording is still named by the path it
/// would have as a file of a family folder, as in
/// `test/fixtures/ios27-device/menu/fusion.json`.
abstract final class Fixtures {
  static final _families = <String, Map<String, String>>{};

  static Map<String, String> _family(String dir) => _families.putIfAbsent(
    dir,
    () => (jsonDecode(
      utf8.decode(gzip.decode(File('$dir.json.gz').readAsBytesSync())),
    ) as Map<String, Object?>).cast<String, String>(),
  );

  static (String, String) _split(String path) {
    final slash = path.lastIndexOf('/');
    return (path.substring(0, slash), path.substring(slash + 1));
  }

  /// The text of the recording at [path].
  static String read(String path) {
    final (dir, name) = _split(path);
    final text = _family(dir)[name];
    if (text == null) throw ArgumentError.value(path, 'path', 'no recording');
    return text;
  }

  /// The lines of the recording at [path].
  static List<String> lines(String path) =>
      const LineSplitter().convert(read(path));

  /// Whether there is a recording at [path].
  static bool exists(String path) {
    final (dir, name) = _split(path);
    return _family(dir).containsKey(name);
  }

  /// The names of the recordings of the family at [dir], sorted.
  static List<String> names(String dir) {
    final names = _family(dir).keys.toList();
    names.sort();
    return names;
  }
}
