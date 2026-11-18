import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar_entry.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/navigation_bar.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/toolbar.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_anchor.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_entries.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:liquid_glass_renderer/painting.dart';

part 'package:apple_liquid_glass/src/widgets/navigation/bar_identity.dart';
part 'package:apple_liquid_glass/src/widgets/navigation/bar_inputs.dart';
part 'package:apple_liquid_glass/src/widgets/navigation/bar_render.dart';
part 'package:apple_liquid_glass/src/widgets/navigation/bar_state.dart';
part 'package:apple_liquid_glass/src/widgets/navigation/bar_widgets.dart';

/// The share of an interactive pop's progress the navigation bar's capsules
/// lean toward their places on the page below while the finger drags the
/// page: half the way when the page is fully out (device fit over four
/// swipes, 0.16 - 0.27 points rms).
@internal
const double glassBarDrift = 0.5;

/// How many child layer handles the bar item render object [object] holds;
/// -1 when it is not one.
@visibleForTesting
int glassBarLayerHandles(RenderObject object) =>
    object is _RenderBarItems ? object._layers.length : -1;

({VoidCallback? onPressed, List<GlassMenuEntry>? menu, bool enabled}) _actionOf(
  _Button button,
) {
  final (onPressed, menu) = switch (button.item) {
    GlassBarButton(:final onPressed, :final menuChildren) => (
      onPressed,
      menuChildren,
    ),
    GlassBarProminentButton(:final onPressed) => (onPressed, null),
    GlassBarCustomItem() || null => (null, null),
  };
  final action = button.back?.onPressed ?? onPressed;
  return (
    onPressed: action,
    menu: menu,
    enabled: action != null || menu != null,
  );
}

// What a button item shows: its icon, else its label; custom content and
// the back button (null) show none.
Widget? _glyphOfItem(GlassBarItem? item) => switch (item) {
  GlassBarButton(:final icon, :final label) ||
  GlassBarProminentButton(:final icon, :final label) => icon ?? label,
  GlassBarCustomItem() || null => null,
};

/// What a page declares to its navigator's bar.
@internal
@immutable
final class GlassBarDeclaration {
  /// Creates a declaration.
  const GlassBarDeclaration({
    this.leading = const [],
    this.trailing = const [],
    this.automaticallyImplyLeading = true,
    this.previousPageTitle,
    this.backButtonDisplayMode = GlassBackButtonDisplayMode.title,
    this.title,
  });

  /// The entries at the leading edge; they replace the back button.
  final List<GlassBarEntry> leading;

  /// The entries at the trailing edge.
  final List<GlassBarEntry> trailing;

  /// Whether the page gets a back button when [leading] is empty and a
  /// glass page lies below.
  final bool automaticallyImplyLeading;

  /// The back button's name for the page below, in place of its title.
  final String? previousPageTitle;

  /// How the back button names the page below.
  final GlassBackButtonDisplayMode backButtonDisplayMode;

  /// The page's title as text, which the back button of a page above
  /// shows; null when the title is not plain text.
  final String? title;
}

/// Where a page's inline title may sit in the bar's row, from the page's
/// final layout.
@internal
typedef GlassTitleRoom = ({double start, double end});

/// Whether the tab around [child] is the one its tab scaffold shows: the
/// bars of a tab left behind withdraw from the page's shared bar, and a
/// tab without bars of its own shows none.
@internal
class GlassTabShown extends InheritedWidget {
  /// Tells the bars below whether their tab shows.
  const GlassTabShown({required this.shown, required super.child, super.key});

  /// Whether the tab shows.
  final bool shown;

  /// Whether the tab around [context] shows; true outside a tab.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassTabShown>()?.shown ??
      true;

  @override
  bool updateShouldNotify(GlassTabShown oldWidget) => shown != oldWidget.shown;
}

/// One page's end of its navigator's shared bar.
///
/// The route creates it when it installs and drops it when it disposes (a
/// standalone host makes its own); the page's bars declare to it as they
/// build.
@internal
final class GlassPageBarLink {
  GlassPageBarLink._(this.host, this.route, this._presence, this._title);

  /// The bar this page belongs to.
  final GlassBarHost host;

  /// The page's route, or null for a page outside any glass page route.
  final ModalRoute<Object?>? route;

  final ValueListenable<double>? _presence;

  // The route's own name for the page.
  final String? _title;

