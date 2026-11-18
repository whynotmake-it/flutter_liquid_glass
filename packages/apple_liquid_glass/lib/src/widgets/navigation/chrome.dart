import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/navigation_bar.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/toolbar.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// How a [GlassContentScroll] separates its content where it passes under
/// a bar.
///
/// UIKit: `UIScrollEdgeEffect.Style`. SwiftUI: `ScrollEdgeEffectStyle`.
enum GlassScrollEdgeEffect {
  /// What UIKit picks for the bar at the edge: hard under a navigation
  /// bar, none under a floating toolbar or tab bar, soft under any other
  /// bar or the status bar.
  automatic,

  /// A light blur over a band reaching 40 points past the bar, fading into
  /// the background along it.
  soft,

  /// The thin film of a navigation bar: a blur with raised saturation over
  /// the bar's own band and a hairline at its edge.
  hard,

  /// None.
  hidden,
}

/// The edge effects of the top and bottom edges of a [GlassContentScroll].
///
/// SwiftUI: `scrollEdgeEffectStyle(_:for:)`.
@immutable
final class GlassScrollEdgeEffects {
  /// Creates the effects of both edges.
  const GlassScrollEdgeEffects({
    this.top = GlassScrollEdgeEffect.automatic,
    this.bottom = GlassScrollEdgeEffect.automatic,
  });

  /// The effect at the top edge.
  final GlassScrollEdgeEffect top;

  /// The effect at the bottom edge.
  final GlassScrollEdgeEffect bottom;

  @override
  bool operator ==(Object other) =>
      other is GlassScrollEdgeEffects &&
      other.top == top &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(top, bottom);
}

/// The kind of bar at an edge of a page, which picks the automatic edge
/// effect.
@internal
enum ChromeBar {
  /// No bar.
  none,

  /// A navigation bar.
  navigation,

  /// A floating toolbar or tab bar.
  floating,

  /// Any other bar.
  custom,
}

/// What a page's chrome tells the scroll views and bars under it.
@internal
@immutable
final class ChromeEdges {
  /// Describes the edges of a page.
  const ChromeEdges({
    required this.top,
    required this.topExtent,
    required this.scrolledUnderAfter,
    required this.bottom,
    required this.bottomExtent,
    required this.background,
  });

  /// The bar at the top.
  final ChromeBar top;

  /// The distance from the page's top to the top bar's far edge.
  final double topExtent;

  /// How far the content scrolls before it passes under the top bar.
  final double scrolledUnderAfter;

  /// The bar at the bottom.
  final ChromeBar bottom;

  /// The distance from the page's bottom to the bottom bar's far edge.
  final double bottomExtent;

  /// The page's background, resolved.
  final Color background;

  @override
  bool operator ==(Object other) =>
      other is ChromeEdges &&
      other.top == top &&
      other.topExtent == topExtent &&
      other.scrolledUnderAfter == scrolledUnderAfter &&
      other.bottom == bottom &&
      other.bottomExtent == bottomExtent &&
      other.background == background;

  @override
  int get hashCode => Object.hash(
    top,
    topExtent,
    scrolledUnderAfter,
    bottom,
    bottomExtent,
    background,
  );
}

/// The chrome of a page: its edges, and the scroll view its bars follow,
/// the latest onstage [GlassContentScroll] to claim it.
@internal
class GlassChrome extends InheritedWidget {
  /// Creates the chrome scope.
  const GlassChrome({
    required this.edges,
    required this.active,
    required this.outer,
    required super.child,
    super.key,
  });

  /// The page's edges.
  final ChromeEdges edges;

  /// The scroll view the bars follow, or null for none.
  final ValueNotifier<MotionScroll?> active;

  /// The chrome around this one, such as a tab scaffold's around a page:
  /// its bars follow the same scroll view.
  final GlassChrome? outer;

  /// The nearest chrome, or null outside a page.
  static GlassChrome? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassChrome>();

