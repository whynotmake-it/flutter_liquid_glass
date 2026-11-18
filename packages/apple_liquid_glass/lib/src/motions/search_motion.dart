import 'dart:ui';

import 'package:apple_liquid_glass/src/motions/glass_press.dart';
import 'package:apple_liquid_glass/src/motions/tab_bar_layout.dart';
import 'package:apple_liquid_glass/src/motions/tab_minimize.dart';
import 'package:flutter/foundation.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// The measured tuning and geometry of the iOS 27 search field: a
/// UISearchController placed in the bottom toolbar, and the tab bar's
/// search tab.
@internal
abstract final class SearchTuning {
  /// The spring of the focus transition: the field widens, the toolbar's
  /// other items leave, the close button arrives. SwiftUI's
  /// `GlassContainerSearchTransitionPTSettings` (duration 0.25, bounce
  /// 0.1); the frames fit 0.238 - 0.246 / 0.92 - 0.94 freely (simulator
  /// and iPhone 16 Pro) and this spring within 0.6 percent of the travel.
  static const transitionSpring = Spring.response(0.25, dampingRatio: 0.9);

  /// The time from a focus change to the start of the transition (0.067 s
  /// from `isActive = false` on an iPhone 16 Pro, 0.077 - 0.086 s on the
  /// simulator, 0.080 s from the lift of a tap on the close button on the
  /// device; a focus that brings up the keyboard waits for it instead, see
  /// [SearchMotion.keyboardLag]).
  static const double transitionDelay = 0.067;

  /// The longest a focus waits for the keyboard before its transition
  /// starts anyway: this package's guard, not UIKit's (UIKit starts the
  /// transition when the keyboard or the active search items change, and
  /// has no timeout).
  static const double keyboardWaitLimit = 0.3;

  /// The space between the screen's sides and the focused bar.
  static const double focusedSideInset = 8;

  /// The space between the field and the close button of a tab bar's
  /// focused search.
  static const double tabCloseGap = 8;

  /// The space between the keyboard and a tab bar's focused search (8,
  /// where the toolbar's search keeps [SearchBarGeometry.keyboardGap]).
  static const double tabKeyboardGap = 8;

  /// The spring of a tab bar turning into a search field and back: the
  /// minimize morph ([TabBarMinimizeTuning.morphSpring], read from UIKit).
  /// The edges of the glass in a 60 Hz simulator video fit 0.276 and 0.8.
  static const tabSpring = TabBarMinimizeTuning.morphSpring;

  /// The spring a tab bar's search field rises above the keyboard on when
  /// it takes the focus, and sinks back on when it loses it: critically
  /// damped, response 0.30 (an iPhone 16 Pro: 0.19 and 0.93 pt rms over
  /// 308 points; [SearchTuning.transitionSpring] leaves 12 pt rms).
  static const tabFocusSpring = Spring.response(0.3);

  /// The time from the lift of the tap on the search tab to the field
  /// taking the focus when the tab activates search (an iPhone 16 Pro:
  /// `willPresentSearchController` 0.085 s and the first responder 0.159
  /// s after the lift, the keyboard's first frame 0.25 s after it, while
  /// the tab's morph still runs).
  static const double tabActivationDelay = 0.16;

  /// The time from the keyboard's first frame to the start of a tab bar
  /// search's rise (an iPhone 16 Pro, 0.07 s).
  static const double tabKeyboardLag = 0.07;

  /// The time from the end of a tab bar search's focus to the start of its
  /// fall (an iPhone 16 Pro: 0.038 and 0.064 s after the lift of the
  /// close tap in two captures; the fall itself runs on [tabFocusSpring],
  /// 0.08 percent rms of 308 points).
  static const double tabUnfocusDelay = 0.05;

  /// The spring of a stacked search field's presentation: one spring for
  /// the page and its field moving up until the field sits under the
  /// status bar, the field narrowing, the close button arriving and the
  /// navigation bar hiding (damping 0.8, response 0.34, read from UIKit;
  /// the iPhone 16 Pro's layers fit 0.346 / 0.794 on the way up and 0.340 /
  /// 0.800 on the way back).
  static const stackedSpring = Spring.response(0.34, dampingRatio: 0.8);

