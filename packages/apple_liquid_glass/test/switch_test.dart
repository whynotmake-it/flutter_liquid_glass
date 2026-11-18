import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/surfaces/flat.dart';
import 'package:flutter/foundation.dart';
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
  bool disableAnimations = false,
}) => MediaQuery(
  data: MediaQueryData(disableAnimations: disableAnimations),
  child: Directionality(
    textDirection: direction,
    child: GlassScope(
      renderer: renderer,
      data: theme,
      child: Center(child: child),
    ),
  ),
);

class _Controlled extends StatefulWidget {
  const _Controlled({this.onChanged});

  final ValueChanged<bool>? onChanged;

  @override
  State<_Controlled> createState() => _ControlledState();
}

class _ControlledState extends State<_Controlled> {
  bool value = false;

  @override
  Widget build(BuildContext context) => GlassSwitch(
    value: value,
    onChanged: (next) {
      widget.onChanged?.call(next);
      setState(() => value = next);
    },
  );
}

class _Probe {
  int builds = 0;
  ValueListenable<GlassFrame>? thumb;
  ValueListenable<double>? progress;
  Set<WidgetState> states = {};

  Widget build(BuildContext context, GlassSwitchDetails details) {
    builds++;
    thumb = details.thumb;
    progress = details.progress;
    states = details.states;
    return const SizedBox.expand();
  }
}

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

