part of 'selector.dart';

/// What a selector shows of its motion, laid out left to right or
/// mirrored.
final class _SelectorFrames {
  _SelectorFrames(this._motion, {required this.mirrored, this.collapse});

  final SelectorMotion _motion;
  final bool mirrored;

  /// What collapses the bar, when something does.
  final GlassSelectorCollapse? collapse;

  late final MotionSelection<GlassFrame> lens = collapse == null
      ? _lens
      : MotionSelection(() {
          final frame = _lens.value;
          final morph = collapse!.morph.value;
          if (morph <= 0) return frame;
          return frame.copyWith(opacity: _lensOpacity(morph, frame.lift));
        });

  /// How much of the lens shows at [morph]: a lens a finger carries stays.
  static double _lensOpacity(double morph, double lift) => math
      .max(
        1 - morph / TabBarMinimizeMotion.lensGoneAt,
        lift,
      )
      .clamp(0.0, 1.0);

  late final MotionSelection<GlassFrame> _lens = _motion.select((motion) {
    final lens = motion.lens;
    if (lens == null) return const GlassFrame();
    final size = lens.size;
    final width = motion.size.width;
    return GlassFrame(
      rect: Rect.fromCenter(
        center: Offset(
          mirrored ? width - lens.center : lens.center,
          motion.size.height / 2,
        ),
        width: size.width * lens.scaleX,
        height: size.height * lens.scaleY,
      ),
      lift: lens.lift.clamp(0.0, 1.0),
    );
  });

  late final MotionSelection<GlassFrame> body = collapse == null
      ? _body
      : MotionSelection(() {
          final frame = _body.value;
          final morph = collapse!.morph.value;
          if (morph == 0) return frame;
          final lifted = collapse!.press?.value ?? 0;
          final circle = collapse!
              .circleIn(_motion.size)
              .inflate(TabBarMinimizeMotion.pressGrowth * lifted);
          final rect = Rect.lerp(frame.rect, circle, morph)!;
          return frame.copyWith(
            rect: rect,
            glow: frame.glow?.shift(
              (frame.rect ?? Offset.zero & _motion.size).topLeft - rect.topLeft,
            ),
          );
        });

  late final MotionSelection<GlassFrame> _body = _motion.select((motion) {
    final rect = motion.movingBounds ?? (collapse == null ? null : motion.bar);
    return GlassFrame(
      rect: rect,
      glow: motion.tabBar
          ? motion.glow.glow?.shift(-(rect?.topLeft ?? Offset.zero))
          : null,
    );
  });

  /// How many items the motion places, ghosts included.
  late final MotionSelection<int> placed = _motion.select(
    (motion) => motion.items.ids.length,
  );

  /// Where every item is drawn, ghosts included.
  late final MotionSelection<List<(Rect, double)?>> items = _motion.select(
    (motion) => [for (final id in motion.items.ids) motion.drawn(id)],
    equals: listEquals,
  );

  late final MotionSelection<(int?, double)> dim = _motion.select((motion) {
    final index = motion.highlight.index;
    return (index, index == null ? 1.0 : motion.highlight.opacity(index));
  });

  late final MotionSelection<Offset> drift = _motion.select((motion) {
    final chrome = motion.lens?.chrome ?? LensMotion.chromeAtRest;
    return Offset(mirrored ? -chrome.driftX : chrome.driftX, chrome.driftY);
  });

  late final MotionSelection<double> scaleX = _motion.select(
    (motion) => (motion.lens?.chrome ?? LensMotion.chromeAtRest).scaleX,
  );

  late final MotionSelection<double> scaleY = _motion.select(
    (motion) => (motion.lens?.chrome ?? LensMotion.chromeAtRest).scaleY,
  );
}
