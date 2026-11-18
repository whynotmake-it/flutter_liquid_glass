import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

import 'fixtures/toy_toolbar.dart';

Widget _app(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    WidgetsApp(
      color: const Color(0xFF000000),
      builder: (context, _) => Directionality(
        textDirection: direction,
        child: FocusScope(
          autofocus: true,
          child: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    );

/// The centre of [item] where the toy toolbar paints it now.
Offset _at(ToyMotion motion, String item) => motion.rectOf(item).center;

/// Takes value commands and activations, as a stepper's interaction does.
class _Values extends Interaction {
  final List<Object> heard = [];

  @override
  bool get adjusts => true;

  @override
  bool get activates => true;

  @override
  bool accepts(PointerDownInput down) => false;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case AdjustInput(:final command):
        heard.add(command);
      case ActivateInput():
        heard.add('activate');
      default:
        break;
    }
    return InteractionUpdate.none;
  }
}

/// Activates on a key or an assistive tap and takes no touch, as a
/// stepper half does.
class _Activated extends Interaction {
  _Activated(this.onActivate);

  final VoidCallback onActivate;

  @override
  bool get activates => true;

  @override
  bool accepts(PointerDownInput down) => false;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is ActivateInput) onActivate();
    return InteractionUpdate.none;
  }
}

class _Downs extends Interaction {
  final List<double> touchSlops = [];

  @override
  bool accepts(PointerDownInput down) => true;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is PointerDownInput) touchSlops.add(input.touchSlop);
    return InteractionUpdate.none;
  }
}

/// A card that records where its source is.
final class _Card extends Motion with Presented, Sourced {
  late final Presence _show = own(Presence(openSpring: Spring.snappy));
  final List<SourceGeometry?> sources = [];

  @override
  PresenceStatus get presence => _show.status;

  @override
  void open(double t) => _show.open(t);

  @override
  bool leave(double t, DismissTrigger trigger) {
    _show.hide(t);
    return true;
  }

  @override
  void sourceMoved(double t, SourceGeometry? geometry) => sources.add(geometry);
}

