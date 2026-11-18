// The framework behaviour the shared navigation bar stands on: one view
// under a GlobalKey that moves between the OverlayPortal slots of the
// routes of a navigator, painted right above the page that holds it and
// under every later route.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host {
  final painter = ValueNotifier<Object?>(null);
  final key = GlobalKey();
  int mounts = 0;
}

class _View extends StatefulWidget {
  const _View(this.host);

  final _Host host;

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  @override
  void initState() {
    super.initState();
    widget.host.mounts++;
  }

  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.topCenter,
    child: SizedBox(width: 100, height: 44, child: Text('bar')),
  );
}

class _Slot extends StatefulWidget {
  const _Slot({required this.host, required this.route, required this.child});

  final _Host host;
  final Object route;
  final Widget child;

  @override
  State<_Slot> createState() => _SlotState();
}

class _SlotState extends State<_Slot> {
  final _portal = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    _portal.show();
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _portal,
    overlayChildBuilder: (context) => ValueListenableBuilder<Object?>(
      valueListenable: widget.host.painter,
      builder: (context, painter, _) => identical(painter, widget.route)
          ? KeyedSubtree(key: widget.host.key, child: _View(widget.host))
          : const SizedBox.shrink(),
    ),
    child: widget.child,
  );
}

class _Page<T> extends PageRoute<T> {
  _Page(this.host, this.name);

  final _Host host;
  final String name;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  bool get opaque => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _Slot(
    host: host,
    route: this,
    child: ColoredBox(
      color: const Color(0xFFFFFFFF),
      child: Center(child: Text(name)),
    ),
  );

  @override
  void didAdd() {
    host.painter.value = this;
    super.didAdd();
  }

  @override
  TickerFuture didPush() {
    host.painter.value = this;
    return super.didPush();
  }

  @override
  void didPopNext(Route<Object?> nextRoute) {
    super.didPopNext(nextRoute);
    host.painter.value = this;
  }
}

void main() {
  testWidgets("one keyed view moves between the routes' slots, keeps its "
      'state and paints between its page and a later dialog', (tester) async {
    final host = _Host();
    addTearDown(host.painter.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      WidgetsApp(
        navigatorKey: navigator,
        color: const Color(0xFF000000),
        onGenerateRoute: (_) => _Page<void>(host, 'One'),
      ),
    );
    expect(find.text('bar'), findsOneWidget);
    expect(host.mounts, 1);

    navigator.currentState!.push(_Page<void>(host, 'Two'));
    await tester.pump();
    expect(find.text('bar'), findsOneWidget);
    expect(host.mounts, 1);
    await tester.pumpAndSettle();
    expect(find.text('bar'), findsOneWidget);
    expect(host.mounts, 1);
    final barLayer = tester.renderObject(find.text('bar'));
    final pageLayer = tester.renderObject(find.text('Two'));
    expect(_paintsAfter(barLayer, pageLayer), isTrue);

    navigator.currentState!.push(
      RawDialogRoute<void>(
        pageBuilder: (context, _, _) => const Center(child: Text('dialog')),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      _paintsAfter(
        tester.renderObject(find.text('dialog')),
        tester.renderObject(find.text('bar')),
      ),
      isTrue,
    );
    navigator.currentState!.pop();
    await tester.pumpAndSettle();

    navigator.currentState!.pop();
    await tester.pump();
    expect(find.text('bar'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('bar'), findsOneWidget);
    expect(host.mounts, 1);
    expect(find.text('Two'), findsNothing);
  });

  testWidgets('a slot under a resting opaque page paints nothing', (
    tester,
  ) async {
    final host = _Host();
    addTearDown(host.painter.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      WidgetsApp(
        navigatorKey: navigator,
        color: const Color(0xFF000000),
        onGenerateRoute: (_) => _Page<void>(host, 'One'),
      ),
    );
    navigator.currentState!.push(
      PageRouteBuilder<void>(
        pageBuilder: (context, _, _) => const ColoredBox(
          color: Color(0xFFFFFFFF),
          child: Center(child: Text('foreign')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('bar'), findsNothing);
    expect(find.text('bar', skipOffstage: false), findsOneWidget);
  });
}

/// Whether [a] paints after [b]: later in a depth-first walk of the render
/// tree from the root, which is paint order for the overlay's children.
bool _paintsAfter(RenderObject a, RenderObject b) {
  final order = <RenderObject>[];
  var root = a;
  while (root.parent != null) {
    root = root.parent!;
  }
  void walk(RenderObject node) {
    order.add(node);
    node.visitChildren(walk);
  }

  walk(root);
  return order.indexOf(a) > order.indexOf(b);
}
