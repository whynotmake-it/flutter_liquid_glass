import 'dart:ui';

import 'package:apple_liquid_glass/src/motions/search_motion.dart';
import 'package:kinesis/motion.dart';

/// The motion of a tab bar with a search tab: the morph of the bar into
/// the field and back, the field's focus, and the moment the opened search
/// activates and its field takes the focus, 0.16 s after it opens.
///
/// Times are seconds on the motion's timeline.
final class SearchTabMotion extends Motion {
  /// Creates the motion of a bar that is [open] or not, at rest.
  SearchTabMotion({required bool open, super.clock}) : _open = open {
    _morph = own(
      MotionValue<double>(open ? 1 : 0, spring: SearchTuning.tabSpring),
      rest: _morphRest,
    );
    focus = own(SearchMotion.tabFocus());
  }

  late final MotionValue<double> _morph;

  /// The field's focus transition.
  late final SearchMotion focus;

  bool _open;
  bool _activated = false;

  // NEAR: the shapes land by up to 0.001 of their travel.
  static double _morphRest() => 1e-3;

  static const _activation = #activation;

  /// Whether the search is open or heading there.
  bool get isOpen => _open;

  /// Whether the open search has activated: its field takes the focus
  /// then.
  bool get activated => _activated;

  /// Runs [action] in the first frame after time [t], on the motion's
  /// timeline.
  void afterFrame(double t, VoidCallback action) =>
      at(t + 1e-6, (_) => action(), slot: #afterFrame);

  /// The morph: 0 a tab bar, 1 a search field.
  double get morph => _morph.valueAt(now);

  /// Opens or closes the search at time [t].
  void turn(double t, {required bool open}) {
    advance(t);
    if (open == _open) return;
    _open = open;
    _morph.retarget(t, open ? 1 : 0);
    if (open) {
      at(t + SearchTuning.tabActivationDelay, (_) {
        _activated = true;
        changed();
      }, slot: _activation);
    } else {
      unschedule(_activation);
      _activated = false;
    }
  }

  /// The field took the focus at time [t] with the keyboard [keyboard]
  /// points up: it rises above a keyboard that is there, and waits for
  /// one that is still to come ([keyboardRose]).
  void focused(double t, {required double keyboard}) {
    if (focus.isFocused) return;
    if (keyboard > 0) {
      focus.focus(t, delay: SearchTuning.tabKeyboardLag);
    } else {
      focus.focusAfterKeyboard(t);
    }
  }

  /// The field lost the focus at time [t]: it sinks back.
  void unfocused(double t) {
    if (focus.isFocused) {
      focus.unfocus(t, delay: SearchTuning.tabUnfocusDelay);
    }
  }

  /// The keyboard started rising at time [t]: a waiting focus starts its
  /// rise.
  void keyboardRose(double t) =>
      focus.keyboardRose(t, lag: SearchTuning.tabKeyboardLag);

  /// The bar rests as a bar and the search circle takes taps.
  bool get resting => !_open && morph.abs() < 0.001;

  /// The search is open and the morph into the field has settled: the
  /// field itself shows.
  bool get settled => _open && (morph - 1).abs() < 0.001;

  /// The close button shows: the field settled and focused or on its way.
  bool get closeShown =>
      settled &&
      (focus.progress > 0.001 || (focus.isFocused && !focus.waitsForKeyboard));

  /// A tap on the tab circle closes the search.
  bool get tabTakesTaps => _open && focus.progress < 0.5;
}