  GlassPageBarLink? _below;
  GlassBarDeclaration? _declaration;
  Object? _declarer;
  List<GlassBarEntry>? _toolbar;
  Object? _toolbarDeclarer;
  bool _declaredToolbar = false;
  final Map<GlassBarKind, List<GlassBarCapsuleLayout>> _layouts = {};
  bool _coveredByForeign = false;
  ValueListenable<double>? _fade;

  /// The room of the page's inline title in its final layout.
  final ValueNotifier<GlassTitleRoom?> titleRoom = ValueNotifier(null);

  /// The link of the page [context] belongs to, without a dependency: a
  /// page never rebuilds because the bar moved.
  static GlassPageBarLink? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_LinkScope>()?.link;
}

/// How one bar widget's State declares to the page's [GlassBarHost].
///
/// Inside a glass page route the declaration goes to the page's link; a bar
/// outside any route gets a host of its own. The State calls [resolve] from
/// `didChangeDependencies`, [withdraw] when its tab no longer shows it, and
/// [dispose] from its own.
@internal
final class GlassBarClient {
  /// A client that declares and withdraws as [declarer].
  GlassBarClient(this.declarer);

  /// The State that declares.
  final Object declarer;

  GlassPageBarLink? _link;
  GlassBarHost? _standalone;

  /// The page's link, or null outside a glass page route.
  GlassPageBarLink? get link => _link;

  /// The host of a bar outside any route, or null inside one.
  GlassBarHost? get standalone => _standalone;

  /// The link to declare to: the page's, or the own host's.
  GlassPageBarLink get target => _link ?? _standalone!.standaloneLink;

  /// Finds the page's link, and the own host when there is none.
  void resolve(BuildContext context) {
    _link = GlassPageBarLink.maybeOf(context);
    if (_link == null) {
      _standalone ??= GlassBarHost.standalone();
    } else if (_standalone case final host?) {
      host.detach(host.standaloneLink);
      _standalone = null;
    }
  }

  /// Takes the declaration back once the host has laid out what is on screen.
  void withdraw({ValueListenable<double>? fade}) {
    if (_link case final link?) {
      link.host.withdraw(link, declarer, fade: fade);
    }
  }

  /// Releases the own host and the declaration.
  void dispose({ValueListenable<double>? fade}) {
    if (_standalone case final host?) host.detach(host.standaloneLink);
    withdraw(fade: fade);
  }
}

/// Which bar of a page.
@internal
enum GlassBarKind {
  /// The navigation bar at the top.
  navigation,

  /// The toolbar at the bottom.
  toolbar,
}

/// The bars a navigator's glass pages share: the one owner of their state.
///
/// One per [NavigatorState], found through the route's navigator, with no
/// app wiring; a page outside any glass page route has a host of its own.
/// Routes report their events and pages their declarations synchronously,
/// and the host decides: it is the only writer of the bars' motion, of
/// which page's slot draws them ([painter]) and of what they head to.
/// Every change counts from the event that caused it (a push or pop call,
/// a finger's lift, a page's build), never from when a bar laid it out.
/// Nothing builds or lays out per frame: the clock steps each bar's motion
/// while its view shows, and the bar writes its frames as the motion
/// changes.
@internal
final class GlassBarHost {
  GlassBarHost._(this._navigator);

  /// A host for one page outside any glass page route, which draws its
  /// bar itself.
  GlassBarHost.standalone() : _navigator = null {
    final link = _standalone = GlassPageBarLink._(this, null, null, null);
    _pages.add(link);
    _show(link);
    _painter.value = link;
  }

  /// The bars of [navigator]'s glass pages.
  factory GlassBarHost.of(NavigatorState navigator) =>
      _hosts[navigator] ??= GlassBarHost._(navigator);

  final NavigatorState? _navigator;

  static final Expando<GlassBarHost> _hosts = Expando('GlassBarHost');

  /// The key of the one bar view, which moves between the pages' slots.
  final GlobalKey viewKey = GlobalKey(debugLabel: 'GlassBarView');

  /// The page whose slot draws the bars: the topmost live glass page.
  ValueListenable<GlassPageBarLink?> get painter => _painter;
  final _painter = ValueNotifier<GlassPageBarLink?>(null);

  late final GlassPageBarLink _standalone;

  /// The one page of a standalone host.
  GlassPageBarLink get standaloneLink => _standalone;

