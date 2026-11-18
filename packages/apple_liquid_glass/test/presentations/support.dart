import 'dart:ui' show SemanticsAction, SemanticsRole, Tristate;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// One frame at 60 Hz.
const Duration frame = Duration(milliseconds: 16);

/// A phone's screen, 402 by 874 points at 3x.
void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Pumps a second of frames.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(frame);
  }
}

/// An app whose home holds an opener: a focusable box with [opener] as its
/// node, that overlays are shown from and that focus returns to.
Widget overlayApp(
  GlobalKey<NavigatorState> navigator, {
  required FocusNode opener,
  TextDirection direction = TextDirection.ltr,
}) => WidgetsApp(
  navigatorKey: navigator,
  color: const Color(0xFF000000),
  pageRouteBuilder: <T>(settings, builder) =>
      GlassPageRoute<T>(builder: builder, settings: settings),
  builder: (context, child) => Directionality(
    textDirection: direction,
    child: GlassScope(renderer: const FlatGlassRenderer(), child: child!),
  ),
  home: ColoredBox(
    color: const Color(0xFFFFFFFF),
    child: Center(
      child: Focus(
        focusNode: opener,
        child: const SizedBox(width: 80, height: 40, child: Text('Opener')),
      ),
    ),
  ),
);

/// Sends Android's back gesture message [method] at [progress].
Future<void> backGesture(
  WidgetTester tester,
  String method, {
  double progress = 0,
}) async {
  final message = const StandardMethodCodec().encodeMethodCall(
    MethodCall(method, <String, Object?>{
      'touchOffset': const <double>[5, 300],
      'progress': progress,
      'swipeEdge': 0,
    }),
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.backGesture.name,
    message,
    (_) {},
  );
}

/// Runs a back gesture to [progress] and leaves it there, frames pumped
/// between its updates.
Future<void> backTo(WidgetTester tester, double progress) async {
  await backGesture(tester, 'startBackGesture');
  await tester.pump(frame);
  for (final p in [progress / 2, progress]) {
    await backGesture(tester, 'updateBackGestureProgress', progress: p);
    await tester.pump(frame);
    await tester.pump(frame);
  }
}

/// The semantics node of the route an overlay opened: the one that scopes
/// a route and has [role].
SemanticsNode routeNode(WidgetTester tester, SemanticsRole role) {
  SemanticsNode? found;
  bool visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.flagsCollection.scopesRoute && data.role == role) {
      found = node;
      return false;
    }
    node.visitChildren(visit);
    return found == null;
  }

  visit(_root(tester));
  if (found == null) throw TestFailure('no route has the role $role');
  return found!;
}

/// The label of the semantics node that has the input focus, or null.
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

  visit(_root(tester));
  return found;
}

SemanticsNode _root(WidgetTester tester) =>
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!;

/// Performs [action] on the semantics node [finder] finds.
void perform(WidgetTester tester, Finder finder, SemanticsAction action) {
  final node = tester.getSemantics(finder);
  node.owner!.performAction(node.id, action);
}
