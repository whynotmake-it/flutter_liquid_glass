import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/widgets/controls/badge.dart';
import 'package:apple_liquid_glass/src/widgets/controls/search_field.dart';
import 'package:apple_liquid_glass/src/widgets/controls/search_glyphs.dart';
import 'package:apple_liquid_glass/src/widgets/controls/selector_glass.dart';
import 'package:apple_liquid_glass/src/widgets/controls/state_colors.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar_entry.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/chrome.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/search_host.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

part 'package:apple_liquid_glass/src/widgets/navigation/tab_bar_accessory.dart';
part 'package:apple_liquid_glass/src/widgets/navigation/tab_bar_circle.dart';
part 'package:apple_liquid_glass/src/widgets/navigation/tab_bar_look.dart';
part 'package:apple_liquid_glass/src/widgets/navigation/tab_bar_minimize.dart';
part 'package:apple_liquid_glass/src/widgets/navigation/tab_bar_render.dart';
part 'package:apple_liquid_glass/src/widgets/navigation/tab_bar_search.dart';

/// One tab of a [GlassTabBar].
///
/// UIKit: `UITabBarItem`, `UITab`. SwiftUI: `Tab`. Flutter:
/// `NavigationDestination`.
@immutable
final class GlassTabDestination {
  /// Creates a tab showing [icon] over [label].
  const GlassTabDestination({
    required this.icon,
    required this.label,
    this.selectedIcon,
    this.badge,
    this.enabled = true,
    this.semanticLabel,
    this.id,
  });

  /// What tells the tab apart across changes of the destinations, or null
  /// to tell it by its position: a change inside `withSpring` slides the
  /// tabs that stay, fades new ones in and old ones out, and the lens
  /// moves with its tab ([RawGlassSelector.itemKeys]). Not measured: UIKit's
  /// animated setItems was not captured.
  final Object? id;

  /// The tab's glyph, 24 points by default.
  final Widget icon;

  /// The tab's title.
  final Widget label;

  /// The glyph the tab shows inside the selection lens (UIKit
  /// `selectedImage`), or null for [icon]. The bar builds each tab several
  /// times at once, so neither glyph may carry a `GlobalKey` or state that
  /// has to be unique.
  final Widget? selectedIcon;

  /// A mark at the top trailing corner of the glyph, usually a
  /// [GlassBadge]; its placement is by eye, not measured (tab bar
  /// passport).
  final Widget? badge;

  /// Whether the tab can be selected. A disabled tab draws at half opacity
  /// (not measured).
  final bool enabled;

  /// What accessibility reads for the tab; null reads the text of its
  /// label: a [Text]'s, or an `Icon`'s semantic label.
  final String? semanticLabel;
}

/// The look of a [GlassTabBar], like Flutter's `ButtonStyle`.
///
/// [backgroundColor] and [thumbColor] are resolved against the bar's
/// states, [foregroundColor] and [textStyle] against each tab's, which
/// include [WidgetState.selected] inside the lens. A bar looks a field up
/// in its own style, then in the theme's, then in its defaults, state by
/// state: a property that gives null for a state leaves that state to the
/// next one.
@immutable
class GlassTabBarStyle extends GlassStyle<GlassTabBarStyle> {
  /// Creates a style.
  const GlassTabBarStyle({
    this.backgroundColor,
    this.thumbColor,
    this.foregroundColor,
    this.textStyle,
    this.focusColor,
    this.hoverColor,
    this.builder,
  });

  /// The theme's [GlassTabBarStyle] at [context], or null without one: the
  /// look between a widget's own style and its defaults.
  static GlassTabBarStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassTabBarStyle>(context);

  /// A tint over the bar's glass (UIKit `barTintColor`); none by default.
  final WidgetStateProperty<Color?>? backgroundColor;

  /// The resting lens under the selected tab; [GlassTabBar.thumb] by
  /// default.
  final WidgetStateProperty<Color?>? thumbColor;

  /// The color of a tab's glyph and title: inside the lens the theme's
  /// primary color, else [GlassTabBar.selected]; outside it
  /// [GlassTabBar.unselected]; by default.
  final WidgetStateProperty<Color?>? foregroundColor;

