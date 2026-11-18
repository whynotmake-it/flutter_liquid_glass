import 'dart:ui' show Tristate;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

Widget _app(Widget child) => WidgetsApp(
  color: const Color(0xFF000000),
  builder: (context, _) => Center(child: child),
);

void main() {
  setUp(MotionClock.debugReset);

  for (final given in [false, true]) {
    testWidgets('a region disabled by an update stops being focusable for '
        'accessibility${given ? ', with a focus node of its own' : ''}', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final focus = given ? FocusNode() : null;
      addTearDown(() => focus?.dispose());
      final press = [PressInteraction()];
      Widget region({required bool enabled}) => _app(
        InputRegion(
          interactions: press,
          enabled: enabled,
          focusNode: focus,
          semantics: const SemanticsProperties(label: 'go'),
          child: const SizedBox(width: 80, height: 40),
        ),
      );
      await tester.pumpWidget(region(enabled: true));
      SemanticsData data() =>
          tester.getSemantics(find.bySemanticsLabel('go')).getSemanticsData();
      expect(data().flagsCollection.isFocused, isNot(Tristate.none));
      expect(data().hasAction(SemanticsAction.focus), isTrue);

      await tester.pumpWidget(region(enabled: false));
      expect(data().flagsCollection.isFocused, Tristate.none);
      expect(data().hasAction(SemanticsAction.focus), isFalse);
      expect(data().hasAction(SemanticsAction.tap), isFalse);
      expect(data().flagsCollection.isEnabled, Tristate.isFalse);

      await tester.pumpWidget(region(enabled: true));
      expect(data().flagsCollection.isFocused, isNot(Tristate.none));
      expect(data().hasAction(SemanticsAction.focus), isTrue);
      semantics.dispose();
    });
  }
}
