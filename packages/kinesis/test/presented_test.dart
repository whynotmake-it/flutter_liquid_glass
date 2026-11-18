import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

final class _Card extends Motion with Presented, Sourced {
  late final Presence _show = own(Presence(openSpring: Spring.snappy));
  final List<DismissTrigger> left = [];
  final List<SourceGeometry?> sources = [];

  @override
  PresenceStatus get presence => _show.status;

  @override
  void open(double t) => _show.open(t);

  @override
  bool leave(double t, DismissTrigger trigger) {
    left.add(trigger);
    _show.hide(t);
    return true;
  }

  /// Leaves without being dismissed, as a menu does once a row is chosen.
  void leaveOnOwn(double t) => _show.hide(t);

  @override
  void sourceMoved(double t, SourceGeometry? geometry) => sources.add(geometry);
}

/// A card that follows Android's predictive back.
final class _BackCard extends _Card with PredictiveBack {
  final List<String> back = [];
  double? velocity;
  late final MotionValue<double> drag = own(
    MotionValue<double>(0, spring: Spring.snappy),
  );

  @override
  void backStarted(double t) => back.add('started');

  @override
  void backMoved(double t, double progress) {
    back.add('moved $progress');
    drag.retarget(t, progress);
  }

  @override
  void backEnded(double t, {required bool commits, required double velocity}) {
    back.add(commits ? 'committed' : 'cancelled');
    this.velocity = velocity;
    if (!commits) drag.retarget(t, 0);
  }
}

final class _Fade extends PresentedProgress {
  _Fade() : super(openSpring: Spring.snappy, rest: 1e-3);
}

