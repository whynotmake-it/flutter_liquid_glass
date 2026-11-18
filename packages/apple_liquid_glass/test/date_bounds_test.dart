import 'package:apple_liquid_glass/raw.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final first = DateTime(2026, 3, 10, 15, 30);
  final last = DateTime(2026, 5, 20, 9, 15);
  final bounds = GlassDateBounds(first, last);

  test('a maximum before the minimum offers every moment', () {
    final inverted = GlassDateBounds(last, first);
    expect(inverted.first, isNull);
    expect(inverted.last, isNull);
    final far = DateTime(1990);
    expect(inverted.clamp(far), far);
    expect(inverted.offersDay(far), isTrue);
    expect(inverted.offersMonth(far), isTrue);
  });

  test('a moment clamps to the bounds themselves', () {
    expect(bounds.clamp(DateTime(2026, 3, 10, 8)), first);
    expect(bounds.clamp(DateTime(2026, 5, 20, 22)), last);
    final inside = DateTime(2026, 4, 1, 12);
    expect(bounds.clamp(inside), inside);
  });

  test('a bound at midday still offers its whole day', () {
    expect(bounds.offersDay(DateTime(2026, 3, 10)), isTrue);
    expect(bounds.offersDay(DateTime(2026, 3, 10, 23, 59)), isTrue);
    expect(bounds.offersDay(DateTime(2026, 5, 20, 23, 59)), isTrue);
    expect(bounds.offersDay(DateTime(2026, 3, 9, 23, 59)), isFalse);
    expect(bounds.offersDay(DateTime(2026, 5, 21)), isFalse);
  });

  test('a day clamps to the nearest day offered at its own time', () {
    expect(
      bounds.clampDay(DateTime(2026, 2, 28, 7, 45)),
      DateTime(2026, 3, 10, 7, 45),
    );
    expect(
      bounds.clampDay(DateTime(2026, 6, 1, 18, 5)),
      DateTime(2026, 5, 20, 18, 5),
    );
    final early = DateTime(2026, 3, 10, 6);
    expect(bounds.clampDay(early), early);
  });

  test('the months of both bounds are offered, and none beyond', () {
    expect(bounds.offersMonth(DateTime(2026, 3)), isTrue);
    expect(bounds.offersMonth(DateTime(2026, 5, 31)), isTrue);
    expect(bounds.offersMonth(DateTime(2026, 2, 28)), isFalse);
    expect(bounds.offersMonth(DateTime(2026, 6)), isFalse);
    expect(GlassDateBounds(null, null).offersMonth(DateTime(1)), isTrue);
  });
}
