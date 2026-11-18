part of 'menu_motion.dart';

enum _Phase { idle, opening, closing }

class _Pointer {
  _Pointer({
    required this.fromButton,
    required this.position,
  });

  final bool fromButton;
  Offset position;
  bool openedByHold = false;
  bool holdForfeited = false;
  bool scrolled = false;
  bool leftButton = false;

  /// Whether the touch started on the top list, and so stretches and lights
  /// it, highlights its rows and can choose one. A touch elsewhere does none
  /// of this wherever it goes (an iPhone 16 Pro).
  bool touchesTopList = true;

  /// Whether the touch started on the parent list showing under a submenu.
  bool startedOnParent = false;

  /// Where a touch off the top list started.
  Offset start = Offset.zero;

  /// The flex this finger stretches, once it does.
  MenuFlex? flex;
}

/// A damped spring driven by an input.
class _DrivenKick {
  _DrivenKick();

  _DrivenKick.of(_DrivenKick other)
    : value = other.value,
      velocity = other.velocity;

  double value = 0;
  double velocity = 0;

  bool get isAtRest =>
      value.abs() < MenuTuning.kickRestValue &&
      velocity.abs() < MenuTuning.kickRestVelocity;

  void reset() {
    value = 0;
    velocity = 0;
  }

  /// One step of [h] seconds on [spring] toward [target].
  void integrate(double h, Spring spring, double target) {
    velocity +=
        (spring.stiffness * (target - value) - spring.damping * velocity) * h;
    value += velocity * h;
  }
}

/// The menu's two driven kicks, stepped on a fixed grid of
/// [MenuTuning.kickIntegrationStep] whatever the frames sample: the
/// recorded kicks were fitted with this step, and the grid makes a replay
/// at any frame rate step the same frames (NEAR, see
/// [MenuTuning.kickIntegrationStep]).
///
/// The loop sleeps once both kicks and the springs that drive them rest,
/// keeping what is left (below [MenuTuning.kickRestValue]), and wakes when
/// the menu opens, closes or kicks. It steps up to three seconds of a
/// longer gap, in which every kick rings out.
final class _KickLoop extends MotionLoop {
  _KickLoop(this.tuning)
    : super(
        rate: 1 / MenuTuning.kickIntegrationStep,
        maxFrames: (3 / MenuTuning.kickIntegrationStep).round(),
      );

  final MenuTuning tuning;

  final menu = _DrivenKick();
  final button = _DrivenKick();

  // The menu's phase as the kicks see it: written where the menu's own
  // phase is.
  _Phase _phase = _Phase.idle;
  MotionValue<double>? _openReference;
  MotionValue<double>? _closeReference;
  double _amplitude = 1;
  double _closeAmplitude = 1;
  double _sourceAmplitude = 1;

  bool get isAtRest => menu.isAtRest && button.isAtRest;

  /// Sizes the kicks for a menu [height] pixels tall.
  void size(double height) {
    _amplitude = _interpolate(_kickAmplitude, height);
    _closeAmplitude = _interpolate(_closeKickAmplitude, height);
    _sourceAmplitude = _interpolate(_sourceKickAmplitude, height);
  }

  /// The menu starts opening at [t]: the menu kick chases the velocity of
  /// an opening spring played from [t].
  void open(double t) {
    _phase = _Phase.opening;
    final reference = MotionValue<double>(0, spring: tuning.openSpring);
    reference.retarget(t, 1);
    _openReference = reference;
    wake(t);
  }

  /// The menu starts closing at [t]: the button kick chases the velocity
  /// of a closing spring played from [t].
  void close(double t) {
    _phase = _Phase.closing;
    final reference = MotionValue<double>(1, spring: tuning.closeSpring);
    reference.retarget(t, 0);
    _closeReference = reference;
    wake(t);
  }

  /// The close strikes the menu kick away from the button at [t], less
  /// the nearer it already is to [MenuTuning.closeKickReach].
  void strike(double t) {
    final reach = tuning.closeKickReach * _closeAmplitude;
    final room = (1 - menu.value / reach).clamp(0.0, 1.0);
    menu.velocity += tuning.closeKickImpulse * _closeAmplitude * room;
    wake(t);
  }

  /// The menu is gone: both kicks and their springs start from nothing.
  void rest() {
    _phase = _Phase.idle;
    menu.reset();
    button.reset();
    _openReference = null;
    _closeReference = null;
  }

  @override
  bool step(double t) => _step(t, menu, button);

