import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  setUp(MotionClock.debugReset);

  Future<({GlobalKey<NavigatorState> navigator, FocusNode opener})> open(
    WidgetTester tester, {
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
    unawaited(
      navigator.currentState!.push(
        GlassPageRoute<void>(
          builder: (context) => const ColoredBox(
            color: Color(0xFFFFFFFF),
            child: Center(child: Text('Page')),
          ),
        ),
      ),
    );
    await settle(tester);
    return (navigator: navigator, opener: opener);
  }

  double left(WidgetTester tester) => tester.getTopLeft(find.text('Page')).dx;

  testWidgets('Escape pops the page and focus goes back to the opener', (
    tester,
  ) async {
    final page = await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text('Page'), findsNothing);
    expect(page.opener.hasPrimaryFocus, isTrue);
  });

  testWidgets('predictive back slides the page with the gesture and pops it '
      'on commit', (tester) async {
    final page = await open(tester);
    final rest = left(tester);
    final navigator = page.navigator.currentState!;
    await backTo(tester, 0.3);
    expect(navigator.userGestureInProgress, isTrue);
    final moved = left(tester) - rest;
    expect(moved, closeTo(0.3 * 402, 1));
    expect(find.text('Opener'), findsOneWidget);
    await backGesture(tester, 'commitBackGesture');
    await settle(tester);
    expect(find.text('Page'), findsNothing);
    expect(navigator.userGestureInProgress, isFalse);
  });

  testWidgets('in right to left the page slides toward the left', (
    tester,
  ) async {
    await open(tester, direction: TextDirection.rtl);
    final rest = left(tester);
    await backTo(tester, 0.3);
    expect(left(tester) - rest, closeTo(-0.3 * 402, 1));
    await backGesture(tester, 'commitBackGesture');
    await settle(tester);
    expect(find.text('Page'), findsNothing);
  });

  testWidgets('a cancelled predictive back returns the page', (tester) async {
    final page = await open(tester);
    final rest = left(tester);
    final navigator = page.navigator.currentState!;
    await backTo(tester, 0.4);
    await backGesture(tester, 'cancelBackGesture');
    await settle(tester);
    expect(left(tester), rest);
    expect(navigator.userGestureInProgress, isFalse);
    expect(navigator.canPop(), isTrue);
    await backTo(tester, 0.2);
    expect(navigator.userGestureInProgress, isTrue);
    await backGesture(tester, 'commitBackGesture');
    await settle(tester);
    expect(find.text('Page'), findsNothing);
  });

  testWidgets('a page a PopScope keeps takes no predictive back', (
    tester,
  ) async {
    phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    final opener = FocusNode();
    addTearDown(opener.dispose);
    await tester.pumpWidget(overlayApp(navigator, opener: opener));
    unawaited(
      navigator.currentState!.push(
        GlassPageRoute<void>(
          builder: (context) =>
              const PopScope(canPop: false, child: Center(child: Text('Page'))),
        ),
      ),
    );
    await settle(tester);
    final rest = left(tester);
    await backTo(tester, 0.3);
    expect(navigator.currentState!.userGestureInProgress, isFalse);
    expect(left(tester), rest);
    await backGesture(tester, 'commitBackGesture');
    await settle(tester);
    expect(find.text('Page'), findsOneWidget);
  });
}
