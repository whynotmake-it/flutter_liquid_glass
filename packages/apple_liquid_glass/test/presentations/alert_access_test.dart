import 'dart:async';
import 'dart:ui' show SemanticsAction, SemanticsRole;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _cancel = GlassAlertAction.cancel(child: Text('Cancel'));
const _keep = GlassAlertAction(child: Text('Keep'));
const _save = GlassAlertAction(isDefaultAction: true, child: Text('Save'));

void main() {
  setUp(MotionClock.debugReset);

  Future<
    ({
      GlobalKey<NavigatorState> navigator,
      FocusNode opener,
      List<GlassAlertAction?> results,
    })
  >
  open(
    WidgetTester tester, {
    List<GlassAlertAction> actions = const [_keep, _save, _cancel],
    TextDirection direction = TextDirection.ltr,
    bool sheet = false,
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
    final results = <GlassAlertAction?>[];
    final context = navigator.currentContext!;
    unawaited(
      (sheet
              ? showGlassActionSheet(
                  context,
                  title: const Text('Share'),
                  actions: actions,
                )
              : showGlassAlert(
                  context,
                  title: const Text('Save changes?'),
                  actions: actions,
                ))
          .then(results.add),
    );
    await settle(tester);
    return (navigator: navigator, opener: opener, results: results);
  }

  testWidgets('focus goes to the default action and back to the opener', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final alert = await open(tester);
    expect(focusedLabel(tester), 'Save');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(alert.results, [_cancel]);
    expect(alert.opener.hasPrimaryFocus, isTrue);
    semantics.dispose();
  });

  testWidgets('Tab cycles through the actions inside the alert', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    final seen = <String?>[];
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      seen.add(focusedLabel(tester));
    }
    expect(seen, ['Cancel', 'Keep', 'Save', 'Cancel']);
    semantics.dispose();
  });

  testWidgets('the arrows move between the actions and Return chooses the '
      'focused one', (tester) async {
    final semantics = tester.ensureSemantics();
    final alert = await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(focusedLabel(tester), 'Keep');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusedLabel(tester), 'Cancel');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(alert.results, [_keep]);
    semantics.dispose();
  });

  testWidgets('Space chooses the focused action too', (tester) async {
    final alert = await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await settle(tester);
    expect(alert.results, [_save]);
  });

  testWidgets('in right to left a row of two puts cancel on the right, and '
      'the arrows follow the screen', (tester) async {
    final semantics = tester.ensureSemantics();
    const delete = GlassAlertAction.destructive(
      isDefaultAction: true,
      child: Text('Delete'),
    );
    final alert = await open(
      tester,
      actions: const [_cancel, delete],
      direction: TextDirection.rtl,
    );
    final cancel = tester.getCenter(find.text('Cancel'));
    final remove = tester.getCenter(find.text('Delete'));
    expect(cancel.dy, remove.dy);
    expect(cancel.dx, greaterThan(remove.dx));
    expect(focusedLabel(tester), 'Delete');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(focusedLabel(tester), 'Cancel');
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(alert.results, [delete]);
    semantics.dispose();
  });

  testWidgets('screen readers hear an alert dialog named by its title, '
      'with each action a button they can press', (tester) async {
    final semantics = tester.ensureSemantics();
    final alert = await open(tester);
    final route = routeNode(tester, SemanticsRole.alertDialog);
    expect(route.label, 'Save changes?');
    expect(route.getSemanticsData().flagsCollection.namesRoute, isTrue);
    final keep = tester.getSemantics(find.bySemanticsLabel('Keep'));
    expect(keep.getSemanticsData().flagsCollection.isButton, isTrue);
    expect(keep.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(keep.rect.height, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel('Keep'), findsOneWidget);
    perform(tester, find.bySemanticsLabel('Keep'), SemanticsAction.tap);
    await settle(tester);
    expect(alert.results, [_keep]);
    semantics.dispose();
  });

  testWidgets('an alert without a cancel action stays on Escape and Back; '
      'its barrier offers no dismissal', (tester) async {
    final semantics = tester.ensureSemantics();
    final alert = await open(tester, actions: const [_keep, _save]);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(await alert.navigator.currentState!.maybePop(), isTrue);
    await settle(tester);
    expect(alert.results, isEmpty);
    expect(find.text('Save changes?'), findsOneWidget);
    expect(find.bySemanticsLabel('Dismiss action sheet'), findsNothing);
    semantics.dispose();
  });

  testWidgets('Back chooses the cancel action', (tester) async {
    final alert = await open(tester);
    await alert.navigator.currentState!.maybePop();
    await settle(tester);
    expect(alert.results, [_cancel]);
  });

  testWidgets('an action sheet is a dialog, not an alert, and labels its '
      'dimming, which screen readers dismiss it by', (tester) async {
    final semantics = tester.ensureSemantics();
    final sheet = await open(tester, sheet: true);
    routeNode(tester, SemanticsRole.dialog);
    final barrier = tester.getSemantics(
      find.bySemanticsLabel('Dismiss action sheet'),
    );
    final data = barrier.getSemanticsData();
    expect(
      data.hasAction(SemanticsAction.tap) ||
          data.hasAction(SemanticsAction.dismiss),
      isTrue,
    );
    perform(
      tester,
      find.bySemanticsLabel('Dismiss action sheet'),
      SemanticsAction.tap,
    );
    await settle(tester);
    expect(sheet.results, [_cancel]);
    semantics.dispose();
  });

  testWidgets('a finger slides across the actions and chooses where it lifts', (
    tester,
  ) async {
    final alert = await open(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Keep')),
    );
    await tester.pump(frame);
    await gesture.moveTo(tester.getCenter(find.text('Save')));
    await tester.pump(frame);
    await gesture.moveTo(tester.getCenter(find.text('Cancel')));
    await tester.pump(frame);
    await gesture.up();
    await settle(tester);
    expect(alert.results, [_cancel]);
  });

  group('predictive back', () {
    testWidgets('fades the alert with the gesture and cancels it on commit', (
      tester,
    ) async {
      final alert = await open(tester);
      final navigator = alert.navigator.currentState!;
      await backTo(tester, 0.5);
      expect(navigator.userGestureInProgress, isTrue);
      expect(alert.results, isEmpty);
      await backGesture(tester, 'commitBackGesture');
      await settle(tester);
      expect(alert.results, [_cancel]);
      expect(find.text('Save changes?'), findsNothing);
      expect(navigator.userGestureInProgress, isFalse);
    });

    testWidgets('springs back on cancel', (tester) async {
      final alert = await open(tester);
      final navigator = alert.navigator.currentState!;
      await backTo(tester, 0.6);
      await backGesture(tester, 'cancelBackGesture');
      await settle(tester);
      expect(alert.results, isEmpty);
      expect(find.text('Save changes?'), findsOneWidget);
      expect(navigator.userGestureInProgress, isFalse);
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(alert.results, [_save]);
    });

    testWidgets('is not taken by an alert that Back may not close', (
      tester,
    ) async {
      final alert = await open(tester, actions: const [_keep, _save]);
      await backTo(tester, 0.5);
      expect(alert.navigator.currentState!.userGestureInProgress, isFalse);
      await backGesture(tester, 'commitBackGesture');
      await settle(tester);
      expect(find.text('Save changes?'), findsOneWidget);
    });
  });
}