  @override
  bool updateShouldNotify(GlassChrome oldWidget) =>
      edges != oldWidget.edges ||
      active != oldWidget.active ||
      outer != oldWidget.outer;
}

/// Marks the scroll view the bars of its page follow, and draws its edge
/// effects where its content passes under them.
///
/// UIKit: a `UIScrollView` whose edge a bar observes
/// (`contentScrollView(for:)`). SwiftUI: the scroll view a `NavigationStack`
/// or `TabView` finds. Flutter: `PrimaryScrollController`, without the
/// controller.
///
/// Wrap the page's main scroll view in it: the navigation bar fades its
/// title and the tab bar minimizes from it, through its notifications, so
/// any scrollable works without a controller. [notificationPredicate]
/// selects the scroll view among nested ones (depth 0 by default). Each
/// page of a `PageView` has its own; the bars follow the latest one shown.
/// Inside a [GlassPageScaffold] the content scrolls under the bars, and
/// each edge effect fades in, on a 0.35 s spring, once content lies under
/// its bar (navigation bar passport); it fades only while the content
/// moves on its own or under a finger, and a jump of the content shows or
/// hides it at once, as UIKit does (read from UIKit, notes private).
class GlassContentScroll extends StatefulWidget {
  /// Marks [child] as the page's scroll view.
  const GlassContentScroll({
    required this.child,
    this.edgeEffects = const GlassScrollEdgeEffects(),
    this.notificationPredicate = defaultScrollNotificationPredicate,
    super.key,
  });

  /// The scroll view.
  final Widget child;

  /// The effects at its top and bottom edges.
  final GlassScrollEdgeEffects edgeEffects;

  /// Which scroll notifications come from the page's scroll view.
  final ScrollNotificationPredicate notificationPredicate;

  @override
  State<GlassContentScroll> createState() => _GlassContentScrollState();
}

class _GlassContentScrollState extends State<GlassContentScroll> {
  late final MotionClock _clock;
  late MotionScroll _scroll = MotionScroll(
    predicate: widget.notificationPredicate,
    clock: _clock,
  );
  late MotionSelection<ScrollMetrics?> _metrics;
  late final _top = PresenceMotion.scrollEdge(clock: _clock);
  late final _bottom = PresenceMotion.scrollEdge(clock: _clock);
  GlassChrome? _chrome;
  bool _laidOut = false;

  MotionSelection<ScrollMetrics?> _follow(MotionScroll scroll) {
    final metrics = scroll.select((s) => s.metrics);
    metrics.addRenderListener(_scrolled);
    return metrics;
  }

  @override
  void initState() {
    super.initState();
    _clock = MotionClockScope.of(context);
    _metrics = _follow(_scroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chrome = GlassChrome.maybeOf(context);
    if (!_followedBySameBars(chrome, _chrome)) _release();
    _chrome = chrome;
    final traits = MotionTraitsOverride.of(context);
    _top.traits = traits;
    _bottom.traits = traits;
    _scrolled();
    if (TickerMode.valuesOf(context).enabled) _claim();
  }

  @override
  void didUpdateWidget(GlassContentScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notificationPredicate != widget.notificationPredicate) {
      _release();
      _metrics.removeRenderListener(_scrolled);
      _scroll = MotionScroll(
        predicate: widget.notificationPredicate,
        clock: _clock,
      );
      _metrics = _follow(_scroll);
      _claim();
    }
  }

  @override
  void dispose() {
    _release();
    _metrics.removeRenderListener(_scrolled);
    super.dispose();
  }

  // A scaffold around this one rebuilds with a new chrome for the same bars:
  // only other bars take the claim away, or the bars would drop the scroll
  // view for a frame and a large title scrolled away would come back.
  static bool _followedBySameBars(GlassChrome? a, GlassChrome? b) {
    if (a == null || b == null) return identical(a, b);
    return identical(a.active, b.active) &&
        _followedBySameBars(a.outer, b.outer);
  }

  // The bars follow the claimed scroll view by swapping their render
  // listeners, without building, so the claim takes effect at once.
  void _claim() {
    for (var scope = _chrome; scope != null; scope = scope.outer) {
      scope.active.value = _scroll;
    }
  }

