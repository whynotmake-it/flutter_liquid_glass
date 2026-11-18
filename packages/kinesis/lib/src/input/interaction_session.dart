part of 'interaction.dart';

/// What a session made of an input: whether the region holds or gives up
/// the touch, and the interactions' events.
@immutable
final class SessionOutput {
  /// Describes a session's answer.
  const SessionOutput({
    this.claim = false,
    this.reject = false,
    this.events = const [],
  });

  /// Nothing to do.
  static const SessionOutput none = SessionOutput();

  /// Whether the region holds the touch against other gestures.
  final bool claim;

  /// Whether the region gives the touch up.
  final bool reject;

  /// What the interactions did, for haptics.
  final List<InteractionEvent> events;
}

/// One region's input policy without widgets: who hears which input when,
/// the scroll delay, onsets, claims and loss.
///
/// UIKit: `UIScrollView.delaysContentTouches` with a control's tracking.
/// SwiftUI: a gesture's priority in a scroll view. Flutter: the gesture
/// arena, without its timers.
///
/// A control or content hears a touch at once outside a scroll view and
/// [scrollDelay] after contact inside one; a gesture hears it at contact
/// plus its onset. Interactions joined with [Interaction.simultaneously]
/// each keep their own timing. A touch released while held back is
/// delivered with its release, so a quick tap still activates. A touch
/// that a scroll takes while held back never reaches content; one already
/// delivered is cancelled. When an interaction recognizes its gesture, the
/// others are cancelled for the rest of the touch. Claims of content are
/// ignored. A second pointer during a touch is rejected. Timed deliveries
/// come due at [nextDue] and run in [advance], so scroll timing replays
/// from recorded input. Observers ([InteractionRole.observer]) hear every
/// pointer they accept at once, beside all of this, and are not cancelled
/// when the touch is [lost].
///
/// Whether a touch is still the session's has two answers, one per side.
/// [isActive] answers for the interactions that take part in the arena:
/// a down one of them accepted starts the touch, and its release, its
/// cancel or [lost] ends it; one touch at a time. [observes] answers for
/// the observers of one pointer: from a down an observer accepted until
/// that pointer lifts or is cancelled, [lost] or not. A host that hands a
/// pointer on asks [observes] for the observers ([observe]) and keeps
/// [track]ing the others while [isActive]:
///
/// ```text
///            down     lost        up
/// isActive   +--------+                   arena members
/// observes   +--------------------+       observers of that pointer
/// ```
class InteractionSession {
  /// Creates a session over [interactions].
  InteractionSession(List<Interaction> interactions)
    : interactions = [for (final i in interactions) ..._apart(i)] {
    _observers = [
      for (final i in this.interactions)
        if (i.role == InteractionRole.observer) i,
    ];
  }

  /// UIScrollView's delay before content hears a touch, in seconds.
  static const double scrollDelay = 0.15;

  /// The interactions, with simultaneous ones taken apart; when two
  /// recognize on one input, the first wins.
  final List<Interaction> interactions;

  static Iterable<Interaction> _apart(Interaction interaction) sync* {
    if (interaction case _Simultaneous(:final a, :final b)) {
      yield* _apart(a);
      yield* _apart(b);
    } else {
      yield interaction;
    }
  }

  late final List<Interaction> _observers;
  final Map<int, List<Interaction>> _observing = {};
  final List<Interaction> _accepting = [];
  final Set<Interaction> _failed = {};
  final Set<Interaction> _cancelled = {};
  double _time = 0;
  final Map<Interaction, double> _held = {};
  PointerDownInput? _down;
  PointerMoveInput? _latest;
  bool _claimed = false;

  /// Whether a touch is being followed.
  bool get isActive => _down != null;

  /// Whether an observer hears [pointer]: one accepted its down and it has
  /// not lifted or been cancelled.
  bool observes(int pointer) => _observing.containsKey(pointer);

