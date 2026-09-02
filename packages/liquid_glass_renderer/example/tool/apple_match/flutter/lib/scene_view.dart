import 'package:flutter/material.dart';

import 'dart:math' as math;

import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'scene.dart';

/// Maps a harness settings JSON object onto structural renderer settings.
///
/// Shared by the legacy per-launch capture path and the persistent hot-reload
/// session so both render byte-identical scenes for the same settings.
LiquidGlassSettings matchGlassSettings(Map<String, Object?> settings) {
  double number(String key, double fallback) =>
      (settings[key] as num?)?.toDouble() ?? fallback;
  const defaults = LiquidGlassSettings();
  return LiquidGlassSettings(
    thickness: number('thickness', defaults.thickness),
    edgeRefraction: number(
      'edgeRefraction',
      8.0 *
          number('thickness', defaults.thickness) *
          math.sqrt(
            math.max(
              0.0,
              math
                      .pow(
                        number(
                          'refractiveIndex',
                          defaults.effectiveOpticalIndex,
                        ),
                        2,
                      )
                      .toDouble() -
                  1.0,
            ),
          ),
    ),
    refractionSpread: number('refractionSpread', defaults.refractionSpread),
    backdropScale: number('backdropScale', defaults.backdropScale),
    frost: number('frost', number('blur', defaults.frost)),
    highlight: number(
      'highlight',
      number('lightIntensity', defaults.highlight),
    ),
    highlightWidth: number('highlightWidth', defaults.highlightWidth),
    highlightWrap: number('highlightWrap', defaults.highlightWrap),
    highlightOppositeStrength: number(
      'highlightOppositeStrength',
      defaults.highlightOppositeStrength,
    ),
    curvatureLighting: number('curvatureLighting', defaults.curvatureLighting),
    contourStrength: number(
      'contourStrength',
      number('edgeAlpha', defaults.contourStrength),
    ),
    contourWidth: number(
      'contourWidth',
      number('edgeWidth', defaults.contourWidth),
    ),
    contourOffset: number('contourOffset', defaults.contourOffset),
    contourTransmittance: number(
      'contourTransmittance',
      number('contourTransmissionRatio', defaults.contourTransmittance),
    ),
    bevelShadowStrength: number(
      'bevelShadowStrength',
      number('innerShadowStrength', defaults.bevelShadowStrength),
    ),
    bevelShadowDepth: number(
      'bevelShadowDepth',
      number('innerShadowDepth', defaults.bevelShadowDepth),
    ),
    bevelShadowOffset: number(
      'bevelShadowOffset',
      number('innerShadowOffset', defaults.bevelShadowOffset),
    ),
    bevelShadowDirectionality: number(
      'bevelShadowDirectionality',
      defaults.bevelShadowDirectionality,
    ),
    bevelShadowSizeResponse: number(
      'bevelShadowSizeResponse',
      defaults.bevelShadowSizeResponse,
    ),
    exteriorShadowSizeResponse: number(
      'exteriorShadowSizeResponse',
      defaults.exteriorShadowSizeResponse,
    ),
    chromaticAberration: number(
      'chromaticAberration',
      defaults.chromaticAberration,
    ),
  );
}

/// Maps color-adjacent harness controls onto per-shape appearance.
LiquidGlassAppearance matchGlassAppearance(Map<String, Object?> settings) {
  double number(String key, double fallback) =>
      (settings[key] as num?)?.toDouble() ?? fallback;
  Color color(String prefix, Color fallback) => Color.fromRGBO(
    number('${prefix}Red', fallback.r * 255).round(),
    number('${prefix}Green', fallback.g * 255).round(),
    number('${prefix}Blue', fallback.b * 255).round(),
    number('${prefix}Alpha', fallback.a),
  );
  const defaults = LiquidGlassAppearance();
  final tint = settings['tint'] is num
      ? Color((settings['tint']! as num).toInt())
      : color('tint', color('glass', defaults.tint));
  final colorModel = settings.containsKey('colorModel')
      ? LiquidGlassColorModel.fromJson(settings['colorModel'])
      : defaults.colorModel;
  return LiquidGlassAppearance(
    tint: tint,
    saturation: number('saturation', defaults.saturation),
    transmissionGamma: number('transmissionGamma', defaults.transmissionGamma),
    vibrancy: number('vibrancy', defaults.vibrancy),
    colorModel: colorModel,
  );
}

