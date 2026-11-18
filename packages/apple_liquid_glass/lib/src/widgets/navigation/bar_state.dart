part of 'bar.dart';

// A change of the bar waiting for the layout it heads to.
final class _Change {
  _Change(this.page, this.time, this.spec, {this.fromEmpty = false});

  // The page whose layout the bar heads to; null is an empty bar.
  final GlassPageBarLink? page;
  final double time;

  // Null snaps.
  final GlassBarTransitionSpec? spec;

  // The bar starts empty: the page's groups appear in place.
  final bool fromEmpty;
}

// A button the bar builds: an item of a page or the back button.
final class _Button {
  _Button.item(this.item, this.kind) : back = null;
  _Button.back(_Back this.back) : item = null, kind = GlassBarButtonKind.back;

  final GlassBarItem? item;
  final _Back? back;
  final GlassBarButtonKind kind;
}

final class _Back {
  _Back({required this.title, required this.mode, required this.onPressed});

  // The page below's name, or null to say "Back".
  final String? title;
  final GlassBackButtonDisplayMode mode;
  final VoidCallback onPressed;

  // What the button shows beside its chevron: nothing when minimal.
  String? shownIn(BuildContext context) => switch (mode) {
    GlassBackButtonDisplayMode.minimal => null,
    GlassBackButtonDisplayMode.generic => _back(context),
    GlassBackButtonDisplayMode.title => title ?? _back(context),
  };

  // What assistive technology reads: the name it shows, or "Back".
  String labelIn(BuildContext context) => shownIn(context) ?? _back(context);

  static String _back(BuildContext context) =>
      GlassLocalizations.of(context).backButtonLabel;
}

// The back button keeps one identity across pages: it stays when both
// pages have one.
const Object _backId = 'glass.back';

// One bar of a host: its motion, the changes waiting for their layouts,
// its glass and the buttons its view builds.
final class _Bar {
  _Bar(this.host, this.kind);

  final GlassBarHost host;
  final GlassBarKind kind;
  late final GlassBarMotion motion = GlassBarMotion(spec: pushSpec);

  // Only the navigation bar fades for a stacked search.
  ValueListenable<double>? get fade =>
      kind == GlassBarKind.navigation ? host._fade : null;

  late final MotionSelection<Object?> _steps = motion.select<Object?>(
    (_) => null,
    equals: (_, _) => false,
  );
  final List<_Change> changes = [];
  final List<ValueNotifier<GlassFrame>> container = [];
  final List<ValueNotifier<GlassFrame>> apart = [];
  final Map<Object, GlassBarItemFrame> itemFrames = {};
  final Map<Object, double> widths = {};
  // The buttons the bar knows, by identity; a leaving one keeps its last.
  final Map<Object, _Button> buttons = {};
  // Which capsules are prominent, by their layout identity.
  final Set<Object> prominent = {};
  Set<Object> built = const {};
  Set<Object> measuredIds = const {};
  double width = 0;
  bool rtl = false;
  Element? view;
  // The capsule of a prominent item, from the theme.
  Color? tint;

  GlassBarItemStyle? itemStyleOf(BuildContext context) => switch (kind) {
    GlassBarKind.navigation => GlassNavigationBarStyle.maybeOf(
      context,
    )?.itemStyle,
    GlassBarKind.toolbar => GlassToolbarStyle.maybeOf(context)?.itemStyle,
  };

  // The frames follow the motion while the bar's items are on screen.
  _RenderBarItems? get items => _items;
  _RenderBarItems? _items;
  set items(_RenderBarItems? items) {
    if (_items == null && items != null) _steps.addRenderListener(publish);
    if (_items != null && items == null) _steps.removeRenderListener(publish);
    _items = items;
  }

  // A finger on a button lifts the button's whole capsule on the glass
  // button's motion (bars passport): the capsule's identity and where the
  // touched button's box sits in the capsule.
  Object? pressed;
  Offset _pressOrigin = Offset.zero;

  bool get _navigation => kind == GlassBarKind.navigation;

  GlassBarCapsuleFrame? _capsuleOf(Object item) => motion.capsuleOf(item);

  // The capsules whose glass a menu has taken over, by the item that opened
  // the menu.
  final Map<Object, Object> _menuCapsules = {};

  /// Hides or shows the capsule of [item], whose menu grows out of it.
  void menuShowing(Object item, {required bool showing}) {
    if (showing) {
      final capsule = _capsuleOf(item);
      if (capsule == null) return;
      _menuCapsules[item] = capsule.id;
    } else {
      _menuCapsules.remove(item);
    }
    if (items != null) publish();
  }