Future<void> _backGesture(
  WidgetTester tester,
  String method, {
  double progress = 0,
  bool button = false,
}) async {
  final message = const StandardMethodCodec().encodeMethodCall(
    MethodCall(method, <String, Object?>{
      'touchOffset': button ? null : <double>[5, 300],
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

const _contentKey = ValueKey('content');

Presentation<String, _Card> _presentation(
  List<_Card> made, {
  DismissPolicy dismiss = const DismissPolicy(),
  MotionSource? source,
  bool modal = true,
  List<DismissTrigger>? vetoes,
  List<String?>? dismissed,
  VoidCallback? onContentPointer,
  String? barrierLabel,
  FocusNode? focus,
  FocusNode? initialFocus,
  bool named = false,
  String? label = 'Panel',
  SemanticsRole? role,
  bool predictive = false,
  bool onScroll = false,
  bool onOutsideTap = false,
}) => Presentation<String, _Card>(
  motion: (_) {
    final card = predictive ? _BackCard() : _Card();
    made.add(card);
    return card;
  },
  builder: (context, motion) => Center(
    child: Listener(
      onPointerDown: (_) => onContentPointer?.call(),
      onPointerMove: (_) => onContentPointer?.call(),
      child: GestureDetector(
        key: _contentKey,
        behavior: HitTestBehavior.opaque,
        onTap: () => PresentationHandle.of(
          context,
        ).dismiss(DismissTrigger.programmatic, 'tapped'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Focus(
              focusNode: focus,
              child: const SizedBox(width: 100, height: 50),
            ),
            Focus(
              focusNode: initialFocus,
              child: const SizedBox(width: 100, height: 50),
            ),
          ],
        ),
      ),
    ),
  ),
  source: source,
  dismiss: dismiss,
  modal: modal ? null : (_) => false,
  onVeto: vetoes?.add,
  onDismissed: dismissed?.add,
  semanticsLabel: label,
  semanticsRole: role,
  barrierLabel: barrierLabel,
  initialFocus: named ? initialFocus : null,
  dismissesOnScroll: onScroll,
  dismissesOnOutsideTap: onOutsideTap,
);

/// One way to show a [Presentation]: a popup route, a page route or a
/// portal.
abstract class _Shell {
  String get name;

  /// Pumps an app whose page shows [page], ready to [present].
  Future<void> pump(WidgetTester tester, Widget page);

  Future<void> present(
    WidgetTester tester,
    Presentation<String, _Card> presentation,
  );

  bool get isPresented;

  /// What the presentation completed with, for the routes.
  String? get result;
}

/// Keys an app maps to intents above every presentation, as an app remaps
/// them.
Map<ShortcutActivator, Intent> _appShortcuts = const {};

Widget _app(Widget home, {GlobalKey<NavigatorState>? key}) => WidgetsApp(
  shortcuts: {...WidgetsApp.defaultShortcuts, ..._appShortcuts},
  navigatorKey: key,
  color: const Color(0xFF000000),
  pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
    settings: settings,
    pageBuilder: (c, _, _) => builder(c),
  ),
  home: home,
);

final class _RouteShell extends _Shell {
  _RouteShell({required this.page});

  final bool page;
  final GlobalKey<NavigatorState> _nav = GlobalKey();
  PresentationRoute<String>? _route;
  PresentationPageRoute<String>? _page;
  @override
  String? result;

  @override
  String get name => page ? 'page route' : 'popup route';

  @override
  Future<void> pump(WidgetTester tester, Widget page) =>
      tester.pumpWidget(_app(page, key: _nav));

  @override
  Future<void> present(
    WidgetTester tester,
    Presentation<String, _Card> presentation,
  ) async {
    final Future<String?> done;
    if (page) {
      final route = _page = _Page(presentation);
      done = _nav.currentState!.push(route);
    } else {
      final route = _route = PresentationRoute(presentation: presentation);
      done = showPresentation(_nav.currentContext!, route);
    }
    unawaited(done.then((r) => result = r));
  }

  @override
  bool get isPresented =>
      (_page?.isCurrent ?? false) ||
      (_route?.isActive ?? false) ||
      (_page?.isActive ?? false);
}

final class _Page<T> extends PresentationPageRoute<T> {
  _Page(this.presentation);

  @override
  final Presentation<T, Presented> presentation;
}

final class _PortalShell extends _Shell {
  final PresentationPortalController controller =
      PresentationPortalController();
  final ValueNotifier<Presentation<String, _Card>?> _shown = ValueNotifier(
    null,
  );

  @override
  String get name => 'portal';

  @override
  String? get result => null;

  @override
  Future<void> pump(WidgetTester tester, Widget page) => tester.pumpWidget(
    _app(
      ValueListenableBuilder(
        valueListenable: _shown,
        builder: (context, presentation, child) => PresentationPortal(
          controller: controller,
          presentation: presentation ?? _presentation([]),
          child: child!,
        ),
        child: page,
      ),
    ),
  );

  @override
  Future<void> present(
    WidgetTester tester,
    Presentation<String, _Card> presentation,
  ) async {
    _shown.value = presentation;
    await tester.pump();
    controller.present();
  }

  @override
  bool get isPresented => controller.isPresented;
}

final List<_Shell Function()> _shells = [
  () => _RouteShell(page: false),
  () => _RouteShell(page: true),
  _PortalShell.new,
];

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

SemanticsNode? _node(WidgetTester tester, String label) {
  SemanticsNode? found;
  bool visit(SemanticsNode node) {
    if (node.label == label) found = node;
    node.visitChildren(visit);
    return found == null;
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return found;
}

/// The labels of the semantics tree in the order a screen reader visits
/// them.
List<String> _readingOrder(WidgetTester tester) {
  final labels = <String>[];
  void visit(SemanticsNode node) {
    if (node.label.isNotEmpty) labels.add(node.label);
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      visit(child);
    }
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return labels;
}

void main() {
  test('policies that allow the same triggers are equal', () {
    expect(
      const DismissPolicy({DismissTrigger.back}),
      const DismissPolicy({DismissTrigger.back, DismissTrigger.programmatic}),
    );
    expect(DismissPolicy.modal.allows(DismissTrigger.programmatic), isTrue);
    expect(DismissPolicy.modal, isNot(const DismissPolicy()));
  });

  setUp(MotionClock.debugReset);

  for (final make in _shells) {
    final name = make().name;

    group(name, () {
      testWidgets('opens at the commit and goes once its leave ends', (
        tester,
      ) async {
        final shell = make();
        final made = <_Card>[];
        final dismissed = <String?>[];
        await shell.pump(tester, const SizedBox.expand());
        await shell.present(
          tester,
          _presentation(made, dismissed: dismissed),
        );
        await tester.pump();
        await tester.pump();
        expect(made, hasLength(1));
        expect(made.single.presence, PresenceStatus.opening);
        expect(find.byKey(_contentKey), findsOneWidget);
        await _settle(tester);
        expect(made.single.presence, PresenceStatus.shown);
        await tester.tap(find.byKey(_contentKey));
        await tester.pump();
        expect(made.single.left, [DismissTrigger.programmatic]);
        expect(find.byKey(_contentKey), findsOneWidget);
        expect(dismissed, isEmpty);
        await _settle(tester);
        expect(dismissed, ['tapped']);
        expect(find.byKey(_contentKey), findsNothing);
        expect(shell.isPresented, isFalse);
        if (shell is _RouteShell) expect(shell.result, 'tapped');
      });

      testWidgets('a motion that leaves on its own takes the presentation '
          'with it', (tester) async {
        final shell = make();
        final made = <_Card>[];
        final dismissed = <String?>[];
        await shell.pump(tester, const SizedBox.expand());
        await shell.present(
          tester,
          _presentation(
            made,
            dismissed: dismissed,
            dismiss: const DismissPolicy({}),
          ),
        );
        await tester.pump();
        await _settle(tester);
        made.single.leaveOnOwn(MotionClock.instance.now);
        await tester.pump();
        expect(made.single.left, [DismissTrigger.programmatic]);
        await _settle(tester);
        expect(dismissed, [null]);
        expect(find.byKey(_contentKey), findsNothing);
        expect(shell.isPresented, isFalse);
      });

      testWidgets('Escape and Back dismiss only as the policy lets them', (
        tester,
      ) async {
        final shell = make();
        final made = <_Card>[];
        final vetoes = <DismissTrigger>[];
        await shell.pump(tester, const SizedBox.expand());
        await shell.present(
          tester,
          _presentation(
            made,
            vetoes: vetoes,
            dismiss: const DismissPolicy({DismissTrigger.back}),
          ),
        );
        await tester.pump();
        await _settle(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(made.single.left, isEmpty);
        final handle = PresentationHandle.of(
          tester.element(find.byKey(_contentKey)),
        );
        expect(handle.canDismiss(DismissTrigger.escape), isFalse);
        expect(handle.canDismiss(DismissTrigger.back), isTrue);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(made.single.left, [DismissTrigger.back]);
        expect(handle.canDismiss(DismissTrigger.programmatic), isFalse);
        await _settle(tester);
        expect(shell.isPresented, isFalse);
      });

      testWidgets('Escape is a DismissIntent an app can remap or take over', (
        tester,
      ) async {
        _appShortcuts = const {
          SingleActivator(LogicalKeyboardKey.keyQ): DismissIntent(),
        };
        addTearDown(() => _appShortcuts = const {});
        final shell = make();
        final made = <_Card>[];
        await shell.pump(tester, const SizedBox.expand());
        await shell.present(tester, _presentation(made));
        await tester.pump();
        await _settle(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
        await tester.pump();
        expect(made.single.left, [DismissTrigger.escape]);
        await _settle(tester);

        var overridden = 0;
        final focus = FocusNode();
        final taken = Presentation<String, _Card>(
          motion: (_) {
            final card = _Card();
            made.add(card);
            return card;
          },
          builder: (context, motion) => Actions(
            actions: {
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) => overridden++,
              ),
            },
            child: Focus(
              focusNode: focus,
              autofocus: true,
              child: const SizedBox(),
            ),
          ),
        );
        await shell.present(tester, taken);
        await tester.pump();
        await _settle(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(overridden, 1);
        expect(made.last.left, isEmpty);
        await tester.pumpWidget(const SizedBox());
        focus.dispose();
      });

      testWidgets('Android predictive back drives the dismissal through the '
          'motion and commits with its velocity', (tester) async {
        final shell = make();
        final made = <_Card>[];
        await shell.pump(tester, const SizedBox.expand());
        await shell.present(tester, _presentation(made, predictive: true));
        await tester.pump();
        await _settle(tester);
        final card = made.single as _BackCard;
        await _backGesture(tester, 'startBackGesture');
        await tester.pump(const Duration(milliseconds: 16));
        await _backGesture(
          tester,
          'updateBackGestureProgress',
          progress: 0.25,
        );
        // Under the test's frame clock, motion time moves only while
        // something moves.
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
        await _backGesture(
          tester,
          'updateBackGestureProgress',
          progress: 0.5,
        );
        await tester.pump(const Duration(milliseconds: 16));
        if (shell is _PortalShell) {
          // Back on a portal stays a plain Back.
          expect(card.back, isEmpty);
        } else {
          expect(card.back, [
            'started',
            'moved 0.0',
            'moved 0.25',
            'moved 0.5',
          ]);
          expect(card.drag.target, 0.5);
          final navigator = tester.state<NavigatorState>(
            find.byType(Navigator),
          );
          expect(navigator.userGestureInProgress, isTrue);
          expect(card.left, isEmpty);
        }
        await _backGesture(tester, 'commitBackGesture');
        await tester.pump();
        expect(card.left, [DismissTrigger.back]);
        if (shell is! _PortalShell) {
          expect(card.back.last, 'committed');
          expect(card.velocity, greaterThan(0));
        }
        await _settle(tester);
        expect(shell.isPresented, isFalse);
        expect(
          tester
              .state<NavigatorState>(find.byType(Navigator))
              .userGestureInProgress,
          isFalse,
        );
      });

      testWidgets('a cancelled predictive back springs the presentation back', (
        tester,
      ) async {
        final shell = make();
        if (shell is _PortalShell) return;
        final made = <_Card>[];
        await shell.pump(tester, const SizedBox.expand());
        await shell.present(tester, _presentation(made, predictive: true));
        await tester.pump();
        await _settle(tester);
        final card = made.single as _BackCard;
        await _backGesture(tester, 'startBackGesture');
        await _backGesture(
          tester,
          'updateBackGestureProgress',
          progress: 0.4,
        );
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
        await _backGesture(tester, 'cancelBackGesture');
        await tester.pump(const Duration(milliseconds: 16));
        expect(card.back.last, 'cancelled');
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        expect(navigator.userGestureInProgress, isTrue);
        await _settle(tester);
        expect(card.drag.value, 0);
        expect(card.left, isEmpty);
        expect(shell.isPresented, isTrue);
        expect(navigator.userGestureInProgress, isFalse);
      });

      for (final commits in [true, false]) {
        testWidgets(
          commits
              ? 'focus returns to the page below after a committed '
                    'predictive back, as after a pop'
              : 'focus returns into the presentation after a cancelled '
                    'predictive back',
          (tester) async {
            final shell = make();
            if (shell is _PortalShell) return;
            final below = FocusNode(debugLabel: 'below');
            final inside = FocusNode(debugLabel: 'inside');
            addTearDown(below.dispose);
            addTearDown(inside.dispose);
            final made = <_Card>[];
            await shell.pump(
              tester,
              Center(
                child: Focus(
                  focusNode: below,
                  autofocus: true,
                  child: const SizedBox(width: 10, height: 10),
                ),
              ),
            );
            await tester.pump();
            expect(below.hasPrimaryFocus, isTrue);
            await shell.present(
              tester,
              _presentation(made, predictive: true, focus: inside),
            );
            await tester.pump();
            await _settle(tester);
            inside.requestFocus();
            await tester.pump();
            expect(inside.hasPrimaryFocus, isTrue);
            await _backGesture(tester, 'startBackGesture');
            await _backGesture(
              tester,
              'updateBackGestureProgress',
              progress: 0.4,
            );
            await tester.pump(const Duration(milliseconds: 16));
            await tester.pump(const Duration(milliseconds: 16));
            await _backGesture(
              tester,
              commits ? 'commitBackGesture' : 'cancelBackGesture',
            );
            await _settle(tester);
            expect(shell.isPresented, !commits);
            if (commits) {
              expect(below.hasPrimaryFocus, isTrue);
            } else {
              expect(inside.hasPrimaryFocus, isTrue);
            }
          },
        );
      }

      testWidgets('predictive back does not start where Back may be refused, '
          'for a motion that does not follow it, or from a button', (
        tester,
      ) async {
        for (final (way, policy, predictive, button) in [
          ('refused', const DismissPolicy({}), true, false),
          ('plain motion', const DismissPolicy(), false, false),
          ('button', const DismissPolicy(), true, true),
        ]) {
          final shell = make();
          final made = <_Card>[];
          final vetoes = <DismissTrigger>[];
          await shell.pump(tester, const SizedBox.expand());
          await shell.present(
            tester,
            _presentation(
              made,
              dismiss: policy,
              predictive: predictive,
              vetoes: vetoes,
            ),
          );
          await tester.pump();
          await _settle(tester);
          final card = made.single;
          await _backGesture(tester, 'startBackGesture', button: button);
          await _backGesture(
            tester,
            'updateBackGestureProgress',
            progress: 0.5,
            button: button,
          );
          if (card is _BackCard) expect(card.back, isEmpty, reason: way);
          await _backGesture(tester, 'commitBackGesture');
          await tester.pump();
          if (way == 'refused') {
            expect(vetoes, [DismissTrigger.back], reason: way);
            expect(card.left, isEmpty, reason: way);
          } else {
            expect(card.left, [DismissTrigger.back], reason: way);
          }
          await tester.pumpWidget(const SizedBox());
        }
      });

      testWidgets('the screen reader dismisses it by its name', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final shell = make();
        final made = <_Card>[];
        await shell.pump(tester, const SizedBox.expand());
        await shell.present(tester, _presentation(made));
        await tester.pump();
        await _settle(tester);
        final node = _node(tester, 'Panel');
        expect(node, isNotNull);
        tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
          node!.id,
          SemanticsAction.dismiss,
        );
        await tester.pump();
        expect(made.single.left, [DismissTrigger.accessibility]);
        semantics.dispose();
      });

      testWidgets('the barrier hides what is below in a route and, '
          'labelled, offers the dismissal after the content', (tester) async {
        final semantics = tester.ensureSemantics();
        final shell = make();
        final made = <_Card>[];
        await shell.pump(
          tester,
          Semantics(label: 'Page below', child: const SizedBox.expand()),
        );
        expect(_readingOrder(tester), contains('Page below'));
        await shell.present(
          tester,
          _presentation(made, barrierLabel: 'Dismiss panel'),
        );
        await tester.pump();
        await _settle(tester);
        // A portal's content reads after its anchor, the page below.
        expect(_readingOrder(tester), [
          if (shell is _PortalShell) 'Page below',
          'Panel',
          'Dismiss panel',
        ]);
        final barrier = _node(tester, 'Dismiss panel')!.getSemanticsData();
        expect(barrier.hasAction(SemanticsAction.tap), isTrue);
        expect(barrier.hasAction(SemanticsAction.dismiss), isTrue);
        tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
          _node(tester, 'Dismiss panel')!.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        expect(made.single.left, [DismissTrigger.outsideTap]);
        semantics.dispose();
      });

      testWidgets('the barrier is silent without a label, when an outside '
          'tap may not dismiss and where the platform has no such dismissal', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        for (final (label, policy, platform) in [
          (null, const DismissPolicy(), TargetPlatform.android),
          ('Dismiss panel', DismissPolicy.modal, TargetPlatform.iOS),
          ('Dismiss panel', const DismissPolicy(), TargetPlatform.linux),
          ('Dismiss panel', const DismissPolicy(), TargetPlatform.windows),
        ]) {
          debugDefaultTargetPlatformOverride = platform;
          final shell = make();
          final made = <_Card>[];
          await shell.pump(
            tester,
            Semantics(label: 'Page below', child: const SizedBox.expand()),
          );
          await shell.present(
            tester,
            _presentation(made, barrierLabel: label, dismiss: policy),
          );
          await tester.pump();
          await _settle(tester);
          expect(_readingOrder(tester), [
            if (shell is _PortalShell) 'Page below',
            'Panel',
          ], reason: '$platform');
          await tester.pumpWidget(const SizedBox());
        }
        debugDefaultTargetPlatformOverride = null;
        semantics.dispose();
      });

      testWidgets('is inert from the start of its leave: no new touch, no '
          'focus, no semantics', (tester) async {
        final semantics = tester.ensureSemantics();
        final shell = make();
        final made = <_Card>[];
        final focus = FocusNode();
        var below = 0;
        var onIt = 0;
        await shell.pump(
          tester,
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => below++,
            child: const SizedBox.expand(),
          ),
        );
        await shell.present(
          tester,
          _presentation(
            made,
            focus: focus,
            onContentPointer: () => onIt++,
          ),
        );
        await tester.pump();
        await _settle(tester);
        focus.requestFocus();
        await tester.pump();
        expect(focus.hasPrimaryFocus, isTrue);
        expect(_node(tester, 'Panel'), isNotNull);
        final center = tester.getCenter(find.byKey(_contentKey));
        await tester.tapAt(center);
        expect(onIt, 1);
        expect(below, 0);

        PresentationHandle.of(
          tester.element(find.byKey(_contentKey)),
        ).dismiss(DismissTrigger.outsideTap);
        await tester.tapAt(center);
        expect(onIt, 1, reason: 'no touch in the frame the leave started');
        // A navigator absorbs every touch in the frame of a pop.
        expect(below, shell is _PortalShell ? 1 : 0);
        await tester.pump(const Duration(milliseconds: 16));
        expect(made.single.presence, PresenceStatus.leaving);
        expect(find.byKey(_contentKey), findsOneWidget);
        expect(focus.hasFocus, isFalse);
        expect(focus.canRequestFocus, isFalse);
        expect(_node(tester, 'Panel'), isNull);
        await tester.tapAt(center);
        expect(onIt, 1);
        expect(below, shell is _PortalShell ? 2 : 1);
        await _settle(tester);
        focus.dispose();
        semantics.dispose();
      });

      testWidgets('the focus moves in at the open: to the named node, to '
          'the first focusable one with the keyboard, to itself on touch', (
        tester,
      ) async {
        for (final keyboard in [false, true]) {
          for (final named in [false, true]) {
            FocusManager.instance.highlightStrategy = keyboard
                ? FocusHighlightStrategy.alwaysTraditional
                : FocusHighlightStrategy.alwaysTouch;
            final shell = make();
            final first = FocusNode();
            final second = FocusNode();
            await shell.pump(tester, const SizedBox.expand());
            await shell.present(
              tester,
              _presentation(
                [],
                focus: first,
                initialFocus: second,
                named: named,
              ),
            );
            await tester.pump();
            await tester.pump();
            final reason = 'keyboard $keyboard, named $named';
            if (named) {
              expect(second.hasPrimaryFocus, isTrue, reason: reason);
            } else if (keyboard) {
              expect(first.hasPrimaryFocus, isTrue, reason: reason);
            } else {
              expect(first.hasFocus || second.hasFocus, isFalse);
              expect(
                FocusManager.instance.primaryFocus?.debugLabel,
                'Presentation',
                reason: reason,
              );
            }
            await tester.pumpWidget(const SizedBox());
            first.dispose();
            second.dispose();
          }
        }
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic;
      });

      testWidgets('Tab cycles inside a modal presentation', (tester) async {
        final shell = make();
        final first = FocusNode();
        final second = FocusNode();
        final outside = FocusNode();
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        await shell.pump(
          tester,
          Focus(focusNode: outside, child: const SizedBox.expand()),
        );
        await shell.present(
          tester,
          _presentation([], focus: first, initialFocus: second),
        );
        await tester.pump();
        await tester.pump();
        expect(first.hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        expect(second.hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        if (shell is _RouteShell && shell.page) {
          // A page keeps its navigator's edge behaviour, as page routes do.
          expect(outside.hasFocus, isFalse);
        } else {
          expect(first.hasPrimaryFocus, isTrue);
        }
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic;
        await tester.pumpWidget(const SizedBox());
        first.dispose();
        second.dispose();
        outside.dispose();
      });

      testWidgets('the focus returns to the opener after Escape, an outside '
          'tap and Back, and falls back when the opener went', (tester) async {
        for (final way in ['escape', 'outside', 'back', 'gone']) {
          final shell = make();
          final opener = FocusNode(debugLabel: 'opener');
          final other = FocusNode(debugLabel: 'other');
          final showOpener = ValueNotifier(true);
          await shell.pump(
            tester,
            Column(
              children: [
                Focus(focusNode: other, child: const SizedBox(height: 10)),
                ValueListenableBuilder(
                  valueListenable: showOpener,
                  builder: (context, show, _) => show
                      ? Focus(
                          focusNode: opener,
                          child: const SizedBox(height: 10),
                        )
                      : const SizedBox(height: 10),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          );
          other.requestFocus();
          await tester.pump();
          opener.requestFocus();
          await tester.pump();
          await shell.present(tester, _presentation([]));
          await tester.pump();
          await tester.pump();
          expect(opener.hasFocus, isFalse, reason: way);
          switch (way) {
            case 'escape':
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            case 'outside':
              await tester.tapAt(const Offset(5, 590));
            case 'back':
              await tester.binding.handlePopRoute();
            default:
              showOpener.value = false;
              await tester.pump();
              PresentationHandle.of(
                tester.element(find.byKey(_contentKey)),
              ).dismiss(DismissTrigger.programmatic);
          }
          await tester.pump();
          await _settle(tester);
          expect(shell.isPresented, isFalse, reason: way);
          if (way == 'gone') {
            final focused = FocusManager.instance.primaryFocus;
            expect(focused, isNotNull);
            expect(focused!.context?.mounted, isTrue, reason: way);
          } else {
            expect(opener.hasPrimaryFocus, isTrue, reason: way);
          }
          await tester.pumpWidget(const SizedBox());
          opener.dispose();
          other.dispose();
        }
      });

      testWidgets('announces itself: a route of its own, named by its '
          'label, with the role the presenter gives', (tester) async {
        final semantics = tester.ensureSemantics();
        final shell = make();
        await shell.pump(tester, const SizedBox.expand());
        await shell.present(
          tester,
          _presentation([], role: SemanticsRole.dialog),
        );
        await tester.pump();
        await _settle(tester);
        final root = find.bySemanticsLabel('Panel');
        expect(
          tester.getSemantics(root),
          matchesSemantics(
            label: 'Panel',
            textDirection: TextDirection.ltr,
            scopesRoute: true,
            namesRoute: true,
            hasDismissAction: true,
          ),
        );
        expect(
          tester.getSemantics(root).getSemanticsData().role,
          SemanticsRole.dialog,
        );
        await tester.pumpWidget(const SizedBox());

        final unnamed = make();
        await unnamed.pump(tester, const SizedBox.expand());
        await unnamed.present(
          tester,
          _presentation([], label: null, dismiss: DismissPolicy.modal),
        );
        await tester.pump();
        await _settle(tester);
        final scopes = <SemanticsData>[];
        bool visit(SemanticsNode node) {
          final data = node.getSemanticsData();
          if (data.flagsCollection.scopesRoute) scopes.add(data);
          node.visitChildren(visit);
          return true;
        }

        visit(
          tester
              .binding
              .renderViews
              .first
              .owner!
              .semanticsOwner!
              .rootSemanticsNode!,
        );
        final content = scopes.last;
        expect(content.flagsCollection.namesRoute, isFalse);
        expect(content.label, isEmpty);
        expect(content.role, SemanticsRole.none);
        expect(content.hasAction(SemanticsAction.dismiss), isTrue);
        semantics.dispose();
      });

      testWidgets('hides its source in the commit frame, follows it and '
          'shows it again once gone', (tester) async {
        final shell = make();
        final made = <_Card>[];
        final source = MotionSource();
        final scroll = ScrollController();
        final shown = ValueNotifier(true);
        var taps = 0;
        await shell.pump(
          tester,
          ListView(
            controller: scroll,
            children: [
              const SizedBox(height: 40),
              ValueListenableBuilder(
                valueListenable: shown,
                builder: (context, show, _) => show
                    ? MotionSourceBox(
                        source: source,
                        child: GestureDetector(
                          onTap: () => taps++,
                          child: const ColoredBox(
                            color: Color(0xFF00FF00),
                            child: SizedBox(height: 50),
                          ),
                        ),
                      )
                    : const SizedBox(height: 50),
              ),
              const SizedBox(height: 2000),
            ],
          ),
        );
        final box = find.byType(MotionSourceBox);
        expect(tester.renderObject(box), isNot(paintsNothing));
        await shell.present(
          tester,
          _presentation(made, source: source, modal: false),
        );
        await tester.pump();
        await tester.pump();
        expect(source.isHidden, isTrue);
        expect(tester.renderObject(box), paintsNothing);
        final card = made.single;
        expect(card.sources.first?.rect.top, 40);

        if (shell is! _RouteShell || !shell.page) {
          await tester.tapAt(const Offset(10, 60));
          expect(taps, 1);
        }

        scroll.jumpTo(30);
        await tester.pump();
        expect(card.sources.last?.rect.top, 10);

        shown.value = false;
        await tester.pump();
        expect(card.sources.last, isNull);

        shown.value = true;
        await tester.pump();
        PresentationHandle.of(
          tester.element(find.byKey(_contentKey)),
        ).dismiss(DismissTrigger.programmatic);
        await _settle(tester);
        expect(source.isHidden, isFalse);
        expect(tester.renderObject(box), isNot(paintsNothing));
      });
    });
  }

  group('anchored', () {
    for (final portal in [true, false]) {
      final name = portal ? 'portal' : 'popup route';

      /// Pumps a list whose second row shows [presentation] when presented,
      /// from inside the list; returns a callback that presents it.
      Future<VoidCallback> pumpList(
        WidgetTester tester,
        Presentation<String, _Card> presentation, {
        required ScrollController scroll,
        required VoidCallback onBelow,
      }) async {
        final controller = PresentationPortalController();
        late BuildContext from;
        await tester.pumpWidget(
          _app(
            Listener(
              onPointerDown: (_) => onBelow(),
              child: ListView(
                controller: scroll,
                children: [
                  const SizedBox(height: 40),
                  Builder(
                    builder: (context) {
                      from = context;
                      const anchor = ColoredBox(
                        key: ValueKey('anchor'),
                        color: Color(0xFF00FF00),
                        child: SizedBox(height: 50),
                      );
                      return portal
                          ? PresentationPortal(
                              controller: controller,
                              presentation: presentation,
                              child: anchor,
                            )
                          : anchor;
                    },
                  ),
                  const SizedBox(height: 2000),
                ],
              ),
            ),
          ),
        );
        return portal
            ? controller.present
            : () => unawaited(
                showPresentation(
                  from,
                  PresentationRoute(presentation: presentation),
                ),
              );
      }

      testWidgets('$name: a scroll around where it was shown from dismisses '
          'it when it asks', (tester) async {
        for (final asks in [false, true]) {
          final made = <_Card>[];
          final scroll = ScrollController();
          final present = await pumpList(
            tester,
            _presentation(made, modal: false, onScroll: asks),
            scroll: scroll,
            onBelow: () {},
          );
          present();
          await tester.pump();
          await _settle(tester);
          await tester.dragFrom(
            const Offset(5, 500),
            const Offset(0, -100),
            touchSlopY: 0,
          );
          await tester.pump();
          expect(
            made.single.left,
            asks ? [DismissTrigger.scroll] : isEmpty,
            reason: 'asks $asks',
          );
          await _settle(tester);
          await tester.pumpWidget(const SizedBox());
          scroll.dispose();
        }
      });

      testWidgets('$name: a tap outside dismisses it when it asks, and still '
          'reaches what it lands on', (tester) async {
        for (final asks in [false, true]) {
          final made = <_Card>[];
          final scroll = ScrollController();
          var below = 0;
          final present = await pumpList(
            tester,
            _presentation(made, modal: false, onOutsideTap: asks),
            scroll: scroll,
            onBelow: () => below++,
          );
          present();
          await tester.pump();
          await _settle(tester);
          await tester.tap(find.byKey(_contentKey));
          await tester.pump();
          expect(made.single.left, [
            DismissTrigger.programmatic,
          ], reason: 'a tap inside');
          made.single.left.clear();
          await _settle(tester);
          present();
          await tester.pump();
          await _settle(tester);
          if (portal) {
            await tester.tap(find.byKey(const ValueKey('anchor')));
            await tester.pump();
            expect(made.last.left, isEmpty, reason: 'the anchor is inside');
          }
          below = 0;
          await tester.tapAt(const Offset(5, 590));
          await tester.pump();
          expect(below, 1);
          expect(
            made.last.left,
            asks ? [DismissTrigger.outsideTap] : isEmpty,
            reason: 'asks $asks',
          );
          await _settle(tester);
          await tester.pumpWidget(const SizedBox());
          scroll.dispose();
        }
      });
    }
  });

  group('portal', () {
    testWidgets('the touch that presents it is not cancelled', (tester) async {
      final shell = _PortalShell();
      final made = <_Card>[];
      final events = <String>[];
      await shell.pump(
        tester,
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => events.add('down'),
          onPointerMove: (_) => events.add('move'),
          onPointerUp: (_) => events.add('up'),
          onPointerCancel: (_) => events.add('cancel'),
          child: const SizedBox.expand(),
        ),
      );
      final gesture = await tester.startGesture(const Offset(20, 20));
      await shell.present(tester, _presentation(made));
      await tester.pump();
      await tester.pump();
      expect(shell.isPresented, isTrue);
      await gesture.moveBy(const Offset(0, 10));
      await gesture.up();
      expect(events, ['down', 'move', 'up']);
    });

    testWidgets('presenting again while it leaves brings it back', (
      tester,
    ) async {
      final shell = _PortalShell();
      final made = <_Card>[];
      final dismissed = <String?>[];
      await shell.pump(tester, const SizedBox.expand());
      await shell.present(tester, _presentation(made, dismissed: dismissed));
      await tester.pump();
      await _settle(tester);
      shell.controller.dismiss(DismissTrigger.programmatic);
      await tester.pump(const Duration(milliseconds: 16));
      expect(made.single.presence, PresenceStatus.leaving);
      shell.controller.present();
      await tester.pump();
      expect(made, hasLength(1));
      expect(made.single.presence, isNot(PresenceStatus.leaving));
      await _settle(tester);
      expect(made.single.presence, PresenceStatus.shown);
      expect(find.byKey(_contentKey), findsOneWidget);
      expect(dismissed, isEmpty);
      shell.controller.dismiss(DismissTrigger.outsideTap);
      expect(made.single.left, [
        DismissTrigger.programmatic,
        DismissTrigger.outsideTap,
      ]);
      await _settle(tester);
      expect(dismissed, [null]);
      expect(shell.isPresented, isFalse);
    });

    testWidgets('a new touch reaches what is below while it leaves, and one '
        'already on it stays', (tester) async {
      final shell = _PortalShell();
      final made = <_Card>[];
      var below = 0;
      var onIt = 0;
      await shell.pump(
        tester,
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => below++,
          child: const SizedBox.expand(),
        ),
      );
      await shell.present(
        tester,
        _presentation(
          made,
          dismiss: DismissPolicy.modal,
          onContentPointer: () => onIt++,
        ),
      );
      await tester.pump();
      await _settle(tester);
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(below, 0);

      final held = await tester.startGesture(
        tester.getCenter(find.byKey(_contentKey)),
      );
      expect(onIt, 1);
      shell.controller.dismiss(DismissTrigger.programmatic);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(below, 1);
      await held.moveBy(const Offset(1, 1));
      expect(onIt, 2);
      await held.up();

      shell.controller.present();
      await tester.pump();
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(below, 1);
      await _settle(tester);
    });

    testWidgets('Tab leaves a presentation that is not modal', (tester) async {
      final shell = _PortalShell();
      final first = FocusNode();
      final outside = FocusNode();
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      await shell.pump(
        tester,
        Focus(focusNode: outside, child: const SizedBox.expand()),
      );
      await shell.present(
        tester,
        _presentation([], focus: first, modal: false),
      );
      await tester.pump();
      await tester.pump();
      expect(first.hasPrimaryFocus, isTrue);
      final visited = <FocusNode?>[];
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        visited.add(FocusManager.instance.primaryFocus);
      }
      expect(visited, contains(outside));
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic;
      await tester.pumpWidget(const SizedBox());
      first.dispose();
      outside.dispose();
    });

    testWidgets('a screen reader reaches it right after a source whose name '
        'sits in a node of its own', (tester) async {
      final semantics = tester.ensureSemantics();
      final shell = _PortalShell();
      final made = <_Card>[];
      await shell.pump(
        tester,
        Align(
          alignment: Alignment.bottomRight,
          child: Semantics(
            onLongPress: () {},
            child: Semantics(
              container: true,
              label: 'Source',
              child: const SizedBox(width: 80, height: 40),
            ),
          ),
        ),
      );
      await shell.present(
        tester,
        _presentation(made, barrierLabel: 'Dismiss panel'),
      );
      await tester.pump();
      await _settle(tester);
      expect(_readingOrder(tester), ['Source', 'Panel', 'Dismiss panel']);
      semantics.dispose();
    });

    testWidgets('takes the focus and gives it back', (tester) async {
      final shell = _PortalShell();
      final made = <_Card>[];
      final field = FocusNode();
      await shell.pump(
        tester,
        Focus(focusNode: field, autofocus: true, child: const SizedBox()),
      );
      await tester.pump();
      expect(field.hasPrimaryFocus, isTrue);
      await shell.present(tester, _presentation(made));
      await tester.pump();
      await tester.pump();
      expect(field.hasFocus, isFalse);
      shell.controller.dismiss(DismissTrigger.programmatic);
      await _settle(tester);
      expect(field.hasPrimaryFocus, isTrue);
      field.dispose();
    });
  });

  group('PresentedProgress', () {
    test('opens to shown and leaves to hidden', () {
      final fade = _Fade();
      expect(fade.presence, PresenceStatus.hidden);
      fade.open(0);
      expect(fade.presence, PresenceStatus.opening);
      fade.advance(3);
      expect(fade.presence, PresenceStatus.shown);
      expect(fade.opacity, closeTo(1, 1e-3));
      expect(fade.leave(3, DismissTrigger.escape), isTrue);
      expect(fade.isLeaving, isTrue);
      expect(fade.presence, PresenceStatus.leaving);
      fade.advance(6);
      expect(fade.presence, PresenceStatus.hidden);
      fade.open(6);
      expect(fade.isLeaving, isFalse);
      expect(fade.presence, PresenceStatus.opening);
    });

    test('a leave in the middle of the opening turns from where it stands, '
        'velocity included', () {
      final fade = _Fade()..open(0);
      fade.advance(0.05);
      final at = fade.progress;
      fade.leave(0.05, DismissTrigger.escape);
      expect(fade.progress, at);
      fade.advance(0.06);
      expect(fade.progress, greaterThan(at));
    });

    test('predictive back holds the progress at one minus the gesture, and '
        'a cancel springs back to shown', () {
      final fade = _Fade()..open(0);
      fade.advance(3);
      fade
        ..backStarted(3)
        ..backMoved(3.1, 0.4);
      expect(fade.progress, closeTo(0.6, 1e-9));
      expect(fade.presence, isNot(PresenceStatus.leaving));
      fade.backEnded(3.1, commits: false, velocity: 0);
      fade.advance(6);
      expect(fade.presence, PresenceStatus.shown);
    });

    test('a committed back leaves with the gesture velocity', () {
      final fade = _Fade()..open(0);
      fade.advance(3);
      fade
        ..backStarted(3)
        ..backMoved(3.1, 0.5)
        ..backEnded(3.1, commits: true, velocity: 2)
        ..leave(3.1, DismissTrigger.back);
      fade.advance(3.11);
      final fromRest = _Fade()..open(0);
      fromRest
        ..advance(3)
        ..backMoved(3.1, 0.5)
        ..leave(3.1, DismissTrigger.back)
        ..advance(3.11);
      expect(fade.progress, lessThan(fromRest.progress));
    });
  });
}
