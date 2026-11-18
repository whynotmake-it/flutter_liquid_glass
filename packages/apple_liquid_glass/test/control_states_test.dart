import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(
      renderer: const FlatGlassRenderer(),
      child: Center(child: SizedBox(width: 300, child: child)),
    ),
  ),
);

typedef _Control = ({
  String name,
  Set<WidgetState> said,
  Widget Function(WidgetStatesController states, {required bool enabled}) build,
});

final List<_Control> _controls = [
  (
    name: 'a button',
    said: {},
    build: (states, {required enabled}) => GlassButton(
      onPressed: enabled ? () {} : null,
      statesController: states,
      child: const Text('Go'),
    ),
  ),
  (
    name: 'a switch',
    said: {WidgetState.selected},
    build: (states, {required enabled}) => GlassSwitch(
      value: true,
      onChanged: enabled ? (_) {} : null,
      statesController: states,
    ),
  ),
  (
    name: 'a slider',
    said: {},
    build: (states, {required enabled}) => GlassSlider(
      value: 0.5,
      onChanged: enabled ? (_) {} : null,
      statesController: states,
    ),
  ),
  (
    name: 'a stepper',
    said: {},
    build: (states, {required enabled}) => GlassStepper(
      value: 1,
      onChanged: enabled ? (_) {} : null,
      statesController: states,
    ),
  ),
  (
    name: 'a list row',
    said: {},
    build: (states, {required enabled}) => GlassListRow(
      title: const Text('Row'),
      onPressed: () {},
      enabled: enabled,
      statesController: states,
    ),
  ),
  (
    name: 'a page control',
    said: {},
    build: (states, {required enabled}) => GlassPageControl(
      count: 3,
      page: 0,
      onChanged: enabled ? (_) {} : null,
      statesController: states,
    ),
  ),
  (
    name: 'a search field',
    said: {},
    build: (states, {required enabled}) =>
        GlassSearchField(enabled: enabled, statesController: states),
  ),
  (
    name: 'a segmented control',
    said: {},
    build: (states, {required enabled}) => GlassSegmentedControl<String>(
      segments: const [
        GlassSegment(value: 'a', label: Text('One')),
        GlassSegment(value: 'b', label: Text('Two')),
      ],
      groupValue: 'a',
      onChanged: enabled ? (_) {} : null,
      statesController: states,
    ),
  ),
];

void main() {
  setUp(MotionClock.debugReset);

  for (final control in _controls) {
    testWidgets('${control.name} shows what it says and disabled, never '
        'hover, while it is disabled, and hover once enabled under the '
        'mouse', (tester) async {
      final states = WidgetStatesController();
      addTearDown(states.dispose);
      Widget app({required bool enabled}) =>
          _app(control.build(states, enabled: enabled));
      await tester.pumpWidget(app(enabled: true));
      final center = tester.getCenter(find.byType(SizedBox).first);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(center);
      await tester.pump();
      expect(states.value, {...control.said, WidgetState.hovered});

      await tester.pumpWidget(app(enabled: false));
      expect(states.value, {...control.said, WidgetState.disabled});
      await mouse.moveTo(center + const Offset(1, 0));
      await tester.pump();
      expect(states.value, {...control.said, WidgetState.disabled});

      await tester.pumpWidget(app(enabled: true));
      expect(states.value, {...control.said, WidgetState.hovered});
      await tester.pumpAndSettle();
    });
  }
}
