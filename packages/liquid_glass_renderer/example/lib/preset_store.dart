import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// Small dependency-free YAML dialect used for user-editable example presets.
/// Values are scalar material fields emitted by [LiquidGlassSettings.toJson].
class PresetStore {
  /// Encodes the scalar preset dialect without requiring a YAML package.
  static String toYaml(LiquidGlassSettings settings) {
    final lines = settings.toJson().entries.map((entry) {
      return '${entry.key}: ${entry.value}';
    });
    return '# Liquid Glass example preset\n${lines.join('\n')}\n';
  }

  /// Decodes the scalar preset dialect used by [toYaml].
  static LiquidGlassSettings fromYaml(String source) {
    final values = <String, Object?>{};
    for (final line in source.split('\n')) {
      if (line.trimLeft().startsWith('#')) continue;
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final key = line.substring(0, separator).trim();
      final raw = line.substring(separator + 1).trim();
      values[key] = num.tryParse(raw) ?? raw;
    }
    return LiquidGlassSettings.fromJson(values);
  }

  Future<Directory> _directory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/liquid_glass_presets');
    if (!directory.existsSync()) directory.createSync(recursive: true);
    return directory;
  }

  Future<List<String>> names() async {
    final directory = await _directory();
    return directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.yaml'))
        .map((file) => file.uri.pathSegments.last.replaceFirst('.yaml', ''))
        .toList()
      ..sort();
  }

  Future<void> save(String name, LiquidGlassSettings settings) async {
    final directory = await _directory();
    final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final file = File('${directory.path}/$safeName.yaml');
    await file.writeAsString(toYaml(settings));
  }

  Future<LiquidGlassSettings?> load(String name) async {
    final directory = await _directory();
    final file = File('${directory.path}/$name.yaml');
    if (!file.existsSync()) return null;
    return fromYaml(await file.readAsString());
  }

  Future<void> seed() async {
    if ((await names()).isEmpty) {
      await save('ios27-toolbar-light', const LiquidGlassSettings.ios27ToolbarLight());
      await save('neutral-default', const LiquidGlassSettings());
    }
  }
}
