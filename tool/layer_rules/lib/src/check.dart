import 'dart:io';

import 'package:layer_rules/src/rules.dart';
import 'package:layer_rules/src/source.dart';

/// The rule a file of `src` reaches another library through a file of its
/// `src` folder instead of its library file, or its own library through its
/// library file.
const throughLibrary = '2:through-library';

/// The rule a file reaches its own library the other way than
/// [LayerRules.sameLibraryImports] says.
const sameLibraryStyle = '2:same-library-style';

/// The rule a library imports a library its row of [LayerRules.libraries]
/// does not name.
const notAllowed = '3:not-allowed';

/// The rule `lib/` imports a package [LayerRules.packages] does not name.
const foreignPackage = '4:package';

/// The rule a library imports a URI [LayerRules.forbidden] names for it.
const forbiddenImport = '4:forbidden';

/// The rule of a [Ban], by its name.
String banned(String name) => '5:$name';

/// How often one file breaks one rule.
final class Violation implements Comparable<Violation> {
  /// [count] breaks of [rule] in [file].
  const Violation(this.rule, this.file, this.count);

  /// The rule, such as [notAllowed] or `banned('dynamic')`.
  final String rule;

  /// The path relative to the package root, such as `lib/src/a/b.dart`.
  final String file;

  /// How many times.
  final int count;

  /// The rule and the file, which identify an entry of the debt file.
  String get key => '$rule $file';

  @override
  int compareTo(Violation other) {
    final byRule = rule.compareTo(other.rule);
    return byRule != 0 ? byRule : file.compareTo(other.file);
  }

  @override
  String toString() => '$rule $file $count';
}

/// What [checkLayers] found.
final class LayerReport {
  /// A report of [structure] errors and [violations].
  const LayerReport({required this.structure, required this.violations});

  /// Breaks of the folder layout (rule 1) and of the configuration itself.
  /// They have no debt: each one fails.
  final List<String> structure;

  /// Breaks of the import rules and the bans, one per rule and file, sorted.
  final List<Violation> violations;
}

/// Checks the package at [root] against [rules].
LayerReport checkLayers(Directory root, LayerRules rules) =>
    _Checker(root, rules).run();

final class _Checker {
  _Checker(this.root, this.rules);

  final Directory root;
  final LayerRules rules;
  final structure = <String>[];
  final counts = <String, Map<String, int>>{};

  String get lib => '${root.path}/lib';

  void count(String rule, String file) {
    final byFile = counts[rule] ??= {};
    byFile[file] = (byFile[file] ?? 0) + 1;
  }

  LayerReport run() {
    _checkTable();
    final files = _dartFiles();
    _checkFolders(files);
    for (final file in files) {
      final source = File('${root.path}/$file').readAsStringSync();
      final library = _libraryOf(file);
      for (final uris in directives(source)) {
        for (final uri in uris) {
          _checkDirective(file, library, uri);
        }
      }
      _checkBans(file, source);
    }
    final violations = [
      for (final MapEntry(key: rule, value: byFile) in counts.entries)
        for (final MapEntry(key: file, value: count) in byFile.entries)
          Violation(rule, file, count),
    ];
    violations.sort();
    structure.sort();
    return LayerReport(structure: structure, violations: violations);
  }

  void _checkTable() {
    final names = rules.libraries.keys.toSet();
    for (final MapEntry(key: library, value: allowed)
        in rules.libraries.entries) {
      for (final name in allowed) {
        if (!names.contains(name)) {
          structure.add('the table lets $library import $name, no library');
        }
      }
    }
    final done = <String>{};
    final path = <String>[];
    void visit(String library) {
      if (done.contains(library)) return;
      if (path.contains(library)) {
        final cycle = [...path.sublist(path.indexOf(library)), library];
        structure.add('the table has a cycle: ${cycle.join(' -> ')}');
        return;
      }
      path.add(library);
      for (final next in rules.libraries[library] ?? const <String>{}) {
        visit(next);
      }
      path.removeLast();
      done.add(library);
    }

    names.forEach(visit);
  }