  /// The spring a navigation bar's large title and items fade out on while
  /// a stacked field presents, starting with the rise (an iPhone 16 Pro's
  /// layers). UIKit fades them in time, not by how far the page has risen,
  /// and their alpha matches to four digits on every frame.
  static const stackedFadeOutSpring = Spring.response(0.117);

  /// The spring they fade back in on as the field ends (fitted to the same
  /// layers, nine cancels).
  static const stackedFadeInSpring = Spring.response(0.25, dampingRatio: 1.47);

  /// How long the fade back in waits after the page starts to come down
  /// (the same layers).
  static const double stackedFadeInDelay = 0.083;

  /// The spring a stacked field's plain fill turns to glass on and back
  /// (`backgroundMaterialSpring`, damping 1.0, response 0.32, read from
  /// UIKit).
  static const stackedGlassSpring = Spring.response(0.32);
}

/// The geometry of a tab bar with a search tab, at rest and searching.
@immutable
class SearchTabGeometry {
  /// Creates a geometry.
  const SearchTabGeometry({
    required this.bar,
    required this.search,
    required this.tab,
    required this.field,
    required this.focusedField,
    required this.close,
  });

  /// The tab bar at rest.
  final Rect bar;

  /// The search tab's circle at rest.
  final Rect search;

  /// The circle the tab bar becomes while searching: the selected tab's
  /// glyph.
  final Rect tab;

  /// The search field while searching.
  final Rect field;

  /// The search field focused above the keyboard.
  final Rect focusedField;

  /// The close button next to the focused field.
  final Rect close;

  /// The diameter of the search tab's circle next to the tab bar.
  static const double circleSize = TabBarLayout.height;
}

/// Lays out a tab bar [barWidth] wide with a search tab in a screen of [size],
/// above a keyboard [keyboard] tall, as iOS 27 does (the iOS 27 simulator's
/// iPhone 18 Pro Max: bar and circle 21 from the sides and bottom; searching,
/// the tab circle 28 from the side and bottom and the field 12 after it to 28
/// from the side; focused, the field 8 from the side, the close button 8 after
/// it, 8 above the keyboard). [rtl] mirrors it.
SearchTabGeometry searchTabLayout({
  required Size size,
  required double barWidth,
  double keyboard = 0,
  bool rtl = false,
}) {
  const inset = TabBarLayout.screenInset;
  const circle = SearchTabGeometry.circleSize;
  const h = SearchBarGeometry.fieldHeight;
  const rest = SearchBarGeometry.restInset;
  final w = size.width;
  final barTop = size.height - inset - circle;
  final top = size.height - rest - h;
  final focusedTop = size.height - keyboard - SearchTuning.tabKeyboardGap - h;
  final close = Rect.fromLTWH(
    w - SearchTuning.focusedSideInset - h,
    focusedTop,
    h,
    h,
  );
  final geometry = SearchTabGeometry(
    bar: Rect.fromLTWH(inset, barTop, barWidth, circle),
    search: Rect.fromLTWH(w - inset - circle, barTop, circle, circle),
    tab: Rect.fromLTWH(rest, top, h, h),
    field: Rect.fromLTRB(
      rest + h + SearchBarGeometry.gap,
      top,
      w - rest,
      top + h,
    ),
    focusedField: Rect.fromLTRB(
      SearchTuning.focusedSideInset,
      focusedTop,
      close.left - SearchTuning.tabCloseGap,
      focusedTop + h,
    ),
    close: close,
  );
  if (!rtl) return geometry;
  Rect mirror(Rect r) =>
      Rect.fromLTRB(w - r.right, r.top, w - r.left, r.bottom);
  return SearchTabGeometry(
    bar: mirror(geometry.bar),
    search: mirror(geometry.search),
    tab: mirror(geometry.tab),
    field: mirror(geometry.field),
    focusedField: mirror(geometry.focusedField),
    close: mirror(geometry.close),
  );
}

