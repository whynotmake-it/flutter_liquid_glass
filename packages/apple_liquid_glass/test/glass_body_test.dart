import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _box = Size(120, 44);

final _outline = GlassOutline(
  Path()..addRRect(RRect.fromLTRBR(14, 6, 90, 40, const Radius.circular(10))),
);

final _frames = <String, GlassFrame>{
  'in place': const GlassFrame(),
  'scaled in place': const GlassFrame(scaleX: 1.15, scaleY: 1.15),
  'placed': const GlassFrame(rect: Rect.fromLTWH(10, 4, 60, 30)),
  'placed and stretched': const GlassFrame(
    rect: Rect.fromLTWH(10, 4, 60, 30),
    scaleX: 1.2,
    scaleY: 0.9,
  ),
  'wider than the box': const GlassFrame(
    rect: Rect.fromLTWH(-5, 0, 200, 44),
    scaleX: 0.8,
    scaleY: 1.3,
  ),
  'outline': GlassFrame(outline: _outline),
};

const _content = Key('content');

void main() {
  setUp(MotionClock.debugReset);

  for (final renderer in const [FlatGlassRenderer(), LiquidGlassRenderer()]) {
    for (final MapEntry(key: name, value: frame) in _frames.entries) {
      testWidgets('${renderer.runtimeType} draws content where GlassBody '
          'says: $name', (tester) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: GlassScope(
              renderer: renderer,
              child: Center(
                child: SizedBox.fromSize(
                  size: _box,
                  child: GlassSurface.live(
                    frame: MotionSelection(() => frame),
                    child: const SizedBox.expand(key: _content),
                  ),
                ),
              ),
            ),
          ),
        );
        final surface = tester.renderObject<RenderBox>(
          find.byType(GlassSurface),
        );
        final content = tester.renderObject<RenderBox>(find.byKey(_content));
        final seen = content.getTransformTo(surface);
        final said = frame.bodyIn(_box).childToBox ?? Matrix4.identity();
        for (final point in const [
          Offset.zero,
          Offset(120, 0),
          Offset(0, 44),
          Offset(37, 21),
        ]) {
          expect(
            MatrixUtils.transformPoint(seen, point),
            offsetMoreOrLessEquals(
              MatrixUtils.transformPoint(said, point),
              epsilon: 1e-6,
            ),
          );
        }
      });
    }
  }

  for (final MapEntry(key: name, value: frame) in _frames.entries) {
    test('the edge an overlay draws is the drawn body: $name', () {
      final body = frame.bodyIn(_box);
      expect(
        body.edgeInBox.getBounds(),
        rectMoreOrLessEquals(body.drawnRect, epsilon: 1e-4),
      );
      expect(
        MatrixUtils.transformRect(
          body.toBox ?? Matrix4.identity(),
          body.edge.getBounds(),
        ),
        rectMoreOrLessEquals(body.drawnRect, epsilon: 1e-4),
      );
    });
  }

  test('corners scale with the body', () {
    const frame = GlassFrame(
      shape: LiquidRoundedRectangle(radius: 8),
      rect: Rect.fromLTWH(0, 0, 60, 30),
      scaleX: 1.5,
      scaleY: 1.5,
    );
    final body = frame.bodyIn(_box);
    expect(body.radius, 8);
    expect(body.drawnRadius, 12);
  });

  test('bodies are equal when they draw the same shape in the same place', () {
    final bodies = [
      for (final frame in _frames.values) () => frame.bodyIn(_box),
      () => const GlassFrame(
        shape: LiquidRoundedRectangle(radius: 8),
      ).bodyIn(_box),
      () => const GlassFrame().bodyIn(const Size(120, 50)),
    ];
    for (final (i, a) in bodies.indexed) {
      for (final (j, b) in bodies.indexed) {
        expect(a() == b(), i == j, reason: 'bodies $i and $j');
        if (i == j) expect(a().hashCode, b().hashCode);
      }
    }
    expect(
      const GlassFrame().bodyIn(_box),
      const GlassFrame(rect: Rect.fromLTWH(0, 0, 120, 44)).bodyIn(_box),
      reason: 'no rect is the whole box',
    );
  });
}