  /// One frame of [menuKick] and [buttonKick] at time [t]; answers whether
  /// they need another.
  bool _step(double t, _DrivenKick menuKick, _DrivenKick buttonKick) {
    if (_phase == _Phase.idle || !tuning.morph.kicks) return false;
    const h = MenuTuning.kickIntegrationStep;
    final mid = t - h / 2;
    final opening = _phase == _Phase.opening;
    final open = opening ? _openReference : null;
    final close = _closeReference;
    menuKick.integrate(
      h,
      opening ? tuning.openKickSpring : tuning.closeKickSpring,
      open == null
          ? 0
          : tuning.openKickGain * _amplitude * open.velocityAt(mid),
    );
    buttonKick.integrate(
      h,
      tuning.sourceKickSpring,
      close == null
          ? 0
          : tuning.sourceKickGain * _sourceAmplitude * close.velocityAt(mid),
    );
    return !(menuKick.isAtRest &&
        buttonKick.isAtRest &&
        (open == null || _referenceRests(open, t)) &&
        (close == null || _referenceRests(close, t)));
  }

  // A kick sleeps only while its input, the reference's velocity, has
  // died out.
  static bool _referenceRests(MotionValue<double> spring, double t) =>
      (spring.valueAt(t) - spring.target).abs() < MenuTuning.kickRestValue &&
      spring.velocityAt(t).abs() < MenuTuning.kickRestVelocity;

  /// The kicks at time [t] as the loop will step them while nothing else
  /// changes, stepped on copies: the loop itself keeps its state.
  ({double menu, double button}) valuesAt(double t) {
    if (!isMoving) return (menu: menu.value, button: button.value);
    final menuKick = _DrivenKick.of(menu);
    final buttonKick = _DrivenKick.of(button);
    final end = (t * rate + 1e-6).floor();
    for (var k = (lastFrame * rate).round() + 1; k <= end; k++) {
      if (!_step(k / rate, menuKick, buttonKick)) break;
    }
    return (menu: menuKick.value, button: buttonKick.value);
  }
}

double _interpolate(List<(double, double)> table, double height) {
  if (height <= table.first.$1) return table.first.$2;
  for (var i = 1; i < table.length; i++) {
    final (h1, a1) = table[i];
    if (height <= h1) {
      final (h0, a0) = table[i - 1];
      return a0 + (a1 - a0) * (height - h0) / (h1 - h0);
    }
  }
  return table.last.$2;
}

/// The menu's values at one time, each made on its first read and kept.
///
/// [MenuMotion] keeps one for [MenuMotion.now] and drops it after every
/// write of what it reads. A frame keeps its time; one asked for at another
/// time is made anew.
///
/// A frame ahead of [MenuMotion.now] is given the [kicks] the loop will
/// have stepped to by its time; the frame at the motion's time reads the
/// loop's own.
final class _MenuFrame {
  _MenuFrame(this._motion, this.time, {this.kicks});

  final MenuMotion _motion;

  /// The time the values are at.
  final double time;

  /// The kicks at [time], or null to read the loop's.
  final ({double menu, double button})? kicks;

  double get menuKick => kicks?.menu ?? _motion._kicks.menu.value;

  double get buttonKick => kicks?.button ?? _motion._kicks.button.value;

  late final Rect rect = _motion._frameAt(time);

  late final MenuFlexShape flex = _motion._flexOfFrame(this);

  late final MenuBlob menuBlob = _motion._blobFor(this, rect, flex: flex);

  late final MenuBlob unflexedBlob = _motion._blobFor(
    this,
    rect,
    flex: noMenuFlex,
  );

  late final MenuBlob rootBlob = _motion._rootBlobOf(this);

  late final MenuStretch? stretch = _motion._stretchOf(this);

  late final MenuStretch? cardStretch = _motion._cardStretchOf(this);

  late final List<MenuCard> cards = List.unmodifiable(
    _motion._stack.at(time),
  );
}

const List<(double, double)> _kickAmplitude = [
  (62, 0.814),
  (104, 0.814),
  (146, 1),
  (188, 1.488),
  (230, 1.628),
  (272, 1.61),
  (356, 1.563),
  (440, 1.481),
];

// The closing amplitudes were captured at 146, 230 and 440 pixels;
// below 146 the opening's amplitude stands in.
const List<(double, double)> _closeKickAmplitude = [
  (62, 0.814),
  (104, 0.814),
  (146, 1),
  (230, 1.644),
  (440, 1.61),
];

const List<(double, double)> _sourceKickAmplitude = [
  (62, 0.814),
  (104, 0.814),
  (146, 1),
  (230, 1.488),
  (440, 1.777),
];