  // Live glass pages, bottom to top, the order of their overlay entries.
  final List<GlassPageBarLink> _pages = [];
  GlassPageBarLink? _shown;
  // The shown page's fade, which the navigation bar's capsules follow.
  final _fade = ValueNotifier<double>(1);
  ValueListenable<double>? _following;

  void _show(GlassPageBarLink? link) {
    _shown = link;
    _followFade();
  }

  void _followFade() {
    final fade = _shown?._fade;
    if (identical(fade, _following)) return;
    _following?.removeListener(_faded);
    _following = fade;
    fade?.addListener(_faded);
    _faded();
  }

  void _faded() {
    final fade = _following?.value ?? 1;
    if (fade == _fade.value) return;
    _fade.value = fade;
    final bar = _bars[GlassBarKind.navigation]!;
    if (bar.items != null) bar.publish();
  }

  /// Tells which opacity [link]'s page's navigation bar fades by while its
  /// stacked search shows.
  void fadedBy(GlassPageBarLink link, ValueListenable<double>? fade) {
    if (identical(link._fade, fade)) return;
    link._fade = fade;
    if (identical(link, _shown)) _followFade();
  }

  /// Forgets [fade] as [link]'s page's fade if it still is: the bar that
  /// reported it goes away, and the fade with it.
  void dropFade(GlassPageBarLink link, ValueListenable<double> fade) {
    if (identical(link._fade, fade)) fadedBy(link, null);
  }

  GlassPageBarLink? _swiped;
  late final Map<GlassBarKind, _Bar> _bars = {
    for (final kind in GlassBarKind.values) kind: _Bar(this, kind),
  };

  double get _now => _bars[GlassBarKind.navigation]!.motion.clock.now;

  // --- the route's events -------------------------------------------------

  /// Registers [route]'s page, which moves by [presence] and is named
  /// [title] where its bar names it with no text.
  GlassPageBarLink attach(
    ModalRoute<Object?> route, {
    required ValueListenable<double> presence,
    String? title,
  }) {
    final link = GlassPageBarLink._(this, route, presence, title);
    _pages.add(link);
    return link;
  }

  /// Unregisters [link]'s page.
  void detach(GlassPageBarLink link) {
    _pages.remove(link);
    for (final page in _pages) {
      if (identical(page._below, link)) page._below = null;
    }
    _settle();
    if (identical(_swiped, link)) _unswipe();
    link.titleRoom.dispose();
    if (_pages.isEmpty) _dispose();
  }

  // The last page went: the host goes with it, and the navigator's next
  // glass page makes a new one.
  void _dispose() {
    _following?.removeListener(_faded);
    _following = null;
    _painter.dispose();
    _fade.dispose();
    if (_navigator case final navigator?
        when identical(_hosts[navigator], this)) {
      _hosts[navigator] = null;
    }
  }

  /// Reports that [link]'s page was presented at [time], the call, with
  /// [below] under it: pushed when [animated], else added or put in place
  /// of another. A [current] page takes the bars: their layouts follow the
  /// ones they show, or grow in place when they show nothing.
  void presented(
    GlassPageBarLink link, {
    required GlassPageBarLink? below,
    required bool current,
    required bool animated,
    required double time,
  }) {
    link._below = below;
    _pages.remove(link);
    if (current) {
      _pages.add(link);
    } else {
      final under = below == null ? -1 : _pages.indexOf(below);
      _pages.insert(under < 0 ? _pages.length : under + 1, link);
    }
    _settle();
    if (!current) {
      _refreshShown(time);
      return;
    }
    final shown = _shown;
    final empty = shown == null || shown._coveredByForeign;
    _show(link);
    for (final bar in _bars.values) {
      bar.enqueue(
        _Change(
          link,
          time,
          animated ? bar.pushSpec : null,
          fromEmpty: empty,
        ),
      );
    }
  }

  /// Reports that the page below [link]'s page changed without a push of
  /// [link]: its back button follows.
  void previousChanged(
    GlassPageBarLink link, {
    required GlassPageBarLink? below,
    required double time,
  }) {
    if (identical(link._below, below)) return;
    link._below = below;
    if (identical(link, _shown)) _refreshShown(time);
  }

  /// Reports whether a route that is not a glass page covers [link]'s page.
  void coveredChanged(GlassPageBarLink link, {required bool covered}) {
    link._coveredByForeign = covered;
  }

