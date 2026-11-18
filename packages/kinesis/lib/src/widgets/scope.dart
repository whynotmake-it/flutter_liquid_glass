import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';

/// Holds [motion] on its clock while this widget is in the tree, so the
/// clock steps it whenever it moves, and gives it the motion preferences
/// of its place ([MotionTraitsOverride], else the platform and
/// `MediaQuery.disableAnimations`).
///
/// Under a muted `TickerMode` the scope lets go of the motion; the clock
/// still steps it while a selection of it has listeners. Nothing is lost,
/// because a motion is a function of its commands: shown again, it reads
/// where it would be.
class MotionScope extends StatefulWidget {
  /// Holds [motion] for [child].
  const MotionScope({required this.motion, required this.child, super.key});

  /// The motion held.
  final Motion motion;

  /// The subtree that shows the motion.
  final Widget child;

  @override
  State<MotionScope> createState() => _MotionScopeState();
}

class _MotionScopeState extends State<MotionScope> {
  Motion? _held;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(MotionScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final motion = widget.motion;
    motion.traits = MotionTraitsOverride.of(context);
    final next = TickerMode.valuesOf(context).enabled ? motion : null;
    if (identical(next, _held)) return;
    _held?.unretain();
    next?.retain();
    _held = next;
  }

  @override
  void dispose() {
    _held?.unretain();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Gives the motions under it these motion preferences instead of the
/// platform's.
class MotionTraitsOverride extends InheritedWidget {
  /// Gives [traits] to the motions in [child].
  const MotionTraitsOverride({
    required this.traits,
    required super.child,
    super.key,
  });

  /// The preferences the motions below read.
  final MotionTraits traits;

  /// The preferences at [context]: the nearest override, else the platform
  /// with `MediaQuery.disableAnimations`.
  static MotionTraits of(BuildContext context) {
    final override = context
        .dependOnInheritedWidgetOfExactType<MotionTraitsOverride>();
    if (override != null) return override.traits;
    final platform = MotionTraits.platform();
    final disabled = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!disabled || platform.reduceMotion) return platform;
    return MotionTraits(
      reduceMotion: true,
      preferCrossFade: platform.preferCrossFade,
    );
  }

  @override
  bool updateShouldNotify(MotionTraitsOverride oldWidget) =>
      traits != oldWidget.traits;
}

/// Gives the widgets under it the clock their motions run on.
///
/// A widget that makes motions or values reads the clock here once, when
/// it makes them, passes it to them (`Motion(clock: ...)`,
/// `MotionValue(..., clock: ...)`) and takes the time of its commands from
/// it (`clock.now`), also before it owns a motion. Without a scope the
/// clock is [MotionClock.instance]. A test or a replay drives a subtree on
/// a clock of its own, such as a `ManualMotionClock`, by putting it here.
/// Motions already made keep their clock when the scope's clock changes.
class MotionClockScope extends InheritedWidget {
  /// Gives [clock] to the widgets in [child].
  const MotionClockScope({
    required this.clock,
    required super.child,
    super.key,
  });

  /// The clock the motions below run on.
  final MotionClock clock;

  /// The clock at [context]: the nearest scope's, else
  /// [MotionClock.instance].
  ///
  /// It makes no dependency, so a state may read it in `initState` and in
  /// its listeners.
  static MotionClock of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MotionClockScope>()?.clock ??
      MotionClock.instance;

  @override
  bool updateShouldNotify(MotionClockScope oldWidget) => false;
}
