import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer_example/playground/backdrops.dart';

void main() {
  testWidgets('the backdrop pager creates its spring before it is disposed', (
    tester,
  ) async {
    final backdrop = ValueNotifier(Backdrop.photos);
    addTearDown(backdrop.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: BackdropPager(backdrop: backdrop),
      ),
    );

    // Flutter 3.47 silently allows a ticker created during dispose(), and
    // 3.44 asserts. Check that the spring's ticker exists while the pager is
    // still mounted and has never paged.
    final ticker = tester
        .state(find.byType(BackdropPager))
        .toDiagnosticsNode()
        .getProperties()
        .singleWhere((property) => property.name == 'ticker');
    expect(ticker.value, isNotNull);

    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