  /// Whether a menu has taken over the capsule [item] stands in.
  bool inMenuCapsule(Object item) =>
      _menuCapsules.isNotEmpty &&
      _menuCapsules.containsValue(_capsuleOf(item)?.id);

  /// Whether the menu of [item] shows.
  bool menuShows(Object item) => _menuCapsules.containsKey(item);

  /// What a menu of [item] grows out of, in [overlay]'s coordinates: the
  /// item's zone where the bar paints it, and the capsule around it.
  MenuSource? menuSource(Object item, RenderBox overlay) {
    final capsule = _capsuleOf(item);
    final zone = zoneRectOf(item);
    final global = zones?.sourceOf(item).geometry?.rect;
    if (capsule == null || zone == null || global == null || zone.isEmpty) {
      return null;
    }
    final sx = global.width / zone.width;
    final sy = global.height / zone.height;
    Rect place(Rect rect) => Rect.fromPoints(
      overlay.globalToLocal(
        global.topLeft +
            Offset((rect.left - zone.left) * sx, (rect.top - zone.top) * sy),
      ),
      overlay.globalToLocal(
        global.topLeft +
            Offset(
              (rect.right - zone.left) * sx,
              (rect.bottom - zone.top) * sy,
            ),
      ),
    );
    return MenuCapsuleSource(
      capsule: place(capsule.rect),
      item: place(zone),
      height: metrics.buttonHeight,
      alone: capsuleItems(item).length < 2,
    );
  }

  /// The box [item] takes input in: its slot across the capsule's height,
  /// where the motion paints it now, without its scale.
  Rect? zoneRectOf(Object item) {
    final frame = itemFrames[item];
    if (frame == null) return null;
    return Rect.fromCenter(
      center: frame.center,
      width: math.max(frame.size.width, widths[item] ?? 0),
      height: metrics.capsuleHeight,
    );
  }

  /// Where [item] lies for input and accessibility now: it takes none
  /// while it leaves, and fades with the item and the bar.
  InputZoneFrame? zoneFrameOf(Object item) {
    final frame = itemFrames[item];
    final rect = zoneRectOf(item);
    if (frame == null || rect == null) return null;
    return InputZoneFrame(
      rect,
      opacity: frame.presence * (fade?.value ?? 1),
      takesInput: !frame.leaving,
      radius: BorderRadius.circular(metrics.capsuleHeight / 2),
    );
  }

  /// The zones of the items: their states, focus and the source a menu
  /// grows out of. The band that shows the bar owns it.
  InputZonesController<Object>? zones;

  /// Notifies when the items' frames move.
  final frames = _Frames();

  final Map<Object, _ItemInput> _inputs = {};

  /// The input of [item], kept across builds by its identity.
  _ItemInput inputOf(Object item) =>
      _inputs.putIfAbsent(item, () => _ItemInput(this, item));

  /// Grows the pools of capsule frames to [count] each.
  void grow(int count) {
    for (final pool in [container, apart]) {
      while (pool.length < count) {
        pool.add(ValueNotifier(const GlassFrame(rect: Rect.zero, opacity: 0)));
      }
    }
  }

  /// The band that owned [zones] goes: the bar's zones and capsule frames
  /// go with it.
  void letGo(InputZonesController<Object> zones) {
    if (!identical(this.zones, zones)) return;
    this.zones = null;
    for (final frame in [...container, ...apart]) {
      frame.dispose();
    }
    container.clear();
    apart.clear();
  }

  /// Forgets the input of items the bar no longer builds.
  void keepInputs(Iterable<Object> items) {
    final kept = items.toSet();
    _inputs.removeWhere((id, _) => !kept.contains(id));
  }

  /// The items of [item]'s capsule, [item] included, with their frames in it.
  List<(Object, Rect)> capsuleItems(Object item) {
    final capsule = _capsuleOf(item);
    if (capsule == null) return const [];
    return [
      for (final MapEntry(key: id, value: frame) in itemFrames.entries)
        if (_capsuleOf(id)?.id == capsule.id)
          (
            id,
            Rect.fromCenter(
              center: frame.center - capsule.rect.topLeft,
              width: frame.size.width,
              height: frame.size.height,
            ),
          ),
    ];
  }

  /// The size of [item]'s capsule.
  Size? capsuleSize(Object item) => _capsuleOf(item)?.rect.size;

