import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis/src/presentation/level.dart';

/// A presented motion that records its commands and reports its end only
/// when the test tells it to.
final class _Panel extends Motion with Presented {
  _Panel({required this.leaves});

  final bool leaves;
  final List<DismissTrigger> left = [];
  PresenceStatus _presence = PresenceStatus.hidden;

  @override
  PresenceStatus get presence => _presence;

  @override
  void open(double t) {
    _presence = PresenceStatus.opening;
    changed();
  }

  @override
  bool leave(double t, DismissTrigger trigger) {
    left.add(trigger);
    if (!leaves) return false;
    _presence = PresenceStatus.leaving;
    changed();
    return true;
  }

  void end() {
    _presence = PresenceStatus.hidden;
    changed();
  }
}

/// What a test presentation reports.
final class _Log {
  _Panel? motion;
  final List<DismissTrigger> attempts = [];
  final List<String?> finished = [];
  bool modalNow = true;

  List<DismissTrigger> get left => motion?.left ?? const [];
}

Presentation<T, _Panel> _presentation<T>(
  _Log log, {
  required Widget Function(BuildContext context) builder,
  bool outside = true,
  bool leaves = true,
}) => Presentation<T, _Panel>(
  motion: (_) => log.motion = _Panel(leaves: leaves),
  builder: (context, _) => builder(context),
  dismiss: outside
      ? const DismissPolicy()
      : DismissPolicy(
          DismissPolicy.all.difference({DismissTrigger.outsideTap}),
        ),
  modal: (_) => log.modalNow,
  onVeto: log.attempts.add,
  onDismissed: (Object? result) => log.finished.add(result as String?),
  barrierLabel: 'Dismiss',
);

class _Route extends PresentationRoute<String> {
  _Route({bool allowsPop = true, bool outside = true})
    : this._(_Log(), allowsPop: allowsPop, outside: outside);

  _Route._(this.log, {required this.allowsPop, required bool outside})
    : super(
        presentation: _presentation(
          log,
          outside: outside,
          builder: (_) =>
              const Center(child: SizedBox(width: 100, height: 100)),
        ),
        semanticsLabel: 'Panel',
      );

  final _Log log;
  final bool allowsPop;
  final List<bool> invoked = [];

  List<DismissTrigger> get left => log.left;
  List<DismissTrigger> get attempts => log.attempts;
  List<String?> get finished => log.finished;
  bool get modalNow => log.modalNow;
  set modalNow(bool value) => log.modalNow = value;

  @override
  Widget buildContent(BuildContext context) => PopScope<String>(
    canPop: allowsPop,
    onPopInvokedWithResult: (didPop, _) => invoked.add(didPop),
    child: super.buildContent(context),
  );
}

Widget _app({GlobalKey<NavigatorState>? key, Widget? home}) => WidgetsApp(
  navigatorKey: key,
  color: const Color(0xFF000000),
  pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
    settings: settings,
    pageBuilder: (c, _, _) => builder(c),
  ),
  home: home ?? const SizedBox.expand(),
);

