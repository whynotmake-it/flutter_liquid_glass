import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

Widget _app(Widget child) => WidgetsApp(
  color: const Color(0xFF000000),
  builder: (context, _) => Center(child: child),
);

/// A row that activates, with a switch inside it that activates too: the
/// shape of a pressable list row in a swipe container, or a switch in a
/// pressable row.
class _Nested extends StatefulWidget {
  const _Nested({
    required this.outerFocus,
    required this.innerFocus,
    required this.log,
  });

  final FocusNode outerFocus;
  final FocusNode innerFocus;
  final List<String> log;

  @override
  State<_Nested> createState() => _NestedState();
}

class _NestedState extends State<_Nested> {
  late final _outer = [PressInteraction(onTap: (t) => widget.log.add('row'))];
  late final _inner = [
    PressInteraction(onTap: (t) => widget.log.add('switch')),
  ];

  @override
  Widget build(BuildContext context) => InputRegion(
    interactions: _outer,
    focusNode: widget.outerFocus,
    child: SizedBox(
      width: 200,
      height: 60,
      child: Center(
        child: InputRegion(
          interactions: _inner,
          focusNode: widget.innerFocus,
          child: const SizedBox(width: 50, height: 30),
        ),
      ),
    ),
  );
}

void main() {
  setUp(MotionClock.debugReset);

  group('nested activation', () {
    late FocusNode outer;
    late FocusNode inner;

    setUp(() {
      outer = FocusNode(debugLabel: 'row');
      inner = FocusNode(debugLabel: 'switch');
    });

    tearDown(() {
      outer.dispose();
      inner.dispose();
    });

    testWidgets('Space and Enter activate the focused inner region, not the '
        'one around it', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(
        _app(_Nested(outerFocus: outer, innerFocus: inner, log: log)),
      );
      inner.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(log, ['switch', 'switch']);

      outer.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(log, ['switch', 'switch', 'row']);
    });

    testWidgets('an app override above both still hears the inner '
        'activation, and its calling action reaches the inner region', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(
        _app(
          Actions(
            actions: {ActivateIntent: _Logging(log)},
            child: _Nested(outerFocus: outer, innerFocus: inner, log: log),
          ),
        ),
      );
      inner.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(log, ['app', 'switch']);
    });

    testWidgets('a focused zone inside a region activates itself', (
      tester,
    ) async {
      final log = <String>[];
      final zones = InputZonesController<int>();
      addTearDown(zones.dispose);
      final frames = ValueNotifier(0);
      addTearDown(frames.dispose);
      final rowPress = [PressInteraction(onTap: (t) => log.add('row'))];
      final zonePress = [PressInteraction(onTap: (t) => log.add('zone'))];
      await tester.pumpWidget(
        _app(
          InputRegion(
            interactions: rowPress,
            focusNode: outer,
            child: InputZones<int>(
              zones: [InputZone(id: 0, interactions: zonePress)],
              frameOf: (id) =>
                  const InputZoneFrame(Rect.fromLTWH(10, 10, 40, 40)),
              frames: frames,
              controller: zones,
              child: const SizedBox(width: 200, height: 60),
            ),
          ),
        ),
      );
      zones.requestFocus(0);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(log, ['zone']);
      outer.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(log, ['zone', 'row']);
    });
  });
}

/// An app's override that logs, then runs what it overrides.
class _Logging extends Action<ActivateIntent> {
  _Logging(this.log);

  final List<String> log;

  @override
  Object? invoke(ActivateIntent intent) {
    log.add('app');
    return callingAction?.invoke(intent);
  }
}
