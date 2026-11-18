import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/widgets/controls/search_field.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar_entry.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/chrome.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/search_host.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

part 'package:apple_liquid_glass/src/widgets/navigation/navigation_bar_search.dart';

/// The look of a [GlassNavigationBar].
@immutable
class GlassNavigationBarStyle extends GlassStyle<GlassNavigationBarStyle> {
  /// Creates a style.
  const GlassNavigationBarStyle({
    this.backgroundColor,
    this.foregroundColor,
    this.titleTextStyle,
    this.largeTitleTextStyle,
    this.itemStyle,
  });

  /// The theme's [GlassNavigationBarStyle] at [context], or null without
  /// one: the look between a widget's own style and its defaults.
  static GlassNavigationBarStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassNavigationBarStyle>(context);

  /// A fill behind the bar (UIKit `backgroundColor` of the bar's
  /// appearance); none by default, as iOS 27's bar shows the content under
  /// it through its edge effect.
  final Color? backgroundColor;

  /// The color of the titles; [GlassColors.label] by default.
  final Color? foregroundColor;

  /// The inline title's style: 17 points semibold by default.
  final TextStyle? titleTextStyle;

  /// The large title's style: 34 points bold by default.
  final TextStyle? largeTitleTextStyle;

  /// The look of the bar's items; read from the theme's style only (see
  /// [GlassBarItemStyle]).
  final GlassBarItemStyle? itemStyle;

  /// This style over [other]: a null field takes [other]'s.
  @override
  GlassNavigationBarStyle merge(GlassNavigationBarStyle? other) {
    if (other == null) return this;
    return GlassNavigationBarStyle(
      backgroundColor: backgroundColor ?? other.backgroundColor,
      foregroundColor: foregroundColor ?? other.foregroundColor,
      titleTextStyle:
          other.titleTextStyle?.merge(titleTextStyle) ?? titleTextStyle,
      largeTitleTextStyle:
          other.largeTitleTextStyle?.merge(largeTitleTextStyle) ??
          largeTitleTextStyle,
      itemStyle: itemStyle?.merge(other.itemStyle) ?? other.itemStyle,
    );
  }

