import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/widgets/glass_surface.dart';
import 'package:motor/motor.dart';

/// A liquid glass segmented control, ported from the reference widget's
/// behavior: the container is a glass pill on its own shared-group layer and
/// the selection indicator is a clear lens that travels between segments with
/// a bouncy spring while the segments glow under touch.
class GlassSegmentedControl<T extends Object> extends StatelessWidget {
  const GlassSegmentedControl({
    required this.segments,
    required this.labels,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  /// The values to choose between, in display order.
  final List<T> segments;

  /// Labels for each segment, aligned with [segments].
  final Map<T, String> labels;

  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final index = segments.indexOf(selected).clamp(0, segments.length - 1);
    final count = segments.length;
    return GlassSurface(
      shape: const LiquidRoundedSuperellipse(borderRadius: 9000),
      appearance: const LiquidGlassAppearance(tint: Color(0x14ffffff)),
      child: SizedBox(
        height: 36,
        child: Stack(
          children: [
            // Selection lens, gliding between segments.
            SingleMotionBuilder(
              motion: const Motion.bouncySpring(snapToEnd: true),
              value: count <= 1 ? 0 : index / (count - 1),
              builder: (context, fraction, child) => Padding(
                padding: const EdgeInsets.all(3),
                child: FractionallySizedBox(
                  widthFactor: 1 / count,
                  alignment: Alignment(fraction * 2 - 1, 0),
                  child: child,
                ),
              ),
              child: const GlassSurface(
                settings: clearLensSettings,
                appearance: clearLensAppearance,
                useOwnLayer: true,
                shape: LiquidRoundedSuperellipse(borderRadius: 9000),
                child: SizedBox.expand(),
              ),
            ),
            GlassGlow(
              hitTestBehavior: HitTestBehavior.translucent,
              child: Row(
                children: [
                  for (var i = 0; i < count; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelected(segments[i]),
                        child: Center(
                          child: Text(
                            labels[segments[i]] ?? segments[i].toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: segments[i] == selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: segments[i] == selected
                                  ? CupertinoColors.label.resolveFrom(context)
                                  : CupertinoColors.secondaryLabel.resolveFrom(
                                      context,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
