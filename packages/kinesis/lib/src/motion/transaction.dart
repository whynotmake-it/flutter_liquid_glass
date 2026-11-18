import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/spring.dart';

/// The motion preferences a motion honors.
///
/// UIKit: `UIAccessibility.isReduceMotionEnabled` and
/// `prefersCrossFadeTransitions`. A motion reads the traits of the
/// `MotionScope` that holds it, which reads `MotionTraitsOverride` or the
/// platform; a value outside a scope reads [MotionTraits.platform].
@immutable
class MotionTraits {
  /// Creates motion preferences.
  const MotionTraits({this.reduceMotion = false, this.preferCrossFade});

  /// The platform's preferences: Reduce Motion or disabled animations.
  factory MotionTraits.platform() {
    final override = debugPlatformOverride;
    if (override != null) return override;
    final features = PlatformDispatcher.instance.accessibilityFeatures;
    return MotionTraits(
      reduceMotion: features.reduceMotion || features.disableAnimations,
    );
  }

  /// Whether `withSpring` resolves its spring to the Reduce Motion
  /// alternative (`Spring.reduced`). A retarget that names its spring keeps
  /// it: a measured control applies its own Reduce Motion rule.
  final bool reduceMotion;

  /// Whether the user prefers transitions that cross-fade over ones that
  /// move, or null where the platform does not say: iOS's Prefer
  /// Cross-Fade Transitions, a part of Reduce Motion.
  final bool? preferCrossFade;

  /// Replaces [MotionTraits.platform] for the whole app: for tests.
  @visibleForTesting
  static MotionTraits? debugPlatformOverride;

  @override
  bool operator ==(Object other) =>
      other is MotionTraits &&
      other.reduceMotion == reduceMotion &&
      other.preferCrossFade == preferCrossFade;

  @override
  int get hashCode => Object.hash(reduceMotion, preferCrossFade);
}

/// How the changes made inside one `withSpring` or `withoutAnimation` body
/// move.
///
/// SwiftUI: `Transaction`.
///
/// A layout host reads [layout], the transaction of the frame's layout
/// changes, to slide what it lays out on the app's spring; a render object
/// built on `MotionResolveHost` reads its spring as `layoutSpring`.
@immutable
class MotionTransaction {
  const MotionTransaction._({
    required this.spring,
    this.tracking = false,
    this.delay = 0,
  });

  /// The spring the changes follow, resolved for Reduce Motion by each
  /// value from its motion's traits; [Spring.immediate] when they jump.
  final Spring spring;

  /// Whether a finger drives the changes, so values follow the spring's
  /// tracking spring.
  final bool tracking;

  /// Seconds before the values turn toward their new targets.
  final double delay;

  static final List<MotionTransaction> _stack = [];

  static MotionTransaction? _layout;

  /// Called when an outermost, non-tracking transaction closes and becomes
  /// the frame's [layout]; set while a view has layout to animate.
  @internal
  static VoidCallback? onLayoutTransaction;

  /// The transaction of the frame's layout changes: the latest outermost
  /// `withSpring` or `withoutAnimation` that closed after the previous frame
  /// drew, or null. A tracking transaction never sets it, so a finger moving
  /// one value does not slide unrelated layout.
  ///
  /// It is kept only while a `MotionResolveHost` is attached, and forgotten
  /// once the frame it belongs to has drawn.
  static MotionTransaction? get layout => _layout;

  /// Forgets [layout] once the frame it belongs to has drawn.
  @internal
  static void clearLayout() => _layout = null;

  /// The transaction in effect, or null outside every body.
  ///
  /// An enclosing `withoutAnimation` dominates every spring inside it;
  /// otherwise the innermost spring wins.
  @internal
  static MotionTransaction? get current {
    if (_stack.isEmpty) return null;
    for (final transaction in _stack) {
      if (transaction.spring.isImmediate) return transaction;
    }
    return _stack.last;
  }

  static void _run(MotionTransaction transaction, VoidCallback changes) {
    _stack.add(transaction);
    try {
      changes();
    } finally {
      _stack.removeLast();
    }
    if (_stack.isNotEmpty || transaction.tracking) return;
    final notify = onLayoutTransaction;
    if (notify == null) return;
    _layout = transaction.spring.isImmediate
        ? transaction
        : MotionTransaction._(
            spring: transaction.spring.resolve(
              reduceMotion: MotionTraits.platform().reduceMotion,
            ),
          );
    notify();
  }
}

/// Animates every motion value whose target [changes] sets, on [spring].
///
/// UIKit: `UIView.animate(springDuration:bounce:)`. SwiftUI:
/// `withAnimation(_:_:)`.
///
/// A value already moving continues from where it is, at the speed it has
/// plus the spring's retarget [Spring.impulse], if any. With [tracking] the
/// values follow the spring's tracking spring, as they do under a finger.
/// With a [delay] in seconds each value keeps its course for that long
/// before it heads to the new target; its target reads the new value at
/// once. Inside an enclosing [withoutAnimation] the changes jump. Under
/// Reduce Motion each value moves on [spring]'s reduced alternative
/// ([MotionTraits.reduceMotion] of its motion).
///
/// The changes start at the clock's time: inside an input callback that is
/// the input's own stamp (`MotionClock.input`).
///
/// It also animates what layout does in the frame it closes before: a
/// `MotionLayout` slides its children on [spring].
void withSpring(
  Spring spring,
  VoidCallback changes, {
  bool tracking = false,
  double delay = 0,
}) => MotionTransaction._run(
  MotionTransaction._(spring: spring, tracking: tracking, delay: delay),
  changes,
);

/// Makes every motion value whose target [changes] sets jump there, even
/// inside an enclosing [withSpring].
///
/// UIKit: `UIView.performWithoutAnimation`.
///
/// A `MotionLayout` changed in the frame it closes before jumps too.
void withoutAnimation(VoidCallback changes) => MotionTransaction._run(
  const MotionTransaction._(spring: Spring.immediate),
  changes,
);