  void _release() {
    for (var scope = _chrome; scope != null; scope = scope.outer) {
      if (identical(scope.active.value, _scroll)) scope.active.value = null;
    }
  }

  // A glide that starts while the scroll still reads as a drag starts at
  // the finger's release.
  bool _released() => _scroll.phase == MotionScrollPhase.dragging;

  void _scrolled() {
    final after = _chrome?.edges.scrolledUnderAfter ?? 0;
    final metrics = _scroll.metrics;
    final laidOut = metrics != null && metrics.hasContentDimensions;
    // Content under a bar when the page appears shows its effect at once.
    final appears = laidOut && !_laidOut;
    _laidOut = laidOut;
    _show(_top, laidOut && metrics.extentBefore > after + 0.5, appears);
    _show(_bottom, laidOut && metrics.extentAfter > 0.5, appears);
  }

  void _show(PresenceMotion edge, bool shown, bool appears) {
    final moving = _scroll.position?.isScrollingNotifier.value ?? false;
    edge.turn(
      _clock.now,
      shown: shown,
      animated: !appears && moving,
    );
  }

  bool? _hard(GlassScrollEdgeEffect style, ChromeBar bar) =>
      switch ((style, bar)) {
        (GlassScrollEdgeEffect.hidden, _) => null,
        (GlassScrollEdgeEffect.soft, _) => false,
        (GlassScrollEdgeEffect.hard, _) => true,
        (_, ChromeBar.navigation) => true,
        (_, ChromeBar.floating) => null,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    final renderer = GlassRendererScope.of(context);
    final edges = _chrome?.edges;
    final top = _hard(
      widget.edgeEffects.top,
      edges?.top ?? ChromeBar.none,
    );
    final bottom = _hard(
      widget.edgeEffects.bottom,
      edges?.bottom ?? ChromeBar.none,
    );
    final background =
        edges?.background ??
        GlassDynamicColor.resolve(GlassColors.systemBackground, context);
    final padding = MediaQuery.paddingOf(context);
    final topExtent = edges?.topExtent ?? padding.top;
    final bottomExtent = edges?.bottomExtent ?? padding.bottom;
    final after = edges?.scrolledUnderAfter ?? 0;
    final configuration = ScrollConfiguration.of(context);
    final content = after <= 0
        ? widget.child
        : ScrollConfiguration(
            behavior: configuration.copyWith(
              physics: LargeTitleScrollPhysics(
                collapseExtent: after,
                released: _released,
                parent: configuration.getScrollPhysics(context),
              ),
            ),
            child: widget.child,
          );
    return NotificationListener<Notification>(
      onNotification: _scroll.handle,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          content,
          if (top != null && topExtent > 0)
            Positioned.fill(
              child: renderer.buildScrollEdge(
                context,
                GlassScrollEdgeDetails(
                  edge: AxisDirection.up,
                  hard: top,
                  extent: topExtent - after,
                  presence: _top.presence,
                  background: background,
                ),
              ),
            ),
          if (bottom != null && bottomExtent > 0)
            Positioned.fill(
              child: renderer.buildScrollEdge(
                context,
                GlassScrollEdgeDetails(
                  edge: AxisDirection.down,
                  hard: bottom,
                  extent: bottomExtent,
                  presence: _bottom.presence,
                  background: background,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// An iOS 27 page: its content scrolls under a navigation bar at the top
/// and a toolbar at the bottom.
///
/// UIKit: a `UIViewController`'s view with its navigation bar and toolbar.
/// SwiftUI: a view with `navigationTitle` and `toolbar` in a
/// `NavigationStack`. Flutter: `CupertinoPageScaffold`.
///
/// Pass the content as [child], a [GlassNavigationBar] as
/// [navigationBar] and a [GlassToolbar] as [toolbar], both optional. Wrap
/// the content's scroll view in a [GlassContentScroll]: the bars follow
/// that scroll view, and it draws the scroll edge effects under them. Push
/// the page as a `GlassPageRoute` so neighbouring pages share their bars,
/// or give one to each tab of a `GlassTabScaffold`.
///
/// ```dart
/// GlassPageScaffold(
///   navigationBar: const GlassNavigationBar(title: Text('Photos')),
///   toolbar: GlassToolbar(
///     items: [
///       GlassBarButton(
///         icon: const Icon(CupertinoIcons.share),
///         onPressed: () => debugPrint('share'),
///       ),
///     ],
///   ),
///   child: GlassContentScroll(
///     child: ListView(children: const [Text('Album')]),
///   ),
/// )
/// ```
///
/// The page draws no glass of its own: it fills [backgroundColor] on every
/// renderer, and its bars draw their capsules as they say. The scroll edge
/// effects come from the renderer: the liquid and fake renderers blur the
/// content under a bar before it fades toward the background, and the flat
/// renderer, which also draws when no `GlassScope` is above, fades it
/// without a blur.
///
/// The bars float over [child]; the media query padding below them grows
/// by their extents, so a `ListView`'s content starts under the navigation
/// bar and can scroll clear of the toolbar (a `CustomScrollView` takes the
/// padding through a `SliverSafeArea`, as under `CupertinoPageScaffold`).
/// A tap on the status bar scrolls the content the bars follow to its
/// start, as `CupertinoPageScaffold` does it, over 500 ms, linear to ease
/// out.
///
/// Fidelity. The scroll to the start on a status bar tap is Flutter's, not
/// measured on iOS 27.
class GlassPageScaffold extends StatefulWidget {
  /// Creates a page.
  const GlassPageScaffold({
    required this.child,
    this.navigationBar,
    this.toolbar,
    this.backgroundColor,
    super.key,
  });

  /// The bar at the top, below the status bar.
  final PreferredSizeWidget? navigationBar;

  /// The bar at the bottom, such as a [GlassToolbar]; a floating one keeps
  /// its own inset from the screen's bottom edge.
  final PreferredSizeWidget? toolbar;

  /// The page's background; [GlassColors.systemBackground] by default.
  final Color? backgroundColor;

  /// The page's content.
  final Widget child;

  @override
  State<GlassPageScaffold> createState() => _GlassPageScaffoldState();
}

class _GlassPageScaffoldState extends State<GlassPageScaffold>
    with WidgetsBindingObserver {
  final _active = ValueNotifier<MotionScroll?>(null);
  final _statusBar = GlobalKey();
  final _lift = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _active.dispose();
    _lift.dispose();
    super.dispose();
  }

  @override
  void handleStatusBarTap() {
    final position = _active.value?.position;
    if (position == null || !position.hasPixels || !_foreground()) return;
    position
        .animateTo(
          position.minScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.linearToEaseOut,
        )
        .ignore();
  }

  // Only the page in front takes the tap: its status bar is what a touch
  // at the top of the screen hits.
  bool _foreground() {
    final box = _statusBar.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      box.localToGlobal(box.size.center(Offset.zero)),
      View.of(context).viewId,
    );
    return result.path.any((entry) => identical(entry.target, box));
  }

  static ChromeBar _kind(PreferredSizeWidget? bar) => switch (bar) {
    null => ChromeBar.none,
    GlassNavigationBar() => ChromeBar.navigation,
    GlassToolbar() => ChromeBar.floating,
    _ => ChromeBar.custom,
  };

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final navigationBar = widget.navigationBar;
    final toolbar = widget.toolbar;
    final top = navigationBar == null
        ? media.padding.top
        : media.padding.top + navigationBar.preferredSize.height;
    final bottomBar = _kind(toolbar);
    final floating = bottomBar == ChromeBar.floating;
    final bottom = toolbar == null
        ? media.padding.bottom
        : floating
        ? math.max(media.padding.bottom, toolbar.preferredSize.height)
        : media.padding.bottom + toolbar.preferredSize.height;
    final background = GlassDynamicColor.resolve(
      widget.backgroundColor ?? GlassColors.systemBackground,
      context,
    );
    final outer = GlassChrome.maybeOf(context);
    final edges = ChromeEdges(
      top: _kind(navigationBar),
      topExtent: top,
      scrolledUnderAfter: switch (navigationBar) {
        GlassNavigationBar(:final scrolledUnderAfter) => scrolledUnderAfter,
        _ => 0,
      },
      bottom: toolbar == null
          ? outer?.edges.bottom ?? ChromeBar.none
          : bottomBar,
      bottomExtent: bottom,
      background: background,
    );
    return GlassChrome(
      edges: edges,
      active: _active,
      outer: outer,
      child: ColoredBox(
        color: background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MotionTransition(
              translateY: _lift,
              child: MediaQuery(
                data: media.copyWith(
                  padding: media.padding.copyWith(top: top, bottom: bottom),
                ),
                child: widget.child,
              ),
            ),
            if (navigationBar != null)
              Positioned(
                top: media.padding.top,
                left: 0,
                right: 0,
                child: PageLift(lift: _lift, child: navigationBar),
              ),
            if (toolbar != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: floating ? 0 : media.padding.bottom,
                child: toolbar,
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: media.padding.top,
              child: MetaData(
                key: _statusBar,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How far a page moves up while its stacked search shows: written by the
/// navigation bar's search, followed by the page's content, its bar and the
/// shared bar's capsules.
@internal
class PageLift extends InheritedWidget {
  /// Provides [lift] to the navigation bar below.
  const PageLift({required this.lift, required super.child, super.key});

  /// The page's offset, 0 at rest and negative while lifted.
  final ValueNotifier<double> lift;

  /// The lift around [context], or null.
  static ValueNotifier<double>? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PageLift>()?.lift;

  @override
  bool updateShouldNotify(PageLift oldWidget) => lift != oldWidget.lift;
}

/// Scroll physics that settle a large title out of or fully under the
/// navigation bar: a finger's release that would leave the title partly
/// away springs to the nearer end; content the app moves stays where it
/// is put.
///
/// UIKit moves the target a release projects to the nearer end, the
/// threshold half the title (read from UIKit, notes private): it snaps a
/// release 25 points away back out and one 30 points away under. The snap
/// is fitted as a critically damped spring of response 0.33 s (damping 1.0
/// to 1.2). A stacked search field folds as part of the same extent;
/// UIKit's threshold for it is not read (approximation).
@internal
class LargeTitleScrollPhysics extends ScrollPhysics {
  /// Creates the physics for a bar whose collapsing part is
  /// [collapseExtent] tall.
  const LargeTitleScrollPhysics({
    required this.collapseExtent,
    required this.released,
    super.parent,
  });

  /// The scroll distance over which the bar's collapsing part (a stacked
  /// search field, then the large title) goes under the row.
  final double collapseExtent;

  /// Whether a glide that starts now starts at a finger's release.
  final bool Function() released;

  @override
  LargeTitleScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      LargeTitleScrollPhysics(
        collapseExtent: collapseExtent,
        released: released,
        parent: buildParent(ancestor),
      );

  static double _restOf(Simulation? simulation, ScrollMetrics position) {
    if (simulation == null) return position.pixels;
    var t = 0.0;
    var x = simulation.x(0);
    while (t < 8 && !simulation.isDone(t)) {
      t += 1 / 60;
      x = simulation.x(t);
    }
    return x;
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final base = super.createBallisticSimulation(position, velocity);
    if (position.outOfRange || !released()) return base;
    final start = position.minScrollExtent;
    final rest = _restOf(base, position) - start;
    if (rest <= 0.5 || rest >= collapseExtent - 0.5) return base;
    final target = start + (rest < collapseExtent / 2 ? 0 : collapseExtent);
    return ScrollSpringSimulation(
      LargeTitleSnap.spring,
      position.pixels,
      math.min(target, position.maxScrollExtent),
      velocity,
      tolerance: toleranceFor(position),
    );
  }
}
