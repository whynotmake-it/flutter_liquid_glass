import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
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

class _Probe {
  int builds = 0;
  GlassStepperHalf? pressed;
  GlassStepperDetails? details;

  Widget build(BuildContext context, GlassStepperDetails details) {
    builds++;
    pressed = details.pressed;
    this.details = details;
    return const SizedBox.expand();
  }
}

Offset _half(WidgetTester tester, GlassStepperHalf half) {
  final box = tester.getRect(find.byType(RawGlassStepper));
  return half == GlassStepperHalf.decrement
      ? box.centerLeft + Offset(box.width / 4, 0)
      : box.centerRight - Offset(box.width / 4, 0);
}

Widget _keyApp(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    WidgetsApp(
      color: const Color(0xFF000000),
      builder: (context, _) => Directionality(
        textDirection: direction,
        child: Center(child: child),
      ),
    );

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a tap commits on release; a held half repeats every half '
      'second', (tester) async {
    final values = <double>[];
    final probe = _Probe();
    await tester.pumpWidget(
      _app(
        RawGlassStepper(
          value: 5,
          onChanged: values.add,
          builder: probe.build,
        ),
      ),
    );
    final tap = await tester.startGesture(
      _half(tester, GlassStepperHalf.increment),
    );
    await tester.pump();
    expect(probe.pressed, GlassStepperHalf.increment);
    expect(values, isEmpty);
    await tap.up();
    await tester.pump();
    expect(values, [6]);
    expect(probe.pressed, isNull);

    values.clear();
    final hold = await tester.startGesture(
      _half(tester, GlassStepperHalf.decrement),
    );
    for (var i = 0; i < 160; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(values, [4, 4, 4]);
    await hold.up();
    await tester.pump();
    expect(values, [4, 4, 4]);
  });

  testWidgets('sliding to the other half moves the highlight without a '
      'step; leaving cancels', (tester) async {
    final values = <double>[];
    final probe = _Probe();
    await tester.pumpWidget(
      _app(
        RawGlassStepper(
          value: 5,
          onChanged: values.add,
          builder: probe.build,
        ),
      ),
    );
    final gesture = await tester.startGesture(
      _half(tester, GlassStepperHalf.decrement),
    );
    await tester.pump();
    await gesture.moveTo(_half(tester, GlassStepperHalf.increment));
    await tester.pump();
    expect(probe.pressed, GlassStepperHalf.increment);
    expect(values, isEmpty);
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(probe.pressed, isNull);
    await gesture.up();
    await tester.pump();
    expect(values, isEmpty);
  });

  testWidgets('limits, keys and two semantic buttons; minus stays left in '
      'right to left', (tester) async {
    final semantics = tester.ensureSemantics();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final values = <double>[];
    final probe = _Probe();
    await tester.pumpWidget(
      _app(
        RawGlassStepper(
          value: 0,
          max: 3,
          onChanged: values.add,
          focusNode: focus,
          builder: probe.build,
        ),
        direction: TextDirection.rtl,
      ),
    );
    expect(probe.details!.canDecrement, isFalse);
    expect(probe.details!.canIncrement, isTrue);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Increment')),
      matchesSemantics(
        label: 'Increment',
        value: '0',
        isButton: true,
        hasTapAction: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    expect(
      tester.getCenter(find.bySemanticsLabel('Decrement')).dx,
      lessThan(tester.getCenter(find.bySemanticsLabel('Increment')).dx),
    );
    await tester.tapAt(_half(tester, GlassStepperHalf.increment));
    await tester.pump();
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    tester.semantics.tap(find.semantics.byLabel('Increment'));
    // The value stays at the minimum, where the left arrow does nothing.
    expect(values, [1, 1, 1]);
    semantics.dispose();
  });

  testWidgets('disabled it ignores touches and keys', (tester) async {
    final probe = _Probe();
    await tester.pumpWidget(
      _app(RawGlassStepper(value: 5, onChanged: null, builder: probe.build)),
    );
    await tester.tapAt(_half(tester, GlassStepperHalf.increment));
    await tester.pump();
    expect(probe.pressed, isNull);
    expect(probe.details!.states, contains(WidgetState.disabled));
  });

  testWidgets('the stock stepper paints from the theme', (tester) async {
    await tester.pumpWidget(
      _app(
        GlassTheme(
          data: GlassThemeData(
            styles: [
              GlassStepper.styleFrom(
                backgroundColor: const Color(0xFF123456),
              ),
            ],
          ),
          child: GlassStepper(value: 5, onChanged: (_) {}),
        ),
      ),
    );
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('under a WidgetsApp the arrows step it as the halves lie in '
      'either direction, Home and End end it, and Page Up, Page Down, Space '
      'and Enter do nothing', (tester) async {
    for (final direction in TextDirection.values) {
      final values = <double>[];
      await tester.pumpWidget(
        _keyApp(
          RawGlassStepper(
            key: ValueKey(direction),
            value: 5,
            max: 10,
            onChanged: values.add,
            autofocus: true,
            builder: _Probe().build,
          ),
          direction: direction,
        ),
      );
      await tester.pump();
      for (final key in [
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.enter,
      ]) {
        await tester.sendKeyEvent(key);
      }
      expect(values, [6, 4, 6, 4, 0, 10], reason: '$direction');
    }
  });

  testWidgets('an app adds keys with Shortcuts and replaces a command with '
      'Actions, for the keys and the buttons alike', (tester) async {
    final semantics = tester.ensureSemantics();
    final values = <double>[];
    final overridden = <ValueCommand>[];
    Widget stepper({bool override = false}) => _keyApp(
      Actions(
        actions: {
          if (override)
            AdjustValueIntent: CallbackAction<AdjustValueIntent>(
              onInvoke: (intent) => overridden.add(intent.command),
            ),
        },
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.equal): AdjustValueIntent(
              ValueCommand.increase,
            ),
          },
          child: RawGlassStepper(
            value: 5,
            onChanged: values.add,
            autofocus: true,
            builder: _Probe().build,
          ),
        ),
      ),
    );
    await tester.pumpWidget(stepper());
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    tester.semantics.tap(find.semantics.byLabel('Decrement'));
    expect(values, [6, 4]);
    await tester.pumpWidget(stepper(override: true));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    tester.semantics.tap(find.semantics.byLabel('Increment'));
    expect(values, [6, 4]);
    expect(overridden, [ValueCommand.increase, ValueCommand.increase]);
    semantics.dispose();
  });

  testWidgets('the adjustable node carries the semantic label and the value', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        RawGlassStepper(
          value: 5,
          semanticLabel: 'Quantity',
          onChanged: (_) {},
          builder: _Probe().build,
        ),
      ),
    );
    await tester.pump();
    final node = tester.getSemantics(find.byType(RawGlassStepper));
    expect(node.label, 'Quantity');
    expect(node.value, '5');
    semantics.dispose();
  });

  testWidgets('one adjustable node with the value over its 44 point target '
      'holds the two buttons', (tester) async {
    final semantics = tester.ensureSemantics();
    final values = <double>[];
    await tester.pumpWidget(
      _app(
        RawGlassStepper(
          value: 5,
          onChanged: values.add,
          builder: _Probe().build,
        ),
      ),
    );
    // A zone's box takes its size at the start of the next frame.
    await tester.pump();
    final node = tester.getSemantics(find.byType(RawGlassStepper));
    expect(
      node,
      matchesSemantics(
        rect: const Rect.fromLTWH(0, -6, 94, 44),
        value: '5',
        increasedValue: '6',
        decreasedValue: '4',
        textDirection: TextDirection.ltr,
        hasIncreaseAction: true,
        hasDecreaseAction: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        children: [
          matchesSemantics(
            label: 'Decrement',
            value: '5',
            rect: const Rect.fromLTWH(0, 0, 47, 44),
            isButton: true,
            hasTapAction: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
          matchesSemantics(
            label: 'Increment',
            value: '5',
            rect: const Rect.fromLTWH(0, 0, 47, 44),
            isButton: true,
            hasTapAction: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
        ],
      ),
    );
    final origin = tester.getTopLeft(find.byType(RawGlassStepper));
    expect(
      tester.getRect(find.bySemanticsLabel('Decrement')).shift(-origin),
      const Rect.fromLTWH(0, -6, 47, 44),
    );
    expect(
      tester.getRect(find.bySemanticsLabel('Increment')).shift(-origin),
      const Rect.fromLTWH(47, -6, 47, 44),
    );
    tester.semantics.increase(
      find.semantics.byAction(SemanticsAction.increase),
    );
    tester.semantics.decrease(
      find.semantics.byAction(SemanticsAction.decrease),
    );
    expect(values, [6, 4]);
    semantics.dispose();
  });

  testWidgets('a tap in the 44 point extension steps the half above or '
      'below it; one beyond does not', (tester) async {
    final values = <double>[];
    await tester.pumpWidget(
      _app(
        RawGlassStepper(
          value: 5,
          onChanged: values.add,
          builder: _Probe().build,
        ),
      ),
    );
    expect(tester.getSize(find.byType(RawGlassStepper)), RawGlassStepper.size);
    await tester.tapAt(
      _half(tester, GlassStepperHalf.increment) + const Offset(0, -21),
    );
    await tester.tapAt(
      _half(tester, GlassStepperHalf.decrement) + const Offset(0, 21),
    );
    await tester.tapAt(
      _half(tester, GlassStepperHalf.increment) + const Offset(0, 23),
    );
    await tester.pump();
    expect(values, [6, 4]);
  });

  testWidgets('the half labels come from GlassLocalizations', (tester) async {
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        localizationsDelegates: const [_FrenchDelegate()],
        builder: (context, _) => Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: GlassStepper(value: 5, onChanged: (_) {}),
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Moins'), findsOneWidget);
    expect(find.bySemanticsLabel('Plus'), findsOneWidget);
    expect(find.bySemanticsLabel('Decrement'), findsNothing);
  });
}

class _French extends DefaultGlassLocalizations {
  const _French();

  @override
  String get decrementLabel => 'Moins';

  @override
  String get incrementLabel => 'Plus';
}

class _FrenchDelegate extends LocalizationsDelegate<GlassLocalizations> {
  const _FrenchDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<GlassLocalizations> load(Locale locale) =>
      SynchronousFuture<GlassLocalizations>(const _French());

  @override
  bool shouldReload(_FrenchDelegate old) => false;
}
