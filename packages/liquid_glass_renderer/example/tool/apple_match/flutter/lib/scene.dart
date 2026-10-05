import 'dart:convert';

import 'package:flutter/widgets.dart';

class MatchScene {
  MatchScene({
    required this.profile,
    required this.appearance,
    required this.width,
    required this.height,
    required this.scale,
    required this.shapeRect,
    required this.shapeKind,
    required this.cornerRadius,
    required this.probes,
    this.mergeShape,
    this.containerSpacing,
    this.glassVariant = 'regular',
    this.glassTint,
  });

  factory MatchScene.fromJson(Map<String, Object?> json) {
    final canvas = json['canvas']! as Map<String, Object?>;
    final shape = MatchShape.fromJson(json['shape']! as Map<String, Object?>);
    final probes = <String, Map<String, Object?>>{};
    for (final value in json['probes']! as List<Object?>) {
      final probe = value! as Map<String, Object?>;
      probes[probe['id']! as String] =
          probe['background']! as Map<String, Object?>;
    }
    final mergeShape = json['mergeShape'] as Map<String, Object?>?;
    final tint = json['glassTint'] as Map<String, Object?>?;
    return MatchScene(
      profile: json['profile']! as String,
      appearance: json['appearance']! as String,
      width: (canvas['logicalWidth']! as num).toDouble(),
      height: (canvas['logicalHeight']! as num).toDouble(),
      scale: canvas['scale']! as int,
      shapeRect: shape.rect,
      shapeKind: shape.kind,
      cornerRadius: shape.cornerRadius,
      probes: probes,
      mergeShape: mergeShape == null ? null : MatchShape.fromJson(mergeShape),
      containerSpacing: (json['containerSpacing'] as num?)?.toDouble(),
      glassVariant: json['glassVariant'] as String? ?? 'regular',
      glassTint: tint == null
          ? null
          : parseColor(tint['color']! as String)
                .withValues(alpha: (tint['opacity'] as num?)?.toDouble() ?? 1),
    );
  }

  factory MatchScene.fromBase64(String encoded) => MatchScene.fromJson(
    jsonDecode(utf8.decode(base64Decode(encoded)))! as Map<String, Object?>,
  );

  final double width;
  final String profile;
  final String appearance;
  final double height;
  final int scale;
  final Rect shapeRect;
  final String shapeKind;
  final double cornerRadius;
  final Map<String, Map<String, Object?>> probes;

  /// The second shape of a `merge_pair` scene, in scene coordinates.
  final MatchShape? mergeShape;

  /// SwiftUI `GlassEffectContainer` spacing for `merge_pair` scenes.
  final double? containerSpacing;

  /// `regular` or `clear` (`.glassEffect(.clear)`).
  final String glassVariant;

  /// The `.tint(color.opacity(opacity))` Apple applies to the material.
  final Color? glassTint;
}

/// One glass shape of a scene.
class MatchShape {
  const MatchShape({
    required this.rect,
    required this.kind,
    required this.cornerRadius,
  });

  factory MatchShape.fromJson(Map<String, Object?> json) => MatchShape(
    rect: Rect.fromLTWH(
      (json['x']! as num).toDouble(),
      (json['y']! as num).toDouble(),
      (json['width']! as num).toDouble(),
      (json['height']! as num).toDouble(),
    ),
    kind: json['kind']! as String,
    cornerRadius: (json['cornerRadius']! as num).toDouble(),
  );

  final Rect rect;
  final String kind;
  final double cornerRadius;
}

Color parseColor(String value) =>
    Color(0xFF000000 | int.parse(value.substring(1), radix: 16));
