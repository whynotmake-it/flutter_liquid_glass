import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'glass_shown.dart';

const _frame = Duration(milliseconds: 16);

Widget _app(
  Widget child, {
  GlassRenderer renderer = const FlatGlassRenderer(),
  GlassThemeData theme = const GlassThemeData(),
  TextDirection direction = TextDirection.ltr,
  double? width = 300,
}) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: direction,
    child: GlassScope(
      renderer: renderer,
      data: theme,
      child: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);

Widget _keys(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    WidgetsApp(
      color: const Color(0xFF000000),
      builder: (context, _) => _app(child, direction: direction),
    );

const _segments = [
  GlassSegment(value: 'a', label: Text('One')),
  GlassSegment(value: 'b', label: Text('Two')),
  GlassSegment(value: 'c', label: Text('Three')),
];

class _Controlled extends StatefulWidget {
  const _Controlled({this.onChanged, this.onReselected});

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onReselected;

  @override
  State<_Controlled> createState() => _ControlledState();
}

class _ControlledState extends State<_Controlled> {
  String value = 'a';

  @override
  Widget build(BuildContext context) => GlassSegmentedControl<String>(
    segments: _segments,
    groupValue: value,
    onChanged: (next) {
      widget.onChanged?.call(next);
      setState(() => value = next);
    },
    onReselected: widget.onReselected,
  );
}

class _Probe {
  int builds = 0;
  GlassSelectorDetails? details;

  Widget build(BuildContext context, GlassSelectorDetails details) {
    builds++;
    this.details = details;
    return details.items();
  }

  GlassFrame get lens => details!.lens.value;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(_frame);
  }
}

