// Run with `flutter test --enable-impeller --enable-flutter-gpu`: glass is
// drawn as on a device, and fake glass otherwise.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_test/liquid_glass_test.dart';

Widget _glass() => const Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: LiquidGlass.withOwnLayer(
      shape: LiquidRoundedSuperellipse(borderRadius: 22),
      child: SizedBox.square(dimension: 44),
    ),
  ),
);

Future<TestFailure?> _failureOf(Future<Object?> check) async {
  try {
    await check;
  } on TestFailure catch (failure) {
    return failure;
  }
  return null;
}

void main() {
  setUpAll(LiquidGlass.precache);

  testWidgets('returns the report of a frame with glass', (tester) async {
    await tester.pumpWidget(_glass());
    await tester.pump();

    final report = await expectGlassBudget(
      tester,
      reads: greaterThanOrEqualTo(0),
      liveReads: isNonNegative,
    );

    expect(report.liveReads, isNonNegative);
  });

  testWidgets('fails a matcher the frame does not meet', (tester) async {
    await tester.pumpWidget(_glass());
    await tester.pump();

    expect(await _failureOf(expectGlassBudget(tester, reads: -1)), isNotNull);
  });

  testWidgets('fails a frame without glass', (tester) async {
    await tester.pumpWidget(const SizedBox());

    final failure = await _failureOf(expectGlassBudget(tester));
    expect(failure?.message, contains('no glass'));
  });
}