  /// The time the next held delivery or timed reaction comes due, a
  /// reaction to hover between touches included.
  double? get nextDue {
    double? due;
    for (final at in _held.values) {
      due = _earliest(due, at);
    }
    for (final interaction in interactions) {
      if (!_held.containsKey(interaction) &&
          !_cancelled.contains(interaction)) {
        due = _earliest(due, interaction.nextDue);
      }
    }
    return due;
  }

  double _deliveryTime(Interaction interaction, PointerDownInput down) =>
      switch (interaction.role) {
        InteractionRole.gesture => down.contactTime + interaction.onset,
        _ when down.scrollAxes.isEmpty => down.time,
        _ => down.contactTime + scrollDelay,
      };

  /// Answers a stamped pointer, keyboard, hover or accessibility input:
  /// [observe] and then [track] it. Hover, scrolls, activations, value
  /// commands and context menu requests reach every interaction.
  SessionOutput handle(InteractionInput input) {
    final observed = observe(input);
    final output = track(input);
    if (observed.events.isEmpty) return output;
    return SessionOutput(
      claim: output.claim,
      reject: output.reject,
      events: [...observed.events, ...output.events],
    );
  }

  /// Answers a stamped pointer input for the observers only: what an input
  /// host hands on as the event reaches the region, as a `Listener` hears
  /// it, before the gesture arena's members hear it ([track]).
  SessionOutput observe(InteractionInput input) {
    final List<Interaction>? observers;
    switch (input) {
      case PointerDownInput(:final pointer):
        observers = [
          for (final observer in _observers)
            if (observer.accepts(input)) observer,
        ];
        if (observers.isEmpty) return SessionOutput.none;
        _observing[pointer] = observers;
      case PointerMoveInput(:final pointer):
        observers = _observing[pointer];
      case PointerUpInput(:final pointer) || PointerCancelInput(:final pointer):
        observers = _observing.remove(pointer);
      case PointerAcceptedInput() ||
          PointerHoverInput() ||
          PointerScrollInput() ||
          ActivateInput() ||
          AdjustInput() ||
          ContextMenuInput():
        return SessionOutput.none;
    }
    if (observers == null) return SessionOutput.none;
    final events = <InteractionEvent>[
      for (final observer in observers) ...observer.handle(input).events,
    ];
    return events.isEmpty ? SessionOutput.none : SessionOutput(events: events);
  }

  /// Answers a stamped input for every interaction but the observers: what
  /// an input host hands on where the gesture arena's members hear the
  /// event.
  SessionOutput track(InteractionInput input) {
    _time = input.time;
    switch (input) {
      case PointerDownInput():
        if (_down != null) return const SessionOutput(reject: true);
        _accepting.clear();
        _failed.clear();
        _cancelled.clear();
        _held.clear();
        _claimed = false;
        for (final interaction in interactions) {
          if (interaction.role != InteractionRole.observer &&
              interaction.accepts(input)) {
            _accepting.add(interaction);
          }
        }
        if (_accepting.isEmpty) return const SessionOutput(reject: true);
        _down = input;
        _latest = null;
        var output = SessionOutput.none;
        for (final interaction in _accepting) {
          final at = _deliveryTime(interaction, input);
          if (at > input.time) {
            _held[interaction] = at;
          } else {
            output = _apply(output, interaction, interaction.handle(input));
          }
        }
        return output;
      case PointerMoveInput():
        if (_down?.pointer != input.pointer) return SessionOutput.none;
        _latest = input;
        return _deliver(advance(input.time), input);
      case PointerUpInput():
        final down = _down;
        if (down == null || down.pointer != input.pointer) {
          return SessionOutput.none;
        }
        var output = advance(input.time);
        for (final interaction in _held.keys.toList()) {
          _held.remove(interaction);
          output = _apply(
            output,
            interaction,
            interaction.handle(down.copyWith(time: input.time)),
          );
        }
        for (final interaction in _accepting) {
          if (_cancelled.contains(interaction)) continue;
          output = _apply(output, interaction, interaction.handle(input));
        }
        _end();
        return output;
      case PointerAcceptedInput():
        if (_down?.pointer != input.pointer) return SessionOutput.none;
        return _deliver(SessionOutput.none, input);
      case PointerCancelInput():
        final down = _down;
        if (down == null || down.pointer != input.pointer) {
          return SessionOutput.none;
        }
        final output = _deliver(SessionOutput.none, input);
        _end();
        return output;
      case PointerHoverInput() ||
          PointerScrollInput() ||
          ActivateInput() ||
          AdjustInput() ||
          ContextMenuInput():
        var output = SessionOutput.none;
        for (final interaction in interactions) {
          output = _apply(output, interaction, interaction.handle(input));
        }
        return output;
    }
  }

