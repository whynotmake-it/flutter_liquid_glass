import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

Widget _app(Widget child, {GlassThemeData theme = const GlassThemeData()}) =>
    MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GlassScope(
          renderer: const FlatGlassRenderer(),
          data: theme.merge(
            const GlassThemeData(),
          ),
          child: Center(child: SizedBox(width: 340, child: child)),
        ),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(_frame);
  }
}

GlassFrame _frameOf(WidgetTester tester) =>
    tester.widget<GlassSurface>(find.byType(GlassSurface)).frame!.value;

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('typing reports the text; the clear button clears it', (
    tester,
  ) async {
    final changes = <String>[];
    await tester.pumpWidget(_app(GlassSearchField(onChanged: changes.add)));
    expect(find.text('Search'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'glass');
    await tester.pump();
    expect(changes.last, 'glass');
    expect(find.text('Search'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Clear text'));
    await tester.pump();
    expect(changes.last, '');
    expect(find.text('Search'), findsOneWidget);
    expect(find.bySemanticsLabel('Clear text'), findsNothing);
  });

  testWidgets('a press lifts the capsule after its delay; a tap focuses', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(_app(GlassSearchField(focusNode: focus)));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GlassSearchField)) - const Offset(140, 0),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(_frame);
    }
    expect(_frameOf(tester).scaleX, greaterThan(1));
    expect(_frameOf(tester).scaleX, _frameOf(tester).scaleY);
    await gesture.up();
    await _settle(tester);
    expect(focus.hasFocus, isTrue);
    expect(_frameOf(tester).scaleX, 1);
  });

  testWidgets('submitting reports the text', (tester) async {
    final submitted = <String>[];
    await tester.pumpWidget(_app(GlassSearchField(onSubmitted: submitted.add)));
    await tester.enterText(find.byType(EditableText), 'lens');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(submitted, ['lens']);
  });

  testWidgets('disabled it drops its glass for a plain fill and takes no '
      'focus', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _app(GlassSearchField(focusNode: focus, enabled: false)),
    );
    final surface = tester.widget<GlassSurface>(find.byType(GlassSurface));
    expect(surface.role, GlassRole.track);
    expect(surface.glass.tint, GlassSearchField.disabledFill);
    await tester.tap(find.byType(GlassSearchField), warnIfMissed: false);
    await _settle(tester);
    expect(focus.hasFocus, isFalse);
  });

  testWidgets('it reads as a search field with its label', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        const GlassSearchField(
          placeholder: Text('Find a song'),
          semanticLabel: 'Songs',
        ),
      ),
    );
    expect(find.text('Find a song'), findsOneWidget);
    expect(find.bySemanticsLabel('Songs'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the theme styles the text and the placeholder follows the '
      'focus', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _app(
        GlassSearchField(focusNode: focus),
        theme: const GlassThemeData(
          styles: [
            GlassSearchFieldStyle(
              foregroundColor: WidgetStatePropertyAll(Color(0xFF123456)),
            ),
          ],
        ),
      ),
    );
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.style.color, isSameColorAs(const Color(0xFF123456)));
    Color placeholder() => tester
        .widget<DefaultTextStyle>(
          find
              .ancestor(
                of: find.text('Search'),
                matching: find.byType(DefaultTextStyle),
              )
              .first,
        )
        .style
        .color!;
    expect(placeholder(), isSameColorAs(const Color(0x69000000)));
    focus.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(placeholder(), isSameColorAs(const Color(0x993C3C43)));
  });

  testWidgets('a raw field types through its look and clears on request', (
    tester,
  ) async {
    final changes = <String>[];
    final states = <Set<WidgetState>>[];
    late GlassSearchFieldDetails seen;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _app(
        RawGlassSearchField(
          focusNode: focus,
          onChanged: changes.add,
          builder: (context, details) {
            seen = details;
            states.add(details.states);
            return details.text(
              style: const TextStyle(fontSize: 17),
              cursorColor: const Color(0xFF0000FF),
              backgroundCursorColor: const Color(0xFF808080),
            );
          },
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(RawGlassSearchField)).height,
      RawGlassSearchField.height,
    );
    focus.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(states.last, contains(WidgetState.focused));
    await tester.enterText(find.byType(EditableText), 'glass');
    await tester.pump();
    expect(seen.controller.text, 'glass');
    seen.clear!();
    await tester.pump();
    expect(changes, ['glass', '']);
    expect(seen.controller.text, isEmpty);
  });
}
