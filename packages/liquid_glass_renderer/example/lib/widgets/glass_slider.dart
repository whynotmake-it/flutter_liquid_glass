import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/widgets/glass_surface.dart';
import 'package:motor/motor.dart';

/// A liquid glass slider, ported from the reference widget's behavior:
///
/// - the track is a glass pill on its own shared-group layer,
/// - the thumb is a clear lens stacked on the track that squashes and
///   stretches with the drag ([LiquidStretch]) and scales through an
///   interactive spring while held,
/// - the fill glows through [GlassGlow] while the knob is touched.
class GlassSlider extends StatefulWidget {
  const GlassSlider({
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.trackHeight = 36,
    super.key,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final double trackHeight;

  @override
  State<GlassSlider> createState() => _GlassSliderState();
}

class _GlassSliderState extends State<GlassSlider> {
  bool _dragging = false;

  double get _normalized {
    final range = widget.max - widget.min;
    return range <= 0 ? 0 : ((widget.value - widget.min) / range).clamp(0, 1);
  }

  double _valueFrom(Offset localPosition, double trackWidth) {
    final fraction = (localPosition.dx / trackWidth).clamp(0.0, 1.0);
    return widget.min + fraction * (widget.max - widget.min);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.trackHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = constraints.maxWidth;
          return Stack(
            children: [
              // Keep the track and thumb as siblings. The thumb is a moving
              // nested lens; making it a child of the track layer causes its
              // retained compositor bounds to go stale during scrolling.
              SizedBox.expand(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (details) {
                    setState(() => _dragging = true);
                    widget.onChanged(
                      _valueFrom(details.localPosition, trackWidth),
                    );
                  },
                  onHorizontalDragUpdate: (details) => widget.onChanged(
                    _valueFrom(details.localPosition, trackWidth),
                  ),
                  onHorizontalDragEnd: (_) => setState(() => _dragging = false),
                  onHorizontalDragCancel: () =>
                      setState(() => _dragging = false),
                  onTapDown: (details) => widget.onChanged(
                    _valueFrom(details.localPosition, trackWidth),
                  ),
                  child: GlassGlow(
                    hitTestBehavior: HitTestBehavior.translucent,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: _normalized,
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemBlue.withValues(
                                alpha: .85,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: SingleMotionBuilder(
                    motion: _dragging
                        ? const Motion.interactiveSpring(snapToEnd: true)
                        : const Motion.snappySpring(snapToEnd: true),
                    value: _normalized,
                    builder: (context, fraction, thumb) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment(fraction * 2 - 1, 0),
                        child: thumb,
                      ),
                    ),
                    child: _GlassSliderThumb(active: _dragging),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The slider's clear glass thumb: a lens stacked on the track glass that
/// stretches with the drag like the reference slider's knob.
class _GlassSliderThumb extends StatelessWidget {
  const _GlassSliderThumb({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return LiquidStretch(
      interactionScale: active ? 1.12 : 1.05,
      stretch: .35,
      child: SingleMotionBuilder(
        motion: const Motion.interactiveSpring(snapToEnd: true),
        value: active ? 1.1 : 1.0,
        builder: (context, scale, child) => Transform.scale(
          scale: scale,
          child: child,
        ),
        child: const GlassSurface(
          settings: clearLensSettings,
          appearance: clearLensAppearance,
          useOwnLayer: true,
          shape: LiquidOval(),
          child: SizedBox.square(dimension: 28),
        ),
      ),
    );
  }
}