  /// The touch of [pointer] went to another gesture at [time], or the
  /// region gave it up: held deliveries are dropped and delivered
  /// interactions cancelled. Observers keep hearing it.
  SessionOutput lost(int pointer, double time) => track(
    PointerCancelInput(
      time: time,
      pointer: pointer,
      reason: PointerCancelReason.taken,
    ),
  );

  /// Runs the held deliveries and timed reactions due by [time], each at
  /// its own time.
  SessionOutput advance(double time) {
    _time = time;
    var output = SessionOutput.none;
    final down = _down;
    while (true) {
      Interaction? next;
      double? at;
      for (final MapEntry(:key, :value) in _held.entries) {
        if (value <= time && (at == null || value < at)) {
          next = key;
          at = value;
        }
      }
      if (next == null || at == null || down == null) break;
      _held.remove(next);
      output = _apply(output, next, next.handle(down.copyWith(time: at)));
      final latest = _latest;
      if (latest != null) {
        output = _apply(output, next, next.handle(latest.copyWith(time: at)));
      }
    }
    for (final interaction in interactions) {
      if (_held.containsKey(interaction) || _cancelled.contains(interaction)) {
        continue;
      }
      final due = interaction.nextDue;
      if (due != null && due <= time) {
        output = _apply(output, interaction, interaction.advance(time));
      }
    }
    return output;
  }

  SessionOutput _deliver(SessionOutput before, InteractionInput input) {
    var output = before;
    for (final interaction in _accepting) {
      if (!_held.containsKey(interaction) &&
          !_cancelled.contains(interaction)) {
        output = _apply(output, interaction, interaction.handle(input));
      }
    }
    return output;
  }

  SessionOutput _apply(
    SessionOutput output,
    Interaction interaction,
    InteractionUpdate update,
  ) {
    if (interaction.role == InteractionRole.observer) {
      if (update.events.isEmpty) return output;
      return SessionOutput(
        claim: output.claim,
        reject: output.reject,
        events: [...output.events, ...update.events],
      );
    }
    final holds = switch (interaction.role) {
      InteractionRole.gesture => true,
      InteractionRole.control =>
        !(_down?.contested ?? false) || update.recognizes,
      InteractionRole.content || InteractionRole.observer => false,
    };
    final claim = holds && (update.claims || update.recognizes) && !_claimed;
    if (claim) _claimed = true;
    if (update.recognizes) _recognized(interaction);
    var reject = false;
    if (update.fails &&
        _failed.add(interaction) &&
        !_claimed &&
        _failed.length == _accepting.length) {
      reject = true;
    }
    if (!claim && !reject && update.events.isEmpty) return output;
    return SessionOutput(
      claim: output.claim || claim,
      reject: output.reject || reject,
      events: [...output.events, ...update.events],
    );
  }

  void _recognized(Interaction winner) {
    final pointer = _down?.pointer;
    for (final other in _accepting) {
      if (identical(other, winner) || !_cancelled.add(other)) continue;
      if (_held.remove(other) != null || pointer == null) continue;
      other.handle(
        PointerCancelInput(
          time: _time,
          pointer: pointer,
          reason: PointerCancelReason.taken,
        ),
      );
    }
  }

  void _end() {
    _down = null;
    _latest = null;
    _held.clear();
  }
}
