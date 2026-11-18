import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/input.dart';

import 'scrub_interaction.dart';

const _size = Size(100, 40);

PointerDownInput _down(double time, {Set<Axis> scroll = const {}}) =>
    PointerDownInput(
      time: time,
      pointer: 1,
      position: const Offset(50, 20),
      regionSize: _size,
      scrollAxes: scroll,
    );

PointerDownInput _downAt(double time, Offset position) => PointerDownInput(
  time: time,
  pointer: 1,
  position: position,
  regionSize: _size,
);

PointerMoveInput _move(
  double time,
  Offset position, {
  Rect box = const Rect.fromLTWH(0, 0, 100, 40),
}) => PointerMoveInput(
  time: time,
  pointer: 1,
  position: position,
  regionBox: box,
);

PointerUpInput _up(
  double time,
  Offset position, {
  Offset velocity = .zero,
  Rect box = const Rect.fromLTWH(0, 0, 100, 40),
}) => PointerUpInput(
  time: time,
  pointer: 1,
  position: position,
  regionBox: box,
  velocity: velocity,
);

final class _Value extends Interaction {
  final List<(ValueCommand, ActivationSource)> heard = [];

  @override
  bool get adjusts => true;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is AdjustInput) heard.add((input.command, input.source));
    return InteractionUpdate.none;
  }
}

final class _Wheel extends Interaction {
  @override
  bool get takesWheel => true;

  @override
  InteractionUpdate handle(InteractionInput input) => InteractionUpdate.none;
}

