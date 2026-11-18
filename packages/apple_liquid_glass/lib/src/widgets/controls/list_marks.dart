part of 'list.dart';

class _Chevron extends StatelessWidget {
  const _Chevron({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: _Metrics.chevronSize,
    painter: _ChevronPainter(
      color: color,
      mirrored: Directionality.of(context) == TextDirection.rtl,
    ),
  );
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.color, required this.mirrored});

  final Color color;
  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    double x(double v) => mirrored ? size.width - v : v;
    final path = Path();
    path.moveTo(x(3.7), 1.8);
    path.lineTo(x(8.7), 7);
    path.lineTo(x(3.7), 12.2);
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) =>
      color != oldDelegate.color || mirrored != oldDelegate.mirrored;
}

/// The box of a checkmark or an info button: 22 points, the size of a body
/// symbol (by eye, not measured).
class _Glyph extends StatelessWidget {
  const _Glyph({required this.painter});

  final CustomPainter painter;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(_Metrics.glyphSize),
    painter: painter,
  );
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    path.moveTo(size.width * 0.2, size.height * 0.52);
    path.lineTo(size.width * 0.42, size.height * 0.74);
    path.lineTo(size.width * 0.82, size.height * 0.26);
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2.2;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) => color != oldDelegate.color;
}

class _InfoPainter extends CustomPainter {
  const _InfoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 0.75;
    final ring = Paint();
    ring.color = color;
    ring.style = PaintingStyle.stroke;
    ring.strokeWidth = 1.5;
    canvas.drawCircle(center, radius, ring);
    final dot = Paint();
    dot.color = color;
    canvas.drawCircle(center.translate(0, -radius * 0.45), 1.3, dot);
    final stem = Paint();
    stem.color = color;
    stem.strokeWidth = 2;
    stem.strokeCap = StrokeCap.round;
    canvas.drawLine(
      center.translate(0, -radius * 0.12),
      center.translate(0, radius * 0.5),
      stem,
    );
  }

  @override
  bool shouldRepaint(_InfoPainter oldDelegate) => color != oldDelegate.color;
}