  /// The text style of a tab's title: 10 points, medium, and semibold
  /// inside the lens, by default (tab bar passport).
  final WidgetStateProperty<TextStyle?>? textStyle;

  /// The ring inside a tab focused from the keyboard; null derives it from
  /// systemBlue as Flutter's Cupertino controls do, and a transparent color
  /// draws none.
  final Color? focusColor;

  /// What a mouse over a tab adds to its colors; null for the wash of a
  /// glass body at half a press's strength, and a transparent color shows
  /// none.
  final Color? hoverColor;

  /// Builds the bar's look in place of the default one; the bar then
  /// ignores [thumbColor], and [backgroundColor] still tints the minimized
  /// circle and the bottom accessory. Null leaves it to the theme's
  /// builder, then the default look.
  final GlassSelectorBuilder? builder;

  /// This style over [other], state by state.
  @override
  GlassTabBarStyle merge(GlassTabBarStyle? other) {
    if (other == null) return this;
    return GlassTabBarStyle(
      backgroundColor: GlassStyle.mergeStates(
        backgroundColor,
        other.backgroundColor,
      ),
      thumbColor: GlassStyle.mergeStates(thumbColor, other.thumbColor),
      foregroundColor: GlassStyle.mergeStates(
        foregroundColor,
        other.foregroundColor,
      ),
      textStyle: GlassStyle.mergeStates(textStyle, other.textStyle),
      focusColor: focusColor ?? other.focusColor,
      hoverColor: hoverColor ?? other.hoverColor,
      builder: builder ?? other.builder,
    );
  }

  /// The style between this one and [other] at [t]; the builder switches
  /// at the middle.
  @override
  GlassTabBarStyle lerp(GlassTabBarStyle other, double t) {
    if (identical(this, other)) return this;
    WidgetStateProperty<Color?>? color(
      WidgetStateProperty<Color?>? from,
      WidgetStateProperty<Color?>? to,
    ) => WidgetStateProperty.lerp<Color?>(
      from,
      to,
      t,
      GlassStyle.lerpNullable(GlassDynamicColor.lerp),
    );
    return GlassTabBarStyle(
      backgroundColor: color(backgroundColor, other.backgroundColor),
      thumbColor: color(thumbColor, other.thumbColor),
      foregroundColor: color(foregroundColor, other.foregroundColor),
      textStyle: WidgetStateProperty.lerp<TextStyle?>(
        textStyle,
        other.textStyle,
        t,
        GlassStyle.lerpNullable(TextStyle.lerp),
      ),
      focusColor: GlassDynamicColor.lerp(focusColor, other.focusColor, t),
      hoverColor: GlassDynamicColor.lerp(hoverColor, other.hoverColor, t),
      builder: t < 0.5 ? builder : other.builder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassTabBarStyle &&
      other.backgroundColor == backgroundColor &&
      other.thumbColor == thumbColor &&
      other.foregroundColor == foregroundColor &&
      other.textStyle == textStyle &&
      other.focusColor == focusColor &&
      other.hoverColor == hoverColor &&
      other.builder == builder;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    thumbColor,
    foregroundColor,
    textStyle,
    focusColor,
    hoverColor,
    builder,
  );
}

/// Where a tab bar's bottom accessory stands.
///
/// UIKit: `UITabAccessory.Environment`. SwiftUI:
/// `TabViewBottomAccessoryPlacement`.
enum GlassTabAccessoryPlacement {
  /// Above the expanded bar, across the bar group.
  expanded,