  /// Lifts [item]'s capsule under a finger that touches the item's zone at
  /// [position], in the zone's coordinates, at time [t].
  void pressDown(Object item, double t, Offset position) {
    final zone = zoneRectOf(item);
    final capsule = _capsuleOf(item);
    if (zone == null || capsule == null) return;
    final lift = pressed == capsule.id ? motion.press : null;
    final press = lift ?? GlassPress(size: capsule.rect.size);
    press.size = capsule.rect.size;
    pressed = capsule.id;
    _pressOrigin = zone.topLeft - capsule.rect.topLeft;
    motion.pressDown(press, t, _pressOrigin + position);
  }

  void pressMove(double t, Offset position) =>
      motion.press?.pointerMove(t, _pressOrigin + position);

  void pressUp(double t, Offset position) =>
      motion.press?.pointerUp(t, _pressOrigin + position);

  void pressCancel(double t) => motion.press?.pointerCancel(t);

  /// How the pressed capsule moves [item] with it, in the bar's
  /// coordinates, or null when [item] is not in it.
  Matrix4? liftOf(Object item) {
    final motion = this.motion.press;
    if (motion == null || motion.isAtRest) return null;
    final capsule = _capsuleOf(item);
    if (capsule == null || capsule.id != pressed) return null;
    final center = capsule.rect.center;
    final transform = Matrix4.translationValues(
      center.dx + motion.lean.dx,
      center.dy + motion.lean.dy,
      0,
    );
    transform.scaleByDouble(motion.scaleX, motion.scaleY, 1, 1);
    transform.translateByDouble(-center.dx, -center.dy, 0, 1);
    return transform;
  }

  GlassBarMetrics get metrics =>
      _navigation ? GlassBarMetrics.navigation : GlassBarMetrics.toolbar;

  /// The space between the screen's sides and the outer capsules.
  double get sideInset =>
      _navigation ? navigationSideInset : GlassToolbar.sideInset;

  /// The tuning of a change on a push or a pop: a navigation bar's own
  /// timing; for a toolbar, the standard timing of an item replacement (an
  /// approximation: a toolbar's push is filmed on the simulator only).
  GlassBarTransitionSpec get pushSpec => _navigation
      ? GlassBarTransitionSpec.navigation
      : GlassBarTransitionSpec.standard;

  void enqueue(_Change change) {
    changes.add(change);
    rebuild();
  }

  // Whether the view builds again in its items' resolve phase.
  bool _rebuildInResolve = false;

  /// Builds the view again in this frame. While the framework builds or
  /// lays out (a page declares as it builds, maybe under the app's
  /// LayoutBuilder; the bar's own layout applies a change), marking the
  /// view would assert or wait for the next frame: the items' resolve phase
  /// marks it instead, and it builds and lays out again in the same frame.
  void rebuild() {
    final view = this.view;
    if (view == null || !view.mounted) return;
    final items = _items;
    if (items != null &&
        items.attached &&
        SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks) {
      _rebuildInResolve = true;
      items.scheduleResolve();
      return;
    }
    view.markNeedsBuild();
  }

  /// The items' resolve phase: withdrawals still waiting apply, the pages
  /// take their title rooms, and the view builds again if a change asked
  /// for it during the frame.
  void resolve() {
    host._drainWithdrawals();
    giveRooms();
    if (!_rebuildInResolve) return;
    _rebuildInResolve = false;
    final view = this.view;
    if (view != null && view.mounted) view.markNeedsBuild();
  }

  /// The runs of [page]'s bar, each a list of capsules with the identities
  /// of their buttons: a navigation bar's leading and trailing sides, a
  /// toolbar's runs between flexible spaces; a repeated identity is
  /// numbered across the whole bar.
  List<List<List<(Object, _Button)>>> runs(GlassPageBarLink page) {
    final seen = <Object, int>{};
    if (!_navigation) {
      final items = page._toolbar;
      if (items == null) return const [];
      final runs = <List<GlassBarEntry>>[[]];
      for (final entry in items) {
        if (entry is GlassBarSpacer && entry.flexible) {
          runs.add([]);
        } else {
          runs.last.add(entry);
        }
      }
      return [for (final run in runs) _capsules(page, run, seen)];
    }
    final declaration = page._declaration;
    if (declaration == null) return const [];
    final leading = declaration.leading.isEmpty
        ? _back(page, declaration)
        : _capsules(page, declaration.leading, seen);
    return [leading, _capsules(page, declaration.trailing, seen)];
  }