  /// Reports that a route that is not a glass page left [link]'s page on
  /// top again: the bars, covered meanwhile, stand on its layouts.
  void revealed(GlassPageBarLink link) {
    link._coveredByForeign = false;
    if (identical(link, _shown)) return;
    _show(link);
    for (final bar in _bars.values) {
      bar.enqueue(_Change(link, _now, null));
    }
  }

  /// Reports that [link]'s page was popped or dismissed at [time]: the
  /// call, or the finger's lift after a swipe.
  void leaving(GlassPageBarLink link, {required double time}) {
    if (!identical(link, _shown)) return;
    final below = link._below;
    _show(below);
    _unswipe();
    for (final bar in _bars.values) {
      bar.enqueue(_Change(below, time, bar.pushSpec));
    }
  }

  /// Reports that [link]'s page left the overlay: the topmost glass page
  /// left takes the bar view.
  void finished(GlassPageBarLink link) {
    _pages.remove(link);
    _settle();
  }

  // What follows from the live pages: the topmost one paints the bars, and
  // a shown page that left them is no longer shown.
  void _settle() {
    _painter.value = _pages.isEmpty ? null : _pages.last;
    if (_shown case final shown? when !_pages.contains(shown)) _show(null);
  }

  /// Reports that a finger began to drag [link]'s page toward a pop: until
  /// it ends, each navigation bar capsule the page below also has leans
  /// toward its place there by [glassBarDrift] of the page's way out; the
  /// toolbar stays.
  void swipeStarted(GlassPageBarLink link) {
    if (!identical(link, _shown) || link._below == null) return;
    _unswipe();
    _swiped = link;
    link._presence?.addListener(_drift);
    _bars[GlassBarKind.navigation]!.rebuild();
    _drift();
  }

  /// Reports that the finger's drag of [link]'s page ended.
  void swipeEnded(GlassPageBarLink link) {
    if (!identical(_swiped, link)) return;
    _unswipe();
    _bars[GlassBarKind.navigation]!.motion.endDrift(_now);
  }

  void _unswipe() {
    _swiped?._presence?.removeListener(_drift);
    _swiped = null;
  }

  void _drift() {
    final presence = _swiped?._presence;
    if (presence == null) return;
    _bars[GlassBarKind.navigation]!.motion.setDrift(
      _swiped?._below?._layouts[GlassBarKind.navigation],
      glassBarDrift * (1 - presence.value).clamp(0.0, 1.0),
    );
  }

  // --- the page's declarations --------------------------------------------

  /// Records what [link]'s page declares for its navigation bar as it
  /// builds; a declaration that changes only callbacks moves nothing.
  void declare(
    GlassPageBarLink link,
    GlassBarDeclaration declaration, {
    Object? by,
  }) {
    _keep(link, by);
    final previous = link._declaration;
    link._declaration = declaration;
    link._declarer = by;
    final bar = _bars[GlassBarKind.navigation]!;
    final same =
        previous != null &&
        previous.automaticallyImplyLeading ==
            declaration.automaticallyImplyLeading &&
        previous.previousPageTitle == declaration.previousPageTitle &&
        previous.backButtonDisplayMode == declaration.backButtonDisplayMode &&
        previous.title == declaration.title &&
        _sameEntries(previous.leading, declaration.leading) &&
        _sameEntries(previous.trailing, declaration.trailing);
    _declared(bar, link, first: previous == null, same: same);
    if (same) return;
    // A title the page above names its back button after.
    for (final page in _pages) {
      if (identical(page._below, link) && identical(page, _shown)) {
        bar.enqueue(_Change(page, _now, GlassBarTransitionSpec.standard));
      }
    }
  }

  /// Records the items [link]'s page declares for its toolbar as it
  /// builds, or null for none.
  void declareToolbar(
    GlassPageBarLink link,
    List<GlassBarEntry>? items, {
    Object? by,
  }) {
    _keep(link, by);
    final previous = link._toolbar;
    link._toolbar = items;
    link._toolbarDeclarer = by;
    final same =
        previous != null && items != null && _sameEntries(previous, items);
    _declared(
      _bars[GlassBarKind.toolbar]!,
      link,
      first: previous == null && !link._declaredToolbar,
      same: same || (previous == null && items == null),
    );
    link._declaredToolbar = true;
  }

