part of 'date_picker.dart';

/// The overlay's box at one time: where it sits, how it scales about its
/// anchor and how far it shows.
@immutable
class _BoxFrame {
  const _BoxFrame({
    required this.box,
    required this.transform,
    required this.opacity,
  });

  factory _BoxFrame.of(
    DatePickerMotion motion,
    DatePickerPlacement placement, {
    required bool below,
  }) {
    final rect = placement.rect;
    final anchor = placement.anchor;
    final s = motion.scale;
    final h = math.min(rect.height, motion.height(rect.height));
    final box = Rect.fromLTWH(
      rect.left,
      below ? rect.top : rect.bottom - h,
      rect.width,
      math.max(0, h),
    );
    final transform = Matrix4.diagonal3Values(s, s, 1);
    transform.setTranslationRaw(
      anchor.dx - s * anchor.dx,
      anchor.dy - s * anchor.dy,
      0,
    );
    return _BoxFrame(
      box: box,
      transform: transform,
      opacity: motion.opacity,
    );
  }

  /// The box before the scale, in the overlay's coordinates.
  final Rect box;

  /// The scale about the anchor, in the overlay's coordinates.
  final Matrix4 transform;

  /// The platter's and the content's opacity.
  final double opacity;

  @override
  bool operator ==(Object other) =>
      other is _BoxFrame &&
      other.box == box &&
      other.transform == transform &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(box, transform, opacity);
}

class _Crossfade extends StatelessWidget {
  const _Crossfade({
    required this.fadeIn,
    required this.fadeOut,
    required this.from,
    required this.to,
    required this.alignment,
  });

  final AlignmentDirectional alignment;
  final ValueListenable<double> fadeIn;
  final ValueListenable<double> fadeOut;
  final Widget from;
  final Widget to;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: alignment,
    clipBehavior: Clip.none,
    children: [
      IgnorePointer(
        child: MotionTransition(opacity: fadeOut, child: from),
      ),
      MotionTransition(opacity: fadeIn, child: to),
    ],
  );
}

abstract final class _DatePickerLook {
  static const double cornerRadius = 28;

  static const double dateLabelHeight = 34.33;

  static const double timeLabelHeight = 36;

  static const double labelPadding = 12;

  static const double labelGap = 4;
}