  List<List<(Object, _Button)>> _back(
    GlassPageBarLink page,
    GlassBarDeclaration declaration,
  ) {
    final below = page._below;
    if (below == null || !declaration.automaticallyImplyLeading) {
      return const [];
    }
    final route = page.route;
    return [
      [
        (
          _backId,
          _Button.back(
            _Back(
              title:
                  declaration.previousPageTitle ??
                  below._declaration?.title ??
                  below._title,
              mode: declaration.backButtonDisplayMode,
              onPressed: () => route?.navigator?.maybePop<Object?>(),
            ),
          ),
        ),
      ],
    ];
  }

  List<List<(Object, _Button)>> _capsules(
    GlassPageBarLink page,
    List<GlassBarEntry> entries,
    Map<Object, int> seen,
  ) {
    final out = <List<(Object, _Button)>>[];
    var run = <(Object, _Button)>[];
    void close() {
      if (run.isNotEmpty) out.add(run);
      run = [];
    }

    for (final entry in entries) {
      switch (entry) {
        case GlassBarSpacer():
          close();
        case GlassBarItem():
          final identity = _ItemIdentity.of(entry);
          final n = seen[identity] = (seen[identity] ?? -1) + 1;
          final base = identity.crossesPages
              ? identity
              : _PageId(page, identity);
          final id = n == 0 ? base : GlassBarItemId(base, n);
          final (kind, prominent) = switch (entry) {
            GlassBarCustomItem() => (GlassBarButtonKind.custom, false),
            GlassBarButton(icon: _?) => (GlassBarButtonKind.icon, false),
            GlassBarButton() => (GlassBarButtonKind.label, false),
            GlassBarProminentButton(icon: _?) => (
              GlassBarButtonKind.icon,
              true,
            ),
            GlassBarProminentButton() => (GlassBarButtonKind.label, true),
          };
          if (prominent) {
            close();
            out.add([(id, _Button.item(entry, kind))]);
            continue;
          }
          run.add((id, _Button.item(entry, kind)));
      }
    }
    close();
    return out;
  }

  void rememberButtons(GlassPageBarLink page) {
    for (final run in runs(page)) {
      for (final capsule in run) {
        for (final (id, button) in capsule) {
          buttons[id] = button;
        }
      }
    }
  }

  /// The buttons the view builds: every item a measured page has and every
  /// item the motion still draws.
  Map<Object, _Button> roster() {
    final pages = host._measured(this).toList();
    for (final page in pages) {
      rememberButtons(page);
    }
    measuredIds = {
      for (final page in pages)
        for (final run in runs(page))
          for (final capsule in run)
            for (final (id, _) in capsule) id,
    };
    final ids = {...measuredIds, for (final frame in motion.items) frame.id};
    buttons.removeWhere((id, _) => !ids.contains(id));
    built = ids;
    return {for (final id in ids) id: buttons[id]!};
  }

  /// The title rooms the latest layout computed, which the pages take in
  /// the frame's resolve phase ([giveRooms]).
  List<(GlassPageBarLink, GlassTitleRoom)> pendingRooms = const [];

  /// Gives the pages the title rooms the latest layout computed.
  void giveRooms() {
    final rooms = pendingRooms;
    pendingRooms = const [];
    for (final (page, room) in rooms) {
      if (host._pages.contains(page)) page.titleRoom.value = room;
    }
  }

  /// Takes the content widths the view measured in a bar [width] wide and
  /// applies the waiting changes, each at its own time.
  void measured(
    Map<Object, double> widths,
    double width, {
    required bool rtl,
  }) {
    final resized = width != this.width || rtl != this.rtl;
    this.width = width;
    this.rtl = rtl;
    this.widths.addAll(widths);
    final pages = host._measured(this).toList();
    final rooms = <(GlassPageBarLink, GlassTitleRoom)>[];
    prominent.clear();
    for (final page in pages) {
      final runs = this.runs(page);
      final layout = page._layouts[kind] = _layoutOf(runs);
      // The layout lists trailing capsules from the edge in, so a capsule
      // is found by its buttons, not by its place in [runs].
      final tinted = {
        for (final run in runs)
          for (final capsule in run)
            if (capsule.first.$2.item is GlassBarProminentButton)
              capsule.first.$1,
      };
      for (final capsule in layout) {
        if (capsule.items.any((item) => tinted.contains(item.id))) {
          prominent.add(capsule.id);
        }
      }
      if (_navigation) {
        final room = _roomOf(layout);
        if (page.titleRoom.value != room) rooms.add((page, room));
      }
    }
    // The titles are laid out in their pages, which this layout must not
    // touch: they take their room in the frame's resolve phase, and lay
    // out again in this frame.
    pendingRooms = rooms;
    final pending = List.of(changes);
    changes.clear();
    for (final change in pending) {
      final target =
          change.page?._layouts[kind] ?? const <GlassBarCapsuleLayout>[];
      if (change.fromEmpty) {
        motion.setLayout(change.time, const [], animated: false);
      }
      motion.setLayout(
        change.time,
        target,
        animated: change.spec != null,
        transition: change.spec,
      );
    }
    if (pending.isEmpty && resized) {
      motion.setLayout(
        host._now,
        host._shown?._layouts[kind] ?? const [],
        animated: false,
      );
    }
    publish();
  }

