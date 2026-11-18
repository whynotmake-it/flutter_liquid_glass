import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

late GlassTraits _seen;

Widget _probe({
  bool reduceMotion = false,
  bool? prefersCrossFade,
  bool? showBorders,
  Widget? child,
}) => MediaQuery(
  data: MediaQueryData(disableAnimations: reduceMotion),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(
      renderer: const FlatGlassRenderer(),
      child: GlassTraitsOverride(
        prefersCrossFade: prefersCrossFade,
        showBorders: showBorders,
        child: Builder(
          builder: (context) {
            _seen = GlassTraits.of(context);
            return child ?? const SizedBox();
          },
        ),
      ),
    ),
  ),
);

void main() {
  setUp(() {
    MotionClock.debugReset();
    MotionTraits.debugPlatformOverride = null;
  });
  tearDown(() => MotionTraits.debugPlatformOverride = null);

  testWidgets('prefer cross-fade follows Reduce Motion unless the platform '
      'or an override says otherwise', (tester) async {
    await tester.pumpWidget(_probe());
    expect(_seen.prefersCrossFade, isFalse);
    await tester.pumpWidget(_probe(reduceMotion: true));
    expect(_seen.prefersCrossFade, isTrue);
    MotionTraits.debugPlatformOverride = const MotionTraits(
      preferCrossFade: false,
    );
    await tester.pumpWidget(_probe(reduceMotion: true, showBorders: true));
    expect(_seen.prefersCrossFade, isFalse);
    await tester.pumpWidget(_probe(reduceMotion: true, prefersCrossFade: true));
    expect(_seen.prefersCrossFade, isTrue);
    await tester.pumpWidget(_probe(prefersCrossFade: true));
    expect(
      _seen.prefersCrossFade,
      isFalse,
      reason: 'cross-fade is a part of Reduce Motion',
    );
  });

  testWidgets('Show Borders draws a hairline around a glass body', (
    tester,
  ) async {
    Widget surface({bool? borders}) => _probe(
      showBorders: borders,
      child: const Center(
        child: GlassSurface(child: SizedBox(width: 100, height: 44)),
      ),
    );
    await tester.pumpWidget(surface());
    expect(_seen.showBorders, isFalse);
    final plain = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.foregroundPainter != null,
    );
    expect(plain, findsNothing);
    await tester.pumpWidget(surface(borders: true));
    expect(_seen.showBorders, isTrue);
    expect(plain, findsOneWidget);
  });
}
