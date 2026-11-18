import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

void main() {
  test('holds its ends and runs straight between them', () {
    const ramp = Ramp(from: 0.2, start: 0.4, end: 0.8);
    expect(ramp.at(0), 0.2);
    expect(ramp.at(0.4), 0.2);
    expect(ramp.at(0.6), moreOrLessEquals(0.6, epsilon: 1e-12));
    expect(ramp.at(0.8), 1);
    expect(ramp.at(2), 1);
  });

  test('runs backwards in progress when start is past end', () {
    const closing = Ramp(from: 1, to: 0, start: 0.9, end: 0.3);
    expect(closing.at(1), 1);
    expect(closing.at(0.6), moreOrLessEquals(0.5, epsilon: 1e-12));
    expect(closing.at(0), 0);
  });

  test('a ramp with no span answers from', () {
    expect(const Ramp(from: 0.3, start: 0.5, end: 0.5).at(0.9), 0.3);
  });
}
