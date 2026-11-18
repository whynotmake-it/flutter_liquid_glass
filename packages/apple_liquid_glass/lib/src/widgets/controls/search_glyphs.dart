import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

Color _glyphColor(BuildContext context, Color? color) {
  if (color != null) return color;
  final theme = IconTheme.of(context);
  final themed = theme.color ?? GlassTheme.labelColorOf(context);
  final opacity = theme.opacity;
  return opacity == null
      ? themed
      : themed.withValues(alpha: themed.a * opacity);
}

/// The search magnifier of iOS 27, scaled to its [size].
///
/// UIKit: SF Symbols' `magnifyingglass`. Flutter: `Icons.search`. The
/// strokes are read from an iPhone 16 Pro's screen in a 20.67 x 19.33 box:
/// a ring 13.33 points across drawn 1.75 thick, its center 8.67 and 7.67
/// points in from the top left, and a handle out to 17.4 and 16.7; all of
/// it scales with the box, fitted inside it.
class GlassSearchIcon extends StatelessWidget {
  /// Creates the magnifier, [size] points across, in [color] or the icon
  /// theme's.
  const GlassSearchIcon({this.size = defaultSize, this.color, super.key});

  /// The size of the magnifier in a search field.
  static const Size defaultSize = Size(20.67, 19.33);

  /// The box the magnifier fits in.
  final Size size;

  /// The color of the strokes, or null for the icon theme's color (the
  /// theme's label color without one).
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: size,
    child: CustomPaint(
      painter: _MagnifierPainter(_glyphColor(context, color)),
    ),
  );
}

/// The cross of a search's close button, [size] points across.
///
/// UIKit: SF Symbols' `xmark` in the close button. Flutter: `Icons.close`,
/// `CloseButtonIcon`. Two 2.3 point strokes with round caps, whose ink
/// fills a 16.67 point square at the center of the box (iPhone 16 Pro
/// screen, search passport).
class GlassCloseIcon extends StatelessWidget {
  /// Creates the cross, [size] points across, in [color] or the icon
  /// theme's.
  const GlassCloseIcon({this.size = _defaultSize, this.color, super.key});

  /// The side of the square the cross's ink fills.
  @internal
  static const double ink = 16.67;

  static const Size _defaultSize = Size(22.67, 21.33);

  /// The box the cross is centered in; by default 22.67 x 21.33, the box of
  /// a search's close button.
  final Size size;

  /// The color of the strokes, or null for the icon theme's color (the
  /// theme's label color without one).
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: size,
    child: CustomPaint(painter: _CrossPainter(_glyphColor(context, color))),
  );
}

class _MagnifierPainter extends CustomPainter {
  const _MagnifierPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const box = GlassSearchIcon.defaultSize;
    final k = math.min(size.width / box.width, size.height / box.height);
    final origin = Offset(
      (size.width - box.width * k) / 2,
      (size.height - box.height * k) / 2,
    );
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1.75 * k;
    paint.strokeCap = StrokeCap.round;
    final c = origin + const Offset(8.67, 7.67) * k;
    final r = (13.33 - 1.75) / 2 * k;
    canvas.drawCircle(c, r, paint);
    final d = r * math.sqrt1_2;
    canvas.drawLine(
      c + Offset(d, d),
      origin + const Offset(17.4, 16.7) * k,
      paint,
    );
  }

  @override
  bool shouldRepaint(_MagnifierPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _CrossPainter extends CustomPainter {
  const _CrossPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const ink = GlassCloseIcon.ink;
    const stroke = 2.3;
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = stroke;
    paint.strokeCap = StrokeCap.round;
    final c = size.center(Offset.zero);
    const h = (ink - stroke) / 2;
    canvas.drawLine(c + const Offset(-h, -h), c + const Offset(h, h), paint);
    canvas.drawLine(c + const Offset(h, -h), c + const Offset(-h, h), paint);
  }

  @override
  bool shouldRepaint(_CrossPainter oldDelegate) => oldDelegate.color != color;
}