  List<GlassBarCapsuleLayout> _layoutOf(
    List<List<List<(Object, _Button)>>> runs,
  ) {
    List<GlassBarCapsuleSpec> specs(List<List<(Object, _Button)>> run) => [
      for (final capsule in run)
        GlassBarCapsuleSpec([
          for (final (id, button) in capsule)
            GlassBarButtonSpec(
              id,
              button.kind == GlassBarButtonKind.back
                  ? _backLabelWidth(widths[id] ?? 0, button.back!)
                  : widths[id] ?? 0,
              button.kind,
            ),
        ]),
    ];
    if (runs.isEmpty) return const [];
    return layoutGlassBar(
      leading: specs(runs.first),
      trailing: runs.length > 1 ? specs(runs.last) : const [],
      center: [
        for (var i = 1; i < runs.length - 1; i++) specs(runs[i]),
      ],
      width: width,
      top: 0,
      leadingInset: sideInset,
      trailingInset: sideInset,
      metrics: metrics,
      rtl: rtl,
    );
  }

  static double _backLabelWidth(double built, _Back back) {
    const metrics = GlassBarMetrics.navigation;
    if (back.mode == GlassBackButtonDisplayMode.minimal) return 0;
    return math.max(
      0,
      built -
          metrics.backChevronInset -
          metrics.backChevronWidth -
          metrics.backChevronGap -
          metrics.backTrailingPadding,
    );
  }

  /// The space between an inline title and the capsules beside it
  /// (`titleControlPadding`, read from UIKit).
  static const double _titleControlPadding = 12;

  GlassTitleRoom _roomOf(List<GlassBarCapsuleLayout> layout) {
    const padding = _titleControlPadding;
    var start = sideInset;
    var end = width - sideInset;
    for (final capsule in layout) {
      final leading = capsule.segment == GlassBarSegment.leading;
      if (leading != rtl) {
        start = math.max(start, capsule.rect.right + padding);
      } else {
        end = math.min(end, capsule.rect.left - padding);
      }
    }
    return (start: start, end: end);
  }

  void publish() {
    final fade = this.fade?.value ?? 1;
    final press = motion.press;
    if (press == null) pressed = null;
    final joined = <GlassBarCapsuleFrame>[];
    final apartFrames = <GlassBarCapsuleFrame>[];
    for (final capsule in motion.capsules) {
      (capsule.apart ? apartFrames : joined).add(capsule);
    }
    void write(
      List<ValueNotifier<GlassFrame>> pool,
      List<GlassBarCapsuleFrame> frames,
    ) {
      for (var i = 0; i < pool.length; i++) {
        if (i >= frames.length) {
          pool[i].value = const GlassFrame(rect: Rect.zero, opacity: 0);
          continue;
        }
        final frame = frames[i];
        final lift = frame.id == pressed ? press : null;
        pool[i].value = GlassFrame(
          rect: lift == null ? frame.rect : frame.rect.shift(lift.lean),
          scaleX: lift?.scaleX ?? 1,
          scaleY: lift?.scaleY ?? 1,
          glow: lift?.touchGlow,
          opacity: _menuCapsules.containsValue(frame.id)
              ? 0
              : frame.opacity * fade,
          tint: prominent.contains(frame.id) ? tint : null,
        );
      }
    }

    write(container, joined);
    write(apart, apartFrames);
    itemFrames.clear();
    for (final frame in motion.items) {
      itemFrames[frame.id] = frame;
    }
    items?.moved();
    frames.notify();
    final ids = {for (final f in motion.items) f.id};
    // A new item joins the roster; one that has left drops from it.
    if (joined.length > container.length ||
        apartFrames.length > apart.length ||
        !built.containsAll(ids) ||
        built.difference(ids).difference(measuredIds).isNotEmpty) {
      rebuild();
    }
  }
}

/// Tells the bar's zones that its items moved.
final class _Frames implements Listenable {
  final List<VoidCallback> _listeners = [];

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}
