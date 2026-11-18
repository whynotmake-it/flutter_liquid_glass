import 'dart:convert';

import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';
import 'package:meta/meta.dart';

/// What an atlas pass writes beside the atlas, by [Tiling.looks]: no look,
/// the tint, or the whole look. Its shaders define LOOKS as its index
/// (look_targets.glsl).
@internal
enum AtlasLooks {
  none(0, ''),
  tint(1, 'Tint'),
  all(3, 'Looks');

  const AtlasLooks(this.count, this.suffix);

  /// What a pass writes beside an atlas of [looks].
  factory AtlasLooks.of(ShapeLooks? looks) => switch (looks) {
    null => none,
    ShapeLooks(tintOnly: true) => tint,
    _ => all,
  };

  /// The look textures written.
  final int count;

  /// What its shaders' names say of it.
  final String suffix;
}

/// A texture an atlas pass writes, by its color attachment in
/// look_targets.glsl: the atlas, then the looks [AtlasLooks.count] counts.
/// A shader that writes one alone defines LOOK_ONLY_ and its name.
@internal
enum AtlasTarget {
  geometry('Geometry'),
  tint('Tint'),
  response('Response'),
  weights('Weights');

  const AtlasTarget(this.suffix);

  /// What the names of the shaders that write it alone say of it.
  final String suffix;
}

/// What an atlas pass draws: shapes (tile_shapes_fragment.glsl) or a
/// fused body (tile_field_fragment.glsl).
@internal
enum AtlasBody {
  shapes('Shapes'),
  field('Field');

  const AtlasBody(this.suffix);

  /// What its shaders' names say of it.
  final String suffix;
}

/// A fragment shader of the atlas passes, in the geometry shader bundle.
@internal
@immutable
final class AtlasShader {
  /// The shader of [body] that writes [looks] beside the atlas, or with
  /// [only] that target alone, for a backend whose pass takes one color
  /// attachment; such a shader reads the whole look.
  const AtlasShader(this.body, this.looks, {this.only})
    : assert(only == null || looks == AtlasLooks.all, 'It reads every look.');

  /// What it draws.
  final AtlasBody body;

  /// What it writes beside the atlas.
  final AtlasLooks looks;

  /// The one target it writes, if it writes one alone.
  final AtlasTarget? only;

  /// The name of the vertex shader of every atlas pass.
  static const String vertex = 'TileVertex';

  /// Every atlas fragment shader: each body with each looks, then with each
  /// target alone.
  static final List<AtlasShader> all = [
    for (final body in AtlasBody.values)
      for (final looks in AtlasLooks.values) AtlasShader(body, looks),
    for (final body in AtlasBody.values)
      for (final target in AtlasTarget.values)
        AtlasShader(body, AtlasLooks.all, only: target),
  ];

  /// The geometry shader bundle's manifest,
  /// liquid_glass_renderer.shaderbundle.json: [vertex], then [all].
  static String get bundle {
    final manifest = {
      vertex: {'type': 'vertex', 'file': '${_folder}tile_vertex.glsl'},
      for (final shader in all)
        shader.name: {'type': 'fragment', 'file': shader.file},
    };
    return '${const JsonEncoder.withIndent('    ').convert(manifest)}\n';
  }

  static const String _folder = 'lib/assets/shaders/gpu/';

  List<String> get _parts => [
    body.suffix,
    if (only case final only?) ...[
      'Only',
      only.suffix,
    ] else if (looks != AtlasLooks.none)
      looks.suffix,
  ];

  /// Its name in the bundle.
  String get name => 'Tile${_parts.join()}Fragment';

  /// Its file, from the package's root.
  String get file {
    final parts = _parts.map((part) => part.toLowerCase()).join('_');
    return '${_folder}tile_${parts}_fragment.glsl';
  }

  /// The source of its file, which defines LOOKS and the LOOK_ONLY_ of its
  /// one target over its body's shader; null for the body's shader itself.
  String? get source => only == null && looks == AtlasLooks.none
      ? null
      : [
          '// Generated from AtlasShader by test/src/atlas_shaders_test.dart:',
          '// do not edit.',
          '',
          '#define LOOKS ${looks.index}',
          if (only case final only?)
            '#define LOOK_ONLY_${only.name.toUpperCase()}',
          '#include "tile_${body.name}_fragment.glsl"',
          '',
        ].join('\n');
}
