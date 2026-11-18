import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:kinesis/src/input/interaction.dart';
import 'package:kinesis/src/input/interaction_event.dart';
import 'package:kinesis/src/input/interaction_input.dart';
import 'package:kinesis/src/input/interaction_values.dart';
import 'package:kinesis/src/input/press_reach.dart';
import 'package:meta/meta.dart';

/// Where the rest of a touch goes after a hand-off: a receiving region in
/// another subtree or an overlay (`InputRegion(port:)`), or any receiver
/// given to [attach], such as a session in a replay.
///
/// The source keeps the touch, so nothing is cancelled when the receiver
/// appears above the finger. Forwarded inputs keep their stamps and are
/// mapped into the receiver's coordinates as each one is delivered. While
/// no receiver is bound they wait, so a menu built a frame after the hold
/// still hears the touch from the hand-off on.
///
/// ```dart
/// final port = InputPort();
/// LongPressInteraction(onStart: open).sequenced(port.forward);
/// // in the menu: InputZones(port: port, slides: true, zones: rows, ...)
/// ```
final class InputPort {
  /// Creates a port with no receiver.
  InputPort();

  final List<PortEvent> _waiting = [];
  void Function(PortEvent event)? _receiver;

  /// The interaction a source hands a touch on to:
  /// `hold.sequenced(port.forward)`. One source forwards at a time.
  late final Interaction forward = _PortForward(this);

  /// Makes [receiver] the receiver and delivers what waited: how an input
  /// host receives the touches handed to it (`InputRegion(port:)` does).
  ///
  /// The host maps each event into its own coordinates with
  /// [PortEvent.input] as it arrives, and hands the result to its session.
  void attach(void Function(PortEvent event) receiver) {
    _receiver = receiver;
    final waiting = List<PortEvent>.of(_waiting);
    _waiting.clear();
    waiting.forEach(receiver);
  }

  /// Drops [receiver] if it is the receiver.
  void detach(void Function(PortEvent event) receiver) {
    if (identical(_receiver, receiver)) _receiver = null;
  }

  void _send(PortEvent event) {
    if (event.handOff) _waiting.clear();
    final receiver = _receiver;
    if (receiver == null) {
      _waiting.add(event);
      return;
    }
    receiver(event);
  }
}

enum _PortPhase {
  /// The hand-off.
  down,

  /// A move.
  move,

  /// The release.
  up,

  /// The touch ended without a release.
  cancel,
}

/// One pointer input an [InputPort] hands on, in global coordinates, as its
/// receiver hears it ([InputPort.attach]).
@immutable
final class PortEvent {
  const PortEvent._({
    required this._phase,
    required this.time,
    required this.pointer,
    this.position = Offset.zero,
    this._velocity = Offset.zero,
    this._kind = PointerDeviceKind.touch,
    this._buttons = kPrimaryButton,
    this._reason = PointerCancelReason.platform,
  });

  final _PortPhase _phase;
  final Offset _velocity;
  final PointerDeviceKind _kind;
  final int _buttons;
  final PointerCancelReason _reason;

  /// The input's stamp.
  final double time;

  /// The pointer.
  final int pointer;

  /// Where it is, in global coordinates; zero for a cancel.
  final Offset position;

  /// Whether this is the hand-off: the down that starts the touch in the
  /// receiver. A receiver works out what only a down needs, such as the
  /// scroll views around it, for this one alone.
  bool get handOff => _phase == _PortPhase.down;

  /// The input in a receiver's coordinates, [toLocal] mapping global ones
  /// as the receiver is now; a hand-off is a down in a region of [size]
  /// with its [reach], inside scroll views along [scrollAxes], [contested]
  /// by a host around it, in an arena of [touchSlop].
  InteractionInput input(
    Offset Function(Offset global) toLocal, {
    required Size size,
    PressReach reach = PressReach.box,
    Set<Axis> scrollAxes = const {},
    bool contested = false,
    double touchSlop = kTouchSlop,
  }) => switch (_phase) {
    _PortPhase.down => PointerDownInput(
      time: time,
      pointer: pointer,
      position: toLocal(position),
      regionSize: size,
      reach: reach,
      globalPosition: position,
      kind: _kind,
      buttons: _buttons,
      scrollAxes: scrollAxes,
      contested: contested,
      touchSlop: touchSlop,
    ),
    _PortPhase.move => PointerMoveInput(
      time: time,
      pointer: pointer,
      position: toLocal(position),
      regionBox: Offset.zero & size,
      globalPosition: position,
    ),
    _PortPhase.up => PointerUpInput(
      time: time,
      pointer: pointer,
      position: toLocal(position),
      regionBox: Offset.zero & size,
      velocity: toLocal(position + _velocity) - toLocal(position),
      globalPosition: position,
      globalVelocity: _velocity,
    ),
    _PortPhase.cancel => PointerCancelInput(
      time: time,
      pointer: pointer,
      reason: _reason,
    ),
  };
}

/// Forwards what it hears to its port, mapped to global coordinates by the
/// mapping its region binds; as they are while none is bound.
final class _PortForward extends Interaction {
  _PortForward(this.port) : super(role: InteractionRole.gesture);

  final InputPort port;

  Offset Function(Offset local)? _toGlobal;

  @override
  void bindRegion(Offset Function(Offset local) toGlobal) =>
      _toGlobal = toGlobal;

  Offset _global(Offset p) => _toGlobal?.call(p) ?? p;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        port._send(
          PortEvent._(
            phase: _PortPhase.down,
            time: input.time,
            pointer: input.pointer,
            position: _global(input.position),
            kind: input.kind,
            buttons: input.buttons,
          ),
        );
      case PointerMoveInput():
        port._send(
          PortEvent._(
            phase: _PortPhase.move,
            time: input.time,
            pointer: input.pointer,
            position: _global(input.position),
          ),
        );
      case PointerUpInput():
        final at = _global(input.position);
        port._send(
          PortEvent._(
            phase: _PortPhase.up,
            time: input.time,
            pointer: input.pointer,
            position: at,
            velocity: _global(input.position + input.velocity) - at,
          ),
        );
      case PointerCancelInput():
        port._send(
          PortEvent._(
            phase: _PortPhase.cancel,
            time: input.time,
            pointer: input.pointer,
            reason: input.reason,
          ),
        );
      case PointerAcceptedInput() ||
          PointerHoverInput() ||
          PointerScrollInput() ||
          ActivateInput() ||
          AdjustInput() ||
          ContextMenuInput():
    }
    return InteractionUpdate.none;
  }
}