Offset _at(WidgetTester tester, String label) =>
    tester.getCenter(find.text(label));

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a tap selects on release and the lens travels there', (
    tester,
  ) async {
    final probe = _Probe();
    final values = <String>[];
    await tester.pumpWidget(
      _app(
        GlassSegmentedControl<String>(
          segments: _segments,
          groupValue: 'a',
          onChanged: values.add,
          style: GlassSegmentedStyle(builder: probe.build),
        ),
      ),
    );
    final start = probe.lens.rect!.center.dx;
    await tester.tapAt(_at(tester, 'Three'));
    await _settle(tester);
    expect(values, ['c']);
    await tester.pumpWidget(
      _app(
        GlassSegmentedControl<String>(
          segments: _segments,
          groupValue: 'c',
          onChanged: values.add,
          style: GlassSegmentedStyle(builder: probe.build),
        ),
      ),
    );
    await _settle(tester);
    expect(probe.lens.rect!.center.dx, closeTo(start + 200, 1));
    expect(probe.lens.lift, 0);
  });

  testWidgets('a drag lifts the lens and carries it without building; the '
      'release selects where it lands', (tester) async {
    final probe = _Probe();
    final values = <String>[];
    await tester.pumpWidget(
      _app(
        GlassSegmentedControl<String>(
          segments: _segments,
          groupValue: 'a',
          onChanged: values.add,
          style: GlassSegmentedStyle(builder: probe.build),
        ),
      ),
    );
    final gesture = await tester.startGesture(_at(tester, 'One'));
    await tester.pump(_frame);
    final built = probe.builds;
    for (var i = 0; i < 25; i++) {
      await gesture.moveBy(const Offset(8, 0));
      await tester.pump(_frame);
    }
    expect(probe.lens.lift, greaterThan(0.9));
    expect(probe.lens.rect!.center.dx, greaterThan(150));
    expect(probe.builds - built, lessThanOrEqualTo(2));
    await gesture.up();
    await _settle(tester);
    expect(values, ['c']);
    expect(probe.lens.lift, 0);
  });

  testWidgets('a release more than 70 points away selects nothing', (
    tester,
  ) async {
    final values = <String>[];
    await tester.pumpWidget(_app(_Controlled(onChanged: values.add)));
    final gesture = await tester.startGesture(_at(tester, 'Two'));
    await tester.pump(_frame);
    await gesture.moveTo(_at(tester, 'Two') + const Offset(0, 90));
    await tester.pump(_frame);
    await gesture.up();
    await _settle(tester);
    expect(values, isEmpty);

    final near = await tester.startGesture(_at(tester, 'Two'));
    await tester.pump(_frame);
    await near.moveTo(_at(tester, 'Two') + const Offset(0, 60));
    await tester.pump(_frame);
    await near.up();
    await _settle(tester);
    expect(values, ['b']);
  });

  testWidgets('with nothing selected there is no lens; a tap selects and the '
      'lens appears at rest', (tester) async {
    final probe = _Probe();
    final values = <String>[];
    Widget control(String? value) => _app(
      GlassSegmentedControl<String>(
        segments: _segments,
        groupValue: value,
        onChanged: values.add,
        style: GlassSegmentedStyle(builder: probe.build),
      ),
    );
    await tester.pumpWidget(control(null));
    expect(probe.details!.selectedIndex, isNull);
    await tester.tapAt(_at(tester, 'Two'));
    await tester.pump();
    expect(values, ['b']);
    await tester.pumpWidget(control('b'));
    await tester.pump(_frame);
    expect(probe.details!.selectedIndex, 1);
    expect(probe.lens.rect!.center.dx, closeTo(150, 1));
    expect(probe.lens.lift, 0);
  });

  testWidgets('a tap on the selected segment reselects it', (tester) async {
    final reselected = <String>[];
    final changed = <String>[];
    await tester.pumpWidget(
      _app(_Controlled(onChanged: changed.add, onReselected: reselected.add)),
    );
    await tester.tapAt(_at(tester, 'One'));
    await _settle(tester);
    expect(reselected, ['a']);
    expect(changed, isEmpty);
  });

  testWidgets('a disabled segment takes no tap; the arrow keys skip it and '
      'select the segment they reach, which Enter and Space select again', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final values = <String>[];
    var value = 'a';
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _keys(
          GlassSegmentedControl<String>(
            segments: const [
              GlassSegment(value: 'a', label: Text('One')),
              GlassSegment(value: 'b', label: Text('Two'), enabled: false),
              GlassSegment(value: 'c', label: Text('Three')),
            ],
            groupValue: value,
            focusNode: focus,
            onChanged: (next) {
              values.add(next);
              setState(() => value = next);
            },
          ),
        ),
      ),
    );
    await tester.tapAt(_at(tester, 'Two'));
    await _settle(tester);
    expect(values, isEmpty);
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(values, ['c']);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(values, ['c']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await _settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await _settle(tester);
    expect(values, ['c', 'a']);
  });

  testWidgets('Home and End select the ends; a key the app binds to '
      'ActivateIntent selects the focused segment again', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final values = <String>[];
    var value = 'b';
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _keys(
          Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.keyS): ActivateIntent(),
            },
            child: GlassSegmentedControl<String>(
              segments: _segments,
              groupValue: value,
              focusNode: focus,
              onChanged: (next) {
                values.add(next);
                setState(() => value = next);
              },
              onReselected: (again) => values.add('again $again'),
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await _settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await _settle(tester);
    expect(values, ['c', 'again c']);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await _settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await _settle(tester);
    expect(values, ['c', 'again c', 'a', 'again a']);
  });

  testWidgets('a finger that slides takes the touch from the item it went '
      'down on and rebuilds no item while it carries the lens', (
    tester,
  ) async {
    var builds = 0;
    final states = <int, Set<WidgetState>>{};
    final changed = <int>[];
    await tester.pumpWidget(
      _app(
        RawGlassSelector(
          itemCount: 3,
          selectedIndex: 0,
          onChanged: changed.add,
          itemBuilder: (context, index, itemStates) {
            builds++;
            if (!itemStates.contains(WidgetState.selected)) {
              states[index] = itemStates;
            }
            return Text('$index');
          },
          builder: (context, details) => details.items(),
        ),
      ),
    );
    final gesture = await tester.startGesture(_at(tester, '0'));
    await tester.pump();
    expect(states[0], {WidgetState.pressed});
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(3, 0));
      await tester.pump(_frame);
    }
    expect(states[0], isEmpty);
    builds = 0;
    for (var i = 0; i < 60; i++) {
      await gesture.moveBy(const Offset(3, 0));
      await tester.pump(_frame);
    }
    expect(builds, 0);
    await gesture.up();
    await _settle(tester);
    expect(changed, [2]);
  });

  testWidgets("a tap in a segment's 44 point extension selects it; one "
      'beyond does not', (tester) async {
    final values = <String>[];
    await tester.pumpWidget(
      _app(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: _Controlled(onChanged: values.add),
        ),
      ),
    );
    final box = tester.getRect(find.byType(GlassSegmentedControl<String>));
    expect(box.height, 32);
    await tester.tapAt(Offset(_at(tester, 'Two').dx, box.bottom + 5));
    await _settle(tester);
    expect(values, ['b']);
    await tester.tapAt(Offset(_at(tester, 'Three').dx, box.top - 5));
    await _settle(tester);
    expect(values, ['b', 'c']);
    await tester.tapAt(Offset(_at(tester, 'One').dx, box.bottom + 7));
    await _settle(tester);
    expect(values, ['b', 'c']);
  });

  testWidgets('right to left, the first segment sits at the right', (
    tester,
  ) async {
    final values = <String>[];
    await tester.pumpWidget(
      _app(_Controlled(onChanged: values.add), direction: TextDirection.rtl),
    );
    expect(_at(tester, 'One').dx, greaterThan(_at(tester, 'Three').dx));
    await tester.tapAt(_at(tester, 'Three'));
    await _settle(tester);
    expect(values, ['c']);
  });

  testWidgets('segments read as a group of buttons, one selected', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final values = <String>[];
    await tester.pumpWidget(_app(_Controlled(onChanged: values.add)));
    expect(
      find.semantics.byLabel('One').evaluate().single,
      matchesSemantics(
        label: 'One',
        isButton: true,
        isInMutuallyExclusiveGroup: true,
        hasSelectedState: true,
        isSelected: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
        textDirection: TextDirection.ltr,
        rect: const Rect.fromLTRB(0, 0, 100, 44),
      ),
    );
    // The zones take their box sizes in the frame after they appear.
    await tester.pump();
    expect(
      tester
          .getRect(find.bySemanticsLabel('One'))
          .shift(
            -tester.getTopLeft(find.byType(GlassSegmentedControl<String>)),
          ),
      const Rect.fromLTRB(0, -6, 100, 38),
    );
    expect(
      find.semantics.byLabel('Two').evaluate().single,
      matchesSemantics(
        label: 'Two',
        isButton: true,
        isInMutuallyExclusiveGroup: true,
        hasSelectedState: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
        textDirection: TextDirection.ltr,
        rect: const Rect.fromLTRB(0, 0, 100, 44),
      ),
    );
    expect(
      tester
          .getRect(find.bySemanticsLabel('Two'))
          .shift(
            -tester.getTopLeft(find.byType(GlassSegmentedControl<String>)),
          ),
      const Rect.fromLTRB(100, -6, 200, 38),
    );
    tester.semantics.tap(find.semantics.byLabel('Two'));
    await _settle(tester);
    expect(values, ['b']);
    semantics.dispose();
  });

  testWidgets('a pressed segment that is not selected dims its label', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Controlled(onChanged: (_) {})));
    double opacityOf(String label) {
      RenderObject? node = tester.renderObject(find.text(label));
      while (node != null && node.debugLayer is! OffsetLayer) {
        node = node.parent;
      }
      final layer = node?.debugLayer;
      return layer is OpacityLayer ? layer.alpha! / 255 : 1;
    }

    final gesture = await tester.startGesture(_at(tester, 'Three'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(_frame);
    }
    final row = tester.layers.whereType<OpacityLayer>().map(
      (layer) => layer.alpha! / 255,
    );
    expect(row, contains(closeTo(0.2, 0.01)));
    expect(opacityOf('One'), 1);
    await gesture.up();
    await _settle(tester);
    expect(
      tester.layers.whereType<OpacityLayer>().where(
        (layer) => layer.alpha! < 255,
      ),
      isEmpty,
    );
  });

  testWidgets('disabled it is dim; the theme styles the track and the '
      'lens', (tester) async {
    await tester.pumpWidget(
      _app(
        const GlassSegmentedControl<String>(
          segments: _segments,
          groupValue: 'a',
          onChanged: null,
        ),
        theme: GlassThemeData(
          styles: [
            GlassSegmentedControl.styleFrom(
              backgroundColor: const Color(0xFF123456),
              thumbColor: const Color(0xFF654321),
            ),
          ],
        ),
      ),
    );
    expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 0.5);
    final surfaces = tester.widgetList<GlassSurface>(
      find.byType(GlassSurface),
    );
    expect(surfaces.first.glass.tint, isSameColorAs(const Color(0xFF123456)));
    expect(surfaces.last.glass.tint, isSameColorAs(const Color(0xFF654321)));
  });

  testWidgets('sized by content, a longer label gets a wider segment; '
      'without a bound the control takes its natural width', (tester) async {
    const segments = [
      GlassSegment(value: 'a', label: Text('A')),
      GlassSegment(value: 'b', label: Text('A much longer label')),
    ];
    final probe = _Probe();
    await tester.pumpWidget(
      _app(
        GlassSegmentedControl<String>(
          segments: segments,
          groupValue: 'a',
          onChanged: (_) {},
          proportionalWidth: true,
          style: GlassSegmentedStyle(builder: probe.build),
        ),
      ),
    );
    expect(probe.lens.rect!.width, lessThan(120));
    await tester.pumpWidget(
      _app(
        UnconstrainedBox(
          child: GlassSegmentedControl<String>(
            segments: segments,
            groupValue: 'a',
            onChanged: (_) {},
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byType(RawGlassSelector));
    expect(size.height, 32);
    expect(size.width, lessThan(300));
    expect(size.width, greaterThan(100));
  });

  testWidgets('a control whose value does not follow returns to it', (
    tester,
  ) async {
    final probe = _Probe();
    await tester.pumpWidget(
      _app(
        GlassSegmentedControl<String>(
          segments: _segments,
          groupValue: 'a',
          onChanged: (_) {},
          style: GlassSegmentedStyle(builder: probe.build),
        ),
      ),
    );
    final start = probe.lens.rect!.center.dx;
    await tester.tapAt(_at(tester, 'Three'));
    await _settle(tester);
    await _settle(tester);
    expect(probe.lens.rect!.center.dx, closeTo(start, 1));
  });

  testWidgets('a change raised while the framework builds does not throw '
      'and reaches the app in the next frame', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final values = <String>[];
    var value = 'a';
    var follow = false;
    var raise = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _keys(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatefulBuilder(
                builder: (context, setRaiser) {
                  rebuild = setRaiser;
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      if (raise) {
                        raise = false;
                        Actions.invoke(
                          FocusManager.instance.primaryFocus!.context!,
                          const ActivateIntent(),
                        );
                      }
                      return const SizedBox();
                    },
                  );
                },
              ),
              GlassSegmentedControl<String>(
                segments: _segments,
                groupValue: value,
                focusNode: focus,
                onChanged: (next) {
                  values.add(next);
                  if (follow) setState(() => value = next);
                },
              ),
            ],
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(values, ['b']);
    expect(value, 'a');
    follow = true;
    rebuild(() => raise = true);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(values, ['b']);
    await tester.pump(_frame);
    expect(values, ['b', 'b']);
    expect(value, 'b');
  });

  testWidgets('on liquid glass the lens gets a glass layer only while '
      'lifted', (tester) async {
    await tester.pumpWidget(
      _app(
        _Controlled(onChanged: (_) {}),
        renderer: const LiquidGlassRenderer(),
      ),
    );
    expect(findShown(LiquidGlassLayer), findsNothing);
    final gesture = await tester.startGesture(_at(tester, 'One'));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(6, 0));
      await tester.pump(_frame);
    }
    expect(findShown(LiquidGlassLayer), findsOneWidget);
    await gesture.up();
    await _settle(tester);
    expect(findShown(LiquidGlassLayer), findsNothing);
  });

  testWidgets('the item states reach a raw selector, once for the row '
      'under the lens and once for the selected copy inside it', (
    tester,
  ) async {
    final seen = <(int, bool), Set<WidgetState>>{};
    await tester.pumpWidget(
      _app(
        RawGlassSelector(
          itemCount: 2,
          selectedIndex: 0,
          onChanged: (_) {},
          disabledItems: const {1},
          itemBuilder: (context, index, states) {
            seen[(index, states.contains(WidgetState.selected))] = states;
            return Text('$index');
          },
          builder: (context, details) => details.items(),
        ),
      ),
    );
    expect(seen[(0, false)], isEmpty);
    expect(seen[(0, true)], {WidgetState.selected});
    expect(seen[(1, false)], {WidgetState.disabled});
    expect(seen[(1, true)], {WidgetState.selected, WidgetState.disabled});
    final gesture = await tester.startGesture(_at(tester, '0'));
    await tester.pump();
    expect(seen[(0, false)], {WidgetState.pressed});
    expect(seen[(0, true)], {WidgetState.selected, WidgetState.pressed});
    await gesture.up();
    await _settle(tester);
    expect(seen[(0, false)], isEmpty);
  });

  testWidgets('the lens draws over the regular items and under the selected '
      'copy it masks', (tester) async {
    const lens = Color(0xFF00FF00);
    await tester.pumpWidget(
      _app(
        RawGlassSelector(
          itemCount: 2,
          selectedIndex: 0,
          onChanged: (_) {},
          itemBuilder: (context, index, states) => Text('$index'),
          builder: (context, details) =>
              details.items(lens: const ColoredBox(color: lens)),
        ),
      ),
    );
    expect(
      find.byType(RawGlassSelector),
      paints
        ..paragraph()
        ..paragraph()
        ..rect(color: lens)
        ..clipRSuperellipse()
        ..paragraph(),
    );
  });

  testWidgets('a lifted lens draws under the selected copies it masks', (
    tester,
  ) async {
    const lens = Color(0xFF00FF00);
    await tester.pumpWidget(
      _app(
        RawGlassSelector(
          itemCount: 2,
          selectedIndex: 0,
          onChanged: (_) {},
          itemBuilder: (context, index, states) => Text('$index'),
          builder: (context, details) =>
              details.items(lens: const ColoredBox(color: lens)),
        ),
      ),
    );
    final gesture = await tester.startGesture(_at(tester, '0'));
    for (var i = 0; i < 30; i++) {
      await gesture.moveBy(const Offset(1, 0));
      await tester.pump(_frame);
    }
    expect(
      find.byType(RawGlassSelector),
      paints
        ..paragraph()
        ..paragraph()
        ..rect(color: lens)
        ..clipRSuperellipse()
        ..paragraph(),
    );
    await gesture.up();
    await _settle(tester);
  });

  testWidgets('the selected copies paint through the content of the lens '
      'renderer, resting and lifted', (tester) async {
    late GlassSelectorDetails details;
    final shown = _RecordingContent();
    await tester.pumpWidget(
      _app(
        RawGlassSelector(
          itemCount: 3,
          selectedIndex: 1,
          onChanged: (_) {},
          itemBuilder: (context, index, states) => Text('Item $index'),
          builder: (context, d) {
            details = d;
            return d.items(lens: _ShowingLens(d.lensContent!, shown));
          },
        ),
      ),
    );
    final selector = find.byType(RawGlassSelector);
    tester.renderObject(selector).markNeedsPaint();
    await tester.pump(_frame);
    expect(shown.frames.last.lift, 0);
    expect(selector, paints..paragraph());

    final gesture = await tester.startGesture(_at(tester, 'Item 1'));
    for (var i = 0; i < 30; i++) {
      await gesture.moveBy(const Offset(1, 0));
      await tester.pump(_frame);
    }
    final frame = details.lens.value;
    expect(frame.lift, greaterThan(GlassFrame.restingLift));
    expect(shown.frames.last, frame);
    expect(shown.sizes.last, tester.getSize(selector));
    // The renderer's content painted the copies it was handed.
    expect(shown.painted, shown.frames.length);
    await gesture.up();
    await _settle(tester);
  });

  test('a style lerps its colors and merges state by state', () {
    final a = GlassSegmentedControl.styleFrom(
      backgroundColor: const Color(0xFF000000),
    );
    final b = GlassSegmentedControl.styleFrom(
      backgroundColor: const Color(0xFFFFFFFF),
      thumbColor: const Color(0xFF00FF00),
    );
    final half = a.lerp(b, 0.5);
    expect(
      half.backgroundColor!.resolve({}),
      isSameColorAs(const Color(0xFF808080)),
    );
    final merged = a.merge(b);
    expect(merged.backgroundColor!.resolve({}), const Color(0xFF000000));
    expect(merged.thumbColor!.resolve({}), const Color(0xFF00FF00));
    expect(listEquals([a], [a]), isTrue);
  });
}

class _ShowingLens extends StatelessWidget {
  const _ShowingLens(this.report, this.content);

  final ValueNotifier<GlassLensContent?> report;
  final GlassLensContent content;

  @override
  Widget build(BuildContext context) {
    report.value = content;
    return const SizedBox.expand();
  }
}

class _RecordingContent implements GlassLensContent {
  final frames = <GlassFrame>[];
  final sizes = <Size>[];
  int painted = 0;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required GlassFrame frame,
    required Size size,
    required PaintingContextCallback content,
  }) {
    frames.add(frame);
    sizes.add(size);
    content(context, offset);
    painted++;
  }
}