  /// Beside the minimized bar's circle.
  inline,
}

/// An iOS 27 tab bar: two to five tabs on a floating glass bar, the
/// selected one under a lens.
///
/// UIKit: `UITabBar`. SwiftUI: `TabView`. Flutter: `NavigationBar`,
/// `CupertinoTabBar`.
///
/// Pass one [GlassTabDestination] per tab, the selected index as
/// [selectedIndex], and set it again in [onDestinationSelected]; a bar
/// whose [selectedIndex] does not follow returns to it, and a null
/// [onDestinationSelected] disables the bar. Put it in a
/// `GlassTabScaffold` as its `tabBar`: the scaffold floats it over the
/// screen's bottom and shows the selected tab's page. [minimizeBehavior],
/// [bottomAccessory] and [searchController] add the minimized circle, an
/// accessory such as a mini player, and a search tab.
///
/// ```dart
/// GlassTabBar(
///   destinations: const [
///     GlassTabDestination(
///       icon: Icon(CupertinoIcons.house),
///       label: Text('Home'),
///     ),
///     GlassTabDestination(
///       icon: Icon(CupertinoIcons.gear),
///       label: Text('Settings'),
///     ),
///   ],
///   selectedIndex: tab,
///   onDestinationSelected: (index) => setState(() => tab = index),
/// )
/// ```
///
/// The bar, the search circle and the accessory are [GlassSurface]s:
/// liquid glass on the liquid renderer, blurred and lit glass on the fake
/// renderer, and a translucent fill with a hairline rim on the flat
/// renderer, which also draws when no `GlassScope` is above. The lens is
/// an opaque platter at rest on every renderer; while a finger drags it,
/// the liquid and fake renderers turn it into glass, and the flat renderer
/// fades the platter and gives it a rim.
///
/// The bar is 62 points tall whatever its titles say. A bar of four or
/// more tabs, or one with a [bottomAccessory] or a [searchController],
/// spans the width it is given and its tabs adapt inside it: to the
/// iPhone's even slots while the titles fit, then to slots as wide as each
/// title asks. A bar of two or three tabs is as wide as its widest title
/// asks, up to the width it is given, as UIKit's is. Given 568 points or
/// more, a bar takes 360 points at most. A title stays on one line at its
/// size and ends in an ellipsis where it does not fit. Its motion is
/// [RawGlassSelector]'s with [GlassSelectorMotion.tabBar]: the bar swells
/// and drifts under the finger, a glow follows it, and a dragged lens
/// carries a selected copy of the tabs under it. Titles follow the text
/// scale up to [maxTextScale]. [onDestinationSelected] runs on every
/// selection, the selected tab's included: a tap on it, Space, Enter or an
/// accessibility tap reselects it, where an app scrolls the tab's content
/// to the top.
///
/// With a [minimizeBehavior] that minimizes, the bar follows the scroll
/// view of its page's [GlassContentScroll] with UIKit's scroll-away
/// interaction of the floating tab bar: a user's scroll of 64 points
/// shrinks it into a 48 point circle that keeps its selected tab's glyph,
/// 7 points inside the bar's leading side, in one liquid morph (damping
/// 0.8, response 0.3); the circle stays the same bar throughout, so the
/// morph turns around from wherever it is. A finger on the circle lifts it
/// to 64 points; lifted in place, however late, the finger expands the bar
/// and selects nothing; moved 4 points along the bar, it expands the bar
/// and carries the lens, and the tab under it on the lift is selected, as
/// on the expanded bar. The content's top end or a scroll past its far end
/// also expands it.
///
/// A [bottomAccessory] stands on its own glass 48 points tall, 8 points
/// above the bar across the bar group, its content inset 16 points at the
/// sides and 8 at the top and bottom; while the bar is minimized it stands
/// level with the circle, 14 points beside it. It travels there along the
/// bar first and up after, and back up first and along after, the second
/// axis 0.05 s late. [accessoryPlacementOf] tells its content which place
/// it heads for, flipping as the transition starts.
///
/// Focused from the keyboard, a tab draws Flutter's Cupertino focus ring
/// inside its slot, and a mouse over a tab washes its slot as a glass
/// body's hover does; the search circle shows both on its glass, as a
/// glass button does.
///
/// Fidelity. The accessory's places and travel are read from UIKit. Close
/// to UIKit's but not identical: UIKit first tightens a long title's
/// tracking by up to 1.2 points before the ellipsis, which this bar does
/// not. Not measured: UIKit's metrics at 568 points or more, where the
/// 360 point limit stands in, and the focus ring and hover response, which
/// are approximations of the platform.
class GlassTabBar extends StatelessWidget {
  /// Creates a tab bar showing [selectedIndex] selected.
  const GlassTabBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.style,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.minimizeBehavior = GlassTabBarMinimizeBehavior.automatic,
    this.bottomAccessory,
    this.searchController,
    super.key,
  });

  /// The tabs, two to five.
  final List<GlassTabDestination> destinations;

  /// The selected tab, clamped to [destinations].
  final int selectedIndex;

  /// Called with the tab the user selects or reselects; null disables the
  /// bar. A bar whose [selectedIndex] does not follow returns to it.
  final ValueChanged<int>? onDestinationSelected;

  /// The look, over the theme's and the bar's defaults.
  final GlassTabBarStyle? style;

  /// Where the bar writes its states, or null for its own.
  final WidgetStatesController? statesController;

  /// The bar's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the bar takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the bar as a whole.
  final String? semanticLabel;

  /// When the bar minimizes as the content under it scrolls;
  /// [GlassTabBarMinimizeBehavior.automatic] does not minimize, as an
  /// iPhone tab bar that does not opt in.
  final GlassTabBarMinimizeBehavior minimizeBehavior;

  /// The content of the glass accessory above the bar (UIKit
  /// `bottomAccessory`, SwiftUI `tabViewBottomAccessory`), or null.
  final Widget? bottomAccessory;

  /// The search of the bar's search tab, or null for a bar without one.
  ///
  /// UIKit: a `UISearchTab` that `automaticallyActivatesSearch`. SwiftUI:
  /// `Tab(role: .search)`.
  ///
  /// The search tab is a glass circle 62 points across at the trailing
  /// side, the bar at the leading one, both 21 points from the sides and
  /// the bottom. Opening the search (a tap on the circle) turns the bar
  /// into a circle 48 points across holding the selected tab's glyph and
  /// the search circle into a search field beside it, on UIKit's liquid
  /// morph (damping 0.8, response 0.3, read from UIKit; the simulator film
  /// fits 0.276 and 0.8); the field takes the focus 0.16 s after the tap
  /// and, once the keyboard starts to rise, rises above it with a close
  /// button on a critically damped spring of response 0.3, while the tab
  /// circle fades under the keyboard (device recordings). The close button
  /// or Escape clears the query and ends the focus; the field falls
  /// straight back. A tap on the tab circle closes the search, and the bar
  /// turns back, clearing the query; it takes the tap while the morph into
  /// the field still runs, which turns around with its velocity, until the
  /// close button shows. The search circle takes no tap until the morph
  /// back has settled, as UIKit's. The bar lays itself out over the
  /// screen's bottom: in a `GlassTabScaffold` it does by itself. A bar with
  /// a search tab does not minimize or carry a [bottomAccessory].
  final GlassSearchController? searchController;

  /// Where the bottom accessory around [context] stands.
  static GlassTabAccessoryPlacement accessoryPlacementOf(
    BuildContext context,
  ) =>
      context
          .dependOnInheritedWidgetOfExactType<_AccessoryScope>()
          ?.notifier
          ?.value ??
      GlassTabAccessoryPlacement.expanded;

  /// The height of the bar group: the bar and, with [accessory], the
  /// accessory above it.
  static double groupHeight({required bool accessory}) =>
      height +
      (accessory ? _Minimized.accessoryGap + _Minimized.accessoryHeight : 0);

  /// The height of the bar.
  static const double height = TabBarLayout.height;

  /// The largest text scale the titles follow (tab bar passport).
  static const double maxTextScale = 1.25;

  /// The size of a tab's glyph (tab bar passport).
  static const double iconSize = 24;

  /// UITabBar's resting lens: what UIKit's color matrices make of the
  /// measured bar under the selection, over a plain page.
  static const thumb = GlassDynamicColor.withBrightness(
    color: Color(0x13000000),
    darkColor: Color(0xAF000000),
  );

  /// The tabs outside the lens: UIKit's vibrant glyph color over the
  /// measured bar (tab bar passport, layout and device).
  static const unselected = GlassDynamicColor.withBrightness(
    color: Color(0xFF0D0D0D),
    darkColor: Color(0xFFFAFAFA),
  );

  /// The tabs inside the lens without a primary color: UIKit's tint over
  /// the measured bar (tab bar passport, layout and device).
  static const selected = GlassDynamicColor.withBrightness(
    color: Color(0xFF0082FC),
    darkColor: Color(0xFF0397FF),
  );

  static const _title = TextStyle(fontSize: 10, fontWeight: FontWeight.w500);
  static const _selectedTitle = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
  );

  /// A style from plain colors and text styles; a null value leaves the
  /// field to the theme, then the default.
  static GlassTabBarStyle styleFrom({
    Color? backgroundColor,
    Color? thumbColor,
    Color? foregroundColor,
    Color? selectedForegroundColor,
    TextStyle? textStyle,
    TextStyle? selectedTextStyle,
  }) => GlassTabBarStyle(
    backgroundColor: GlassStyle.allOrNull(backgroundColor),
    thumbColor: GlassStyle.allOrNull(thumbColor),
    foregroundColor: foregroundColor == null && selectedForegroundColor == null
        ? null
        : WidgetStateMapper<Color?>({
            WidgetState.selected: selectedForegroundColor,
            WidgetState.any: foregroundColor,
          }),
    textStyle: textStyle == null && selectedTextStyle == null
        ? null
        : WidgetStateMapper<TextStyle?>({
            WidgetState.selected: selectedTextStyle,
            WidgetState.any: textStyle,
          }),
  );

  GlassTabBarStyle _defaults(BuildContext context) => GlassTabBarStyle(
    thumbColor: const WidgetStatePropertyAll(thumb),
    foregroundColor: WidgetStateMapper<Color?>({
      WidgetState.selected: GlassTheme.primaryColorOf(context) ?? selected,
      WidgetState.any: unselected,
    }),
    textStyle: const WidgetStateMapper<TextStyle?>({
      WidgetState.selected: _selectedTitle,
      WidgetState.any: _title,
    }),
  );

  @override
  Widget build(BuildContext context) {
    final themed = GlassTabBarStyle.maybeOf(context);
    final look = (style ?? const GlassTabBarStyle())
        .merge(themed)
        .merge(_defaults(context));
    final onSelected = onDestinationSelected;
    Widget bar(GlassSelectorCollapse? collapse, {required bool hosted}) =>
        RawGlassSelector(
          motion: GlassSelectorMotion.tabBar,
          collapse: collapse,
          hosted: hosted,
          itemCount: destinations.length,
          itemKeys: [
            for (final (i, destination) in destinations.indexed)
              if (destination.id == null) (null, i) else (destination.id, null),
          ],
          selectedIndex: selectedIndex,
          onChanged: onSelected,
          onReselected: onSelected,
          disabledItems: {
            for (var i = 0; i < destinations.length; i++)
              if (!destinations[i].enabled) i,
          },
          statesController: statesController,
          focusNode: focusNode,
          autofocus: autofocus,
          semanticLabel: semanticLabel,
          itemLabels: [
            for (final destination in destinations)
              destination.semanticLabel ?? glassLabelTextOf(destination.label),
          ],
          itemBuilder: (context, index, states) => _TabContent(
            destination: destinations[index],
            look: look,
            states: states,
            morph: collapse?.morph,
          ),
          builder:
              style?.builder ??
              themed?.builder ??
              (context, details) => SelectorGlass(
                details: details,
                role: GlassRole.bar,
                background: look.backgroundColor,
                thumb: look.thumbColor,
              ),
        );
    if (searchController case final search?) {
      return _SearchTabBar(controller: search, bar: bar);
    }
    final accessory = bottomAccessory;
    if (!minimizeBehavior.minimizes && accessory == null) {
      return bar(null, hosted: false);
    }
    return _MinimizingBar(
      behavior: minimizeBehavior,
      accessory: accessory,
      look: look,
      bar: bar,
    );
  }
}
