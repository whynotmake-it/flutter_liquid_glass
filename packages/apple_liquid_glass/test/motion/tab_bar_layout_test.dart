import 'package:apple_liquid_glass/src/motions/tab_bar_layout.dart';
import 'package:flutter_test/flutter_test.dart';

// The bars of an iPhone 16 Pro (402 pt, 360 available): the title widths,
// the bar's width and each button's leading edge and width in the bar.
const _device = <(String, List<double>, double, List<(double, double)>)>[
  ('en 2', [29, 35], 188, [(4, 94), (90, 94)]),
  ('en 3', [29, 35, 28], 274, [(4, 94), (90, 94), (176, 94)]),
  (
    'en 4',
    [29, 35, 28, 36.33],
    360,
    [(4, 98), (88.67, 98), (173.33, 98), (258, 98)],
  ),
  (
    'en 5',
    [29, 35, 28, 36.33, 34.33],
    360,
    [(4, 77), (72.75, 77), (141.5, 77), (210.25, 77), (279, 77)],
  ),
  ('ru 2', [40.67, 56.33], 192.67, [(4, 96.33), (92.33, 96.33)]),
  (
    'ru 3',
    [40.67, 56.33, 56],
    281,
    [(4, 96.33), (92.33, 96.33), (180.67, 96.33)],
  ),
  (
    'ru 4',
    [40.67, 56.33, 56, 32],
    360,
    [(4, 96.33), (89.22, 96.33), (174.44, 96.33), (259.67, 96.33)],
  ),
  (
    'ru 5',
    [40.67, 56.33, 56, 32, 57],
    360,
    [
      (4, 77.22),
      (61.22, 92.4),
      (133.62, 92.05),
      (205.67, 77.22),
      (262.89, 93.11),
    ],
  ),
  ('long 2', [118.67, 119.33], 318.67, [(4, 159.33), (155.33, 159.33)]),
  (
    'long 3',
    [130, 130, 130],
    360,
    [(4, 122.67), (118.67, 122.67), (233.33, 122.67)],
  ),
];

void main() {
  for (final (name, naturals, width, buttons) in _device) {
    test('$name lays out as on the device', () {
      final layout = TabBarLayout.of(naturals, available: 360);
      expect(layout.width, closeTo(width, 0.02));
      for (final (i, (left, buttonWidth)) in buttons.indexed) {
        final button = layout.buttons[i];
        expect(button.width, closeTo(buttonWidth, 0.04), reason: 'width $i');
        expect(
          button.center - button.width / 2,
          closeTo(left, 0.04),
          reason: 'left $i',
        );
      }
    });
  }

  test('four tabs keep the bar across languages; their tabs adapt', () {
    final short = TabBarLayout.of(const [29, 35, 28, 36], available: 360);
    final long = TabBarLayout.of(const [120, 130, 140, 150], available: 360);
    expect(long.width, short.width);
    expect(long.buttons.last.center, lessThan(360));
  });

  test('a hosted bar of two tabs fills its room', () {
    expect(
      TabBarLayout.of(const [29, 35], available: 360, hosted: true).width,
      360,
    );
  });

  test('tabs too long for the bar end up inside it', () {
    final layout = TabBarLayout.of(
      const [200, 200, 200, 200, 200],
      available: 360,
    );
    final last = layout.buttons.last;
    expect(last.center + last.width / 2, lessThanOrEqualTo(360 - 4 + 1e-6));
    expect(layout.buttons.first.center - layout.buttons.first.width / 2, 4);
  });
}
