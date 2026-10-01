import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/draggable_glass.dart';

/// Shapes with different appearances in one layer and one blend group.
///
/// Appearance is per shape, so light, dark, clear and tinted glass share a
/// single backdrop capture, and their colors blend where the shapes merge.
class ColorsScene extends StatelessWidget {
  const ColorsScene({required this.blend, super.key});

  final ValueListenable<double> blend;

  static const _swatches = [
    (
      label: 'Light',
      offset: Offset(-50, -50),
      glyph: Color(0xFF000000),
      appearance: LiquidGlassAppearance.ios27RegularLight(),
    ),
    (
      label: 'Dark',
      offset: Offset(50, -50),
      glyph: Color(0xFFFFFFFF),
      appearance: LiquidGlassAppearance.ios27RegularDark(),
    ),
    (
      label: 'Clear',
      offset: Offset(-50, 50),
      glyph: Color(0xFFFFFFFF),
      appearance: LiquidGlassAppearance.ios27Clear(),
    ),
    (
      label: 'Blue',
      offset: Offset(50, 50),
      glyph: Color(0xFFFFFFFF),
      appearance: LiquidGlassAppearance.ios27RegularLight(
        tint: Color(0xFF0A84FF),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final center = constraints.biggest.center(Offset.zero);
        return ValueListenableBuilder(
          valueListenable: blend,
          builder: (context, blend, shapes) =>
              LiquidGlassBlendGroup(blend: blend, child: shapes!),
          child: Stack(
            children: [
              for (final swatch in _swatches)
                DraggableGlass(
                  center: center,
                  offset: swatch.offset,
                  size: const Size.square(108),
                  shape: const LiquidOval(),
                  grouped: true,
                  appearance: swatch.appearance,
                  child: Text(
                    swatch.label,
                    style: TextStyle(
                      color: swatch.glyph,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
