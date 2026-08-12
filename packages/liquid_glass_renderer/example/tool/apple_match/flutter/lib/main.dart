import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'scene.dart';

const _sceneBase64 = String.fromEnvironment('SCENE_B64');
const _configurationChannel = MethodChannel('apple_match/config');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  if (_sceneBase64.isEmpty) {
    throw StateError('SCENE_B64 is required');
  }
  final arguments =
      await _configurationChannel.invokeListMethod<String>('arguments') ??
      const [];
  runApp(
    MatchApp(
      scene: MatchScene.fromBase64(_sceneBase64),
      probe: _argument(arguments, '--probe') ?? 'A',
      settings: _decodeSettings(_argument(arguments, '--settings-b64') ?? ''),
    ),
  );
}

String? _argument(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  return index >= 0 && index + 1 < arguments.length
      ? arguments[index + 1]
      : null;
}

Map<String, Object?> _decodeSettings(String value) {
  if (value.isEmpty) {
    return const {};
  }
  return jsonDecode(utf8.decode(base64Decode(value)))! as Map<String, Object?>;
}

class MatchApp extends StatelessWidget {
  const MatchApp({
    required this.scene,
    required this.probe,
    required this.settings,
    super.key,
  });

  final MatchScene scene;
  final String probe;
  final Map<String, Object?> settings;

  @override
  Widget build(BuildContext context) {
    final background = scene.probes[probe]!;
    final shapeWidth = _number('shapeWidth', scene.shapeRect.width);
    final shapeHeight = _number('shapeHeight', scene.shapeRect.height);
    final shapeRect = Rect.fromCenter(
      center:
          scene.shapeRect.center +
          Offset(_number('shapeOffsetX', 0), _number('shapeOffsetY', 0)),
      width: shapeWidth,
      height: shapeHeight,
    );
    final cornerRadius = _number('cornerRadius', shapeHeight / 2);
    final shape = settings['shapeProfile'] == 'superellipse'
        ? LiquidRoundedSuperellipse(borderRadius: cornerRadius)
        : LiquidRoundedRectangle(borderRadius: cornerRadius);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SizedBox(
          width: scene.width,
          height: scene.height,
          child: Stack(
            children: [
              Positioned.fill(child: ProbeBackground(spec: background)),
              Positioned.fromRect(
                rect: shapeRect,
                child: LiquidGlass.withOwnLayer(
                  settings: LiquidGlassSettings(
                    glassColor: Color.fromRGBO(
                      _number('glassRed', 255).round(),
                      _number('glassGreen', 255).round(),
                      _number('glassBlue', 255).round(),
                      _number('glassAlpha', 0),
                    ),
                    thickness: _number('thickness', 20),
                    blur: _number('blur', 5),
                    lightAngle: _number('lightAngle', 1.5707963267948966),
                    lightIntensity: _number('lightIntensity', 0.5),
                    ambientStrength: _number('ambientStrength', 0),
                    refractiveIndex: _number('refractiveIndex', 1.2),
                    saturation: _number('saturation', 1.5),
                    chromaticAberration: _number('chromaticAberration', 0.01),
                  ),
                  shape: shape,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _number(String key, double fallback) =>
      (settings[key] as num?)?.toDouble() ?? fallback;
}

class ProbeBackground extends StatelessWidget {
  const ProbeBackground({required this.spec, super.key});

  final Map<String, Object?> spec;

  @override
  Widget build(BuildContext context) {
    if (spec['kind'] == 'solid') {
      return ColoredBox(color: parseColor(spec['color']! as String));
    }
    return CustomPaint(painter: RgbwGridPainter(spec: spec));
  }
}

class RgbwGridPainter extends CustomPainter {
  const RgbwGridPainter({required this.spec});

  final Map<String, Object?> spec;

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = (spec['cellSize']! as num).toDouble();
    final gutter = (spec['gutter']! as num).toDouble();
    final colors = (spec['colors']! as List<Object?>)
        .cast<String>()
        .map(parseColor)
        .toList();
    canvas.drawColor(parseColor(spec['gutterColor']! as String), BlendMode.src);
    final rows = (size.height / cellSize).ceil();
    final columns = (size.width / cellSize).ceil();
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final colorIndex = _colorIndex(column, row);
        canvas.drawRect(
          Rect.fromLTWH(
            column * cellSize,
            row * cellSize,
            cellSize - gutter,
            cellSize - gutter,
          ),
          Paint()..color = colors[colorIndex],
        );
      }
    }
  }

  int _colorIndex(int column, int row) {
    final marker = (spec['marker']! as List<Object?>).cast<String>();
    final markerRow = row - (spec['markerRow']! as int);
    final markerColumn = column - (spec['markerColumn']! as int);
    if (markerRow >= 0 &&
        markerRow < marker.length &&
        markerColumn >= 0 &&
        markerColumn < marker[markerRow].length) {
      return 'RGBW'.indexOf(marker[markerRow][markerColumn]);
    }
    if (spec['layout'] == 'primary') {
      return (column + 2 * row + row ~/ 4) % 4;
    }
    return (3 * column + row + column ~/ 5) % 4;
  }

  @override
  bool shouldRepaint(RgbwGridPainter oldDelegate) => oldDelegate.spec != spec;
}