/// The focus transition of an iOS 27 search field.
///
/// One progress, 0 at rest and 1 focused, drives the whole transition on
/// [SearchTuning.transitionSpring], starting
/// [SearchTuning.transitionDelay] after the change: the field's
/// frame, the close button arriving (its opacity is the progress, its
/// scale 1.2 at nothing) and the toolbar's other items leaving the same
/// way in reverse. A change in the middle of another reverses from where
/// it stands, velocity included. A focus that brings up the keyboard waits
/// for it ([focusAfterKeyboard], [keyboardRose]).
///
/// The progress rests within 0.001 of its travel. NEAR: the field lands by
/// up to 0.3 pt over a 300 pt rise, looser than [MotionRest.length];
/// resting at 0.1 pt keeps a cancel two frames longer.
///
/// The field's touch lift is the glass search field's own press
/// ([GlassPress.search]).
///
/// Times are seconds on the motion's timeline.
final class SearchMotion extends Motion {
  /// Creates the motion of a resting field, stepped by [clock] on screen.
  SearchMotion({MotionClock? clock})
    : this._(SearchTuning.transitionSpring, clock: clock);

  /// Creates the focus of a tab bar's search field, which rides
  /// [SearchTuning.tabFocusSpring].
  @internal
  SearchMotion.tabFocus({MotionClock? clock})
    : this._(SearchTuning.tabFocusSpring, clock: clock);

  SearchMotion._(Spring spring, {super.clock})
    : _progress = MotionValue<double>(0, spring: spring) {
    own(_progress, rest: _rest);
  }

  final MotionValue<double> _progress;
  bool _focused = false;
  bool _waiting = false;

  static double _rest() => 1e-3;

  static const _turn = #turn;

  /// The time from the keyboard's first frame to the start of a focus
  /// transition: UIKit holds the transition of a focus that brings up the
  /// keyboard until the keyboard starts to rise (an iPhone 16 Pro: 0.015 s
  /// after its first frame, 0.17 - 0.19 s after the lift of the tap that
  /// focused, 0.28 s for the first keyboard of a launch).
  static const double keyboardLag = 0.015;

  /// The scale an item appears from and leaves at, around its center,
  /// while it fades: the close button arrives from 1.2, the toolbar's
  /// other items leave toward it.
  static const double appearScale = 1.2;

  /// The blur of an item at the start of its appearance, in logical
  /// pixels (`GlassContainerAppearanceSearchPTSettings.blurRadius`).
  static const double appearBlur = 10;

  /// Whether the field is focused or heading there.
  bool get isFocused => _focused;

  /// Whether a focus waits for the keyboard to start rising.
  bool get waitsForKeyboard => _waiting;

  /// The focus progress: 0 at rest, 1 focused.
  double get progress => _progress.valueAt(now);

  /// Focuses the field at time [t]; the transition starts [delay] seconds
  /// later.
  void focus(double t, {double delay = SearchTuning.transitionDelay}) =>
      _turnTo(t, focused: true, delay: delay);

  /// Ends the search at time [t]; the transition starts [delay] seconds
  /// later.
  void unfocus(double t, {double delay = SearchTuning.transitionDelay}) =>
      _turnTo(t, focused: false, delay: delay);

  /// Focuses the field at time [t] while the keyboard is still to rise:
  /// the transition waits for [keyboardRose], and starts anyway [limit]
  /// seconds later.
  void focusAfterKeyboard(
    double t, {
    double limit = SearchTuning.keyboardWaitLimit,
  }) {
    advance(t);
    if (_focused) return;
    _focused = true;
    _waiting = true;
    at(t + limit, _arrive, slot: _turn);
  }

  /// The keyboard started rising at time [t]: a waiting focus starts its
  /// transition [lag] seconds later.
  void keyboardRose(double t, {required double lag}) {
    advance(t);
    if (!_waiting) return;
    _waiting = false;
    at(t + lag, _arrive, slot: _turn);
  }

