import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_read.dart';

void main() {
  test('a frost dissolves smoothly between its rows, top or bottom', () {
    const down = FrostDissolve(100, 140);
    expect(down.at(90), 1);
    expect(down.at(100), 1);
    expect(down.at(120), closeTo(0.5, 1e-9));
    expect(down.at(140), 0);
    expect(down.at(150), 0);
    // No slope where it starts or ends, so no line shows there.
    expect(down.at(100.5), closeTo(1, 1e-4));
    expect(down.at(139.5), closeTo(0, 1e-4));
    const up = FrostDissolve(140, 100);
    expect(up.at(150), 1);
    expect(up.at(110), closeTo(1 - down.at(110), 1e-9));
  });

  test('a frost with no rows is whole everywhere and stays so mapped', () {
    expect(FrostDissolve.none.at(0), 1);
    expect(FrostDissolve.none.at(-500), 1);
    expect(FrostDissolve.none.mapped(40, 3).isNone, isTrue);
  });

  test('rows map to the pixels of a copy', () {
    expect(
      const FrostDissolve(100, 140).mapped(-20, 2),
      const FrostDissolve(160, 240),
    );
  });
}