void main() {
  final haptics = <String>[];
  late ToyMotion motion;
  late InputZonesController<String> zones;
  late List<String> pressed;

  setUp(() {
    MotionClock.debugReset();
    haptics.clear();
    motion = ToyMotion();
    zones = InputZonesController<String>();
    pressed = [];
  });

  tearDown(() {
    motion.dispose();
    zones.dispose();
  });

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments as String);
          }
          return null;
        });
  });

  Widget toolbar({
    Set<String> disabled = const {},
    bool slides = false,
    Map<String, List<Interaction>> extra = const {},
    ToyCounts? counts,
    InputPort? port,
    Axis? axis = Axis.horizontal,
    InputZoneStops stops = InputZoneStops.each,
    String? current,
    bool activatesOnMove = false,
  }) => ToyToolbar(
    motion: motion,
    controller: zones,
    onPressed: pressed.add,
    disabled: disabled,
    slides: slides,
    extra: extra,
    counts: counts,
    port: port,
    axis: axis,
    stops: stops,
    current: current,
    activatesOnMove: activatesOnMove,
    feedback: (item, event) => switch (event) {
      ActivationEvent() => MotionHaptic.lightImpact,
      ScrubChangeEvent(atDown: false) => MotionHaptic.selection,
      _ => null,
    },
  );

  group('touch', () {
    testWidgets("a press on a zone is that zone's, with its states", (
      tester,
    ) async {
      await tester.pumpWidget(_app(toolbar()));
      final gesture = await tester.startGesture(_at(motion, 'b'));
      await tester.pump();
      expect(zones.states('b').value, contains(WidgetState.pressed));
      expect(zones.states('a').value, isNot(contains(WidgetState.pressed)));
      await gesture.up();
      await tester.pump();
      expect(zones.states('b').value, isNot(contains(WidgetState.pressed)));
      expect(pressed, ['b']);
      expect(haptics, ['HapticFeedbackType.lightImpact']);
    });

    testWidgets('a finger that slides moves the press when the host asks', (
      tester,
    ) async {
      await tester.pumpWidget(_app(toolbar(slides: true)));
      final gesture = await tester.startGesture(_at(motion, 'a'));
      await tester.pump();
      await gesture.moveTo(_at(motion, 'b'));
      await tester.pump();
      expect(zones.states('a').value, isNot(contains(WidgetState.pressed)));
      expect(zones.states('b').value, contains(WidgetState.pressed));
      await gesture.moveTo(_at(motion, 'c'));
      await gesture.up();
      await tester.pump();
      expect(pressed, ['c']);
      expect(haptics, [
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.lightImpact',
      ]);
    });

    testWidgets('a press that slides onto a zone keeps the touch slop of its '
        'device', (tester) async {
      final downs = _Downs();
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                gestureSettings: const DeviceGestureSettings(touchSlop: 12),
              ),
              child: toolbar(
                slides: true,
                extra: {
                  'b': [downs],
                },
              ),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(_at(motion, 'a'));
      await tester.pump();
      await gesture.moveTo(_at(motion, 'b'));
      await tester.pump();
      await gesture.up();
      expect(downs.touchSlops, [12]);
    });

    testWidgets('without sliding the press stays on its zone', (
      tester,
    ) async {
      await tester.pumpWidget(_app(toolbar()));
      final gesture = await tester.startGesture(_at(motion, 'a'));
      await tester.pump();
      await gesture.moveTo(_at(motion, 'b'));
      await tester.pump();
      expect(zones.states('a').value, isNot(contains(WidgetState.pressed)));
      expect(zones.states('b').value, isNot(contains(WidgetState.pressed)));
      await gesture.moveTo(_at(motion, 'a'));
      await gesture.up();
      await tester.pump();
      expect(pressed, ['a']);
    });

    testWidgets('a zone takes pointers in its minimum hit size', (
      tester,
    ) async {
      await tester.pumpWidget(_app(toolbar()));
      final a = motion.rectOf('a');
      // 28 high, 44 hit: 8 points above and below.
      await tester.tapAt(Offset(a.center.dx, a.bottom + 7));
      await tester.tapAt(Offset(a.right + 1.5, a.center.dy));
      await tester.tapAt(Offset(a.center.dx, a.bottom + 9));
      await tester.tapAt(Offset(a.right + 5, a.center.dy));
      expect(pressed, ['a', 'a']);
    });

    testWidgets('a zone is hit where it is painted, with no rebuild or '
        'layout as it moves', (tester) async {
      final counts = ToyCounts();
      await tester.pumpWidget(_app(toolbar(counts: counts)));
      // An anchor takes its zone's size at the start of the next frame.
      await tester.pump();
      final builds = counts.builds;
      final layouts = counts.layouts;
      final before = _at(motion, 'a');
      final marks = <String>[];
      final print = debugPrint;
      debugPrint = (message, {wrapWidth}) => marks.add(message ?? '');
      debugPrintMarkNeedsLayoutStacks = true;
      motion.slide(25);
      await tester.pump();
      motion.slide(40);
      await tester.pump();
      debugPrintMarkNeedsLayoutStacks = false;
      debugPrint = print;
      expect(marks, isEmpty);
      expect(counts.builds, builds);
      expect(counts.layouts, layouts);
      await tester.tapAt(before);
      expect(pressed, isEmpty);
      await tester.tapAt(_at(motion, 'a'));
      expect(pressed, ['a']);
    });

    testWidgets('a zone is a box of its hit size where it is painted, which '
        'tests find and tap and which takes a new size by itself', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(toolbar()));
      // An anchor takes its zone's size at the start of the next frame.
      await tester.pump();
      final item = find.bySemanticsLabel('Item b');
      Rect hit() => Rect.fromCenter(
        center: motion.rectOf('b').center,
        width: 44,
        height: 44,
      );
      expect(tester.getRect(item), hit());
      motion.slide(30);
      await tester.pump();
      expect(tester.getRect(item), hit());
      expect(
        tester
            .hitTestOnBinding(hit().center)
            .path
            .any((entry) => entry.target == tester.renderObject(item)),
        isTrue,
      );
      await tester.tap(item);
      expect(pressed, ['b']);
      motion.sizes['b'] = const Size(60, 50);
      motion.changed();
      await tester.pump();
      expect(tester.getRect(item), motion.rectOf('b'));
      await tester.pump();
      expect(tester.getSize(item), const Size(60, 50));
      expect(tester.getRect(item), motion.rectOf('b'));
      handle.dispose();
    });

    testWidgets('a finger resting on a moving zone stays inside it', (
      tester,
    ) async {
      await tester.pumpWidget(_app(toolbar()));
      final gesture = await tester.startGesture(_at(motion, 'b'));
      await tester.pump();
      motion.slide(30);
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0));
      await gesture.up();
      await tester.pump();
      expect(pressed, ['b']);
    });

    testWidgets('a disabled zone and one that takes no input take nothing', (
      tester,
    ) async {
      await tester.pumpWidget(_app(toolbar(disabled: {'b'})));
      motion.leaving.add('c');
      motion.opacity['a'] = InputZoneFrame.minimumOpacity / 2;
      motion.changed();
      await tester.pump();
      for (final item in ToyMotion.items) {
        await tester.tapAt(_at(motion, item));
      }
      expect(pressed, isEmpty);
      expect(zones.states('b').value, contains(WidgetState.disabled));
      motion.opacity['a'] = InputZoneFrame.minimumOpacity;
      motion.changed();
      await tester.pump();
      await tester.tapAt(_at(motion, 'a'));
      expect(pressed, ['a']);
    });

    testWidgets('disabling a zone ends its touch', (tester) async {
      await tester.pumpWidget(_app(toolbar()));
      final gesture = await tester.startGesture(_at(motion, 'b'));
      await tester.pump();
      await tester.pumpWidget(_app(toolbar(disabled: {'b'})));
      expect(zones.states('b').value, isNot(contains(WidgetState.pressed)));
      await gesture.up();
      await tester.pump();
      expect(pressed, isEmpty);
    });

    testWidgets('touches handed on through a port arrive on no zone first '
        'and slide onto one', (tester) async {
      final port = InputPort();
      await tester.pumpWidget(
        _app(
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              toolbar(slides: true, port: port),
              InputRegion(
                interactions: [port.forward],
                child: const SizedBox(width: 200, height: 60),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      final gesture = await tester.startGesture(const Offset(30, 70));
      await tester.pump();
      await gesture.moveTo(const Offset(30, 50));
      await tester.pump();
      await gesture.moveTo(_at(motion, 'b'));
      await tester.pump();
      expect(zones.states('b').value, contains(WidgetState.pressed));
      await gesture.up();
      await tester.pump();
      expect(pressed, ['b']);
    });
  });

  group('mouse', () {
    MouseCursor active() =>
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1)!;

    testWidgets('each zone has its cursor and hover, a disabled one its '
        'cursor alone, also under a resting mouse when the zones move', (
      tester,
    ) async {
      await tester.pumpWidget(_app(toolbar(disabled: {'c'})));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(5, 100));
      await tester.pump();
      await mouse.moveTo(_at(motion, 'a'));
      await tester.pump();
      expect(zones.states('a').value, contains(WidgetState.hovered));
      expect(active(), SystemMouseCursors.click);
      await mouse.moveTo(_at(motion, 'c'));
      await tester.pump();
      expect(zones.states('a').value, isNot(contains(WidgetState.hovered)));
      expect(zones.states('c').value, {WidgetState.disabled});
      expect(active(), SystemMouseCursors.forbidden);
      await mouse.moveTo(_at(motion, 'b'));
      await tester.pump();
      expect(zones.states('b').value, contains(WidgetState.hovered));
      motion.slide(60);
      await tester.pump();
      expect(zones.states('b').value, isNot(contains(WidgetState.hovered)));
      expect(zones.states('a').value, contains(WidgetState.hovered));
      motion.slide(200);
      await tester.pump();
      expect(zones.states('a').value, isNot(contains(WidgetState.hovered)));
      expect(active(), SystemMouseCursors.basic);
      await mouse.removePointer();
    });

    testWidgets('a zone enabled under a resting mouse is hovered after the '
        'frame that enables it', (tester) async {
      await tester.pumpWidget(_app(toolbar(disabled: {'c'})));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: _at(motion, 'c'));
      await tester.pump();
      expect(zones.states('c').value, {WidgetState.disabled});
      await tester.pumpWidget(_app(toolbar(disabled: {})));
      expect(zones.states('c').value, {WidgetState.hovered});
    });

    testWidgets('a zone that adjusts gets the adaptive click cursor, one '
        'that takes no key defers', (tester) async {
      Widget zonesOf(List<Interaction> interactions) => _app(
        MouseRegion(
          cursor: SystemMouseCursors.text,
          child: InputZones<String>(
            zones: [InputZone(id: 'a', interactions: interactions)],
            frameOf: (zone) =>
                const InputZoneFrame(Rect.fromLTWH(0, 0, 40, 40)),
            frames: motion,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      await tester.pumpWidget(zonesOf([_Values()]));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(20, 20));
      addTearDown(mouse.removePointer);
      await tester.pump();
      expect(
        active(),
        WidgetStateMouseCursor.adaptiveClickable.resolve(const {}),
      );
      await tester.pumpWidget(zonesOf([DragInteraction()]));
      await tester.pump();
      expect(active(), SystemMouseCursors.text);
    });

    testWidgets('a hover dwell fires for the zone the mouse rests on', (
      tester,
    ) async {
      final fired = <double>[];
      await tester.pumpWidget(
        _app(
          toolbar(
            extra: {
              'b': [HoverDwellInteraction(duration: 0.3, onDwell: fired.add)],
            },
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(5, 100));
      await mouse.moveTo(_at(motion, 'b'));
      await tester.pump(const Duration(milliseconds: 100));
      await mouse.moveTo(_at(motion, 'a'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(fired, isEmpty);
      await mouse.moveTo(_at(motion, 'b'));
      // The clock dozes on a timer until the due time, then asks for the
      // frame that runs it.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(fired, hasLength(1));
    });

    testWidgets('a secondary click reaches the zone under it, in its '
        'coordinates', (tester) async {
      final clicks = <Offset>[];
      await tester.pumpWidget(
        _app(
          toolbar(
            extra: {
              'c': [
                SecondaryClickInteraction(onClick: (t, p) => clicks.add(p)),
              ],
            },
          ),
        ),
      );
      await tester.tapAt(
        _at(motion, 'b'),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      final c = motion.rectOf('c');
      await tester.tapAt(
        c.topLeft + const Offset(4, 6),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      expect(clicks, [const Offset(4, 6)]);
      expect(pressed, isEmpty);
    });
  });

  group('keyboard', () {
    testWidgets('Tab visits the zones in order, skipping the ones that take '
        'no input', (tester) async {
      await tester.pumpWidget(_app(toolbar(disabled: {'b'})));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(zones.focusedZone, 'a');
      expect(zones.states('a').value, contains(WidgetState.focused));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(zones.focusedZone, 'c');
      expect(zones.states('a').value, isNot(contains(WidgetState.focused)));
      motion.leaving.add('a');
      motion.changed();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(zones.focusedZone, 'c');
    });

    group('one stop', () {
      late FocusNode after;

      setUp(() => after = FocusNode(debugLabel: 'after'));
      tearDown(() => after.dispose());

      Widget group({String? current, bool activatesOnMove = false}) => _app(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            toolbar(
              stops: InputZoneStops.one,
              current: current,
              activatesOnMove: activatesOnMove,
            ),
            Focus(
              focusNode: after,
              child: const SizedBox(width: 10, height: 10),
            ),
          ],
        ),
      );

      Future<void> tab(WidgetTester tester, {bool back = false}) async {
        if (back) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        if (back) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
      }

      testWidgets('Tab enters at the current zone and leaves on the next '
          'Tab, both ways', (tester) async {
        await tester.pumpWidget(group(current: 'b'));
        await tab(tester);
        expect(zones.focusedZone, 'b');
        expect(zones.states('b').value, contains(WidgetState.focused));
        await tab(tester);
        expect(after.hasPrimaryFocus, isTrue);
        await tab(tester, back: true);
        expect(zones.focusedZone, 'b');
        await tab(tester, back: true);
        expect(zones.focusedZone, isNull);
      });

      testWidgets('the arrows, Home and End move among the zones, and Tab '
          'comes back to the zone focused last', (tester) async {
        await tester.pumpWidget(group());
        await tab(tester);
        expect(zones.focusedZone, 'a');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(zones.focusedZone, 'b');
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pump();
        expect(zones.focusedZone, 'c');
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(zones.focusedZone, 'b');
        await tab(tester);
        expect(after.hasPrimaryFocus, isTrue);
        await tab(tester, back: true);
        expect(zones.focusedZone, 'b');
        expect(pressed, isEmpty);
      });

      testWidgets('a zone that cannot take focus is not where Tab enters', (
        tester,
      ) async {
        await tester.pumpWidget(group(current: 'b'));
        motion.leaving.add('b');
        motion.changed();
        await tester.pump();
        await tab(tester);
        expect(zones.focusedZone, 'a');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(zones.focusedZone, 'c');
      });

      testWidgets('with activatesOnMove the zone an arrow, Home or End '
          'reaches is activated, with no haptic', (tester) async {
        await tester.pumpWidget(group(current: 'a', activatesOnMove: true));
        await tab(tester);
        expect(pressed, isEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        expect(pressed, ['b', 'c', 'a', 'a']);
        expect(haptics, isEmpty);
      });

      testWidgets('assistive technology still reaches every zone', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(group(current: 'b'));
        for (final item in ToyMotion.items) {
          final data = tester
              .getSemantics(find.bySemanticsLabel('Item $item'))
              .getSemanticsData();
          expect(data.hasAction(SemanticsAction.focus), isTrue, reason: item);
        }
        handle.dispose();
      });
    });

    testWidgets('the arrows move along the zones, Home and End reach the '
        'ends', (tester) async {
      await tester.pumpWidget(_app(toolbar()));
      expect(zones.requestFocus('a'), isTrue);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(zones.focusedZone, 'b');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(zones.focusedZone, 'c');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(zones.focusedZone, 'b');
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(zones.focusedZone, 'a');
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(zones.focusedZone, 'c');
    });

    testWidgets('the arrows are mirrored right to left', (tester) async {
      await tester.pumpWidget(
        _app(toolbar(), direction: TextDirection.rtl),
      );
      expect(motion.rectOf('b').left, lessThan(motion.rectOf('a').left));
      zones.requestFocus('a');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(zones.focusedZone, 'b');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(zones.focusedZone, 'a');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(zones.focusedZone, 'b');
    });

    testWidgets('without an axis the arrows go to the nearest zone on screen', (
      tester,
    ) async {
      await tester.pumpWidget(_app(toolbar(axis: null)));
      zones.requestFocus('c');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(zones.focusedZone, 'b');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(zones.focusedZone, 'a');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(zones.focusedZone, 'b');
    });

    testWidgets('an arrow past the end asks the host before focus leaves', (
      tester,
    ) async {
      final edges = <(String, TraversalDirection)>[];
      await tester.pumpWidget(
        _app(
          InputZones<String>(
            zones: [
              for (final item in ToyMotion.items)
                InputZone(id: item, interactions: [PressInteraction()]),
            ],
            frameOf: motion.frameOf,
            frames: motion,
            controller: zones,
            onEdge: (zone, direction) {
              edges.add((zone, direction));
              return true;
            },
            child: const SizedBox(width: 200, height: 32),
          ),
        ),
      );
      zones.requestFocus('c');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(zones.focusedZone, 'c');
      expect(edges, [
        ('c', TraversalDirection.right),
        ('c', TraversalDirection.down),
      ]);
    });

    testWidgets('Enter and Space activate the focused zone, with no haptic', (
      tester,
    ) async {
      await tester.pumpWidget(_app(toolbar()));
      zones.requestFocus('b');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(pressed, ['b', 'b']);
      expect(haptics, isEmpty);
    });

    testWidgets('a drag region around the host leaves Space and Enter to '
        'the focused zone', (tester) async {
      await tester.pumpWidget(
        _app(InputRegion(interactions: [DragInteraction()], child: toolbar())),
      );
      zones.requestFocus('b');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(pressed, ['b', 'b']);
    });

    testWidgets('zones that are not focusable are targets with their own '
        'buttons inside the one stop of a region around them', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final values = _Values();
      final halves = <String>[];
      final focus = FocusNode();
      addTearDown(focus.dispose);
      InputZone<String> half(String id) => InputZone(
        id: id,
        interactions: [_Activated(() => halves.add(id))],
        focusable: false,
        reach: const PressReach(minimumHit: Size.square(44)),
        semantics: SemanticsProperties(label: id, button: true),
      );
      await tester.pumpWidget(
        _app(
          InputRegion(
            interactions: [values],
            focusNode: focus,
            child: InputZones<String>(
              zones: [half('minus'), half('plus')],
              frameOf: (id) => InputZoneFrame(
                id == 'minus'
                    ? const Rect.fromLTWH(0, 0, 47, 32)
                    : const Rect.fromLTWH(47, 0, 47, 32),
              ),
              frames: motion,
              controller: zones,
              child: const SizedBox(width: 94, height: 32),
            ),
          ),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(focus.hasPrimaryFocus, isTrue);
        expect(zones.focusedZone, isNull);
      }
      expect(zones.requestFocus('plus'), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(values.heard, [ValueCommand.increase, 'activate']);
      expect(
        tester.getSemantics(find.bySemanticsLabel('plus')),
        matchesSemantics(
          label: 'plus',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      tester.semantics.tap(find.semantics.byLabel('plus'));
      tester.semantics.tap(find.semantics.byLabel('minus'));
      expect(halves, ['plus', 'minus']);
      handle.dispose();
    });

    testWidgets('a zone that adjusts keeps the arrows, Home and End for its '
        'value', (tester) async {
      final values = _Values();
      await tester.pumpWidget(
        _app(
          toolbar(
            extra: {
              'b': [values],
            },
          ),
        ),
      );
      zones.requestFocus('b');
      await tester.pump();
      for (final key in [
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
      ]) {
        await tester.sendKeyEvent(key);
      }
      await tester.pump();
      expect(zones.focusedZone, 'b');
      expect(values.heard, [
        ValueCommand.increase,
        ValueCommand.decrease,
        ValueCommand.toMinimum,
        ValueCommand.toMaximum,
      ]);
    });
    testWidgets('a zone at an end offers neither the action nor the keys '
        'toward it', (tester) async {
      final semantics = tester.ensureSemantics();
      final range = ValueNotifier(const AdjustRange(canDecrease: false));
      addTearDown(range.dispose);
      final values = _Values();
      await tester.pumpWidget(
        _app(
          InputZones<String>(
            zones: [
              InputZone(
                id: 'a',
                interactions: [values],
                semantics: const SemanticsProperties(label: 'level'),
                adjustRange: range,
              ),
            ],
            frameOf: (zone) =>
                const InputZoneFrame(Rect.fromLTWH(0, 0, 40, 40)),
            frames: motion,
            controller: zones,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      zones.requestFocus('a');
      await tester.pump();
      SemanticsData data() => tester
          .getSemantics(find.bySemanticsLabel('level'))
          .getSemanticsData();
      expect(data().hasAction(SemanticsAction.increase), isTrue);
      expect(data().hasAction(SemanticsAction.decrease), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(values.heard, [ValueCommand.increase]);
      range.value = AdjustRange.open;
      await tester.pump();
      expect(data().hasAction(SemanticsAction.decrease), isTrue);
      semantics.dispose();
    });
  });

  testWidgets('a portal presentation grows out of a zone and follows it as '
      'the zone moves', (tester) async {
    final portal = PresentationPortalController();
    final cards = <_Card>[];
    var notified = 0;
    zones.addListener(() => notified++);
    final source = zones.sourceOf('b');
    expect(zones.sourceOf('b'), same(source));
    expect(source.geometry, isNull);
    await tester.pumpWidget(
      _app(
        Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) => Align(
                alignment: Alignment.topLeft,
                child: PresentationPortal(
                  controller: portal,
                  presentation: Presentation<Object?, _Card>(
                    motion: (_) {
                      final card = _Card();
                      cards.add(card);
                      return card;
                    },
                    builder: (context, motion) => const SizedBox(width: 10),
                    source: source,
                  ),
                  child: toolbar(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    portal.present();
    await tester.pump();
    await tester.pump();
    expect(source.isHidden, isTrue);
    expect(notified, greaterThan(0));
    final card = cards.single;
    expect(card.sources.first?.rect, motion.rectOf('b'));
    motion.slide(30);
    await tester.pump();
    expect(card.sources.last?.rect, motion.rectOf('b'));
    expect(
      card.sources.last?.rect,
      card.sources.first?.rect.shift(const Offset(30, 0)),
    );
    motion.opacity['b'] = 0;
    motion.changed();
    await tester.pump();
    expect(card.sources.last, isNull);
    portal.dismiss(DismissTrigger.programmatic);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(source.isHidden, isFalse);
  });

  group('semantics', () {
    testWidgets('each live zone is a node with its flags and actions over '
        'its hit rectangle, which follows the motion', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(toolbar(disabled: {'c'})));
      // An anchor takes its zone's size at the start of the next frame.
      await tester.pump();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Item b')),
        matchesSemantics(
          label: 'Item b',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Item c')),
        matchesSemantics(
          label: 'Item c',
          isButton: true,
          hasEnabledState: true,
        ),
      );
      expect(find.semantics.byLabel('paint'), findsNothing);
      final rect = tester.getSemantics(find.bySemanticsLabel('Item b')).rect;
      expect(rect.size, const Size(44, 44));
      final before = tester.getRect(find.bySemanticsLabel('Item b'));
      motion.slide(20);
      await tester.pump();
      expect(
        tester.getRect(find.bySemanticsLabel('Item b')),
        before.shift(const Offset(20, 0)),
      );
      tester.semantics.tap(find.semantics.byLabel('Item b'));
      await tester.pump();
      expect(pressed, ['b']);
      expect(haptics, isEmpty);
      motion.leaving.add('b');
      motion.changed();
      await tester.pump();
      expect(find.semantics.byLabel('Item b'), findsNothing);
      handle.dispose();
    });

    testWidgets('a zone reads its value, selection and role', (tester) async {
      final handle = tester.ensureSemantics();
      final values = _Values();
      await tester.pumpWidget(
        _app(
          InputZones<String>(
            zones: [
              InputZone(
                id: 'a',
                interactions: [values],
                semantics: const SemanticsProperties(
                  label: 'Day',
                  value: '12',
                  increasedValue: '13',
                  decreasedValue: '11',
                  selected: true,
                  role: SemanticsRole.tab,
                ),
              ),
            ],
            frameOf: motion.frameOf,
            frames: motion,
            child: const SizedBox(width: 200, height: 32),
          ),
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Day')),
        matchesSemantics(
          label: 'Day',
          value: '12',
          increasedValue: '13',
          decreasedValue: '11',
          hasSelectedState: true,
          isSelected: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          hasIncreaseAction: true,
          hasDecreaseAction: true,
          role: SemanticsRole.tab,
        ),
      );
      tester.semantics.increase(find.semantics.byLabel('Day'));
      await tester.pump();
      expect(values.heard, [ValueCommand.increase]);
      handle.dispose();
    });
  });

  testWidgets('a haptic scope silences the zones', (tester) async {
    await tester.pumpWidget(
      _app(MotionHapticScope(enabled: false, child: toolbar())),
    );
    await tester.tapAt(_at(motion, 'a'));
    expect(pressed, ['a']);
    expect(haptics, isEmpty);
  });

  testWidgets('zones that leave the set give up their focus node', (
    tester,
  ) async {
    Widget host(List<String> ids) => _app(
      InputZones<String>(
        zones: [
          for (final id in ids)
            InputZone(id: id, interactions: [PressInteraction()]),
        ],
        frameOf: motion.frameOf,
        frames: motion,
        controller: zones,
        child: const SizedBox(width: 200, height: 32),
      ),
    );
    await tester.pumpWidget(host(['a', 'b', 'c']));
    zones.requestFocus('b');
    await tester.pump();
    expect(zones.focusedZone, 'b');
    await tester.pumpWidget(host(['a', 'c']));
    expect(zones.focusedZone, isNull);
    expect(zones.requestFocus('b'), isFalse);
    expect(zones.requestFocus('c'), isTrue);
  });

  testWidgets('a touch reads each zone where it lies once, and again after '
      'the frames move', (tester) async {
    final reads = <String, int>{};
    final frames = ValueNotifier(0);
    addTearDown(frames.dispose);
    await tester.pumpWidget(
      _app(
        InputZones<String>(
          zones: [
            for (final id in const ['a', 'b', 'c'])
              InputZone(id: id, interactions: [PressInteraction()]),
          ],
          frameOf: (id) {
            reads[id] = (reads[id] ?? 0) + 1;
            return motion.frameOf(id);
          },
          frames: frames,
          slides: true,
          child: const SizedBox(width: 200, height: 32),
        ),
      ),
    );
    reads.clear();
    final gesture = await tester.startGesture(_at(motion, 'a'));
    await gesture.moveTo(_at(motion, 'b'));
    await gesture.moveTo(_at(motion, 'c'));
    expect(reads, {'a': 1, 'b': 1, 'c': 1});
    reads.clear();
    frames.value++;
    await gesture.moveTo(_at(motion, 'b'));
    await gesture.up();
    expect(reads.values, everyElement(1));
  });

  testWidgets('a zone publishes what its control says, and each zone is '
      'heard on its own', (tester) async {
    final controller = InputZonesController<String>();
    addTearDown(controller.dispose);
    final heard = <String>[];
    void count() => heard.add('a');
    controller.states('a').addListener(count);
    final press = {
      'a': [PressInteraction()],
      'b': [PressInteraction()],
    };
    Widget zonesOf({required bool selected}) => _app(
      InputZones<String>(
        controller: controller,
        zones: [
          InputZone(
            id: 'a',
            interactions: press['a']!,
            states: {if (selected) WidgetState.selected},
          ),
          InputZone(id: 'b', interactions: press['b']!),
        ],
        frameOf: (zone) => InputZoneFrame(
          Rect.fromLTWH(zone == 'a' ? 0 : 50, 0, 40, 40),
        ),
        frames: motion,
        child: const SizedBox(width: 100, height: 40),
      ),
    );
    await tester.pumpWidget(zonesOf(selected: true));
    expect(controller.states('a').value, {WidgetState.selected});
    expect(heard, isEmpty, reason: 'what a build says notifies nobody');

    final gesture = await tester.startGesture(
      tester.getTopLeft(find.byType(SizedBox)) + const Offset(70, 20),
    );
    await tester.pump();
    expect(controller.states('b').value, {WidgetState.pressed});
    expect(heard, isEmpty);
    await gesture.up();
    await tester.pump();

    await tester.pumpWidget(zonesOf(selected: false));
    expect(controller.states('a').value, isEmpty);
    await tester.tapAt(
      tester.getTopLeft(find.byType(SizedBox)) + const Offset(20, 20),
    );
    await tester.pump();
    expect(heard, isNotEmpty);
    controller.states('a').removeListener(count);
    expect(controller.states('a'), controller.states('a'));
  });
}