List<BoxShadow> matchGlassShadows(Map<String, Object?> settings) {
  double number(String key, double fallback) =>
      (settings[key] as num?)?.toDouble() ?? fallback;
  BoxShadow? shadow(String prefix) {
    final alpha = number('${prefix}Alpha', 0.0);
    if (alpha <= 0.0) return null;
    final luminance = number('${prefix}Luminance', 0.0).round();
    return BoxShadow(
      color: Color.fromRGBO(luminance, luminance, luminance, alpha),
      offset: Offset(
        number('${prefix}OffsetX', 0.0),
        number('${prefix}OffsetY', 0.0),
      ),
      blurRadius: number('${prefix}Blur', 0.0),
      spreadRadius: number('${prefix}Spread', 0.0),
    );
  }

  return [
    if (shadow('contactShadow') case final contact?) contact,
    if (shadow('shadow') case final cast?) cast,
  ];
}

/// Maps the `shapeProfile` settings key onto a concrete [LiquidShape].
LiquidShape matchGlassShape(
  Map<String, Object?> settings,
  String sceneShapeKind,
  double cornerRadius,
) {
  if (sceneShapeKind == 'circle') {
    return const LiquidOval();
  }
  if (sceneShapeKind == 'roundedSuperellipse') {
    return LiquidRoundedSuperellipse(borderRadius: cornerRadius);
  }
  return settings['shapeProfile'] == 'superellipse'
      ? LiquidRoundedSuperellipse(borderRadius: cornerRadius)
      : LiquidRoundedRectangle(borderRadius: cornerRadius);
}

/// The deterministic capture scene: one probe background plus one glass shape.
///
/// This widget is the exact visual subtree used for screenshots. It contains
/// no animation, no timers, and no randomness, so equal settings and probe
/// always produce equal pixels.
class MatchSceneView extends StatelessWidget {
  const MatchSceneView({
    required this.scene,
    required this.probe,
    required this.settings,
    this.fake = false,
    super.key,
  });

  final MatchScene scene;
  final String probe;
  final Map<String, Object?> settings;
  final bool fake;

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
    final cornerRadius = _number('cornerRadius', scene.cornerRadius);
    return SizedBox(
      width: scene.width,
      height: scene.height,
      child: Stack(
        children: [
          Positioned.fill(child: ProbeBackground(spec: background)),
          // The reference capture retains the iPhone 17 Pro Dynamic Island
          // even though the harness hides system overlays. Reproduce that
          // device chrome deterministically so full-frame RGBW registration
          // does not reject an otherwise identical loupe candidate. It is
          // outside the scored crop and is never part of the shipped app.
          if (scene.profile == 'loupe')
            const Positioned(
              left: 138.3333,
              top: 14.0,
              width: 125.3333,
              height: 36.6667,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.all(Radius.circular(18.3333)),
                ),
              ),
            ),
          if (scene.profile == 'loupe')
            _MatchLoupe(
              rect: shapeRect,
              cornerRadius: cornerRadius,
              settings: matchGlassSettings(settings),
              appearance: matchGlassAppearance(settings),
              shadows: matchGlassShadows(settings),
            )
          else if (scene.profile == 'tab_bar_holdout')
            _MatchTabBar(
              rect: shapeRect,
              cornerRadius: cornerRadius,
              settings: matchGlassSettings(settings),
              appearance: matchGlassAppearance(settings),
              shadows: matchGlassShadows(settings),
              probe: probe,
            )
          else
            Positioned.fromRect(
              rect: shapeRect,
              child: _MatchGlassSurface(
                fake: fake,
                settings: matchGlassSettings(settings),
                appearance: matchGlassAppearance(settings),
                shape: matchGlassShape(settings, scene.shapeKind, cornerRadius),
                shadows: matchGlassShadows(settings),
              ),
            ),
        ],
      ),
    );
  }

  double _number(String key, double fallback) =>
      (settings[key] as num?)?.toDouble() ?? fallback;
}

