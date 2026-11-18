import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

class _Control extends StatefulWidget {
  const _Control({
    required this.enabled,
    required this.builds,
    this.selected = false,
    this.statesController,
    this.focusNode,
  });

  final bool enabled;
  final bool selected;
  final List<Set<WidgetState>> builds;
  final WidgetStatesController? statesController;
  final FocusNode? focusNode;

  @override
  State<_Control> createState() => _ControlState();
}

class _ControlState extends State<_Control> with ControlStates<_Control> {
  final List<Interaction> _press = [PressInteraction(onTap: (_) {})];

  @override
  WidgetStatesController? get givenStates => widget.statesController;

  @override
  bool get enabled => widget.enabled;

  @override
  Set<WidgetState> get saidStates => {
    if (widget.selected) WidgetState.selected,
  };

  @override
  Widget build(BuildContext context) {
    widget.builds.add({...widgetStates.value});
    return InputRegion(
      interactions: _press,
      enabled: enabled,
      states: saidStates,
      statesController: widgetStates,
      focusNode: widget.focusNode,
      child: const SizedBox(width: 80, height: 40),
    );
  }
}

Widget _app(Widget child) => WidgetsApp(
  color: const Color(0xFF000000),
  builder: (context, _) => Center(child: child),
);

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('what the control says is published before its first build '
      'and on every update, in one build each', (tester) async {
    final builds = <Set<WidgetState>>[];
    await tester.pumpWidget(
      _app(_Control(enabled: false, selected: true, builds: builds)),
    );
    expect(builds.single, {WidgetState.disabled, WidgetState.selected});

    await tester.pumpWidget(_app(_Control(enabled: true, builds: builds)));
    expect(builds, hasLength(2));
    expect(builds.last, isEmpty);
  });

  testWidgets('input changes rebuild the control', (tester) async {
    final builds = <Set<WidgetState>>[];
    await tester.pumpWidget(_app(_Control(enabled: true, builds: builds)));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SizedBox).last),
    );
    await tester.pump();
    expect(builds.last, {WidgetState.pressed});
    await gesture.up();
    await tester.pump();
    expect(builds.last, isEmpty);
  });

  testWidgets('a disabled control is never hovered, and one enabled under '
      'a resting mouse is hovered after the frame that enables it', (
    tester,
  ) async {
    final builds = <Set<WidgetState>>[];
    final controller = WidgetStatesController();
    addTearDown(controller.dispose);
    Widget control({required bool enabled}) => _app(
      _Control(enabled: enabled, builds: builds, statesController: controller),
    );
    await tester.pumpWidget(control(enabled: true));
    final center = tester.getCenter(find.byType(SizedBox).last);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(center);
    await tester.pump();
    expect(controller.value, {WidgetState.hovered});

    await tester.pumpWidget(control(enabled: false));
    expect(controller.value, {WidgetState.disabled});
    await mouse.moveTo(center + const Offset(2, 0));
    await tester.pump();
    expect(controller.value, {WidgetState.disabled});

    final count = builds.length;
    await tester.pumpWidget(control(enabled: true));
    expect(builds, hasLength(count + 1));
    expect(builds.last, isEmpty);
    expect(controller.value, {WidgetState.hovered});
    await tester.pump();
    expect(builds.last, {WidgetState.hovered});

    await tester.pumpWidget(control(enabled: false));
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    await tester.pumpWidget(control(enabled: true));
    await tester.pump();
    expect(controller.value, isEmpty);
  });

  testWidgets('a keyboard-focused control that is disabled loses its focus '
      'ring in the same build', (tester) async {
    final builds = <Set<WidgetState>>[];
    final focus = FocusNode();
    addTearDown(focus.dispose);
    Widget control({required bool enabled}) => _app(
      _Control(enabled: enabled, builds: builds, focusNode: focus),
    );
    await tester.pumpWidget(control(enabled: true));
    focus.requestFocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    expect(builds.last, {WidgetState.focused});

    final count = builds.length;
    await tester.pumpWidget(control(enabled: false));
    expect(builds, hasLength(count + 1));
    expect(builds.last, {WidgetState.disabled});
  });

  testWidgets('a given controller is an output: what else writes to it is '
      'written over at the next change', (tester) async {
    final builds = <Set<WidgetState>>[];
    await tester.pumpWidget(_app(_Control(enabled: true, builds: builds)));
    final given = WidgetStatesController();
    addTearDown(given.dispose);
    given.update(WidgetState.error, true);
    await tester.pumpWidget(
      _app(_Control(enabled: false, builds: builds, statesController: given)),
    );
    expect(given.value, {WidgetState.disabled});
    expect(builds.last, {WidgetState.disabled});
  });
}
