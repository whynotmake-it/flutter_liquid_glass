import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _accent = Color(0xFF0088FF);
const _black = Color(0xFF000000);
const _white = Color(0xFFFFFFFF);
const _todayFill = Color(0x1F0088FF);

class _App extends StatelessWidget {
  const _App({required this.home, this.builder, this.brightness});

  final Widget home;
  final TransitionBuilder? builder;
  final Brightness? brightness;

  @override
  Widget build(BuildContext context) => WidgetsApp(
    color: const Color(0xFF000000),
    pageRouteBuilder: <T>(settings, builder) =>
        GlassPageRoute<T>(builder: builder, settings: settings),
    builder: (context, child) => GlassScope(
      renderer: const FlatGlassRenderer(),
      data: GlassThemeData(
        brightness: brightness,
      ),
      child: builder?.call(context, child) ?? child!,
    ),
    home: home,
  );
}

/// A property of the day cell drawing [day]'s disc and number.
Object? _dayCell(WidgetTester tester, String day, String name) {
  final cell = tester.widget(
    find
        .ancestor(
          of: find.text(day),
          matching: find.byWidgetPredicate(
            (Widget w) => w.runtimeType.toString() == '_DayCell',
          ),
        )
        .first,
  );
  return cell
      .toDiagnosticsNode()
      .getProperties()
      .firstWhere((DiagnosticsNode p) => p.name == name)
      .value;
}