List<String> _labels(WidgetTester tester) {
  final labels = <String>[];
  bool visit(SemanticsNode node) {
    labels.add(node.label);
    node.visitChildren(visit);
    return true;
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return labels;
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('the push completes at the open and the route goes at the '
      "close's end", (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(key: nav));
    final route = _Route();
    String? result;
    unawaited(nav.currentState!.push(route).then((r) => result = r));
    await tester.pump();
    expect(route.animation!.status, AnimationStatus.forward);
    expect(route.animation!.value, 1);
    route.didOpen();
    await tester.pump();
    expect(route.animation!.status, AnimationStatus.completed);
    nav.currentState!.pop('done');
    await tester.pump();
    expect(result, 'done');
    expect(route.left, [DismissTrigger.programmatic]);
    expect(route.isActive, isFalse);
    expect(find.byType(PopScope<String>), findsOneWidget);
    route.log.motion!.end();
    await tester.pump();
    expect(find.byType(PopScope<String>), findsNothing);
    expect(route.finished, ['done']);
  });

  testWidgets('Back goes through the PopScope: a veto keeps the route', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(key: nav));
    final route = _Route(allowsPop: false);
    nav.currentState!.push(route);
    await tester.pump();
    route.didOpen();
    await tester.pump();
    await nav.currentState!.maybePop();
    await tester.pump();
    expect(route.isActive, isTrue);
    expect(route.canDismiss(DismissTrigger.back), isFalse);
    expect(route.canDismiss(DismissTrigger.programmatic), isTrue);
    expect(route.invoked, [false]);
    expect(route.attempts, [DismissTrigger.back]);
    expect(route.left, isEmpty);
  });

  testWidgets('Back pops a route its PopScope lets go, with its close', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(key: nav));
    final route = _Route();
    nav.currentState!.push(route);
    await tester.pump();
    route.didOpen();
    await tester.pump();
    await nav.currentState!.maybePop();
    await tester.pump();
    expect(route.isActive, isFalse);
    expect(route.left, [DismissTrigger.back]);
    expect(route.invoked, [true]);
  });

  testWidgets('Escape dismisses through the gate', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(key: nav));
    final route = _Route();
    nav.currentState!.push(route);
    await tester.pump();
    route.didOpen();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(route.left, [DismissTrigger.escape]);
  });

  testWidgets('an outside tap dismisses only when the route allows it', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(key: nav));
    final kept = _Route(outside: false);
    nav.currentState!.push(kept);
    await tester.pump();
    kept.didOpen();
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(kept.isActive, isTrue);
    nav.currentState!.pop();
    kept.didLeave();
    await tester.pump();
    final route = _Route();
    nav.currentState!.push(route);
    await tester.pump();
    route.didOpen();
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(route.left, [DismissTrigger.outsideTap]);
  });

  testWidgets('the barrier hides the page below from screen readers and '
      'offers a labelled dismiss', (tester) async {
    final semantics = tester.ensureSemantics();
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _app(
        key: nav,
        home: Semantics(label: 'Page below', child: const SizedBox.expand()),
      ),
    );
    expect(_labels(tester), contains('Page below'));
    final route = _Route();
    nav.currentState!.push(route);
    await tester.pump();
    route.didOpen();
    await tester.pump();
    expect(_labels(tester), isNot(contains('Page below')));
    expect(_labels(tester), contains('Dismiss'));
    final panel = tester.getSemantics(find.bySemanticsLabel('Panel'));
    expect(panel.getSemanticsData().hasAction(SemanticsAction.dismiss), isTrue);
    semantics.dispose();
  });

  testWidgets('a route that is not modal lets taps and screen readers reach '
      'the page below', (tester) async {
    final semantics = tester.ensureSemantics();
    final nav = GlobalKey<NavigatorState>();
    var taps = 0;
    await tester.pumpWidget(
      _app(
        key: nav,
        home: Semantics(
          label: 'Page below',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    final route = _Route();
    route.modalNow = false;
    nav.currentState!.push(route);
    await tester.pump();
    await tester.tapAt(const Offset(5, 5));
    expect(taps, 1);
    expect(_labels(tester), contains('Page below'));
    route.modalNow = true;
    route.modalityChanged();
    await tester.pump();
    await tester.tapAt(const Offset(5, 5));
    expect(taps, 1);
    expect(_labels(tester), isNot(contains('Page below')));
    semantics.dispose();
  });

  testWidgets('a dismissed route under another closes under it and then '
      'leaves; the top one stays', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(key: nav));
    final below = _Route();
    nav.currentState!.push(below);
    await tester.pump();
    below.didOpen();
    final above = _Route();
    nav.currentState!.push(above);
    await tester.pump();
    above.didOpen();
    await tester.pump();
    below.dismiss(DismissTrigger.interaction, 'below');
    await tester.pump();
    expect(below.left, [DismissTrigger.interaction]);
    expect(below.isLeaving, isTrue);
    expect(below.finished, isEmpty);
    below.didLeave();
    below.didLeave();
    await tester.pump();
    expect(below.isActive, isFalse);
    expect(below.finished, ['below']);
    expect(above.isActive, isTrue);
    expect(above.isCurrent, isTrue);
  });

  testWidgets('a route closing under its cover keeps its result and its '
      'close when it is popped, and its PopScopes hear it go', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(key: nav));
    final below = _Route();
    String? result;
    unawaited(nav.currentState!.push(below).then((r) => result = r));
    await tester.pump();
    below.didOpen();
    final above = _Route();
    nav.currentState!.push(above);
    await tester.pump();
    below.dismiss(DismissTrigger.programmatic, 'chosen');
    nav.currentState!.pop();
    above.didLeave();
    await tester.pump();
    nav.currentState!.pop('other');
    await tester.pump();
    expect(below.left, [DismissTrigger.programmatic]);
    expect(result, 'chosen');
    below.didLeave();
    await tester.pump();
    expect(below.finished, ['chosen']);
    expect(below.invoked, [true]);
  });

  testWidgets('a refused trigger is reported as a veto; Back on the first '
      'route goes to whatever is outside the navigator', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(key: nav));
    final route = _Route(outside: false);
    nav.currentState!.push(route);
    await tester.pump();
    route.dismiss(DismissTrigger.outsideTap);
    expect(route.attempts, [DismissTrigger.outsideTap]);
    expect(route.isActive, isTrue);
    final first = _Route();
    final own = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        builder: (context, _) => Navigator(
          key: own,
          onGenerateInitialRoutes: (_, _) => [first],
        ),
      ),
    );
    expect(await own.currentState!.maybePop(), isFalse);
    expect(first.left, isEmpty);
  });

  testWidgets('a window presentation from a nested navigator goes to the '
      'outermost one, inside its PresentationContext', (tester) async {
    late BuildContext inner;
    final outer = GlobalKey<NavigatorState>();
    final framed = GlobalKey<NavigatorState>();
    Widget nested(GlobalKey<NavigatorState>? key) => Navigator(
      key: key,
      onGenerateRoute: (_) => PageRouteBuilder<void>(
        pageBuilder: (context, _, _) => Navigator(
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            pageBuilder: (context, _, _) => Builder(
              builder: (context) {
                inner = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(_app(key: outer, home: nested(null)));
    expect(presentationNavigatorOf(inner), outer.currentState);
    expect(
      presentationNavigatorOf(inner, level: PresentationLevel.page),
      isNot(outer.currentState),
    );
    await tester.pumpWidget(
      _app(
        key: outer,
        home: PresentationContext(child: nested(framed)),
      ),
    );
    expect(presentationNavigatorOf(inner), framed.currentState);
  });

  testWidgets('a page runs the same lifecycle: Back closes it through its '
      'content, and it goes at the end of the close', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(key: nav));
    final page = _Page();
    String? result;
    unawaited(nav.currentState!.push(page).then((r) => result = r));
    await tester.pump();
    page.didOpen();
    await tester.pump();
    expect(page.animation!.status, AnimationStatus.completed);
    expect(find.text('page'), findsOneWidget);
    await nav.currentState!.maybePop('back');
    await tester.pump();
    expect(page.left, [DismissTrigger.back]);
    expect(result, 'back');
    expect(find.text('page'), findsOneWidget);
    page.didLeave();
    await tester.pump();
    expect(find.text('page'), findsNothing);
    expect(page.finished, ['back']);
  });

  testWidgets('an interaction shows the page below until it ends, and a '
      'dismissal it makes closes the page', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _app(
        key: nav,
        home: const Text('home', textDirection: TextDirection.ltr),
      ),
    );
    final page = _Page();
    unawaited(nav.currentState!.push(page));
    await tester.pump();
    page.didOpen();
    await tester.pump();
    expect(find.text('home'), findsNothing);
    page.beginInteraction();
    await tester.pump();
    expect(find.text('home'), findsOneWidget);
    expect(nav.currentState!.userGestureInProgress, isTrue);
    page.endInteraction();
    await tester.pump();
    expect(find.text('home'), findsNothing);
    expect(nav.currentState!.userGestureInProgress, isFalse);
    page.beginInteraction();
    page.dismiss(DismissTrigger.interaction);
    page.endInteraction();
    await tester.pump();
    expect(page.left, [DismissTrigger.interaction]);
    expect(find.text('home'), findsOneWidget);
    page.didLeave();
    await tester.pump();
    expect(find.text('page'), findsNothing);
  });

  testWidgets('showPresentation carries the themes around its source', (
    tester,
  ) async {
    late BuildContext source;
    await tester.pumpWidget(
      _app(
        home: DefaultTextStyle(
          style: const TextStyle(fontSize: 31),
          child: Builder(
            builder: (context) {
              source = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    final route = _ThemedRoute();
    unawaited(showPresentation(source, route));
    await tester.pump();
    expect(route.seen, 31);
  });
}

class _Page extends PresentationPageRoute<String> {
  @override
  late final Presentation<String, Presented> presentation = _presentation(
    log,
    builder: (_) =>
        const SizedBox.expand(child: Text('page', textDirection: .ltr)),
  );

  final _Log log = _Log();

  List<DismissTrigger> get left => log.left;
  List<String?> get finished => log.finished;

  @override
  bool get maintainState => true;
}

class _ThemedRoute extends PresentationRoute<void> {
  _ThemedRoute() : this._(_Seen());

  _ThemedRoute._(this._seen)
    : super(
        presentation: _presentation(
          _Log(),
          leaves: false,
          builder: (context) {
            _seen.fontSize = DefaultTextStyle.of(context).style.fontSize;
            return const SizedBox();
          },
        ),
      );

  final _Seen _seen;

  double? get seen => _seen.fontSize;
}

final class _Seen {
  double? fontSize;
}