class _MatchGlassSurface extends StatelessWidget {
  const _MatchGlassSurface({
    required this.fake,
    required this.settings,
    required this.appearance,
    required this.shape,
    required this.shadows,
  });

  final bool fake;
  final LiquidGlassSettings settings;
  final LiquidGlassAppearance appearance;
  final LiquidShape shape;
  final List<BoxShadow> shadows;

  @override
  Widget build(BuildContext context) => fake
      ? FakeGlass(
          settings: settings,
          appearance: appearance,
          shape: shape,
          shadows: shadows,
          child: const SizedBox.expand(),
        )
      : LiquidGlass.withOwnLayer(
          settings: settings,
          appearance: appearance,
          shape: shape,
          shadows: shadows,
          child: const SizedBox.expand(),
        );
}

/// Reproduces the small foreground that the system TabView places inside its
/// glass bar. The holdout scene is intentionally harness-only: shipped users
/// provide their own child content to [LiquidGlass].
class _MatchTabBar extends StatelessWidget {
  const _MatchTabBar({
    required this.rect,
    required this.cornerRadius,
    required this.settings,
    required this.appearance,
    required this.shadows,
    required this.probe,
  });

  final Rect rect;
  final double cornerRadius;
  final LiquidGlassSettings settings;
  final LiquidGlassAppearance appearance;
  final List<BoxShadow> shadows;
  final String probe;

  @override
  Widget build(BuildContext context) {
    final foreground = probe == 'C' ? Colors.white : Colors.black;
    // The pinned white solid probe contains no visible system tab bar. Keep
    // that capture honest instead of inventing foreground pixels for it.
    final child = probe == 'D'
        ? const SizedBox.expand()
        : _MatchTabItems(foreground: foreground);
    return Positioned.fromRect(
      rect: rect,
      child: LiquidGlass.withOwnLayer(
        settings: settings,
        appearance: appearance,
        shape: LiquidRoundedSuperellipse(borderRadius: cornerRadius),
        shadows: shadows,
        child: child,
      ),
    );
  }
}

class _MatchTabItems extends StatelessWidget {
  const _MatchTabItems({required this.foreground});

  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MatchTabItem(
          label: 'First',
          glyph: _TabGlyph.circle,
          foreground: foreground,
          selected: true,
        ),
        _MatchTabItem(
          label: 'Second',
          glyph: _TabGlyph.square,
          foreground: foreground,
        ),
        _MatchTabItem(
          label: 'Third',
          glyph: _TabGlyph.triangle,
          foreground: foreground,
        ),
      ],
    );
  }
}

enum _TabGlyph { circle, square, triangle }

class _MatchTabItem extends StatelessWidget {
  const _MatchTabItem({
    required this.label,
    required this.glyph,
    required this.foreground,
    this.selected = false,
  });

