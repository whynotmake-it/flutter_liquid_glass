import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

/// A control that shows a number its app owns.
class _Control extends StatefulWidget {
  const _Control({required this.value, required this.onChanged, super.key});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_Control> createState() => _ControlState();
}

class _ControlState extends State<_Control> with ControlledValue<_Control> {
  late int shown = widget.value;
  bool leads = false;

  @override
  MotionClock get valueClock => MotionClock.instance;

  @override
  bool get userLeads => leads;

  @override
  void followWidget() => shown = widget.value;

  @override
  void didUpdateWidget(_Control oldWidget) {
    super.didUpdateWidget(oldWidget);
    followWidget();
  }

  /// What a motion's event does when the user picks [value].
  void choose(int value) {
    shown = value;
    tellApp(() => widget.onChanged(value));
  }

  /// What a motion's event does when the user stops leading.
  void release() {
    leads = false;
    returnUnlessFollowed();
  }

  @override
  Widget buildControl(BuildContext context) =>
      Text('$shown', textDirection: TextDirection.ltr);
}

void main() {
  setUp(MotionClock.debugReset);

  final key = GlobalKey<_ControlState>();

  testWidgets('keeps the value an app follows', (tester) async {
    var value = 1;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _Control(
          key: key,
          value: value,
          onChanged: (next) => setState(() => value = next),
        ),
      ),
    );
    key.currentState!.choose(2);
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    expect(value, 2);
  });

  testWidgets('returns to the value of an app that does not follow', (
    tester,
  ) async {
    final heard = <int>[];
    await tester.pumpWidget(
      _Control(key: key, value: 1, onChanged: heard.add),
    );
    key.currentState!.choose(2);
    expect(key.currentState!.shown, 2);
    await tester.pump();
    expect(heard, [2]);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('does not return while the user leads, and returns once told '
      'they stopped', (tester) async {
    await tester.pumpWidget(_Control(key: key, value: 1, onChanged: (_) {}));
    final state = key.currentState!;
    state.leads = true;
    state.choose(2);
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    state.release();
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('an event raised while the framework lays out reaches the app '
      'in the coming publish phase, where it may rebuild', (tester) async {
    var value = 1;
    var raise = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return LayoutBuilder(
            builder: (context, constraints) {
              if (raise) {
                raise = false;
                key.currentState!.choose(2);
              }
              return _Control(
                key: key,
                value: value,
                onChanged: (next) => setState(() => value = next),
              );
            },
          );
        },
      ),
    );
    rebuild(() => raise = true);
    await tester.pump();
    expect(value, 1);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 16));
    expect(value, 2);
    expect(find.text('2'), findsOneWidget);
  });
}
