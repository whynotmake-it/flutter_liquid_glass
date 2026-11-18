import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: direction,
        child: Center(child: child),
      ),
    );

class _Pages extends StatefulWidget {
  const _Pages({this.picks, this.accept = true});

  final List<int>? picks;
  final bool accept;

  @override
  State<_Pages> createState() => _PagesState();
}

class _PagesState extends State<_Pages> {
  int page = 2;

  @override
  Widget build(BuildContext context) => GlassPageControl(
    count: 5,
    page: page,
    semanticLabel: 'Pages',
    onChanged: (next) {
      widget.picks?.add(next);
      if (widget.accept) setState(() => page = next);
    },
  );
}

Widget _keyApp(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    WidgetsApp(
      color: const Color(0xFF000000),
      builder: (context, _) => Directionality(
        textDirection: direction,
        child: Center(child: child),
      ),
    );

List<Object?> _haptics(WidgetTester tester) {
  final played = <Object?>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') played.add(call.arguments);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return played;
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a tap on either half steps toward it on the lift', (
    tester,
  ) async {
    final picks = <int>[];
    await tester.pumpWidget(_app(_Pages(picks: picks)));
    final box = tester.getRect(find.byType(GlassPageControl));
    await tester.tapAt(box.centerRight - const Offset(6, 0));
    await tester.pump();
    await tester.tapAt(box.centerLeft + const Offset(6, 0));
    await tester.pump();
    await tester.tapAt(box.centerLeft + const Offset(6, 0));
    await tester.pump();
    expect(picks, [3, 2, 1]);
  });

  testWidgets('a scrub follows the nearest dot and plays a selection haptic '
      'per page', (tester) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final picks = <int>[];
    await tester.pumpWidget(_app(_Pages(picks: picks)));
    final box = tester.getRect(find.byType(GlassPageControl));
    final gesture = await tester.startGesture(box.center);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(5, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    expect(picks, [3, 4]);
    expect(haptics, hasLength(2));
  });

  testWidgets('keys and accessibility step; it reads as an adjustable value', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final picks = <int>[];
    await tester.pumpWidget(
      _app(
        GlassPageControl(
          count: 5,
          page: 2,
          onChanged: picks.add,
          focusNode: focus,
          semanticLabel: 'Pages',
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Pages')),
      matchesSemantics(
        label: 'Pages',
        value: 'page 3 of 5',
        increasedValue: 'page 4 of 5',
        decreasedValue: 'page 2 of 5',
        hasIncreaseAction: true,
        hasDecreaseAction: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    tester.semantics.increase(find.semantics.byLabel('Pages'));
    expect(picks, [3, 1, 3]);
    semantics.dispose();
  });

  testWidgets('right to left the pages run from the right', (tester) async {
    final picks = <int>[];
    await tester.pumpWidget(
      _app(_Pages(picks: picks), direction: TextDirection.rtl),
    );
    final box = tester.getRect(find.byType(GlassPageControl));
    await tester.tapAt(box.centerLeft + const Offset(6, 0));
    await tester.pump();
    expect(picks, [3]);
  });

  testWidgets('a control whose page does not follow returns to it; disabled '
      'it ignores taps', (tester) async {
    final picks = <int>[];
    await tester.pumpWidget(_app(_Pages(picks: picks, accept: false)));
    final box = tester.getRect(find.byType(GlassPageControl));
    await tester.tapAt(box.centerRight - const Offset(6, 0));
    await tester.pump();
    await tester.pump();
    await tester.tapAt(box.centerRight - const Offset(6, 0));
    await tester.pump();
    expect(picks, [3, 3]);

    await tester.pumpWidget(
      _app(const GlassPageControl(count: 5, page: 2, onChanged: null)),
    );
    await tester.tapAt(box.centerRight - const Offset(6, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a progress capsule widens the control by its extra width', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const GlassPageControl(count: 5, page: 0, onChanged: null)),
    );
    final plain = tester.getSize(find.byType(GlassPageControl)).width;
    await tester.pumpWidget(
      _app(
        const GlassPageControl(
          count: 5,
          page: 0,
          progress: 0.5,
          onChanged: null,
        ),
      ),
    );
    final withProgress = tester.getSize(find.byType(GlassPageControl)).width;
    expect(withProgress - plain, closeTo(27.33 - 9.67, 1e-9));
  });

  testWidgets('a raw control builds its look from the pose, mirrored in a '
      'right-to-left context', (tester) async {
    GlassPageControlDetails? seen;
    Widget raw(TextDirection direction) => _app(
      RawGlassPageControl(
        count: 3,
        page: 0,
        onChanged: null,
        backgroundStyle: GlassPageControlBackground.prominent,
        builder: (context, details) {
          seen = details;
          return const SizedBox.expand();
        },
      ),
      direction: direction,
    );
    await tester.pumpWidget(raw(TextDirection.ltr));
    final box = tester.getSize(find.byType(RawGlassPageControl));
    final ltr = seen!.pose.value;
    expect(seen!.states, {WidgetState.disabled});
    expect(ltr.platter, 1);
    expect(ltr.indicators, hasLength(3));
    expect(ltr.indicators.first.center.dx, lessThan(box.width / 2));

    await tester.pumpWidget(raw(TextDirection.rtl));
    final rtl = seen!.pose.value;
    expect(rtl.indicators.first.center.dx, greaterThan(box.width / 2));
    expect(
      rtl.indicators.first.center.dx,
      closeTo(box.width - ltr.indicators.first.center.dx, 1e-9),
    );
  });

  testWidgets('under a WidgetsApp the value commands step it, mirrored in '
      'right to left; Page Up, Page Down, Space and Enter do nothing, and an '
      'app adds keys with Shortcuts', (tester) async {
    for (final direction in TextDirection.values) {
      final picks = <int>[];
      await tester.pumpWidget(
        _keyApp(
          Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.keyN): AdjustValueIntent(
                ValueCommand.increase,
              ),
            },
            child: GlassPageControl(
              key: ValueKey(direction),
              count: 5,
              page: 2,
              onChanged: picks.add,
              autofocus: true,
            ),
          ),
          direction: direction,
        ),
      );
      await tester.pump();
      for (final key in [
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.keyN,
      ]) {
        await tester.sendKeyEvent(key);
      }
      final right = direction == TextDirection.ltr ? 3 : 1;
      expect(picks, [right, 3, 0, 4, 3], reason: '$direction');
    }
  });

  testWidgets('it reads as one adjustable value over its 44 point target', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final picks = <int>[];
    await tester.pumpWidget(
      _app(
        GlassPageControl(
          count: 3,
          page: 2,
          onChanged: picks.add,
          semanticLabel: 'Pages',
        ),
      ),
    );
    final size = tester.getSize(find.byType(RawGlassPageControl));
    final node = tester.getSemantics(find.bySemanticsLabel('Pages'));
    expect(node.rect.size, Size(size.width, 44));
    expect(node.rect.top, closeTo((size.height - 44) / 2, 1e-9));
    expect(
      node,
      matchesSemantics(
        label: 'Pages',
        textDirection: TextDirection.ltr,
        value: 'page 3 of 3',
        increasedValue: 'page 3 of 3',
        decreasedValue: 'page 2 of 3',
        hasIncreaseAction: true,
        hasDecreaseAction: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
      ),
    );
    tester.semantics.increase(find.semantics.byLabel('Pages'));
    tester.semantics.decrease(find.semantics.byLabel('Pages'));
    expect(picks, [1]);
    semantics.dispose();
  });

  testWidgets('a tap in the 44 point extension steps; one beyond does not', (
    tester,
  ) async {
    final picks = <int>[];
    await tester.pumpWidget(_app(_Pages(picks: picks)));
    final box = tester.getRect(find.byType(GlassPageControl));
    expect(box.height, lessThan(44));
    final above = box.centerRight + Offset(-6, -box.height / 2 - 2);
    await tester.tapAt(above);
    await tester.pump();
    expect(picks, [3]);
    await tester.tapAt(box.centerRight + const Offset(-6, 23));
    await tester.pump();
    expect(picks, [3]);
  });

  testWidgets('keys and accessibility play no haptic, nor does a scrub '
      'under a haptic scope that turns them off', (tester) async {
    final semantics = tester.ensureSemantics();
    final played = _haptics(tester);
    await tester.pumpWidget(
      _keyApp(
        MotionHapticScope(
          enabled: false,
          child: GlassPageControl(
            count: 5,
            page: 2,
            onChanged: (_) {},
            autofocus: true,
            semanticLabel: 'Pages',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    tester.semantics.increase(find.semantics.byLabel('Pages'));
    final box = tester.getRect(find.byType(GlassPageControl));
    final gesture = await tester.startGesture(box.center);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(5, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    expect(played, isEmpty);
    semantics.dispose();
  });

  testWidgets('an app passes its own states controller, and the builder '
      'sees pressed', (tester) async {
    final states = WidgetStatesController();
    addTearDown(states.dispose);
    final seen = <Set<WidgetState>>[];
    await tester.pumpWidget(
      _app(
        RawGlassPageControl(
          count: 5,
          page: 2,
          onChanged: (_) {},
          statesController: states,
          builder: (context, details) {
            seen.add(details.states);
            return const SizedBox.expand();
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(RawGlassPageControl)),
    );
    await tester.pump();
    expect(states.value, contains(WidgetState.pressed));
    expect(seen.last, contains(WidgetState.pressed));
    await gesture.up();
    await tester.pump();
    expect(states.value, isNot(contains(WidgetState.pressed)));
  });

  testWidgets('an app that passes the page back late sees the control '
      'return, then follow', (tester) async {
    var page = 2;
    late StateSetter set;
    GlassPageControlPose? pose;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return RawGlassPageControl(
              count: 5,
              page: page,
              onChanged: (_) {},
              builder: (context, details) {
                return ValueListenableBuilder(
                  valueListenable: details.pose,
                  builder: (context, value, _) {
                    pose = value;
                    return const SizedBox.expand();
                  },
                );
              },
            );
          },
        ),
      ),
    );
    final box = tester.getRect(find.byType(RawGlassPageControl));
    await tester.tapAt(box.centerRight - const Offset(6, 0));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(pose!.page, 2);
    set(() => page = 3);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(pose!.page, 3);
  });

  testWidgets('a change raised while the framework builds does not throw '
      'and reaches the app in the next frame', (tester) async {
    var page = 2;
    var raise = false;
    late StateSetter rebuild;
    late PageControlMotion motion;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return LayoutBuilder(
              builder: (context, constraints) {
                if (raise) {
                  raise = false;
                  motion.pointerUp(motion.clock.now, 1000, width: 10);
                }
                return RawGlassPageControl(
                  count: 5,
                  page: page,
                  onChanged: (next) => setState(() => page = next),
                  builder: (context, details) => const SizedBox.expand(),
                );
              },
            );
          },
        ),
      ),
    );
    motion =
        tester
                .widget<MotionScope>(
                  find.descendant(
                    of: find.byType(RawGlassPageControl),
                    matching: find.byType(MotionScope),
                  ),
                )
                .motion
            as PageControlMotion;
    motion.pointerDown(motion.clock.now, 1000);
    rebuild(() => raise = true);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(page, 2);
    await tester.pump(const Duration(milliseconds: 16));
    expect(page, 3);
    expect(motion.page, 3);
  });
}
