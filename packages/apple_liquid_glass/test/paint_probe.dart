import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A painter that calls [onPaint] each time it paints, so a test can ask
/// whether what holds it painted in a frame.
class PaintProbe extends CustomPainter {
  /// A painter that calls [onPaint] on every paint.
  PaintProbe(this.onPaint);

  /// Runs on every paint.
  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) => onPaint();

  @override
  bool shouldRepaint(PaintProbe oldDelegate) => true;
}

/// Marks every render object [finder] finds as needing paint and pumps a
/// frame: a probe among them paints again unless something above it no
/// longer paints its child.
Future<void> repaint(WidgetTester tester, Finder finder) async {
  for (final object in tester.renderObjectList(finder)) {
    object.markNeedsPaint();
  }
  await tester.pump();
}
