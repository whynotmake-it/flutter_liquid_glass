import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/playground/inspector/grouped_list.dart';
import 'package:liquid_glass_renderer_example/playground/playground_state.dart';

/// Refraction and lighting controls for the layer-wide settings.
class MaterialSections extends StatelessWidget {
  const MaterialSections({required this.material, super.key});

  final ValueNotifier<GlassMaterial> material;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: material,
      builder: (context, value, _) {
        final settings = value.settings;
        void edit(LiquidGlassSettings next) =>
            material.value = material.value.withSettings(next);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InspectorSection(
              header: 'Refraction',
              footer:
                  'Glass is a flat face with a rounded bevel. Height is the '
                  'bevel width, amount how far inside the silhouette the rim '
                  'samples. Fitting shrinks the lens on small shapes, like '
                  'regular glass; clear glass keeps it.',
              children: [
                SliderRow(
                  title: 'Height',
                  value: settings.refractionHeight,
                  min: 0,
                  max: 60,
                  format: _points,
                  onChanged: (v) =>
                      edit(settings.copyWith(refractionHeight: v)),
                ),
                SliderRow(
                  title: 'Amount',
                  value: settings.refractionAmount,
                  min: 0,
                  max: 120,
                  format: _points,
                  onChanged: (v) =>
                      edit(settings.copyWith(refractionAmount: v)),
                ),
                SliderRow(
                  title: 'Magnification',
                  value: settings.magnification,
                  min: 0.5,
                  max: 2,
                  format: (v) => '${v.toStringAsFixed(2)}×',
                  onChanged: (v) => edit(settings.copyWith(magnification: v)),
                ),
                SliderRow(
                  title: 'Dispersion',
                  value: settings.chromaticAberration,
                  min: 0,
                  max: 0.05,
                  format: (v) => v.toStringAsFixed(3),
                  onChanged: (v) =>
                      edit(settings.copyWith(chromaticAberration: v)),
                ),
                SliderRow(
                  title: 'Blur',
                  value: settings.frost,
                  min: 0,
                  max: 30,
                  format: _points,
                  onChanged: (v) => edit(settings.copyWith(frost: v)),
                ),
                SwitchRow(
                  title: 'Fit Small Shapes',
                  value: settings.refractionFitsShape,
                  onChanged: (v) =>
                      edit(settings.copyWith(refractionFitsShape: v)),
                ),
                SwitchRow(
                  title: 'Smooth Sampling',
                  value: settings.smoothRefraction,
                  onChanged: (v) =>
                      edit(settings.copyWith(smoothRefraction: v)),
                ),
              ],
            ),
            InspectorSection(
              header: 'Lighting',
              children: [
                SliderRow(
                  title: 'Glint',
                  value: settings.highlight,
                  min: 0,
                  max: 2,
                  format: (v) => v.toStringAsFixed(2),
                  onChanged: (v) => edit(settings.copyWith(highlight: v)),
                ),
                SliderRow(
                  title: 'Border',
                  value: settings.contourStrength,
                  min: 0,
                  max: 1,
                  format: (v) => v.toStringAsFixed(2),
                  onChanged: (v) => edit(settings.copyWith(contourStrength: v)),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

String _points(double value) => '${value.toStringAsFixed(1)} pt';