  /// The style between this one and [other] at [t].
  @override
  GlassNavigationBarStyle lerp(GlassNavigationBarStyle other, double t) {
    if (identical(this, other)) return this;
    final color = GlassStyle.lerpNullable(GlassDynamicColor.lerp);
    final text = GlassStyle.lerpNullable(TextStyle.lerp);
    return GlassNavigationBarStyle(
      backgroundColor: color(backgroundColor, other.backgroundColor, t),
      foregroundColor: color(foregroundColor, other.foregroundColor, t),
      titleTextStyle: text(titleTextStyle, other.titleTextStyle, t),
      largeTitleTextStyle: text(
        largeTitleTextStyle,
        other.largeTitleTextStyle,
        t,
      ),
      itemStyle: GlassBarItemStyle.lerp(itemStyle, other.itemStyle, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassNavigationBarStyle &&
      other.backgroundColor == backgroundColor &&
      other.foregroundColor == foregroundColor &&
      other.titleTextStyle == titleTextStyle &&
      other.largeTitleTextStyle == largeTitleTextStyle &&
      other.itemStyle == itemStyle;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    foregroundColor,
    titleTextStyle,
    largeTitleTextStyle,
    itemStyle,
  );
}

/// An iOS 27 navigation bar: a title and glass capsules of buttons at the
/// top of a page, with an optional large title.
///
/// UIKit: `UINavigationBar` with a `UINavigationItem`. SwiftUI: the bar of
/// a `NavigationStack`. Flutter: `CupertinoNavigationBar`,
/// `CupertinoSliverNavigationBar`.
///
/// Pass a [title] or a [largeTitle], and bar items such as `GlassBarButton`
/// in [leading] and [trailing]; items side by side share a capsule. A page
/// pushed as a `GlassPageRoute` gets a back button by itself. Put the bar
/// in a [GlassPageScaffold] as its `navigationBar`, and wrap the page's
/// scroll view in a [GlassContentScroll] so the large title and the scroll
/// edge effect follow it. [searchField] stacks a [GlassSearchField] under
/// the titles.
///
/// ```dart
/// GlassPageScaffold(
///   navigationBar: GlassNavigationBar(
///     largeTitle: const Text('Inbox'),
///     trailing: [
///       GlassBarButton(
///         icon: const Icon(CupertinoIcons.square_pencil),
///         onPressed: () => debugPrint('compose'),
///       ),
///     ],
///   ),
///   child: GlassContentScroll(
///     child: ListView(children: const [Text('No mail')]),
///   ),
/// )
/// ```
///
/// The capsules are `GlassSurface`s in one `GlassGroup`. The liquid
/// renderer draws them as liquid glass in one shared layer, so capsules
/// that come close flow together; the fake renderer does the same with
/// blurred and lit glass; the flat renderer, which also draws when no
/// `GlassScope` is above, draws each as a translucent fill with a hairline
/// rim and a soft shadow. The bar puts no glass behind its titles: the
/// page's scroll edge effect separates the content there.
///
/// The bar is a row 54 points tall under the status bar: [leading] and
/// [trailing] capsules 16 points in from the sides, centered 22 points
/// below the status bar, and [title] centered on the bar when it fits
/// between them, else from the leading side, truncated. With a
/// [largeTitle] the bar is 52 points taller: the large title sits under
/// the row and scrolls away with the content of the page's
/// [GlassContentScroll], after which the inline title rises in, 0.45 s in
/// and 0.7 s out, from 15 points below and blurred; a jump of the content
/// switches it at once. A finger's release that leaves the large title
/// partly away springs to the nearer end.
///
/// The pages of one navigator pushed as `GlassPageRoute`s share one bar,
/// as UIKit's navigation controller does: on a push, a pop and an edge
/// swipe its glass stays in place and the capsules change into the next
/// page's, each side into itself, groups growing out of a capsule of
/// their side or appearing in place with a swell, items travelling,
/// timed from the push or pop call; during a swipe the capsules the page
/// below also has lean halfway toward their places there at most. The
/// titles belong to the page and move with it. A page with a glass page
/// below gets a back button, named after that page's title, as the first
/// leading capsule; [leading] replaces it and [automaticallyImplyLeading]
/// false removes it. Elsewhere, the bar draws its capsules for its page
/// alone.
///
/// Fidelity. The row's layout is measured on iOS 27: 46 bars match within
/// 1 point. The inline title's timing is fitted on the device and read
/// from UIKit. The capsules' change on a push and a pop is checked against
/// device recordings.
class GlassNavigationBar extends StatefulWidget implements PreferredSizeWidget {
  /// Creates a navigation bar.
  const GlassNavigationBar({
    this.leading = const [],
    this.title,
    this.largeTitle,
    this.trailing = const [],
    this.automaticallyImplyLeading = true,
    this.previousPageTitle,
    this.backButtonDisplayMode = GlassBackButtonDisplayMode.title,
    this.searchField,
    this.style,
    super.key,
  });

  /// The capsules at the leading edge; when not empty they replace the
  /// back button (UIKit `leftBarButtonItems`).
  final List<GlassBarEntry> leading;

  /// The inline title; [largeTitle] when null.
  final Widget? title;

  /// The large title under the row, or null for an inline title only.
  final Widget? largeTitle;

  /// The capsules at the trailing edge (UIKit `rightBarButtonItems`).
  final List<GlassBarEntry> trailing;

  /// Whether the page gets a back button when [leading] is empty and a
  /// glass page lies below (UIKit `hidesBackButton` false).
  final bool automaticallyImplyLeading;

  /// The back button's name for the page below, in place of that page's
  /// title.
  final String? previousPageTitle;

  /// How the back button names the page below.
  final GlassBackButtonDisplayMode backButtonDisplayMode;

  /// A [GlassSearchField] stacked under the titles, or null for none.
  ///
  /// UIKit: `UINavigationItem.searchController` with the stacked placement.
  /// SwiftUI: `searchable` in a `NavigationStack`. Flutter:
  /// `CupertinoSliverNavigationBar.search`.
  ///
  /// At rest the field is 44 points tall on a plain fill, 16 points from
  /// the sides and 10 above the content. Scrolling the content first folds
  /// the field away, its height shrinking with the scroll, its text gone
  /// by a fifth of the way and its fill fading out between 80 and 95
  /// percent of it, then the large title goes (read from UIKit, notes
  /// private). Focusing the field presents the search on one spring
  /// (damping 0.8, response 0.34, read from UIKit): the page, the large
  /// title and the field rise until the field sits under the status bar,
  /// the field narrows for a close button that slides in 40 points from the
  /// side, and its plain fill turns to glass on a critically damped spring
  /// of response 0.32 (read from UIKit). The large title, the inline title
  /// and the bar's capsules fade in time while this happens, the capsules
  /// and the inline title where they stand; nothing is cut (an iPhone 16
  /// Pro's layers). The close button clears the field and ends the search;
  /// the page comes back down. A field folded away by a scroll
  /// presents from where it rests: the rise is not shortened (an
  /// approximation).
  final Widget? searchField;

  /// The look, over the theme's.
  final GlassNavigationBarStyle? style;

  /// The height of the row under the status bar (navigation bar passport).
  static const double height = 54;

  /// The height a large title adds under the row (navigation bar
  /// passport).
  static const double largeTitleHeight = 52;

  /// The height a stacked search field adds under the titles: the field
  /// and the space below it.
  static const double searchFieldHeight =
      _StackedMetrics.fieldHeight + _StackedMetrics.bottomGap;

  double get _search => searchField == null ? 0 : searchFieldHeight;

  @override
  Size get preferredSize => Size.fromHeight(height + scrolledUnderAfter);

  /// How far the content scrolls before it passes under the bar: the
  /// large title and the search field it scrolls away first.
  @internal
  double get scrolledUnderAfter =>
      (largeTitle == null ? 0 : largeTitleHeight) + _search;

  @override
  State<GlassNavigationBar> createState() => _GlassNavigationBarState();
}

class _GlassNavigationBarState extends State<GlassNavigationBar> {
  late final MotionClock _clock;
  late final _title = PresenceMotion.inlineTitle(
    shown: widget.largeTitle == null,
    clock: _clock,
  );
  late final _opacity = MotionSelection(
    () => _title.presence.value.clamp(0.0, 1.0),
    clock: _clock,
  );
  late final _rise = MotionSelection(
    () => _title.traits.reduceMotion
        ? 0.0
        : _Metrics.hiddenOffset * (1 - _opacity.value),
    clock: _clock,
  );
  late final _blur = MotionSelection(
    () => _title.traits.reduceMotion
        ? 0.0
        : _Metrics.hiddenBlur * (1 - _opacity.value),
    clock: _clock,
  );
  ValueNotifier<MotionScroll?>? _active;
  MotionScroll? _scroll;
  MotionSelection<ScrollMetrics?>? _metrics;
  MotionSelection<double>? _scrolledBy;
  late final _followed = ContentOffsetMotion(clock: _clock);
  late final MotionSelection<double> _offset = _followed.select(
    (m) => m.offset.value,
  );
  MotionSelection<double>? _away;
  double? _awayDelay;
  bool _laidOut = false;
  late final _bar = GlassBarClient(this);
  late final _fade = MotionValue<double>(
    1,
    restDistance: MotionRest.opacity,
    clock: _clock,
  );

  @override
  void initState() {
    super.initState();
    _clock = MotionClockScope.of(context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bar.resolve(context);
    _title.traits = MotionTraitsOverride.of(context);
    final active = GlassChrome.maybeOf(context)?.active;
    if (identical(active, _active)) return;
    _active?.removeListener(_follow);
    _active = active;
    active?.addListener(_follow);
    _follow();
  }

  @override
  void didUpdateWidget(GlassNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.largeTitle == null) != (widget.largeTitle == null)) {
      _laidOut = false;
      _scrolled();
    }
  }

  @override
  void dispose() {
    if (_bar.link case final link?) link.host.dropFade(link, _fade);
    _bar.dispose(fade: _fade);
    _active?.removeListener(_follow);
    _metrics?.removeRenderListener(_scrolled);
    _scrolledBy?.removeRenderListener(_moved);
    super.dispose();
  }

  static double _offsetIn(ScrollMetrics? metrics) {
    if (metrics == null || !metrics.hasContentDimensions) return 0;
    return metrics.pixels - metrics.minScrollExtent;
  }

  // The scroll view the bar follows changes during a build, so the bar
  // follows it without building: its offset feeds the bar's own.
  void _follow() {
    final next = _active?.value;
    if (identical(next, _scroll)) return;
    _metrics?.removeRenderListener(_scrolled);
    _scrolledBy?.removeRenderListener(_moved);
    _scroll = next;
    final metrics = _metrics = next?.select((s) => s.metrics);
    metrics?.addRenderListener(_scrolled);
    final scrolledBy = _scrolledBy = next?.select((s) => _offsetIn(s.metrics));
    scrolledBy?.addRenderListener(_moved);
    _moved();
    _laidOut = false;
    _scrolled();
  }

  void _moved() => _followed.offset.write(_clock.now, _scrolledBy?.value ?? 0);

  // The large title moves with the content once a stacked search field
  // has folded away.
  MotionSelection<double> _awayAfter(double delay) {
    final away = _away;
    if (away != null && delay == _awayDelay) return away;
    _awayDelay = delay;
    return _away = _followed.select((m) {
      final o = m.offset.value;
      return o < 0 ? -o : -math.max<double>(0, o - delay);
    });
  }

  void _scrolled() {
    final metrics = _scroll?.metrics;
    final laidOut = metrics != null && metrics.hasContentDimensions;
    final shown =
        widget.largeTitle == null ||
        (laidOut &&
            metrics.pixels - metrics.minScrollExtent >=
                widget.scrolledUnderAfter - 0.5);
    final appears = !_laidOut;
    _laidOut = laidOut;
    // A jump of the content switches the title at once, as UIKit does.
    final moving = _scroll?.position?.isScrollingNotifier.value ?? false;
    _title.turn(
      _clock.now,
      shown: shown,
      animated: !appears && moving,
    );
  }

  @override
  Widget build(BuildContext context) {
    final look = (widget.style ?? const GlassNavigationBarStyle()).merge(
      GlassNavigationBarStyle.maybeOf(context),
    );
    final color = GlassDynamicColor.resolve(
      look.foregroundColor ?? GlassTheme.labelColorOf(context),
      context,
    );
    final title = widget.title ?? widget.largeTitle;
    final largeTitle = widget.largeTitle;
    final titleScale = GlassTextScale.of(context, max: _Metrics.maxTextScale);
    final largeScale = GlassTextScale.of(context, max: 1);
    final background = look.backgroundColor;
    final link = _bar.target;
    if (GlassTabShown.of(context)) {
      link.host.declare(
        link,
        GlassBarDeclaration(
          leading: widget.leading,
          trailing: widget.trailing,
          automaticallyImplyLeading: widget.automaticallyImplyLeading,
          previousPageTitle: widget.previousPageTitle,
          backButtonDisplayMode: widget.backButtonDisplayMode,
          title: switch (title) {
            Text(:final data?) => data,
            _ => null,
          },
        ),
        by: this,
      );
      link.host.fadedBy(link, _fade);
    } else {
      _bar.withdraw(fade: _fade);
    }
    final standalone = _bar.standalone;
    final row = SizedBox(
      height: GlassNavigationBar.height,
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          if (standalone != null)
            MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: GlassBarView(
                host: standalone,
                only: GlassBarKind.navigation,
              ),
            ),
          if (title != null)
            MotionTransition(
              opacity: _fade,
              child: CustomSingleChildLayout(
                delegate: _TitleLayout(
                  link.titleRoom,
                  Directionality.of(context),
                ),
                child: MotionTransition(
                  opacity: _opacity,
                  translateY: _rise,
                  blur: _blur,
                  child: titleScale.apply(
                    DefaultTextStyle(
                      style: titleScale.resolve(
                        _Metrics.title
                            .merge(look.titleTextStyle)
                            .copyWith(color: color),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: Semantics(header: true, child: title),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    final lift = PageLift.maybeOf(context);
    final filled = background == null
        ? null
        : GlassDynamicColor.resolve(background, context);
    Widget fill(Widget child) =>
        filled == null ? child : ColoredBox(color: filled, child: child);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        fill(row),
        if (largeTitle != null || widget.searchField != null)
          MotionTransition(
            translateY: lift,
            child: fill(
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (largeTitle != null)
                    SizedBox(
                      height: GlassNavigationBar.largeTitleHeight,
                      child: _ScrollAway(
                        shift: _awayAfter(widget._search),
                        opacity: _fade,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(
                            start: _Metrics.largeTitleInset,
                            end: _Metrics.largeTitleInset,
                            top: _Metrics.largeTitleTop,
                          ),
                          child: Align(
                            alignment: AlignmentDirectional.topStart,
                            child: largeScale.apply(
                              DefaultTextStyle(
                                style: largeScale.resolve(
                                  _Metrics.largeTitle
                                      .merge(look.largeTitleTextStyle)
                                      .copyWith(color: color),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                child: Semantics(
                                  header: true,
                                  child: largeTitle,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (widget.searchField case final field?)
                    _StackedSearch(
                      field: field,
                      offset: _offset,
                      travel:
                          GlassNavigationBar.height +
                          (largeTitle == null
                              ? 0
                              : GlassNavigationBar.largeTitleHeight),
                      lift: lift,
                      fade: _fade,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

abstract final class _Metrics {
  /// How far below the status bar the capsules and the inline title are
  /// centered: the capsules sit at the row's top (device recordings).
  static const double capsuleCenter = 22;

  /// The inset of the large title from the bar's sides.
  static const double largeTitleInset = navigationSideInset;

  /// The space between the top of the large title area and its text.
  static const double largeTitleTop = 3.67;

  /// The largest text scale the inline title follows.
  static const double maxTextScale = 1.25;

  /// How far below its place the hidden inline title sits.
  static const double hiddenOffset = 15;

  /// The blur of the hidden inline title.
  static const double hiddenBlur = 4;

  /// The inline title: UIKit's title role, 17 points semibold, in the
  /// line box UIKit's bar labels lay out in.
  static const title = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  /// The large title: 34 points bold.
  static const largeTitle = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
}

/// Lays the inline title out as UIKit does: on the bar's center, 22
/// points below the status bar like the capsules, when it fits in the
/// [room] between the page's capsules; else from the room's leading end,
/// truncated at the other.
class _TitleLayout extends SingleChildLayoutDelegate {
  _TitleLayout(this.room, this.direction) : super(relayout: room);

  final ValueListenable<GlassTitleRoom?> room;
  final TextDirection direction;

  GlassTitleRoom _roomIn(Size size) =>
      room.value ??
      (start: navigationSideInset, end: size.width - navigationSideInset);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final room = _roomIn(constraints.biggest);
    return BoxConstraints(
      maxWidth: math.max(0, room.end - room.start),
      maxHeight: constraints.maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final room = _roomIn(size);
    final center = size.width / 2;
    final half = childSize.width / 2;
    final fits =
        center - half >= room.start - 0.01 && center + half <= room.end + 0.01;
    final left = fits
        ? center - half
        : direction == TextDirection.rtl
        ? room.end - childSize.width
        : room.start;
    return Offset(left, _Metrics.capsuleCenter - childSize.height / 2);
  }

  @override
  bool shouldRelayout(_TitleLayout oldDelegate) =>
      !identical(room, oldDelegate.room) || direction != oldDelegate.direction;
}

/// A large title that scrolls away with the content: it paints its child
/// moved by the content's offset and cut off at its own top, following the
/// scroll view without building or laying out.
class _ScrollAway extends StatelessWidget {
  const _ScrollAway({
    required this.shift,
    required this.opacity,
    required this.child,
  });

  final ValueListenable<double> shift;
  final ValueListenable<double> opacity;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ClipRect(
      clipper: const BelowTop(),
      child: MotionTransition(
        translateY: shift,
        opacity: opacity,
        child: child,
      ),
    ),
  );
}
