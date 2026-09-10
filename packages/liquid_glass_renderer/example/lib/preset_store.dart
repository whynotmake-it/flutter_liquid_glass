import 'dart:io';

import 'package:flutter/services.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:path_provider/path_provider.dart';

typedef GlassPreset = ({
  LiquidGlassSettings settings,
  LiquidGlassAppearance appearance,
});

/// Small dependency-free YAML dialect used for user-editable example presets.
class PresetStore {
  /// Encodes the scalar preset dialect without requiring a YAML package.
  static String toYaml(GlassPreset preset) {
    final lines = <String>[
      for (final entry in preset.settings.toJson().entries)
        'settings.${entry.key}: ${entry.value}',
      for (final entry in preset.appearance.toJson().entries)
        'appearance.${entry.key}: ${entry.value}',
    ];
    return '# Liquid Glass example preset\n${lines.join('\n')}\n';
  }

  /// Decodes the scalar preset dialect used by [toYaml].
  static GlassPreset fromYaml(String source) {
    final settings = <String, Object?>{};
    final appearance = <String, Object?>{};
    for (final line in source.split('\n')) {
      if (line.trimLeft().startsWith('#')) continue;
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final key = line.substring(0, separator).trim();
      final raw = line.substring(separator + 1).trim();
      final value = num.tryParse(raw) ?? raw;
      if (key.startsWith('settings.')) {
        settings[key.substring('settings.'.length)] = value;
      } else if (key.startsWith('appearance.')) {
        appearance[key.substring('appearance.'.length)] = value;
      }
    }
    return (
      settings: LiquidGlassSettings.fromJson(settings),
      appearance: LiquidGlassAppearance.fromJson(appearance),
    );
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

  Future<void> save(String name, GlassPreset preset) async {
    final directory = await _directory();
    final safeName = name.replaceAll(RegExp('[^A-Za-z0-9_.-]'), '_');
    final file = File('${directory.path}/$safeName.yaml');
    await file.writeAsString(toYaml(preset));
  }

  Future<GlassPreset?> load(String name) async {
    final directory = await _directory();
    final file = File('${directory.path}/$name.yaml');
    if (!file.existsSync()) return null;
    return fromYaml(await file.readAsString());
  }

  Future<void> seed() async {
    if ((await names()).isEmpty) {
      for (final name in [
        'ios27-toolbar-light',
        'ios27-toolbar-dark',
        'neutral-default',
      ]) {
        final yaml = await rootBundle.loadString('assets/presets/$name.yaml');
        final directory = await _directory();
        await File('${directory.path}/$name.yaml').writeAsString(yaml);
      }
    }
  }
}