  /// Withdraws what [declarer] declared for [link]'s page, and [fade] as
  /// its fade, if they still stand: its tab was left or it went away, and
  /// the page's bar empties unless another bar declared since. It happens
  /// in the bars' next layout, in this frame, once a bar that shows now
  /// has declared; a declaration of [declarer] before then cancels it.
  void withdraw(
    GlassPageBarLink link,
    Object declarer, {
    ValueListenable<double>? fade,
  }) {
    _withdrawals.add((link: link, declarer: declarer, fade: fade));
    for (final bar in _bars.values) {
      bar.rebuild();
    }
  }

  final List<
    ({GlassPageBarLink link, Object declarer, ValueListenable<double>? fade})
  >
  _withdrawals = [];

  void _keep(GlassPageBarLink link, Object? declarer) {
    if (declarer == null || _withdrawals.isEmpty) return;
    _withdrawals.removeWhere(
      (w) => identical(w.link, link) && identical(w.declarer, declarer),
    );
  }

  void _drainWithdrawals() {
    if (_withdrawals.isEmpty) return;
    final pending = List.of(_withdrawals);
    _withdrawals.clear();
    for (final (:link, :declarer, :fade) in pending) {
      _withdraw(link, declarer);
      if (fade != null) dropFade(link, fade);
    }
  }

  void _withdraw(GlassPageBarLink link, Object declarer) {
    if (!_pages.contains(link)) return;
    if (identical(link._declarer, declarer)) {
      link._declarer = null;
      link._declaration = null;
      _declared(
        _bars[GlassBarKind.navigation]!,
        link,
        first: false,
        same: false,
      );
    }
    if (identical(link._toolbarDeclarer, declarer)) {
      link._toolbarDeclarer = null;
      link._toolbar = null;
      _declared(_bars[GlassBarKind.toolbar]!, link, first: false, same: false);
    }
  }

  void _declared(
    _Bar bar,
    GlassPageBarLink link, {
    required bool first,
    required bool same,
  }) {
    if (same) {
      bar.rememberButtons(link);
      return;
    }
    final shown = identical(link, _shown);
    if (shown && !first) {
      bar.enqueue(_Change(link, _now, GlassBarTransitionSpec.standard));
    } else if (shown && !bar.changes.any((c) => identical(c.page, link))) {
      // The page's first declaration with no change waiting for it (a
      // standalone page, or a bar added after its push was applied): it
      // stands.
      bar.enqueue(_Change(link, _now, null));
    } else {
      bar.rebuild();
    }
  }

  void _refreshShown(double time) {
    final shown = _shown;
    if (shown == null) return;
    _bars[GlassBarKind.navigation]!.enqueue(
      _Change(shown, time, GlassBarTransitionSpec.standard),
    );
  }

  static bool _sameEntries(List<GlassBarEntry> x, List<GlassBarEntry> y) {
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      final same = switch ((x[i], y[i])) {
        (final GlassBarSpacer p, final GlassBarSpacer q) =>
          p.flexible == q.flexible,
        (final GlassBarButton p, final GlassBarButton q) =>
          _ItemIdentity.of(p) == _ItemIdentity.of(q) &&
              (p.menuChildren == null) == (q.menuChildren == null) &&
              (p.onPressed == null) == (q.onPressed == null),
        (final GlassBarProminentButton p, final GlassBarProminentButton q) =>
          _ItemIdentity.of(p) == _ItemIdentity.of(q) &&
              (p.onPressed == null) == (q.onPressed == null),
        (final GlassBarCustomItem p, final GlassBarCustomItem q) =>
          _ItemIdentity.of(p) == _ItemIdentity.of(q) && p.child == q.child,
        _ => false,
      };
      if (!same) return false;
    }
    return true;
  }

  // The pages whose layout [bar] needs: the shown one, those its changes
  // head to, and, for the navigation bar, the page below a swiped one.
  Iterable<GlassPageBarLink> _measured(_Bar bar) sync* {
    final seen = <GlassPageBarLink>{};
    final shown = _shown;
    if (shown != null && seen.add(shown)) yield shown;
    for (final change in bar.changes) {
      final page = change.page;
      if (page != null && seen.add(page)) yield page;
    }
    if (bar.kind == GlassBarKind.navigation) {
      final below = _swiped?._below;
      if (below != null && seen.add(below)) yield below;
    }
  }
}