  /// Puts the transition at rest, focused or not, at time [t].
  void snap(double t, {required bool focused}) {
    advance(t);
    _focused = focused;
    _waiting = false;
    unschedule(_turn);
    _progress.snap(t, focused ? 1 : 0);
  }

  void _turnTo(double t, {required bool focused, required double delay}) {
    advance(t);
    if (_focused == focused) return;
    _focused = focused;
    _waiting = false;
    at(t + delay, (s) => _progress.retarget(s, focused ? 1 : 0), slot: _turn);
  }

  void _arrive(double t) {
    _waiting = false;
    _progress.retarget(t, 1);
  }

  /// The scale of an item that is [presence] there (0 gone, 1 fully
  /// there): [SearchMotion.appearScale] at nothing.
  static double appearScaleFor(double presence) =>
      1 + (SearchMotion.appearScale - 1) * (1 - presence.clamp(0.0, 1.0));
}

/// The geometry of a bottom search bar in one configuration: the field,
/// the close button and the toolbar items around the field.
@immutable
class SearchBarGeometry {
  /// Creates a geometry.
  const SearchBarGeometry({
    required this.field,
    required this.close,
    required this.leading,
    required this.trailing,
  });

  /// The field's capsule.
  final Rect field;

  /// Where the close button sits in this configuration.
  final Rect close;

  /// The items before the field, in order.
  final List<Rect> leading;

  /// The items after the field, in order.
  final List<Rect> trailing;

  /// The height of the field, the close button and the toolbar's items
  /// (bars passport).
  static const double fieldHeight = 48;

  /// The space between the screen's sides and the bar at rest, and
  /// between the screen's bottom and the bar (bars passport, read from
  /// UIKit).
  static const double restInset = 28;

  /// The space between the keyboard (or the screen's bottom) and the
  /// focused bar.
  static const double keyboardGap = 10;

  /// The space between the field and its neighbours.
  static const double gap = 12;
}

/// Lays out a bottom search bar [width] wide whose capsules' bottom edge
/// is at [bottom]: at rest ([focused] false) the [leading] and [trailing]
/// item widths around a flexible field, [SearchBarGeometry.restInset]
/// from the sides; focused, the field and the close button,
/// [SearchTuning.focusedSideInset] from the sides. Items absent from
/// a configuration still get the slot they would take there, so they can
/// arrive from it. [rtl] mirrors everything.
SearchBarGeometry searchBarLayout({
  required double width,
  required double bottom,
  required bool focused,
  List<double> leading = const [],
  List<double> trailing = const [],
  bool rtl = false,
}) {
  const h = SearchBarGeometry.fieldHeight;
  const gap = SearchBarGeometry.gap;
  final inset = focused
      ? SearchTuning.focusedSideInset
      : SearchBarGeometry.restInset;
  final top = bottom - h;
  final lead = <Rect>[];
  var x = inset;
  for (final w in leading) {
    lead.add(Rect.fromLTWH(x, top, w, h));
    x += w + gap;
  }
  final trail = <Rect>[];
  var right = width - inset;
  for (final w in trailing.reversed) {
    trail.insert(0, Rect.fromLTWH(right - w, top, w, h));
    right -= w + gap;
  }
  final close = Rect.fromLTWH(width - inset - h, top, h, h);
  final Rect field;
  if (focused) {
    field = Rect.fromLTRB(inset, top, close.left - gap, bottom);
  } else {
    final left = leading.isEmpty ? inset : lead.last.right + gap;
    final end = trailing.isEmpty ? width - inset : trail.first.left - gap;
    field = Rect.fromLTRB(left, top, end, bottom);
  }
  if (!rtl) {
    return SearchBarGeometry(
      field: field,
      close: close,
      leading: lead,
      trailing: trail,
    );
  }
  Rect mirror(Rect r) =>
      Rect.fromLTRB(width - r.right, r.top, width - r.left, r.bottom);
  return SearchBarGeometry(
    field: mirror(field),
    close: mirror(close),
    leading: [for (final r in lead) mirror(r)],
    trailing: [for (final r in trail) mirror(r)],
  );
}