void main() {
  setUp(MotionClock.debugReset);

  group('GlassDatePicker', () {
    Future<void> pump(
      WidgetTester tester, {
      DateTime? value,
      ValueChanged<DateTime>? onChanged,
      GlassDatePickerMode mode = GlassDatePickerMode.date,
      Brightness? brightness,
      TextDirection direction = TextDirection.ltr,
      double textScale = 1,
      bool use24 = true,
      Alignment alignment = const Alignment(0, -0.4),
      GlassDatePickerStyle? style,
    }) async {
      await tester.binding.setSurfaceSize(const Size(440, 956));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var current = value ?? DateTime(2026, 10, 3, 9, 41);
      await tester.pumpWidget(
        _App(
          brightness: brightness,
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Directionality(textDirection: direction, child: child!),
          ),
          home: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) => Align(
              alignment: alignment,
              child: GlassCompactDatePicker(
                value: current,
                mode: mode,
                style: style,
                use24HourFormat: use24,
                today: DateTime(2026, 10, 3),
                semanticLabel: 'Date',
                onChanged: onChanged == null
                    ? null
                    : (DateTime v) {
                        onChanged(v);
                        setState(() => current = v);
                      },
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('a style colors the label and its open accent', (
      tester,
    ) async {
      const accent = Color(0xFFAA0000);
      const label = Color(0xFF00AA00);
      await pump(
        tester,
        onChanged: (_) {},
        style: const GlassDatePickerStyle(
          accentColor: accent,
          labelColor: label,
        ),
      );
      Color? color() =>
          tester.widget<Text>(find.text('Oct 3, 2026')).style?.color;
      expect(color(), label);
      await tester.tap(find.text('Oct 3, 2026'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(color(), accent);
    });

    testWidgets('opens the calendar, picks a day, stays open, closes', (
      tester,
    ) async {
      final picked = <DateTime>[];
      await pump(tester, onChanged: picked.add);
      expect(find.text('Oct 3, 2026'), findsOneWidget);
      await tester.tap(find.text('Oct 3, 2026'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(find.text('October 2026'), findsOneWidget);
      final label = tester.widget<Text>(find.text('Oct 3, 2026'));
      expect(label.style?.color, _accent);
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(picked.single, DateTime(2026, 10, 15, 9, 41));
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('Oct 15, 2026'), findsOneWidget);
      await tester.tapAt(const Offset(220, 900));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(find.text('October 2026'), findsNothing);
    });

    testWidgets('a tap on the label while it closes opens a new overlay', (
      tester,
    ) async {
      await pump(tester, onChanged: (_) {});
      await tester.tap(find.text('Oct 3, 2026'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      await tester.tapAt(const Offset(220, 900));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('October 2026'), findsOneWidget);
      await tester.tap(find.text('Oct 3, 2026'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('October 2026'), findsNWidgets(2));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(find.text('October 2026'), findsOneWidget);
      final label = tester.widget<Text>(find.text('Oct 3, 2026'));
      expect(label.style?.color, _accent);
      await tester.tapAt(const Offset(220, 900));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(find.text('October 2026'), findsNothing);
    });

    testWidgets('the open spring leaves the days unbuilt', (tester) async {
      await pump(tester, onChanged: (_) {});
      await tester.tap(find.text('Oct 3, 2026'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final day = find.text('15');
      expect(day, findsOneWidget);
      final before = tester.widget(day);
      await tester.pump(const Duration(milliseconds: 16));
      expect(identical(tester.widget(day), before), isTrue);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
    });

    testWidgets('the label dims its text color, not through a layer', (
      tester,
    ) async {
      await pump(tester, onChanged: (_) {});
      double alpha() {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text('Oct 3, 2026'),
            matching: find.byWidgetPredicate((Widget w) => w is RichText),
          ),
        );
        return (paragraph.text as TextSpan).style!.color!.a;
      }

      int fades() {
        var count = 0;
        void walk(Layer layer) {
          if (layer is OpacityLayer && (layer.alpha ?? 255) < 255) count++;
          if (layer is ContainerLayer) {
            for (var c = layer.firstChild; c != null; c = c.nextSibling) {
              walk(c);
            }
          }
        }

        walk(tester.binding.renderViews.first.debugLayer!);
        return count;
      }

      final press = await tester.startGesture(
        tester.getCenter(find.text('Oct 3, 2026')),
      );
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(alpha(), lessThan(0.9));
      expect(fades(), 0);
      await press.cancel();
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(alpha(), 1);
    });

    testWidgets('the open lays out the overlay and its days on two frames', (
      tester,
    ) async {
      await pump(tester, onChanged: (_) {});
      final press = await tester.startGesture(
        tester.getCenter(find.text('Oct 3, 2026')),
      );
      await tester.pump(const Duration(milliseconds: 16));
      Future<int> layoutsOf(Future<void> Function() frame) async {
        debugProfileLayoutsEnabled = true;
        FlutterTimeline.debugCollectionEnabled = true;
        FlutterTimeline.debugReset();
        try {
          await frame();
          return FlutterTimeline.debugCollect().timedBlocks
              .where((TimedBlock b) => b.name.contains('Render'))
              .length;
        } finally {
          FlutterTimeline.debugCollectionEnabled = false;
          debugProfileLayoutsEnabled = false;
        }
      }

      // The overlay and every day of the month mounted on one frame lay
      // out about 400 render objects there.
      final open = await layoutsOf(() async {
        await press.up();
        await tester.pump(const Duration(milliseconds: 16));
      });
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('15'), findsNothing);
      final days = await layoutsOf(
        () => tester.pump(const Duration(milliseconds: 16)),
      );
      expect(find.text('15'), findsOneWidget);
      expect(open, lessThanOrEqualTo(120));
      expect(days, lessThanOrEqualTo(120));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
    });

    testWidgets('a tap outside while it opens closes it', (tester) async {
      await pump(tester, onChanged: (_) {});
      await tester.tap(find.text('Oct 3, 2026'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(220, 900));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(find.text('October 2026'), findsNothing);
    });

    testWidgets('the overlay hangs below and extends to the leading side', (
      tester,
    ) async {
      await pump(tester, onChanged: (_) {});
      final label = tester.getRect(find.byType(GlassCompactDatePicker));
      await tester.tap(find.byType(GlassCompactDatePicker));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      final title = tester.getRect(find.text('October 2026'));
      expect(title.top, greaterThan(label.center.dy));
      expect(title.left, closeTo(20 + 20.33, 1));
    });

    testWidgets('in right-to-left the overlay extends to the right', (
      tester,
    ) async {
      await pump(
        tester,
        onChanged: (_) {},
        direction: TextDirection.rtl,
        alignment: const Alignment(-0.6, -0.4),
      );
      final label = tester.getRect(find.byType(GlassCompactDatePicker));
      await tester.tap(find.byType(GlassCompactDatePicker));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      final title = tester.getRect(find.text('October 2026'));
      expect(title.right, greaterThan(label.center.dx));
    });

    testWidgets('the chevrons turn the month', (tester) async {
      await pump(tester, onChanged: (_) {});
      await tester.tap(find.byType(GlassCompactDatePicker));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      await tester.tap(find.bySemanticsLabel('Next month'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('November 2026'), findsOneWidget);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      await tester.tap(find.bySemanticsLabel('Previous month'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(find.text('October 2026'), findsOneWidget);
    });

    testWidgets('Escape closes the overlay', (tester) async {
      await pump(tester, onChanged: (_) {});
      await tester.tap(find.byType(GlassCompactDatePicker));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(find.text('October 2026'), findsNothing);
    });

    testWidgets('time mode opens the wheels', (tester) async {
      final picked = <DateTime>[];
      await pump(tester, mode: GlassDatePickerMode.time, onChanged: picked.add);
      expect(find.text('09:41'), findsOneWidget);
      await tester.tap(find.text('09:41'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(find.byType(ListWheelScrollView), findsNWidgets(2));
      // The probe's drag on an iPhone 16 Pro (rec-vid-time): 64 points up
      // in 0.375 s turns UIKit's wheel by exactly two rows.
      await tester.timedDrag(
        find.byType(ListWheelScrollView).last,
        const Offset(0, -64),
        const Duration(milliseconds: 375),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(picked.last.minute, 43);
    });

    testWidgets('formats twelve-hour times and both labels', (tester) async {
      await pump(
        tester,
        mode: GlassDatePickerMode.dateAndTime,
        use24: false,
        onChanged: (_) {},
      );
      expect(find.text('Oct 3, 2026'), findsOneWidget);
      expect(find.text('9:41 AM'), findsOneWidget);
    });

    testWidgets('a disabled picker does not open', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(GlassCompactDatePicker));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(find.text('October 2026'), findsNothing);
    });

    testWidgets('screen readers see a button that expands', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, onChanged: (_) {});
      expect(find.bySemanticsLabel('Date, Oct 3, 2026'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('dark colors and a large text scale', (tester) async {
      await pump(
        tester,
        onChanged: (_) {},
        brightness: Brightness.dark,
        textScale: 2,
      );
      final label = tester.widget<Text>(find.text('Oct 3, 2026'));
      expect(label.style?.color, _white);
      await tester.tap(find.byType(GlassCompactDatePicker));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('GlassDatePicker on an iPhone 16 Pro', () {
    Future<void> pump(
      WidgetTester tester,
      GlassDatePickerMode mode, {
      DateTime? start,
    }) async {
      await tester.binding.setSurfaceSize(const Size(402, 874));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var value = start ?? DateTime(2026, 10, 3, 7, 41);
      await tester.pumpWidget(
        _App(
          home: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) => Align(
              alignment: const Alignment(0, -0.3135),
              child: GlassCompactDatePicker(
                value: value,
                mode: mode,
                use24HourFormat: true,
                today: DateTime(2026, 10, 3),
                onChanged: (DateTime v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('the calendar keeps 16 points from the side, title whole', (
      tester,
    ) async {
      await pump(
        tester,
        GlassDatePickerMode.date,
        start: DateTime(2026, 5, 3, 7, 41),
      );
      await tester.tap(find.text('May 3, 2026'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      final title = find.text('May 2026');
      expect(
        tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
        isFalse,
      );
      // The screen recording: the platter's left edge at 16, the title's
      // ink at 37.
      expect(tester.getRect(title).left, closeTo(16 + 20.33, 0.5));
    });

    testWidgets('a chosen day that is not today sits on a label disc', (
      tester,
    ) async {
      await pump(tester, GlassDatePickerMode.date);
      await tester.tap(find.text('Oct 3, 2026'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(
        _dayCell(tester, '15', 'fill'),
        _black,
      );
      expect(
        _dayCell(tester, '3', 'fill'),
        _todayFill,
      );
      final text = tester.widget<Text>(find.text('15'));
      expect(
        text.style?.color,
        _white,
      );
    });

    testWidgets('the overlay opens 0.14 s after the lift', (tester) async {
      await pump(tester, GlassDatePickerMode.date);
      await tester.tap(find.text('Oct 3, 2026'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      double opacity() => tester
          .widgetList<MotionTransition>(
            find.ancestor(
              of: find.text('October 2026'),
              matching: find.byType(MotionTransition),
            ),
          )
          .where((w) => w.opacity != null)
          .last
          .opacity!
          .value;
      expect(opacity(), 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacity(), greaterThan(0.1));
    });

    testWidgets('the other label turns the open overlay into its picker', (
      tester,
    ) async {
      await pump(tester, GlassDatePickerMode.dateAndTime);
      await tester.tap(find.text('Oct 3, 2026'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(find.text('October 2026'), findsOneWidget);
      await tester.tap(find.text('07:41').first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.byType(ListWheelScrollView), findsNWidgets(2));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(find.text('October 2026'), findsNothing);
      expect(find.byType(ListWheelScrollView), findsNWidgets(2));
      final label = tester.widget<Text>(find.text('07:41').first);
      expect(label.style?.color, _accent);
      final date = tester.widget<Text>(find.text('Oct 3, 2026'));
      expect(date.style?.color, _black);
      await tester.tapAt(const Offset(201, 800));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(find.byType(ListWheelScrollView), findsNothing);
    });
  });

  group('GlassDatePicker time wheels', () {
    testWidgets("rows sit on UIKit's cylinder", (tester) async {
      await tester.binding.setSurfaceSize(const Size(402, 874));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _App(
          home: Align(
            alignment: const Alignment(0, -0.3135),
            child: GlassCompactDatePicker(
              value: DateTime(2026, 10, 3, 7, 41),
              mode: GlassDatePickerMode.time,
              use24HourFormat: true,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.tap(find.byType(GlassCompactDatePicker));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      final center = tester.getRect(find.text('07').last);
      // UIKit's labels on an iPhone 16 Pro (rec-vid-time): neighbours 31.3
      // and 56.7 points from the selected row, 0.905 and 0.647 of its
      // height; the hour column 73.5 and the minute column 148.5 points
      // from the platter's leading edge (16 on this screen).
      for (final (text, dy, h) in [
        ('06', -31.3, 0.905),
        ('08', 31.3, 0.905),
        ('05', -56.9, 0.647),
        ('09', 56.6, 0.647),
      ]) {
        final r = tester.getRect(find.text(text).last);
        expect(r.center.dy - center.center.dy, closeTo(dy, 0.6), reason: text);
        expect(r.height / center.height, closeTo(h, 0.03), reason: text);
        expect(r.center.dx, closeTo(16 + 73.5, 0.5), reason: text);
      }
      expect(
        tester.getRect(find.text('41').last).center.dx,
        closeTo(16 + 148.5, 0.5),
      );
    });
  });

  group('GlassDatePicker 12-hour wheels', () {
    Future<List<DateTime>> open(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(402, 874));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final changes = <DateTime>[];
      var value = DateTime(2026, 10, 3, 7, 41);
      await tester.pumpWidget(
        _App(
          home: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) => Align(
              alignment: const Alignment(0, -0.3135),
              child: GlassCompactDatePicker(
                value: value,
                mode: GlassDatePickerMode.time,
                use24HourFormat: false,
                onChanged: (DateTime v) {
                  changes.add(v);
                  setState(() => value = v);
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('7:41 AM'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      return changes;
    }

    testWidgets('an AM/PM wheel sits where UIKit puts it', (tester) async {
      await open(tester);
      expect(find.byType(ListWheelScrollView), findsNWidgets(3));
      // UIKit's labels on an iPhone 16 Pro (en_US@hours=h12, platter at
      // 16): hours end 51.33 points in, minutes centered 110.67, AM and PM
      // start 158.
      expect(
        tester.getRect(find.text('8').last).right,
        closeTo(16 + 51.33, 0.5),
      );
      expect(
        tester.getRect(find.text('6').last).right,
        closeTo(16 + 51.33, 0.5),
      );
      expect(
        tester.getRect(find.text('42').last).center.dx,
        closeTo(16 + 110.67, 0.5),
      );
      expect(tester.getRect(find.text('PM')).left, closeTo(16 + 158, 0.5));
      final am = tester.getRect(find.text('AM'));
      expect(
        am.center.dy,
        closeTo(tester.getRect(find.text('41').last).center.dy, 1),
      );
    });

    testWidgets('the hour wheel turns AM into PM between 11 and 12', (
      tester,
    ) async {
      final changes = await open(tester);
      final hour = tester.getCenter(find.text('7').last);
      await tester.timedDragFrom(
        hour,
        const Offset(0, -5 * 32.4),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(changes.last, DateTime(2026, 10, 3, 12, 41));
      expect(find.text('12:41 PM'), findsOneWidget);
      await tester.timedDragFrom(
        hour,
        const Offset(0, 3 * 32.4),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(changes.last, DateTime(2026, 10, 3, 9, 41));
      expect(find.text('9:41 AM'), findsOneWidget);
    });

    testWidgets('the AM/PM wheel moves twelve hours', (tester) async {
      final changes = await open(tester);
      await tester.timedDragFrom(
        tester.getCenter(find.text('AM')),
        const Offset(0, -32.4),
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(changes.last, DateTime(2026, 10, 3, 19, 41));
    });
  });

  group('GlassTimePicker with a value the app sets', () {
    testWidgets('an hour across noon jumps the AM/PM wheel', (tester) async {
      await tester.binding.setSurfaceSize(const Size(402, 874));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Widget picker(DateTime value) => _App(
        home: Center(
          child: GlassTimePicker(
            value: value,
            use24HourFormat: false,
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pumpWidget(picker(DateTime(2026, 10, 3, 9, 41)));
      await tester.pump();
      FixedExtentScrollController meridiem() =>
          tester
                  .widgetList<ListWheelScrollView>(
                    find.byType(ListWheelScrollView),
                  )
                  .last
                  .controller!
              as FixedExtentScrollController;
      expect(meridiem().selectedItem, 0);
      await tester.pumpWidget(picker(DateTime(2026, 10, 3, 21, 41)));
      expect(meridiem().selectedItem, 1);
    });
  });

  group('GlassDatePicker month and year wheels', () {
    Future<List<DateTime>> open(
      WidgetTester tester, {
      DateTime? start,
      TextDirection direction = TextDirection.ltr,
    }) async {
      await tester.binding.setSurfaceSize(const Size(402, 874));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final changes = <DateTime>[];
      var value = start ?? DateTime(2026, 10, 3, 7, 41);
      await tester.pumpWidget(
        _App(
          builder: (BuildContext context, Widget? child) =>
              Directionality(textDirection: direction, child: child!),
          home: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) => Align(
              alignment: const Alignment(0, -0.3135),
              child: GlassCompactDatePicker(
                value: value,
                today: DateTime(2026, 10, 3),
                onChanged: (DateTime v) {
                  changes.add(v);
                  setState(() => value = v);
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(GlassCompactDatePicker));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      return changes;
    }

    Finder title(String text) => find.descendant(
      of: find.bySemanticsLabel(RegExp('year picker')),
      matching: find.text(text),
    );

    testWidgets('a tap on the month title shows the wheels', (tester) async {
      final changes = await open(tester);
      expect(find.byType(ListWheelScrollView), findsNothing);
      await tester.tap(find.text('October 2026'));
      await tester.pump();
      expect(find.byType(ListWheelScrollView), findsNWidgets(2));
      final accent = tester.widget<Text>(find.text('October 2026'));
      expect(accent.style?.color, _accent);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(find.bySemanticsLabel('Hide year picker'), findsOneWidget);
      expect(find.text('October'), findsWidgets);
      expect(find.text('2026'), findsWidgets);
      // The day grid is hidden and does not take taps.
      await tester.tapAt(tester.getCenter(find.text('15')));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(changes, isEmpty);
      // The chevron points down.
      final m = tester
          .renderObject(
            find
                .descendant(
                  of: find.bySemanticsLabel('Hide year picker'),
                  matching: find.byType(CustomPaint),
                )
                .first,
          )
          .getTransformTo(null);
      expect(
        math.atan2(m.entry(1, 0), m.entry(0, 0)),
        closeTo(math.pi / 2, 1e-6),
      );
      await tester.tap(find.text('October 2026'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(find.byType(ListWheelScrollView), findsNothing);
      expect(find.bySemanticsLabel('Show year picker'), findsOneWidget);
      final label = tester.widget<Text>(find.text('October 2026'));
      expect(label.style?.color, _black);
    });

    testWidgets("the change runs 0.25 s after UIKit's delay", (tester) async {
      await open(tester);
      await tester.tap(find.text('October 2026'));
      await tester.pump();
      double wheels() => tester
          .widgetList<MotionTransition>(
            find.ancestor(
              of: find.byType(ListWheelScrollView).first,
              matching: find.byType(MotionTransition),
            ),
          )
          .where((w) => w.opacity != null)
          .first
          .opacity!
          .value;
      await tester.pump(const Duration(milliseconds: 60));
      expect(wheels(), 0);
      await tester.pump(const Duration(milliseconds: 134));
      expect(wheels(), closeTo(0.5, 0.08));
      await tester.pump(const Duration(milliseconds: 150));
      expect(wheels(), 1);
    });

    testWidgets('the wheels sit where UIKit puts them', (tester) async {
      await open(tester);
      await tester.tap(find.text('October 2026'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      // month-year.json, relative to the platter's top-left (16 points
      // from the side; its top from the title, centered 34.84 down): the
      // rows outside the band start their month 57.95 points in and center
      // their year 229.83 in, the selected row 184.84 down, its neighbours
      // 31.2 and 58.3 away. The band's larger copy is the same row
      // magnified about the month box's center, so its month starts at 54.
      const left = 16.0;
      final top = tester.getRect(find.text('October 2026')).center.dy - 34.84;
      final october = tester.getRect(find.text('October').last);
      expect(october.left, closeTo(left + 57.95, 0.6));
      expect(october.center.dy, closeTo(top + 184.84, 0.6));
      final year = tester.getRect(find.text('2026').last);
      expect(year.center.dx, closeTo(left + 229.83, 0.6));
      final november = tester.getRect(find.text('November').last);
      expect(november.left, closeTo(left + 57.95, 0.6));
      expect(november.center.dy - october.center.dy, closeTo(31.2, 0.8));
      final august = tester.getRect(find.text('August').last);
      expect(august.center.dy - october.center.dy, closeTo(-58.3, 0.8));
    });

    testWidgets('a turned wheel moves the shown month and the value', (
      tester,
    ) async {
      final changes = await open(tester);
      await tester.tap(find.text('October 2026'));
      // The wheels fade in after UIKit's delay, which the clock waits
      // out on a timer that pumpAndSettle alone does not reach.
      await tester.pump();
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      await tester.timedDrag(
        find.text('October').last,
        const Offset(0, -50),
        const Duration(milliseconds: 800),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(changes.last, DateTime(2026, 11, 3, 7, 41));
      expect(title('November 2026'), findsOneWidget);
      await tester.timedDrag(
        find.text('2026').last,
        const Offset(0, 50),
        const Duration(milliseconds: 800),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(changes.last, DateTime(2025, 11, 3, 7, 41));
      await tester.tap(find.text('November 2025'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(find.byType(ListWheelScrollView), findsNothing);
      expect(find.text('Nov 3, 2025'), findsOneWidget);
    });

    testWidgets('the 31st turned to November is the 30th', (tester) async {
      final changes = await open(tester, start: DateTime(2026, 10, 31, 8, 41));
      await tester.tap(find.text('October 2026'));
      // The wheels fade in after UIKit's delay, which the clock waits
      // out on a timer that pumpAndSettle alone does not reach.
      await tester.pump();
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      await tester.timedDrag(
        find.text('October').last,
        const Offset(0, -50),
        const Duration(milliseconds: 800),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(changes.last, DateTime(2026, 11, 30, 8, 41));
      await tester.timedDrag(
        find.text('November').last,
        const Offset(0, 50),
        const Duration(milliseconds: 800),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(changes.last, DateTime(2026, 10, 30, 8, 41));
    });

    testWidgets('the wheels open on the shown month', (tester) async {
      final changes = await open(tester);
      await tester.tap(find.bySemanticsLabel('Next month'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      await tester.tap(find.text('November 2026'));
      // The wheels fade in after UIKit's delay, which the clock waits
      // out on a timer that pumpAndSettle alone does not reach.
      await tester.pump();
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(changes, isEmpty);
      final november = tester.getRect(find.text('November').last);
      final band = tester.getRect(find.text('2026').last);
      expect(november.center.dy, closeTo(band.center.dy, 0.5));
      await tester.timedDrag(
        find.text('November').last,
        const Offset(0, -50),
        const Duration(milliseconds: 800),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(changes, [DateTime(2026, 12, 3, 7, 41)]);
    });

    testWidgets('a second tap turns the change around', (tester) async {
      await open(tester);
      await tester.tap(find.text('October 2026'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(find.text('October 2026'));
      await tester.pump();
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(find.byType(ListWheelScrollView), findsNothing);
      expect(find.bySemanticsLabel('Show year picker'), findsOneWidget);
    });

    testWidgets('screen readers adjust the month and the year', (tester) async {
      final semantics = tester.ensureSemantics();
      final changes = await open(tester);
      await tester.tap(find.text('October 2026'));
      // The wheels fade in after UIKit's delay, which the clock waits
      // out on a timer that pumpAndSettle alone does not reach.
      await tester.pump();
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      final month = find.bySemanticsLabel('Month');
      expect(tester.getSemantics(month).value, 'October');
      tester.semantics.increase(find.semantics.byLabel('Month'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(changes.last, DateTime(2026, 11, 3, 7, 41));
      final year = find.bySemanticsLabel('Year');
      expect(tester.getSemantics(year).value, '2026');
      tester.semantics.decrease(find.semantics.byLabel('Year'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(changes.last, DateTime(2025, 11, 3, 7, 41));
      semantics.dispose();
    });

    testWidgets('a six-week month keeps the platter and packs its rows', (
      tester,
    ) async {
      await open(tester, start: DateTime(2026, 8, 15, 7, 41));
      // August 2026 on an iPhone 16 Pro: the platter stays 320 x 332, the
      // six rows 38 apart, the chosen day's disc 38 across.
      final one = tester.getCenter(find.text('1'));
      final eight = tester.getCenter(find.text('8'));
      expect(eight.dy - one.dy, closeTo(38, 0.01));
      expect(_dayCell(tester, '15', 'disc'), 38);
      final top = tester.getRect(find.text('August 2026')).center.dy - 34.84;
      expect(tester.getCenter(find.text('1')).dy, closeTo(top + 105.34, 0.6));
      expect(tester.getCenter(find.text('31')).dy, closeTo(top + 295.34, 0.6));
    });
  });

  group('RawGlassDatePicker', () {
    Future<List<DateTime>> pump(
      WidgetTester tester, {
      TextDirection direction = TextDirection.ltr,
      DateTime? value,
      FocusNode? focusNode,
    }) async {
      final picked = <DateTime>[];
      var current = value ?? DateTime(2026, 10, 3, 9, 41);
      await tester.pumpWidget(
        _App(
          builder: (BuildContext context, Widget? child) =>
              Directionality(textDirection: direction, child: child!),
          home: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) => Center(
              child: RawGlassDatePicker(
                value: current,
                today: DateTime(2026, 10, 3),
                focusNode: focusNode,
                onChanged: (DateTime v) {
                  picked.add(v);
                  setState(() => current = v);
                },
                dayBuilder: (context, day) => SizedBox.fromSize(
                  size: day.size,
                  child: Center(child: Text('${day.date.day}')),
                ),
                titleBuilder: (context, title) => Text(title.text),
                arrowBuilder: (context, arrow) =>
                    Center(child: Text(arrow.next ? '>' : '<')),
                weekdayBuilder: (context, label) => Text(label),
                monthYearBuilder: (context, details) => const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return picked;
    }

    testWidgets('the outer columns keep 44-point targets', (tester) async {
      final handle = tester.ensureSemantics();
      final picked = await pump(tester);
      // October 2026 in weeks from Sunday: the 4th opens a row, the 3rd
      // closes one.
      for (final (day, edge) in [('4', -0.5), ('3', 0.5)]) {
        final node = tester.getSemantics(find.text(day));
        final rect = switch (node.transform) {
          final transform? => MatrixUtils.transformRect(transform, node.rect),
          null => node.rect,
        };
        expect(rect.width, greaterThanOrEqualTo(44 - 0.01), reason: day);
        final cell = tester.getRect(
          find
              .ancestor(of: find.text(day), matching: find.byType(SizedBox))
              .first,
        );
        await tester.tapAt(
          (edge < 0 ? cell.centerLeft : cell.centerRight) + Offset(edge, 0),
        );
        await tester.pumpAndSettle();
        expect(picked.last.day, int.parse(day));
      }
      handle.dispose();
    });

    String? focusedLabel(WidgetTester tester) {
      String? found;
      bool visit(SemanticsNode node) {
        final data = node.getSemanticsData();
        if (data.flagsCollection.isFocused == Tristate.isTrue) {
          found = data.label;
          return false;
        }
        node.visitChildren(visit);
        return found == null;
      }

      final root = tester.binding.renderViews.first.owner!.semanticsOwner!;
      visit(root.rootSemanticsNode!);
      return found;
    }

    testWidgets('an arrow that turns the month takes the focus along', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      // Weeks from Sunday: October 2026 ends on a Saturday, November 2026
      // starts on a Sunday.
      for (final (direction, month, start, key, lands) in [
        (TextDirection.ltr, 10, 31, LogicalKeyboardKey.arrowDown, 'November 7'),
        (TextDirection.ltr, 10, 3, LogicalKeyboardKey.arrowUp, 'September 26'),
        (
          TextDirection.ltr,
          10,
          31,
          LogicalKeyboardKey.arrowRight,
          'November 1',
        ),
        (TextDirection.ltr, 11, 1, LogicalKeyboardKey.arrowLeft, 'October 31'),
        (TextDirection.rtl, 10, 31, LogicalKeyboardKey.arrowLeft, 'November 1'),
        (TextDirection.rtl, 11, 1, LogicalKeyboardKey.arrowRight, 'October 31'),
        (TextDirection.rtl, 10, 31, LogicalKeyboardKey.arrowDown, 'November 7'),
      ]) {
        final node = FocusNode();
        await tester.pumpWidget(const SizedBox());
        final picked = await pump(
          tester,
          direction: direction,
          value: DateTime(2026, month, start, 9, 41),
          focusNode: node,
        );
        node.requestFocus();
        await tester.pumpAndSettle();
        expect(focusedLabel(tester), contains(' $start, 2026'));
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(
          focusedLabel(tester),
          contains('$lands, 2026'),
          reason: '$direction $key',
        );
        expect(picked, isEmpty);
        await tester.pumpWidget(const SizedBox());
        node.dispose();
      }
      handle.dispose();
    });
  });

  group('GlassCompactDatePicker in a narrow box', () {
    Future<Rect> labels(WidgetTester tester, double? width) async {
      await tester.pumpWidget(
        _App(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: Align(
                alignment: Alignment.centerLeft,
                child: GlassCompactDatePicker(
                  value: DateTime(2026, 10, 3, 9, 41),
                  mode: GlassDatePickerMode.dateAndTime,
                  today: DateTime(2026, 10, 3),
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getRect(
        find
            .descendant(
              of: find.byType(GlassCompactDatePicker),
              matching: find.byType(Row),
            )
            .first,
      );
    }

    testWidgets('scales its labels down instead of overflowing', (
      tester,
    ) async {
      final natural = await labels(tester, null);
      expect(await labels(tester, natural.right), natural);
      final narrow = await labels(tester, 60);
      expect(tester.takeException(), isNull);
      expect(narrow.right, lessThanOrEqualTo(60));
      expect(narrow.width / natural.width, closeTo(60 / natural.right, 0.01));
      await labels(tester, 0);
      expect(tester.takeException(), isNull);
    });
  });
}
