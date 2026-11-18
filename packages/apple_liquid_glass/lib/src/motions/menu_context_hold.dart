import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:kinesis/motion.dart';

/// A finger resting on a context menu's view before its menu opens, as
/// UIKit's `UIContextMenuInteraction` runs it (measured on iPhone 16 Pro,
/// iOS 27, context-menu.md).
///
/// The view grows by [growthAfter] while the finger rests. At
/// [commitAfter] the hold commits ([onCommit]): a release from then on
/// opens the menu anyway. At [openAfter] the menu opens under the finger
/// ([onOpen]), at that time exactly, with the growth the view had reached.
final class ContextHold extends Motion {
  /// Creates a hold no finger rests on.
  ContextHold({required this.onCommit, required this.onOpen, super.clock});

  /// Called when the hold commits.
  final VoidCallback onCommit;

  /// Called at time `t` when the finger has rested for [openAfter], with
  /// the view's [growth] then; the hold has ended.
  final void Function(double t, double growth) onOpen;

  /// UIKit's growth of a held view before its menu opens, in points along
  /// its longest side, after [held] seconds: nothing for 0.184 s, then 32
  /// points a second to 8 points, then 20 a second to 15 points (within
  /// 0.21 points of every frame).
  static double growthAfter(double held) {
    if (held <= _growthStart) return 0;
    if (held <= _growthKnee) return _growthFastRate * (held - _growthStart);
    return math.min(
      _growthKneePoints + _growthSlowRate * (held - _growthKnee),
      _growthPoints,
    );
  }

  static const double _growthStart = 0.184;
  static const double _growthKnee = 0.434;
  static const double _growthFastRate = 32;
  static const double _growthSlowRate = 20;
  static const double _growthPoints = 15;
  static const double _growthKneePoints =
      _growthFastRate * (_growthKnee - _growthStart);

  /// The hold time past which a release opens the menu anyway (0.400 s
  /// cancelled and 0.433 s opened).
  static const double commitAfter = 0.42;

  /// The hold time at which the menu opens under the finger (measured
  /// 0.768 - 0.797 s).
  static const double openAfter = 0.78;

  /// How far, in points, a finger may travel from where it touched before
  /// the hold commits; beyond it the hold drops. Not measured: Flutter's
  /// touch slop.
  static const double moveAllowance = 18;

  /// Whether a finger that has travelled [travel] since the touch has
  /// left the view, dropping the hold.
  static bool leaves(Offset travel) => travel.distance > moveAllowance;

  static const _commitSlot = #commit;
  static const _openSlot = #open;

  double? _since;
  bool _committed = false;

  /// Whether a finger rests on the view.
  bool get isHeld => _since != null;

  /// Whether the resting finger has held past [commitAfter].
  bool get isCommitted => _committed;

  /// The view's growth now, 0 while no finger rests on it.
  double get growth => growthAt(now);

  /// The view's growth at time [t], 0 while no finger rests on it.
  double growthAt(double t) => switch (_since) {
    final since? => growthAfter(t - since),
    null => 0,
  };

  @override
  bool get holds => isHeld;

  /// A finger came to rest on the view at time [t].
  void down(double t) {
    advance(t);
    _since = t;
    _committed = false;
    at(t + commitAfter, (double s) {
      _committed = true;
      onCommit();
    }, slot: _commitSlot);
    at(t + openAfter, (double s) {
      final grown = growthAt(s);
      _end();
      onOpen(s, grown);
    }, slot: _openSlot);
    changed();
  }

  /// The finger lifted, moved off or was cancelled at time [t]: the view
  /// drops back at once. Answers the growth it had then.
  double release(double t) {
    advance(t);
    final grown = growthAt(t);
    _end();
    changed();
    return grown;
  }

  void _end() {
    _since = null;
    _committed = false;
    unschedule(_commitSlot);
    unschedule(_openSlot);
  }
}