  final String label;
  final _TabGlyph glyph;
  final Color foreground;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF007AFF) : foreground;
    return Expanded(
      child: DecoratedBox(
        decoration: selected
            ? BoxDecoration(
                color: foreground.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(32),
              )
            : const BoxDecoration(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CustomPaint(
              size: const Size.square(22),
              painter: _TabGlyphPainter(glyph: glyph, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 14, height: 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabGlyphPainter extends CustomPainter {
  const _TabGlyphPainter({required this.glyph, required this.color});

  final _TabGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final bounds = Offset.zero & size;
    switch (glyph) {
      case _TabGlyph.circle:
        canvas.drawCircle(bounds.center, size.shortestSide / 2, paint);
      case _TabGlyph.square:
        canvas.drawRRect(
          RRect.fromRectAndRadius(bounds.deflate(1), const Radius.circular(2)),
          paint,
        );
      case _TabGlyph.triangle:
        final path = Path()
          ..moveTo(bounds.center.dx, 1)
          ..lineTo(bounds.right - 1, bounds.bottom - 1)
          ..lineTo(bounds.left + 1, bounds.bottom - 1)
          ..close();
        canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_TabGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}

/// Composes the iOS loupe as Flutter does: magnify the painted backdrop first,
/// then apply the ordinary liquid-glass pass to that higher-resolution source.
/// This keeps intentional loupe enlargement out of the renderer shader and
/// avoids magnifying already filtered pixels.
class _MatchLoupe extends StatelessWidget {
  const _MatchLoupe({
    required this.rect,
    required this.cornerRadius,
    required this.settings,
    required this.appearance,
    required this.shadows,
  });

  final Rect rect;
  final double cornerRadius;
  final LiquidGlassSettings settings;
  final LiquidGlassAppearance appearance;
  final List<BoxShadow> shadows;

  @override
  Widget build(BuildContext context) {
    final size = rect.size;
    final borderRadius = BorderRadius.circular(cornerRadius);
    return Positioned.fromRect(
      rect: rect,
      child: SizedBox.fromSize(
        size: size,
        child: Stack(
          children: [
            RawMagnifier(
              size: size,
              magnificationScale: 1.55,
              focalPointOffset: const Offset(0, 75.15),
              decoration: MagnifierDecoration(
                shape: RoundedRectangleBorder(borderRadius: borderRadius),
              ),
            ),
            LiquidGlass.withOwnLayer(
              // The system text-selection loupe is a clear lens. Its
              // magnification belongs to RawMagnifier above; never let a
              // candidate's ordinary material vector turn this holdout into
              // a frosted, opaque pill or a full-face shader zoom.
              settings: settings.copyWith(refractionSpread: 0, frost: 0),
              appearance: const LiquidGlassAppearance(),
              shape: LiquidRoundedRectangle(borderRadius: cornerRadius),
              shadows: shadows,
              child: const SizedBox.expand(),
            ),
          ],
        ),
      ),
    );
  }
}

class ProbeBackground extends StatelessWidget {
  const ProbeBackground({required this.spec, super.key});

  final Map<String, Object?> spec;

  @override
  Widget build(BuildContext context) {
    if (spec['kind'] == 'solid') {
      return ColoredBox(color: parseColor(spec['color']! as String));
    }
    if (spec['kind'] == 'tileGrid') {
      return CustomPaint(painter: TileGridPainter(spec: spec));
    }
    if (spec['kind'] == 'linearGradient') {
      final axis = spec['axis']! as String;
      final begin = switch (axis) {
        'vertical' => Alignment.topCenter,
        'diagonal' => Alignment.topLeft,
        _ => Alignment.centerLeft,
      };
      final end = switch (axis) {
        'vertical' => Alignment.bottomCenter,
        'diagonal' => Alignment.bottomRight,
        _ => Alignment.centerRight,
      };
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: begin,
            end: end,
            colors: [
              parseColor(spec['startColor']! as String),
              parseColor(spec['endColor']! as String),
            ],
          ),
        ),
      );
    }
    return CustomPaint(painter: RgbwGridPainter(spec: spec));
  }
}

class TileGridPainter extends CustomPainter {
  const TileGridPainter({required this.spec});

  final Map<String, Object?> spec;

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = (spec['cellSize']! as num).toDouble();
    final gutter = (spec['gutter']! as num).toDouble();
    final palette = (spec['palette']! as Map<String, Object?>).map(
      (key, value) => MapEntry(key, parseColor(value! as String)),
    );
    final pattern = (spec['pattern']! as List<Object?>).cast<String>();
    canvas.drawColor(parseColor(spec['gutterColor']! as String), BlendMode.src);
    final rows = (size.height / cellSize).ceil();
    final columns = (size.width / cellSize).ceil();
    for (var row = 0; row < rows; row++) {
      final patternRow = pattern[row % pattern.length];
      for (var column = 0; column < columns; column++) {
        final code = patternRow[column % patternRow.length];
        canvas.drawRect(
          Rect.fromLTWH(
            column * cellSize,
            row * cellSize,
            cellSize - gutter,
            cellSize - gutter,
          ),
          Paint()..color = palette[code]!,
        );
      }
    }
  }

  @override
  bool shouldRepaint(TileGridPainter oldDelegate) => oldDelegate.spec != spec;
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
