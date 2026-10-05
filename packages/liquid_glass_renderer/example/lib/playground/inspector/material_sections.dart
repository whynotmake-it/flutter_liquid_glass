import 'dart:math' as math;

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
            InspectorCard(
              header: 'Refraction',
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
                  title: 'Backdrop Shrink',
                  value: settings.backdropShrink,
                  min: 0,
                  max: 0.5,
                  format: (v) => v.toStringAsFixed(2),
                  onChanged: (v) => edit(settings.copyWith(backdropShrink: v)),
                ),
                SliderRow(
                  title: 'Dispersion',
                  value: dispersionToTrack(settings.dispersion),
                  min: -1,
                  max: 1,
                  format: (t) => trackToDispersion(t).toStringAsFixed(3),
                  onChanged: (t) =>
                      edit(settings.copyWith(dispersion: trackToDispersion(t))),
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
              ],
            ),
            const SizedBox(height: 28),
            InspectorCard(
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
                SliderRow(
                  title: 'Inner Shadow',
                  value: settings.bevelShadowStrength,
                  min: 0,
                  max: 1,
                  format: (v) => v.toStringAsFixed(2),
                  onChanged: (v) =>
                      edit(settings.copyWith(bevelShadowStrength: v)),
                ),
              ],
            ),
            const SizedBox(height: 28),
          ],
        );
      },
    );
  }
}

String _points(double value) => '${value.toStringAsFixed(1)} pt';

/// Largest dispersion on the slider. At ±2 one channel no longer refracts and
/// the other refracts twice as far; beyond it the channels cross over.
const maxDispersion = 2.0;

/// Maps dispersion onto a cubic track so the middle third covers the subtle
/// values real glass uses (iOS 27's loupe is about −0.07).
double dispersionToTrack(double dispersion) {
  final normalized = (dispersion / maxDispersion).clamp(-1.0, 1.0);
  return normalized.sign * math.pow(normalized.abs(), 1 / 3);
}

/// Inverse of [dispersionToTrack], snapping the centre of the track to `0`.
double trackToDispersion(double track) {
  if (track.abs() < 0.05) return 0;
  return maxDispersion * track * track * track;
}
