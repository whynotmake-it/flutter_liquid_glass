import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/src/widgets/input_shared.dart';
import 'package:meta/meta.dart';

/// Turns the haptics of the input regions below it on or off: an app's
/// setting for haptics, or a part of a screen that stays quiet.
///
/// UIKit: the System Haptics setting. Flutter: none; `TickerMode` is the
/// same shape for tickers.
///
/// An `InputRegion` or `InputZones` below a scope with [enabled] false
/// plays no feedback, and [MotionHapticPlay.play] plays nothing there. A
/// scope cannot turn haptics back on below one that turned them off.
class MotionHapticScope extends StatelessWidget {
  /// Turns the haptics of [child] on or off.
  const MotionHapticScope({
    required this.enabled,
    required this.child,
    super.key,
  });

  /// Whether the regions below play their haptics.
  final bool enabled;

  /// The subtree the scope governs.
  final Widget child;

  /// Whether haptics are on at [context]: false below any scope that turns
  /// them off, true otherwise. Rebuilds [context] when that changes.
  static bool enabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HapticScope>()?.enabled ??
      true;

  @override
  Widget build(BuildContext context) => _HapticScope(
    enabled: enabled && enabledOf(context),
    child: child,
  );
}

/// Plays [haptic] for the control at [context], unless a scope there turns
/// haptics off or an input host is handling a keyboard or accessibility
/// input; [context] does not come to depend on the scope.
@internal
void playHaptic(BuildContext context, MotionHaptic haptic) {
  if (!context.mounted || !gestureInput) return;
  if (!(context.getInheritedWidgetOfExactType<_HapticScope>()?.enabled ??
      true)) {
    return;
  }
  switch (haptic) {
    case .selection:
      HapticFeedback.selectionClick().ignore();
    case .lightImpact:
      HapticFeedback.lightImpact().ignore();
    case .mediumImpact:
      HapticFeedback.mediumImpact().ignore();
    case .heavyImpact:
      HapticFeedback.heavyImpact().ignore();
  }
}

class _HapticScope extends InheritedWidget {
  const _HapticScope({required this.enabled, required super.child});

  final bool enabled;

  @override
  bool updateShouldNotify(_HapticScope oldWidget) =>
      enabled != oldWidget.enabled;
}

/// Plays a [MotionHaptic] for a control.
///
/// UIKit: `UIFeedbackGenerator`. SwiftUI: `sensoryFeedback`. Flutter:
/// `HapticFeedback`.
extension MotionHapticPlay on MotionHaptic {
  /// Plays the haptic for the control at [context], at once.
  ///
  /// This is how a control plays a haptic for something that is not an
  /// event of its interactions: a switch whose shown state flips under the
  /// finger, a slider that reaches its end stop, a wheel that turns to
  /// the next row. The haptics of the interactions' own events go through
  /// `InputRegion.feedback` and `InputZones.feedback`, which play the same
  /// way.
  ///
  /// It plays nothing below a [MotionHapticScope] that turns haptics off,
  /// and nothing while an input region or a zone handles a keyboard or
  /// accessibility input (an `ActivateInput` or `AdjustInput` whose source
  /// is not the pointer): a control that answers a key or an assistive
  /// action by calling it stays silent, as UIKit's controls are.
  void play(BuildContext context) => playHaptic(context, this);
}
