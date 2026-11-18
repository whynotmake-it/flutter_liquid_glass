import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

void main() {
  setUp(MotionClock.debugReset);

  for (final enabled in [true, false]) {
    testWidgets('a region that acts is a semantics node of its own beside '
        'plain content${enabled ? '' : ', disabled too'}', (tester) async {
      final semantics = tester.ensureSemantics();
      final press = [PressInteraction()];
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFF000000),
          builder: (context, _) => Semantics(
            container: true,
            child: Column(
              children: [
                const Text('note'),
                InputRegion(
                  interactions: press,
                  enabled: enabled,
                  semantics: const SemanticsProperties(label: 'go'),
                  child: const SizedBox(width: 80, height: 40),
                ),
              ],
            ),
          ),
        ),
      );
      final node = tester.getSemantics(find.bySemanticsLabel('go'));
      expect(node.rect.size, const Size(80, 40));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        enabled,
      );
      semantics.dispose();
    });
  }
}
