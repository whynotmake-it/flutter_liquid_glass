import 'dart:async';
import 'dart:ui' show SemanticsAction, SemanticsRole;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

class _Content extends StatelessWidget {
  const _Content({required this.taps});

  final List<String> taps;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final name in ['First', 'Second'])
          GlassButton(
            onPressed: () => taps.add(name),
            child: Text(name),
          ),
      ],
    ),
  );
}

void main() {
  setUp(MotionClock.debugReset);

  Future<
    ({GlobalKey<NavigatorState> navigator, FocusNode opener, List<String> taps})
  >
  open(WidgetTester tester, {bool keyboard = false}) async {
    phone(tester);
    if (keyboard) {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
    }
    final navigator = GlobalKey<NavigatorState>();
    final opener = FocusNode(debugLabel: 'opener');
    addTearDown(opener.dispose);
    await tester.pumpWidget(overlayApp(navigator, opener: opener));
    opener.requestFocus();
    await tester.pump();
    final taps = <String>[];
    unawaited(
      showGlassPopover<void>(
        navigator.currentContext!,
        anchorRect: const Rect.fromLTWH(180, 600, 40, 40),
        adaptsToSheet: false,
        semanticLabel: 'Options',
        builder: (context) => _Content(taps: taps),
      ),
    );
    await settle(tester);
    return (navigator: navigator, opener: opener, taps: taps);
  }

  testWidgets('screen readers hear a dialog named by its label, and the '
      'labelled dimming dismisses it', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    final route = routeNode(tester, SemanticsRole.dialog);
    expect(route.label, 'Options');
    final barrier = find.bySemanticsLabel('Dismiss popover');
    expect(barrier, findsOneWidget);
    perform(tester, barrier, SemanticsAction.tap);
    await settle(tester);
    expect(find.text('First'), findsNothing);
    semantics.dispose();
  });

  testWidgets('with the keyboard in use focus goes to the first control, '
      'Tab stays inside and Escape hands focus back to the opener', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final popover = await open(tester, keyboard: true);
    expect(focusedLabel(tester), 'First');
    final seen = <String?>[];
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      seen.add(focusedLabel(tester));
    }
    expect(seen, ['Second', 'First', 'Second']);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text('First'), findsNothing);
    expect(popover.opener.hasPrimaryFocus, isTrue);
    semantics.dispose();
  });

  testWidgets('it is inert from the start of its close', (tester) async {
    final popover = await open(tester);
    final first = tester.getCenter(find.text('First'));
    await popover.navigator.currentState!.maybePop();
    await tester.pump(frame);
    await tester.tapAt(first);
    await settle(tester);
    expect(popover.taps, isEmpty);
  });

  testWidgets('predictive back shrinks it with the gesture and closes it on '
      'commit', (tester) async {
    final popover = await open(tester);
    final before = tester.getRect(find.text('First'));
    await backTo(tester, 0.5);
    expect(popover.navigator.currentState!.userGestureInProgress, isTrue);
    expect(tester.getRect(find.text('First')).width, lessThan(before.width));
    await backGesture(tester, 'commitBackGesture');
    await settle(tester);
    expect(find.text('First'), findsNothing);
  });

  testWidgets('a cancelled predictive back springs it back', (tester) async {
    final popover = await open(tester);
    final before = tester.getRect(find.text('First'));
    await backTo(tester, 0.5);
    await backGesture(tester, 'cancelBackGesture');
    await settle(tester);
    expect(tester.getRect(find.text('First')), before);
    expect(popover.navigator.currentState!.userGestureInProgress, isFalse);
    await tester.tap(find.text('Second'));
    await tester.pump();
    expect(popover.taps, ['Second']);
  });
}
