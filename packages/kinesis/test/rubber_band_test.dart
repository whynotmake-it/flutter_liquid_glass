import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

void main() {
  const band = RubberBand(0, 100, dimension: 12);

  test('shows a position inside the range as it is', () {
    expect(band.show(0), 0);
    expect(band.show(40), 40);
    expect(band.show(100), 100);
    expect(band.stretch(40), 0);
  });

  test('past an end it starts with the coefficient as its slope and '
      'approaches the dimension', () {
    const steep = RubberBand(0, 100, dimension: 12, coefficient: 0.54);
    expect(
      (steep.show(100 + 1e-6) - 100) / 1e-6,
      moreOrLessEquals(0.54, epsilon: 1e-6),
    );
    expect(band.show(1000000000), moreOrLessEquals(112, epsilon: 1e-6));
    expect(band.show(-1000000000), moreOrLessEquals(-12, epsilon: 1e-6));
    expect(
      band.stretch(-30),
      moreOrLessEquals(-(band.show(130) - 100), epsilon: 1e-12),
    );
  });

  test('UIKit formula past the edge', () {
    const x = 7.0;
    expect(band.show(100 + x), 100 + x * 12 * 0.55 / (12 + 0.55 * x));
  });

  test('unshow inverts show and holds short of the asymptote', () {
    for (final raw in <double>[-50, -3, 0, 50, 103, 160]) {
      expect(band.unshow(band.show(raw)), moreOrLessEquals(raw, epsilon: 1e-9));
    }
    expect(band.unshow(112).isFinite, isTrue);
    expect(band.unshow(200), band.unshow(112));
  });

  test('an infinite end never resists', () {
    const open = RubberBand(double.negativeInfinity, 10, dimension: 5);
    expect(open.show(-1000000), -1000000);
    expect(open.show(12), lessThan(12));
  });
}