Widget _keyApp(Widget child, {Map<ShortcutActivator, Intent>? shortcuts}) =>
    WidgetsApp(
      color: const Color(0xFF000000),
      shortcuts: shortcuts,
      builder: (context, _) => Center(child: child),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(_frame);
  }
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a tap toggles on release, and the track turns on', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(_app(_Controlled(onChanged: changes.add)));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GlassSwitch)),
    );
    await tester.pump(_frame);
    expect(changes, isEmpty);
    await gesture.up();
    await tester.pump(_frame);
    expect(changes, [true]);
    await _settle(tester);
    final track = tester
        .widgetList<GlassSurface>(find.byType(GlassSurface))
        .first
        .frame!
        .value
        .tint!;
    expect(track, isSameColorAs(const Color(0xFF34C759)));
  });

  testWidgets('a switch whose value does not follow returns to it', (
    tester,
  ) async {
    final probe = _Probe();
    var value = false;
    await tester.pumpWidget(
      _app(
        RawGlassSwitch(
          value: value,
          onChanged: (next) => value = next,
          builder: probe.build,
        ),
      ),
    );
    await tester.tap(find.byType(RawGlassSwitch));
    await _settle(tester);
    expect(value, isTrue);
    expect(probe.progress!.value, 0);
    expect(probe.thumb!.value.rect!.center.dx, lessThan(31.5));
  });

  testWidgets('a drag toward on flips it and the release keeps it', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(_app(_Controlled(onChanged: changes.add)));
    final start =
        tester.getTopLeft(find.byType(GlassSwitch)) + const Offset(20, 14);
    final gesture = await tester.startGesture(start);
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(start + Offset(4.0 * i, 0));
      await tester.pump(_frame);
    }
    await gesture.up();
    await tester.pump(_frame);
    expect(changes, [true]);
    await _settle(tester);
  });

  testWidgets('without onChanged it is disabled, dim and ignores touches', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const GlassSwitch(value: false, onChanged: null)),
    );
    await tester.tap(find.byType(GlassSwitch));
    await _settle(tester);
    expect(
      tester.widget<Opacity>(find.byType(Opacity)).opacity,
      0.5,
    );
  });

  testWidgets('keys and the accessibility tap toggle; it reads as a '
      'toggle', (tester) async {
    final semantics = tester.ensureSemantics();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final changes = <bool>[];
    await tester.pumpWidget(
      _app(
        Shortcuts(
          shortcuts: WidgetsApp.defaultShortcuts,
          child: GlassSwitch(
            value: false,
            onChanged: changes.add,
            focusNode: focus,
            semanticLabel: 'Wi-Fi',
          ),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Wi-Fi')),
      matchesSemantics(
        label: 'Wi-Fi',
        hasToggledState: true,
        hasTapAction: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    tester.semantics.tap(find.semantics.byLabel('Wi-Fi'));
    expect(changes, [true, true]);
    semantics.dispose();
  });

  testWidgets('the builder runs on state edges only while the knob lifts '
      'and travels', (tester) async {
    final probe = _Probe();
    var value = false;
    late StateSetter set;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return RawGlassSwitch(
              value: value,
              onChanged: (next) => set(() => value = next),
              builder: probe.build,
            );
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(RawGlassSwitch)),
    );
    final lifts = <double>[];
    for (var i = 0; i < 10; i++) {
      await tester.pump(_frame);
      lifts.add(probe.thumb!.value.lift);
    }
    final pressed = probe.builds;
    expect(lifts.last, greaterThan(0.9));
    await gesture.up();
    final xs = <double>[];
    for (var i = 0; i < 40; i++) {
      await tester.pump(_frame);
      xs.add(probe.thumb!.value.rect!.center.dx);
    }
    expect(xs.last, greaterThan(xs.first));
    expect(probe.states, contains(WidgetState.selected));
    expect(probe.builds - pressed, lessThanOrEqualTo(2));
    await _settle(tester);
  });

  testWidgets('right to left, on is to the left', (tester) async {
    final probe = _Probe();
    await tester.pumpWidget(
      _app(
        RawGlassSwitch(value: true, onChanged: (_) {}, builder: probe.build),
        direction: TextDirection.rtl,
      ),
    );
    await tester.pump(_frame);
    expect(probe.thumb!.value.rect!.center.dx, lessThan(31.5));
  });

  testWidgets('on liquid glass the knob gets a glass layer only while '
      'lifted', (tester) async {
    await tester.pumpWidget(
      _app(const _Controlled(), renderer: const LiquidGlassRenderer()),
    );
    expect(findShown(LiquidGlassLayer), findsNothing);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GlassSwitch)),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(_frame);
    }
    expect(findShown(LiquidGlassLayer), findsOneWidget);
    await gesture.up();
    await _settle(tester);
    expect(findShown(LiquidGlassLayer), findsNothing);
  });

  testWidgets('the theme styles the track; Reduce Motion keeps the knob '
      'down', (tester) async {
    final probe = _Probe();
    await tester.pumpWidget(
      _app(
        RawGlassSwitch(value: false, onChanged: (_) {}, builder: probe.build),
        disableAnimations: true,
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(RawGlassSwitch)),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(_frame);
    }
    expect(probe.thumb!.value.lift, 0);
    await gesture.up();
    await _settle(tester);

    await tester.pumpWidget(
      _app(
        const GlassSwitch(value: true, onChanged: null),
        theme: GlassThemeData(
          styles: [
            GlassSwitch.styleFrom(
              activeTrackColor: const Color(0xFF123456),
            ),
          ],
        ),
      ),
    );
    await _settle(tester);
    final track = tester
        .widgetList<GlassSurface>(find.byType(GlassSurface))
        .first
        .frame!
        .value
        .tint!;
    expect(track, isSameColorAs(const Color(0xFF123456)));
  });

  testWidgets('disabling a switch under a finger ends the press quietly', (
    tester,
  ) async {
    Widget sw(ValueChanged<bool>? onChanged) =>
        _app(GlassSwitch(value: false, onChanged: onChanged));
    await tester.pumpWidget(sw((_) {}));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GlassSwitch)),
    );
    await tester.pump(_frame);
    await tester.pumpWidget(sw(null));
    expect(tester.takeException(), isNull);
    await gesture.up();
    await _settle(tester);
  });

  testWidgets('on liquid glass the lifted knob covers its platter instead '
      'of fading it', (tester) async {
    await tester.pumpWidget(
      _app(const _Controlled(), renderer: const LiquidGlassRenderer()),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GlassSwitch)),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(_frame);
    }
    final flat = find.byElementPredicate(
      (element) =>
          element is RenderObjectElement &&
          element.renderObject is RenderFlatGlass,
    );
    expect(flat, findsNWidgets(2));
    expect(
      find.descendant(of: find.byType(LiquidGlass), matching: flat),
      findsNothing,
    );
    await gesture.up();
    await _settle(tester);
  });

  testWidgets('a held knob on fake glass does not rebuild its layer every '
      'frame', (tester) async {
    await tester.pumpWidget(
      _app(const _Controlled(), renderer: const FakeGlassRenderer()),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GlassSwitch)),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(_frame);
    }
    var layerBuilds = 0;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (element.widget is LiquidGlassLayer) layerBuilds++;
    };
    for (var i = 0; i < 30; i++) {
      await tester.pump(_frame);
    }
    debugOnRebuildDirtyWidget = null;
    expect(layerBuilds, 0);
    await gesture.up();
    await _settle(tester);
  });

  testWidgets('a switch in a larger box keeps its size and its knob', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const SizedBox(
          width: 120,
          height: 50,
          child: GlassSwitch(value: false, onChanged: null),
        ),
      ),
    );
    expect(tester.getSize(find.byType(RawGlassSwitch)), const Size(120, 50));
    final knob = find.byType(GlassSurface).last;
    expect(tester.getSize(knob), RawGlassSwitch.size);
    expect(
      tester.getCenter(knob),
      tester.getCenter(find.byType(RawGlassSwitch)),
    );
  });

  testWidgets('the track takes the switch style, then the theme style, then '
      'its default', (tester) async {
    Color track() => tester
        .widgetList<GlassSurface>(find.byType(GlassSurface))
        .first
        .frame!
        .value
        .tint!;
    final themed = GlassThemeData(
      styles: [
        GlassSwitch.styleFrom(activeTrackColor: const Color(0xFF123456)),
      ],
    );
    await tester.pumpWidget(
      _app(const GlassSwitch(value: true, onChanged: null)),
    );
    await _settle(tester);
    expect(
      track(),
      isSameColorAs(GlassColors.systemGreen.resolvedWith(const GlassTraits())),
    );

    await tester.pumpWidget(
      _app(const GlassSwitch(value: true, onChanged: null), theme: themed),
    );
    await _settle(tester);
    expect(track(), isSameColorAs(const Color(0xFF123456)));

    await tester.pumpWidget(
      _app(
        GlassSwitch(
          value: true,
          onChanged: null,
          style: GlassSwitch.styleFrom(
            activeTrackColor: const Color(0xFF654321),
          ),
        ),
        theme: themed,
      ),
    );
    await _settle(tester);
    expect(track(), isSameColorAs(const Color(0xFF654321)));
  });

  testWidgets('under a WidgetsApp Space and Enter toggle it, and an app '
      'that rebinds the keys toggles it with its own', (tester) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      _keyApp(
        GlassSwitch(value: false, onChanged: changes.add, autofocus: true),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(changes, [true, true]);

    changes.clear();
    await tester.pumpWidget(
      _keyApp(
        GlassSwitch(value: false, onChanged: changes.add, autofocus: true),
        shortcuts: {
          ...WidgetsApp.defaultShortcuts,
          const SingleActivator(LogicalKeyboardKey.space):
              const DoNothingAndStopPropagationIntent(),
          const SingleActivator(LogicalKeyboardKey.keyT):
              const ActivateIntent(),
        },
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(changes, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    expect(changes, [true]);
  });

  testWidgets('it reads as one toggle over its 44 point target, below the '
      'region', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        GlassSwitch(value: true, onChanged: (_) {}, semanticLabel: 'Wi-Fi'),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Wi-Fi')),
      matchesSemantics(
        label: 'Wi-Fi',
        rect: const Rect.fromLTWH(0, -8, 63, 44),
        textDirection: TextDirection.ltr,
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
      ),
    );
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('a tap in the 44 point extension toggles it; one beyond does '
      'not', (tester) async {
    final changes = <bool>[];
    await tester.pumpWidget(_app(_Controlled(onChanged: changes.add)));
    final center = tester.getCenter(find.byType(GlassSwitch));
    expect(tester.getSize(find.byType(GlassSwitch)), RawGlassSwitch.size);
    await tester.tapAt(center + const Offset(0, -21));
    await _settle(tester);
    expect(changes, [true]);
    await tester.tapAt(center + const Offset(0, 23));
    await _settle(tester);
    expect(changes, [true]);
  });

  testWidgets('a touch that toggles plays a light impact; a key, the '
      'accessibility tap and a haptic scope play none', (tester) async {
    final semantics = tester.ensureSemantics();
    final played = _haptics(tester);
    Widget sw({bool haptics = true}) => _keyApp(
      MotionHapticScope(
        enabled: haptics,
        child: GlassSwitch(
          value: false,
          onChanged: (_) {},
          autofocus: true,
          semanticLabel: 'Wi-Fi',
        ),
      ),
    );
    await tester.pumpWidget(sw());
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    tester.semantics.tap(find.semantics.byLabel('Wi-Fi'));
    await _settle(tester);
    expect(played, isEmpty);
    await tester.tap(find.byType(GlassSwitch));
    await _settle(tester);
    expect(played, ['HapticFeedbackType.lightImpact']);
    await tester.pumpWidget(sw(haptics: false));
    await tester.tap(find.byType(GlassSwitch));
    await _settle(tester);
    expect(played, ['HapticFeedbackType.lightImpact']);
    semantics.dispose();
  });

  testWidgets('Reduce Motion from MotionTraitsOverride keeps the knob '
      'down', (tester) async {
    final probe = _Probe();
    await tester.pumpWidget(
      _app(
        MotionTraitsOverride(
          traits: const MotionTraits(reduceMotion: true),
          child: RawGlassSwitch(
            value: false,
            onChanged: (_) {},
            builder: probe.build,
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(RawGlassSwitch)),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(_frame);
    }
    expect(probe.thumb!.value.lift, 0);
    await gesture.up();
    await _settle(tester);
  });

  testWidgets('an app that passes the value back late sees the switch '
      'return, then follow', (tester) async {
    final probe = _Probe();
    var value = false;
    late StateSetter set;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return RawGlassSwitch(
              value: value,
              onChanged: (_) {},
              builder: probe.build,
            );
          },
        ),
      ),
    );
    await tester.tap(find.byType(RawGlassSwitch));
    await _settle(tester);
    expect(probe.progress!.value, 0);
    set(() => value = true);
    await _settle(tester);
    expect(probe.progress!.value, 1);
    expect(probe.thumb!.value.rect!.center.dx, greaterThan(31.5));
  });

  testWidgets('a change raised while the framework builds does not throw '
      'and reaches the app in the next frame', (tester) async {
    final probe = _Probe();
    var value = false;
    var raise = false;
    late StateSetter rebuild;
    late SwitchMotion motion;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return LayoutBuilder(
              builder: (context, constraints) {
                if (raise) {
                  raise = false;
                  motion.pointerUp(motion.clock.now, 10);
                }
                return RawGlassSwitch(
                  value: value,
                  onChanged: (next) => setState(() => value = next),
                  builder: probe.build,
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
                    of: find.byType(RawGlassSwitch),
                    matching: find.byType(MotionScope),
                  ),
                )
                .motion
            as SwitchMotion;
    motion.pointerDown(motion.clock.now, 10);
    rebuild(() => raise = true);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(value, isFalse);
    await tester.pump(_frame);
    expect(value, isTrue);
    await _settle(tester);
    expect(probe.progress!.value, 1);
  });

  testWidgets('the track tint selection survives a rebuild of the body', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _Controlled()));
    Object? track() =>
        tester.widgetList<GlassSurface>(find.byType(GlassSurface)).first.frame;
    final before = track();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GlassSwitch)),
    );
    await tester.pump(_frame);
    await gesture.up();
    await tester.pump(_frame);
    await _settle(tester);
    expect(track(), same(before));
  });
}
