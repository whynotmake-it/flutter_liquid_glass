import 'dart:convert';

import 'package:flutter/widgets.dart';

class MatchScene {
  MatchScene({
    required this.width,
    required this.height,
    required this.scale,
    required this.shapeRect,
    required this.cornerRadius,
    required this.probes,
  });

  factory MatchScene.fromJson(Map<String, Object?> json) {
    final canvas = json['canvas']! as Map<String, Object?>;
    final shape = json['shape']! as Map<String, Object?>;
    final probes = <String, Map<String, Object?>>{};
    for (final value in json['probes']! as List<Object?>) {
      final probe = value! as Map<String, Object?>;
      probes[probe['id']! as String] =
          probe['background']! as Map<String, Object?>;
    }
    return MatchScene(
      width: (canvas['logicalWidth']! as num).toDouble(),
      height: (canvas['logicalHeight']! as num).toDouble(),
      scale: canvas['scale']! as int,
      shapeRect: Rect.fromLTWH(
        (shape['x']! as num).toDouble(),
        (shape['y']! as num).toDouble(),
        (shape['width']! as num).toDouble(),
        (shape['height']! as num).toDouble(),
      ),
      cornerRadius: (shape['cornerRadius']! as num).toDouble(),
      probes: probes,
    );
  }

  factory MatchScene.fromBase64(String encoded) => MatchScene.fromJson(
    jsonDecode(utf8.decode(base64Decode(encoded)))! as Map<String, Object?>,
  );

  final double width;
  final double height;
  final int scale;
  final Rect shapeRect;
  final double cornerRadius;
  final Map<String, Map<String, Object?>> probes;
}

Color parseColor(String value) =>
    Color(0xFF000000 | int.parse(value.substring(1), radix: 16));
