import 'dart:async';
import 'dart:ui' show SemanticsAction, SemanticsRole;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  setUp(MotionClock.debugReset);

  Future<
    ({
      GlobalKey<NavigatorState> navigator,
      FocusNode opener,
      List<GlassSheetDetent> changes,
    })
  >
  open(
    WidgetTester tester, {
    List<GlassSheetDetent> detents = const [
      GlassSheetDetent.medium,
      GlassSheetDetent.large,
    ],
    bool showDragHandle = true,
    bool isDismissible = true,
    TextDirection direction = TextDirection.ltr,
  }) async {
    phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    final opener = FocusNode(debugLabel: 'opener');
    addTearDown(opener.dispose);
    await tester.pumpWidget(
      overlayApp(navigator, opener: opener, direction: direction),
    );
    opener.requestFocus();
    await tester.pump();
    final changes = <GlassSheetDetent>[];
    unawaited(
      showGlassSheet<void>(
        navigator.currentContext!,
        detents: detents,
        showDragHandle: showDragHandle,
        isDismissible: isDismissible,
        semanticLabel: 'Details',
        onDetentChanged: changes.add,
        builder: (context) => const Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: 60),
            child: Text('Body'),
          ),
        ),
      ),
    );
    await settle(tester);
    return (navigator: navigator, opener: opener, changes: changes);
  }

  Finder grabber() => find.bySemanticsLabel('Sheet grabber');

  double top(WidgetTester tester) => tester.getTopLeft(find.text('Body')).dy;

  testWidgets('screen readers hear a dialog named by its label, and the '
      'labelled dimming dismisses it', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester, detents: const [GlassSheetDetent.large]);
    final route = routeNode(tester, SemanticsRole.dialog);
    expect(route.label, 'Details');
    final barrier = find.bySemanticsLabel('Dismiss sheet');
    expect(barrier, findsOneWidget);
    perform(tester, barrier, SemanticsAction.tap);
    await settle(tester);
    expect(find.text('Body'), findsNothing);
    semantics.dispose();
  });

  testWidgets('a sheet that may not be dismissed offers no dismissal on its '
      'dimming', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester, isDismissible: false);
    expect(find.bySemanticsLabel('Dismiss sheet'), findsNothing);
    semantics.dispose();
  });

  testWidgets('the grabber is a labelled 44 point target whose value is the '
      'detent, with increase and decrease', (tester) async {
    final semantics = tester.ensureSemantics();
    final sheet = await open(tester);
    final node = tester.getSemantics(grabber());
    var data = node.getSemanticsData();
    expect(node.rect.width, greaterThanOrEqualTo(44));
    expect(node.rect.height, greaterThanOrEqualTo(44));
    expect(data.value, 'Medium');
    expect(data.increasedValue, 'Large');
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    expect(data.hasAction(SemanticsAction.decrease), isFalse);
    final medium = top(tester);
    perform(tester, grabber(), SemanticsAction.increase);
    await settle(tester);
    expect(top(tester), lessThan(medium));
    expect(sheet.changes, [GlassSheetDetent.large]);
    data = tester.getSemantics(grabber()).getSemanticsData();
    expect(data.value, 'Large');
    expect(data.decreasedValue, 'Medium');
    expect(data.hasAction(SemanticsAction.increase), isFalse);
    perform(tester, grabber(), SemanticsAction.decrease);
    await settle(tester);
    expect(top(tester), medium);
    expect(sheet.changes, [GlassSheetDetent.large, GlassSheetDetent.medium]);
    semantics.dispose();
  });

  testWidgets('a tap on the grabber steps the detent; a pull the sheet '
      'follows is no tap, however short', (tester) async {
    final sheet = await open(tester);
    final pull = await tester.startGesture(tester.getCenter(grabber()));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await pull.moveBy(const Offset(0, 5));
    }
    await tester.pump(const Duration(milliseconds: 16));
    await pull.up();
    await settle(tester);
    expect(sheet.changes, isEmpty, reason: 'a 15 point pull, past 12');
    await tester.tapAt(tester.getCenter(grabber()));
    await settle(tester);
    expect(sheet.changes, [GlassSheetDetent.large]);
  });

  testWidgets('a sheet without a drag handle still has the target', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester, showDragHandle: false);
    expect(
      tester.getSemantics(grabber()).getSemanticsData().value,
      'Medium',
    );
    semantics.dispose();
  });

  testWidgets('a single detent without a handle has no grabber', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(
      tester,
      detents: const [GlassSheetDetent.large],
      showDragHandle: false,
    );
    expect(grabber(), findsNothing);
    semantics.dispose();
  });

  testWidgets('the focused grabber steps the detents with the arrows, Home '
      'and End', (tester) async {
    final semantics = tester.ensureSemantics();
    final sheet = await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focusedLabel(tester), 'Sheet grabber');
    final medium = top(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await settle(tester);
    final large = top(tester);
    expect(large, lessThan(medium));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await settle(tester);
    expect(top(tester), large);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await settle(tester);
    expect(top(tester), medium);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await settle(tester);
    expect(top(tester), large);
    expect(sheet.changes, [
      GlassSheetDetent.large,
      GlassSheetDetent.medium,
      GlassSheetDetent.large,
    ]);
    semantics.dispose();
  });

  testWidgets('in right to left the grabber steps the same way', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final sheet = await open(tester, direction: TextDirection.rtl);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focusedLabel(tester), 'Sheet grabber');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await settle(tester);
    expect(sheet.changes, [GlassSheetDetent.large]);
    expect(
      tester.getSemantics(grabber()).getSemanticsData().textDirection,
      TextDirection.rtl,
    );
    semantics.dispose();
  });

  testWidgets('Escape closes it and focus goes back to the opener', (
    tester,
  ) async {
    final sheet = await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text('Body'), findsNothing);
    expect(sheet.opener.hasPrimaryFocus, isTrue);
  });

  testWidgets('it is inert from the start of its close', (tester) async {
    final sheet = await open(tester);
    final band = tester.getTopLeft(find.text('Body')) - const Offset(0, 50);
    final at = Offset(tester.getCenter(find.text('Body')).dx, band.dy);
    await sheet.navigator.currentState!.maybePop();
    await tester.pump(frame);
    await tester.tapAt(at);
    await tester.pump(frame);
    expect(sheet.changes, isEmpty);
    await settle(tester);
    expect(find.text('Body'), findsNothing);
  });

  testWidgets('predictive back drags it down with the gesture and closes it '
      'on commit', (tester) async {
    final sheet = await open(tester);
    final before = top(tester);
    await backTo(tester, 0.5);
    expect(sheet.navigator.currentState!.userGestureInProgress, isTrue);
    expect(top(tester), greaterThan(before));
    await backGesture(tester, 'commitBackGesture');
    await settle(tester);
    expect(find.text('Body'), findsNothing);
    expect(sheet.changes, isEmpty);
  });

  testWidgets('a cancelled predictive back puts it back at its detent', (
    tester,
  ) async {
    final sheet = await open(tester);
    final before = top(tester);
    await backTo(tester, 0.5);
    await backGesture(tester, 'cancelBackGesture');
    await settle(tester);
    expect(top(tester), before);
    expect(sheet.navigator.currentState!.userGestureInProgress, isFalse);
    expect(sheet.changes, isEmpty);
  });
}