void main() {
  group('value commands', () {
    test('reach every interaction of a session with their source', () {
      final value = _Value();
      final session = InteractionSession([PressInteraction(), value]);
      session.handle(
        const AdjustInput(time: 1, command: ValueCommand.toMaximum),
      );
      session.handle(
        const AdjustInput(
          time: 2,
          command: ValueCommand.decrease,
          source: ActivationSource.accessibility,
        ),
      );
      expect(value.heard, [
        (ValueCommand.toMaximum, ActivationSource.keyboard),
        (ValueCommand.decrease, ActivationSource.accessibility),
      ]);
    });

    test('a relation adjusts when a part does', () {
      expect(PressInteraction().adjusts, isFalse);
      expect(PressInteraction().simultaneously(_Value()).adjusts, isTrue);
      expect(PressInteraction().exclusively(_Value()).adjusts, isTrue);
      expect(_Value().sequenced(PressInteraction()).adjusts, isTrue);
      expect(PressInteraction().sequenced(_Value()).adjusts, isFalse);
    });
  });

  group('SecondaryClickInteraction', () {
    test('a secondary press clicks at once and the press does not hear '
        'it', () {
      final clicks = <(double, Offset)>[];
      var taps = 0;
      final press = PressInteraction(onTap: (t) => taps++);
      final session = InteractionSession([
        press,
        SecondaryClickInteraction(
          onClick: (t, position) => clicks.add((t, position)),
        ),
      ]);
      final output = session.handle(
        const PointerDownInput(
          time: 1,
          pointer: 1,
          position: Offset(10, 5),
          regionSize: _size,
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        ),
      );
      expect(output.claim, isTrue);
      expect(press.pressed, isFalse);
      session.handle(_up(1.1, const Offset(10, 5)));
      expect(clicks, [(1.0, const Offset(10, 5))]);
      session.handle(_down(2));
      session.handle(_up(2.1, const Offset(50, 20)));
      expect(clicks, hasLength(1));
      expect(taps, 1);
    });

    test('a relation takes the wheel when a part does', () {
      expect(PressInteraction().takesWheel, isFalse);
      expect(PressInteraction().simultaneously(_Wheel()).takesWheel, isTrue);
      expect(PressInteraction().exclusively(_Wheel()).takesWheel, isTrue);
      expect(_Wheel().sequenced(PressInteraction()).takesWheel, isTrue);
    });
  });

  group('HoverDwellInteraction', () {
    PointerHoverInput hover(double time, {bool inside = true}) =>
        PointerHoverInput(
          time: time,
          position: const Offset(10, 10),
          inside: inside,
        );

    test('fires once at its due time after the pointer enters, through a '
        'session between touches', () {
      final fired = <double>[];
      final dwell = HoverDwellInteraction(duration: 0.3, onDwell: fired.add);
      final session = InteractionSession([PressInteraction(), dwell]);
      session.handle(hover(1));
      session.handle(hover(1.1));
      expect(session.nextDue, 1.3);
      session.advance(1.2);
      expect(fired, isEmpty);
      session.advance(1.5);
      expect(fired, [1.3]);
      expect(session.nextDue, isNull);
      session.advance(2);
      expect(fired, [1.3]);
    });

    test('leaving before the due time cancels it; a leave stamped after it '
        'fires it first', () {
      final fired = <double>[];
      final dwell = HoverDwellInteraction(duration: 0.3, onDwell: fired.add);
      dwell.handle(hover(0));
      dwell.handle(hover(0.2, inside: false));
      expect(dwell.waiting, isFalse);
      dwell.advance(1);
      expect(fired, isEmpty);
      dwell.handle(hover(2));
      dwell.handle(hover(2.4, inside: false));
      expect(fired, [2.3]);
    });
  });

  group('PressInteraction', () {
    test('highlights inside the reach of its region and taps on a release '
        'inside', () {
      final highlights = <bool>[];
      var taps = 0;
      final press = PressInteraction(
        onHighlightChanged: (t, {required highlighted}) =>
            highlights.add(highlighted),
        onTap: (t) => taps++,
      );
      final session = InteractionSession([press]);
      const down = PointerDownInput(
        time: 0,
        pointer: 1,
        position: Offset(50, 20),
        regionSize: _size,
        reach: PressReach(slop: 20),
      );
      expect(session.handle(down).claim, isTrue);
      session.handle(_move(0.1, const Offset(110, 20)));
      session.handle(_move(0.2, const Offset(130, 20)));
      session.handle(_move(0.3, const Offset(90, 20)));
      final release = session.handle(_up(0.4, const Offset(90, 20)));
      expect(highlights, [true, false, true, false]);
      expect(taps, 1);
      expect(release.events.single, isA<ActivationEvent>());
    });

    test('the reach holds the box of the region as it is at each input', () {
      var taps = 0;
      final session = InteractionSession([
        PressInteraction(onTap: (t) => taps++),
      ]);
      PointerDownInput down() => const PointerDownInput(
        time: 0,
        pointer: 1,
        position: Offset(50, 20),
        regionSize: _size,
        reach: PressReach(minimumHit: Size(44, 44), slop: 10),
      );
      const shrunk = Rect.fromLTWH(30, 10, 40, 20);
      session.handle(down());
      session.handle(_up(0.1, const Offset(85, 20), box: shrunk));
      expect(taps, 0, reason: '15 past the shrunk box, within the old one');
      session.handle(down());
      session.handle(_up(0.2, const Offset(50, -1), box: shrunk));
      expect(taps, 1, reason: 'the 44 point minimum around the shrunk box');
      session.handle(down());
      session.handle(_up(0.3, const Offset(79, 20), box: shrunk));
      expect(taps, 2, reason: '9 past the shrunk box, within the slop');
    });

    test('a release outside does not tap', () {
      var taps = 0;
      final session = InteractionSession([
        PressInteraction(onTap: (t) => taps++),
      ]);
      session.handle(_down(0));
      final release = session.handle(_up(0.1, const Offset(200, 20)));
      expect(taps, 0);
      expect(release.events, isEmpty);
      expect(session.isActive, isFalse);
    });
  });

  group('InteractionSession', () {
    test('a long press that is recognized cancels the press', () {
      final heard = <String>[];
      final session = InteractionSession([
        LongPressInteraction(onStart: (t) => heard.add('long')),
        PressInteraction(onTap: (t) => heard.add('tap')),
      ]);
      session.handle(_down(0));
      session.advance(0.5);
      session.handle(_up(0.7, const Offset(50, 20)));
      expect(heard, ['long']);
    });

    test('the claims of content are ignored', () {
      final session = InteractionSession([
        DragInteraction(role: InteractionRole.content),
      ]);
      session.handle(_down(0));
      expect(session.handle(_move(0.05, const Offset(50, 60))).claim, isFalse);
    });

    test('a press and a drag together each keep their own timing', () {
      final heard = <String>[];
      final session = InteractionSession([
        PressInteraction(
          onHighlightChanged: (t, {required highlighted}) =>
              heard.add('press $highlighted'),
        ).simultaneously(
          DragInteraction(
            axis: Axis.horizontal,
            onStart: (_) => heard.add('drag'),
          ),
        ),
      ]);
      final down = session.handle(_down(0, scroll: {Axis.vertical}));
      expect(down.claim, isFalse);
      session.handle(_move(0.05, const Offset(80, 20)));
      expect(heard, ['drag']);
    });

    test('a second pointer during a touch is rejected', () {
      final session = InteractionSession([PressInteraction()]);
      session.handle(_down(0));
      final second = session.handle(
        const PointerDownInput(
          time: 0.1,
          pointer: 2,
          position: Offset(10, 10),
          regionSize: _size,
        ),
      );
      expect(second.reject, isTrue);
    });

    test('a control in a scroll view hears the touch 0.15 s after contact '
        'and claims then', () {
      final highlights = <bool>[];
      final session = InteractionSession([
        PressInteraction(
          onHighlightChanged: (t, {required highlighted}) =>
              highlights.add(highlighted),
        ),
      ]);
      final down = session.handle(_down(0, scroll: {Axis.vertical}));
      expect(down.claim, isFalse);
      expect(highlights, isEmpty);
      expect(session.nextDue, closeTo(0.15, 1e-12));
      expect(session.advance(0.1).claim, isFalse);
      expect(session.advance(0.15).claim, isTrue);
      expect(highlights, [true]);
    });

    test('a quick tap held back is delivered with its release', () {
      final heard = <String>[];
      final session = InteractionSession([
        PressInteraction(
          onHighlightChanged: (t, {required highlighted}) =>
              heard.add(highlighted ? 'on' : 'off'),
          onTap: (t) => heard.add('tap'),
        ),
      ]);
      session.handle(_down(0, scroll: {Axis.vertical}));
      session.handle(_up(0.08, const Offset(50, 20)));
      expect(heard, ['on', 'off', 'tap']);
      expect(session.isActive, isFalse);
    });

    test('a touch a scroll takes while held back never reaches content', () {
      final heard = <bool>[];
      final session = InteractionSession([
        PressInteraction(
          role: InteractionRole.content,
          onHighlightChanged: (t, {required highlighted}) =>
              heard.add(highlighted),
        ),
      ]);
      session.handle(_down(0, scroll: {Axis.vertical}));
      session.lost(1, 0.05);
      session.advance(0.3);
      expect(heard, isEmpty);
    });

    test('a region nothing accepts rejects the touch at once', () {
      final session = InteractionSession([PressInteraction()]);
      final output = session.handle(
        const PointerDownInput(
          time: 0,
          pointer: 1,
          position: Offset.zero,
          regionSize: _size,
          buttons: 2,
        ),
      );
      expect(output.reject, isTrue);
    });
  });

  group('LongPressInteraction', () {
    test('is recognized at its duration from contact, however late the '
        'frame that runs it, and claims', () {
      final heard = <(String, double)>[];
      final long = LongPressInteraction(
        onStart: (t) => heard.add(('start', t)),
        onCommit: (t) => heard.add(('commit', t)),
      );
      final session = InteractionSession([long]);
      session.handle(_down(0.01));
      expect(session.nextDue, 0.51);
      final due = session.advance(0.523);
      expect(due.claim, isTrue);
      expect((due.events.single as LongPressStartEvent).time, 0.51);
      session.handle(_up(0.7, const Offset(50, 20)));
      expect(heard, [('start', 0.51), ('commit', 0.7)]);
    });

    test('fails when the finger travels first', () {
      var started = false;
      final session = InteractionSession([
        LongPressInteraction(onStart: (t) => started = true),
      ]);
      session.handle(_down(0));
      final move = session.handle(_move(0.2, const Offset(80, 20)));
      session.advance(0.6);
      expect(started, isFalse);
      expect(move.reject, isTrue);
    });
  });

  group('DragInteraction', () {
    test('starts past its slop and counts travel from there', () {
      final updates = <DragInteractionDetails>[];
      DragInteractionDetails? end;
      final drag = DragInteraction(
        axis: Axis.horizontal,
        onStart: updates.add,
        onUpdate: updates.add,
        onEnd: (details) => end = details,
      );
      final session = InteractionSession([drag]);
      session.handle(_down(0));
      expect(session.handle(_move(0.01, const Offset(55, 20))).claim, isFalse);
      expect(session.handle(_move(0.02, const Offset(70, 30))).claim, isTrue);
      session.handle(_move(0.03, const Offset(90, 20)));
      session.handle(
        _up(0.04, const Offset(90, 20), velocity: const Offset(400, 50)),
      );
      expect(updates.map((d) => d.translation.dx), [10, 30]);
      expect(updates.first.translation.dy, 0);
      expect(end!.velocity, const Offset(400, 0));
      expect(end!.time, 0.04);
    });

    test('does not hold a touch a scroll view shares its axis with', () {
      final session = InteractionSession([
        DragInteraction(axis: Axis.vertical),
      ]);
      session.handle(_down(0, scroll: {Axis.vertical}));
      final move = session.handle(_move(0.02, const Offset(50, 60)));
      expect(move.claim, isFalse);
    });

    test('a touch from the leading edge starts past the edge slop, one '
        'elsewhere past the slop; mayBegin gives a touch up', () {
      final drag = DragInteraction(
        axis: Axis.horizontal,
        slop: 20,
        edgeZone: 0.1,
        edgeSlop: 5,
        mayBegin: (travel) => travel.dx > -8,
      );
      final session = InteractionSession([drag]);
      session.handle(_downAt(0, const Offset(4, 20)));
      expect(session.handle(_move(0.01, const Offset(10, 20))).claim, isTrue);
      session.handle(_up(0.02, const Offset(10, 20)));
      session.handle(_downAt(1, const Offset(50, 20)));
      expect(session.handle(_move(1.01, const Offset(60, 20))).claim, isFalse);
      expect(session.handle(_move(1.02, const Offset(71, 20))).claim, isTrue);
      session.handle(_up(1.03, const Offset(71, 20)));
      session.handle(_downAt(2, const Offset(50, 20)));
      expect(session.handle(_move(2.01, const Offset(41, 20))).reject, isTrue);
    });

    test('mirrored, the leading edge and the travel are on the right', () {
      final travel = <double>[];
      final drag = DragInteraction(
        axis: Axis.horizontal,
        edgeZone: 0.1,
        edgeSlop: 5,
        mirrored: true,
        onStart: (d) => travel.add(d.translation.dx),
        onUpdate: (d) => travel.add(d.translation.dx),
      );
      final session = InteractionSession([drag]);
      session.handle(_downAt(0, const Offset(96, 20)));
      session.handle(_move(0.01, const Offset(80, 20)));
      session.handle(_move(0.02, const Offset(70, 20)));
      expect(travel, [11, 21]);
    });
  });

  group('TapInteraction', () {
    test('a single tap waits for the double tap to time out', () {
      final heard = <String>[];
      final double = TapInteraction(count: 2, onTap: (t) => heard.add('two'));
      final single = TapInteraction(onTap: (t) => heard.add('one'));
      final session = InteractionSession([double.exclusively(single)]);
      session.handle(_down(0));
      session.handle(_up(0.05, const Offset(50, 20)));
      expect(heard, isEmpty);
      expect(session.nextDue, closeTo(0.35, 1e-12));
      session.advance(0.35);
      expect(heard, ['one']);
    });

    test('a double tap is preferred to a single one, which waits', () {
      final heard = <String>[];
      final double = TapInteraction(count: 2, onTap: (t) => heard.add('two'));
      final single = TapInteraction(onTap: (t) => heard.add('one'));
      final session = InteractionSession([double.exclusively(single)]);
      session.handle(_down(0));
      session.handle(_up(0.05, const Offset(50, 20)));
      expect(heard, isEmpty);
      session.handle(_down(0.15));
      session.handle(_up(0.2, const Offset(50, 20)));
      expect(heard, ['two']);
    });
  });

  group('relations', () {
    test('activates when a press or a tap is in it', () {
      expect(PressInteraction().activates, isTrue);
      expect(TapInteraction().activates, isTrue);
      expect(DragInteraction().activates, isFalse);
      expect(
        DragInteraction().simultaneously(PressInteraction()).activates,
        isTrue,
      );
      expect(
        LongPressInteraction().sequenced(PressInteraction()).activates,
        isFalse,
      );
    });

    test('sequenced hands the rest of the touch on from the moment the '
        'first recognizes, where the finger is then', () {
      final heard = <String>[];
      final rows = ScrubInteraction(
        hit: (p) => p.dy > 30 ? 'row' : null,
        onChanged: (selected, t) => heard.add('over $selected at $t'),
        onCommit: (selected, t) => heard.add('commit $selected at $t'),
      );
      final session = InteractionSession([
        LongPressInteraction(
          onStart: (t) => heard.add('hold at $t'),
        ).sequenced(rows),
      ]);
      session.handle(_down(0));
      session.handle(_move(0.3, const Offset(52, 22)));
      session.advance(0.55);
      session.handle(_move(0.6, const Offset(52, 35)));
      session.handle(_up(0.7, const Offset(52, 35)));
      expect(heard, [
        'hold at 0.5',
        'over row at 0.6',
        'commit row at 0.7',
      ]);
    });

    test('sequenced hears nothing on a touch the first gives up', () {
      var heard = 0;
      final session = InteractionSession([
        LongPressInteraction().sequenced(
          FollowInteraction(_Count(() => heard++)),
        ),
      ]);
      session.handle(_down(0));
      session.handle(_move(0.1, const Offset(90, 20)));
      session.handle(_up(0.2, const Offset(90, 20)));
      expect(heard, 0);
    });
  });

  group('FollowInteraction', () {
    test('feeds one pointer, mirrored when asked, and decides nothing', () {
      final follower = _Log();
      final follow = FollowInteraction(follower, mirrored: true);
      final session = InteractionSession([follow]);
      final down = session.handle(_down(0));
      session.handle(_move(0.1, const Offset(30, 20)));
      session.handle(
        _up(0.2, const Offset(30, 20), velocity: const Offset(100, 5)),
      );
      expect(down.claim, isFalse);
      expect(follower.log, [
        'down 50.0',
        'move 70.0',
        'up 70.0 -100.0',
      ]);
    });
  });
}

class _Log extends PointerFollower {
  final List<String> log = [];

  @override
  void down(PointerDownInput input) => log.add('down ${input.position.dx}');

  @override
  void move(PointerMoveInput input) => log.add('move ${input.position.dx}');

  @override
  void up(PointerUpInput input) =>
      log.add('up ${input.position.dx} ${input.velocity.dx}');

  @override
  void cancel(PointerCancelInput input) => log.add('cancel');
}

class _Count extends PointerFollower {
  _Count(this.heard);

  final VoidCallback heard;

  @override
  void down(PointerDownInput input) => heard();

  @override
  void move(PointerMoveInput input) => heard();

  @override
  void up(PointerUpInput input) => heard();

  @override
  void cancel(PointerCancelInput input) => heard();
}