  List<String> _dartFiles() {
    final dir = Directory(lib);
    if (!dir.existsSync()) return const [];
    final base = root.absolute.uri.path;
    final files = [
      for (final entity in dir.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          entity.absolute.uri.path.substring(base.length),
    ];
    files.sort();
    return files;
  }

  void _checkFolders(List<String> files) {
    final folders = Directory('$lib/src').existsSync()
        ? {
            for (final entity in Directory('$lib/src').listSync())
              if (entity is Directory) entity.path.split('/').last,
          }
        : <String>{};
    final libraryFiles = {
      for (final file in files)
        if (_topLevel(file) case final name?) name,
    };
    for (final file in files) {
      if (RegExp(r'^lib/src/[^/]+\.dart$').hasMatch(file)) {
        structure.add('$file sits directly in lib/src/');
      }
    }
    for (final folder in folders) {
      if (!libraryFiles.contains(folder)) {
        structure.add('lib/src/$folder/ has no library file lib/$folder.dart');
      }
      if (!rules.libraries.containsKey(folder)) {
        structure.add('lib/src/$folder/ is not in the table');
      }
    }
    for (final name in rules.libraries.keys) {
      if (!folders.contains(name)) {
        structure.add('the table names $name, which has no lib/src/$name/');
      }
    }
    for (final name in libraryFiles) {
      final exempt = name == rules.umbrella || rules.unchecked.contains(name);
      if (!exempt && !folders.contains(name)) {
        structure.add('lib/$name.dart has no folder lib/src/$name/');
      }
    }
    final umbrella = rules.umbrella;
    if (umbrella != null) _checkUmbrella(umbrella);
    for (final name in libraryFiles) {
      if (name == umbrella || rules.unchecked.contains(name)) continue;
      _checkLibraryFile(name);
    }
  }

  void _checkUmbrella(String name) {
    final file = File('$lib/$name.dart');
    if (!file.existsSync()) {
      structure.add('the umbrella lib/$name.dart is missing');
      return;
    }
    final exported = <String>{};
    for (final uris in directives(file.readAsStringSync())) {
      for (final uri in uris) {
        if (rules.umbrellaReexports.contains(uri)) continue;
        final target = _resolve('lib/$name.dart', uri);
        final library = target == null ? null : _topLevel(target);
        if (library == null || !rules.libraries.containsKey(library)) {
          structure.add('the umbrella lib/$name.dart names $uri');
        } else {
          exported.add(library);
        }
      }
    }
    final listed = rules.umbrellaLibraries ?? rules.libraries.keys.toSet();
    for (final library in listed) {
      if (!rules.libraries.containsKey(library)) {
        structure.add('the umbrella is to export $library, no library');
      } else if (!exported.contains(library)) {
        structure.add('the umbrella lib/$name.dart does not export $library');
      }
    }
    for (final library in exported.difference(listed)) {
      structure.add(
        'the umbrella lib/$name.dart exports $library, which it does not list',
      );
    }
  }

  void _checkLibraryFile(String name) {
    final path = 'lib/$name.dart';
    for (final uris in directives(File('$lib/$name.dart').readAsStringSync())) {
      for (final uri in uris) {
        final target = _resolve(path, uri);
        if (target != null && !target.startsWith('lib/src/$name/')) {
          structure.add('$path names $uri, outside lib/src/$name/');
        }
      }
    }
  }

  /// The library a file of `lib/` belongs to: its folder of `src`, or its
  /// own name for a library file.
  String? _libraryOf(String file) {
    final match = RegExp('^lib/src/([^/]+)/').firstMatch(file);
    return match?.group(1) ?? _topLevel(file);
  }

  /// The name of a library file such as `lib/a.dart`, or null.
  String? _topLevel(String file) =>
      RegExp(r'^lib/([^/]+)\.dart$').firstMatch(file)?.group(1);

  /// The path relative to the package root of [uri] seen from [file], or
  /// null when [uri] is in another package or the SDK.
  String? _resolve(String file, String uri) {
    final own = 'package:${rules.package}/';
    if (uri.startsWith(own)) return 'lib/${uri.substring(own.length)}';
    if (uri.contains(':')) return null;
    return Uri.parse(file).resolve(uri).path;
  }

  void _checkDirective(String file, String? library, String uri) {
    final target = _resolve(file, uri);
    if (target == null) {
      _checkForeign(file, library, uri);
      return;
    }
    if (_topLevel(file) != null || library == null) return;
    final targetFolder = RegExp('^lib/src/([^/]+)/')
        .firstMatch(target)
        ?.group(1);
    final targetLibrary = targetFolder ?? _topLevel(target);
    if (targetLibrary == null) return;
    if (targetLibrary == library) {
      if (targetFolder == null) {
        count(throughLibrary, file);
      } else if (uri.startsWith('package:') !=
          (rules.sameLibraryImports == SameLibraryImports.package)) {
        count(sameLibraryStyle, file);
      }
      return;
    }
    if (targetFolder != null) count(throughLibrary, file);
    if (!(rules.libraries[library]?.contains(targetLibrary) ?? false)) {
      count(notAllowed, file);
    }
  }

  void _checkForeign(String file, String? library, String uri) {
    if (uri.startsWith('package:')) {
      final package = uri.substring('package:'.length).split('/').first;
      if (!rules.packages.contains(package)) count(foreignPackage, file);
    }
    final prefixes = [
      ...?rules.forbidden[everyLibrary],
      if (library != null) ...?rules.forbidden[library],
    ];
    if (prefixes.any(uri.startsWith)) count(forbiddenImport, file);
  }

  void _checkBans(String file, String source) {
    final code = blank(source, strings: true);
    for (final ban in rules.bans) {
      if (ban.allowedIn.any(
        (path) => path == file || path.endsWith('/') && file.startsWith(path),
      )) {
        continue;
      }
      final text = ban.code ? code : source;
      for (final hit in RegExp(ban.pattern, multiLine: true).allMatches(text)) {
        if (_allowedWith(ban.allowedWith, source, hit.start)) continue;
        count(banned(ban.name), file);
      }
    }
  }

  // Whether the line comments right above the line of [offset] in [source]
  // open with [words] and give a reason after them.
  static bool _allowedWith(String? words, String source, int offset) {
    if (words == null) return false;
    final lines = source.substring(0, offset).split('\n');
    String? opening;
    for (var i = lines.length - 2; i >= 0; i--) {
      final line = lines[i].trimLeft();
      if (!line.startsWith('//')) break;
      opening = line;
    }
    if (opening == null || !opening.startsWith('// $words')) return false;
    return opening.substring('// $words'.length).trim().isNotEmpty;
  }
}
