import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/chrome.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/tab_bar.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/widgets.dart';

/// An iOS 27 tab interface: a tab bar floating over the bottom of the
/// screen and the selected tab's page under it.
///
/// UIKit: `UITabBarController`. SwiftUI: `TabView`. Flutter:
/// `CupertinoTabScaffold`.
///
/// Pass a [GlassTabBar] as [tabBar] and build each tab's page in
/// [tabBuilder]; the bar's `selectedIndex` picks the page shown, so the
/// app selects a tab by rebuilding the bar. [searchBuilder] builds the
/// page of the bar's search tab. Use it as the app's home, under the
/// `GlassScope`, and give each tab a [GlassPageScaffold] for its bars.
///
/// ```dart
/// GlassTabScaffold(
///   tabBar: GlassTabBar(
///     destinations: const [
///       GlassTabDestination(
///         icon: Icon(CupertinoIcons.house),
///         label: Text('Home'),
///       ),
///       GlassTabDestination(
///         icon: Icon(CupertinoIcons.gear),
///         label: Text('Settings'),
///       ),
///     ],
///     selectedIndex: tab,
///     onDestinationSelected: (index) => setState(() => tab = index),
///   ),
///   tabBuilder: (context, index) => Center(child: Text('Tab $index')),
/// )
/// ```
///
/// The scaffold draws no glass of its own: it fills the background with
/// [backgroundColor] on every renderer. The bar draws as [GlassTabBar]
/// says, as glass on the liquid and fake renderers and flat on the flat
/// renderer and with no `GlassScope` above.
///
/// [tabBuilder] builds a tab the first time it is selected; a tab left
/// keeps its state, offstage, with its tickers muted and its focus kept
/// apart. The bar stands 21 points from the screen's sides and bottom, and
/// the media query padding of the tabs grows to clear it, so a page's
/// content scrolls clear of the bar and a [GlassPageScaffold] in a tab sees
/// the floating bar at its bottom edge. While the search of a bar with a
/// [GlassTabBar.searchController] is open, [searchBuilder]'s page shows
/// instead of the selected tab, kept the same way once built.
///
/// Fidelity. The bar's 21 point inset is measured on iOS 27.
class GlassTabScaffold extends StatefulWidget {
  /// Creates a tab interface.
  const GlassTabScaffold({
    required this.tabBar,
    required this.tabBuilder,
    this.searchBuilder,
    this.backgroundColor,
    super.key,
  });

  /// The tab bar; its selected index picks the tab shown.
  final GlassTabBar tabBar;

  /// Builds the tab at an index.
  final IndexedWidgetBuilder tabBuilder;

  /// Builds the page of the bar's search tab, or null for none.
  final WidgetBuilder? searchBuilder;

  /// The background behind the tabs; [GlassColors.systemBackground] by
  /// default.
  final Color? backgroundColor;

  /// The space between the screen's sides and bottom and the bar.
  static const double inset = TabBarLayout.screenInset;

  @override
  State<GlassTabScaffold> createState() => _GlassTabScaffoldState();
}

class _GlassTabScaffoldState extends State<GlassTabScaffold> {
  final _active = ValueNotifier<MotionScroll?>(null);
  final _built = <int>{};
  final _focus = <FocusScopeNode>[];
  final _searchFocus = FocusScopeNode(debugLabel: 'GlassTabScaffold search');
  bool _searchBuilt = false;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    widget.tabBar.searchController?.addListener(_searchChanged);
    _searching = widget.tabBar.searchController?.isOpen ?? false;
  }

  @override
  void didUpdateWidget(GlassTabScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.tabBar.searchController;
    final search = widget.tabBar.searchController;
    if (!identical(old, search)) {
      old?.removeListener(_searchChanged);
      search?.addListener(_searchChanged);
      _searching = search?.isOpen ?? false;
    }
  }

  @override
  void dispose() {
    widget.tabBar.searchController?.removeListener(_searchChanged);
    _active.dispose();
    _searchFocus.dispose();
    for (final node in _focus) {
      node.dispose();
    }
    super.dispose();
  }

  void _searchChanged() {
    final open = widget.tabBar.searchController?.isOpen ?? false;
    if (open != _searching) setState(() => _searching = open);
  }

  FocusScopeNode _focusOf(int index) {
    while (_focus.length <= index) {
      _focus.add(FocusScopeNode(debugLabel: 'GlassTabScaffold tab'));
    }
    return _focus[index];
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final count = widget.tabBar.destinations.length;
    final selected = count == 0
        ? -1
        : widget.tabBar.selectedIndex.clamp(0, count - 1);
    final searchBuilder = widget.searchBuilder;
    final searching = _searching && searchBuilder != null;
    if (selected >= 0 && !searching) _built.add(selected);
    _built.removeWhere((index) => index >= count);
    if (searching) _searchBuilt = true;
    final bottom = math.max(
      media.padding.bottom,
      GlassTabScaffold.inset +
          GlassTabBar.groupHeight(
            accessory: widget.tabBar.bottomAccessory != null,
          ),
    );
    final background = GlassDynamicColor.resolve(
      widget.backgroundColor ?? GlassColors.systemBackground,
      context,
    );
    return GlassChrome(
      edges: ChromeEdges(
        top: ChromeBar.none,
        topExtent: media.padding.top,
        scrolledUnderAfter: 0,
        bottom: ChromeBar.floating,
        bottomExtent: bottom,
        background: background,
      ),
      active: _active,
      outer: GlassChrome.maybeOf(context),
      child: ColoredBox(
        color: background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MediaQuery(
              data: media.copyWith(
                padding: media.padding.copyWith(bottom: bottom),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  for (var i = 0; i < count; i++)
                    if (_built.contains(i))
                      Offstage(
                        key: ValueKey(i),
                        offstage: searching || i != selected,
                        child: TickerMode(
                          enabled: !searching && i == selected,
                          child: GlassTabShown(
                            shown: !searching && i == selected,
                            child: FocusScope(
                              node: _focusOf(i),
                              child: Builder(
                                builder: (context) =>
                                    widget.tabBuilder(context, i),
                              ),
                            ),
                          ),
                        ),
                      ),
                  if (_searchBuilt && searchBuilder != null)
                    Offstage(
                      key: const ValueKey('search'),
                      offstage: !searching,
                      child: TickerMode(
                        enabled: searching,
                        child: GlassTabShown(
                          shown: searching,
                          child: FocusScope(
                            node: _searchFocus,
                            child: Builder(builder: searchBuilder),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.tabBar.searchController != null)
              Positioned.fill(child: widget.tabBar)
            else
              Positioned(
                left: GlassTabScaffold.inset,
                right: GlassTabScaffold.inset,
                bottom: GlassTabScaffold.inset,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  heightFactor: 1,
                  child: widget.tabBar,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
