import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis/src/presentation/session.dart';

final class _Panel extends Motion with Presented {
  final List<double> opened = [];
  final List<DismissTrigger> left = [];

  @override
  PresenceStatus get presence => PresenceStatus.shown;

  @override
  void open(double t) => opened.add(t);

  @override
  bool leave(double t, DismissTrigger trigger) {
    left.add(trigger);
    return true;
  }
}

final class _Log {
  final List<_Panel> motions = [];
  final List<DismissTrigger> vetoes = [];
  final List<Object?> dismissed = [];
}

PresentationSession _session(_Log log, {MotionSource? source}) {
  final presentation = Presentation<String, _Panel>(
    motion: (_) {
      final motion = _Panel();
      log.motions.add(motion);
      return motion;
    },
    builder: (context, _) => const SizedBox(),
    source: source,
    dismiss: DismissPolicy.modal,
    modal: (_) => false,
    result: (result) => result ?? 'cancel',
    onVeto: log.vetoes.add,
    onDismissed: log.dismissed.add,
  );
  return PresentationSession(
    presentation: () => presentation,
    scopeClock: () => MotionClock.instance,
  );
}

PresentationEnvironment _environment(double time) => PresentationEnvironment(
  clock: MotionClock.instance,
  time: time,
  bounds: Size.zero,
  padding: EdgeInsets.zero,
  traits: const MotionTraits(),
);

void main() {
  setUp(MotionClock.debugReset);

  test('the commit makes and opens the motion, leases the source and reads '
      'the modality', () {
    final log = _Log();
    final source = MotionSource();
    final session = _session(log, source: source);
    expect(session.motion, isNull);
    expect(session.modal.value, isTrue);
    session.commit(_environment(3));
    expect(session.motion, same(log.motions.single));
    expect(log.motions.single.opened, [3]);
    expect(source.isHidden, isTrue);
    expect(session.modal.value, isFalse);
    expect(session.isLeaving, isFalse);
    session.dispose();
  });

  test('a refused trigger calls onVeto; an allowed one does not', () {
    final log = _Log();
    final session = _session(log);
    session.commit(_environment(0));
    expect(session.admits(DismissTrigger.outsideTap), isFalse);
    expect(session.admits(DismissTrigger.escape), isTrue);
    expect(log.vetoes, [DismissTrigger.outsideTap]);
    session.dispose();
  });

  test("a leave keeps the presentation's mapped result and starts the "
      "motion's leave", () {
    final log = _Log();
    final session = _session(log);
    session.commit(_environment(0));
    expect(session.resultOf('ok'), 'ok');
    expect(
      session.leave(DismissTrigger.escape, session.resultOf(null)),
      isTrue,
    );
    expect(session.isLeaving, isTrue);
    expect(session.inert.value, isTrue);
    expect(session.result, 'cancel');
    expect(log.motions.single.left, [DismissTrigger.escape]);
    session.dispose();
  });

  test('the end runs once: the source is released and the presentation '
      'hears its result', () {
    final log = _Log();
    final source = MotionSource();
    final session = _session(log, source: source);
    session.commit(_environment(0));
    session.leave(DismissTrigger.programmatic, 'done');
    session.end();
    session.end();
    expect(source.isHidden, isFalse);
    expect(session.motion, isNull);
    expect(session.ended, isTrue);
    expect(log.dismissed, ['done']);
    session.dispose();
  });

  test('a reopen brings a leaving presentation back without its result', () {
    final log = _Log();
    final session = _session(log);
    session.commit(_environment(0));
    session.leave(DismissTrigger.escape, 'gone');
    session.reopen();
    expect(session.isLeaving, isFalse);
    expect(session.inert.value, isFalse);
    expect(session.result, isNull);
    expect(log.motions.single.opened, hasLength(2));
    session.dispose();
  });

  testWidgets('a leave while the frame builds is read at once and made '
      'inert in the next publish phase', (tester) async {
    final log = _Log();
    final session = _session(log);
    session.commit(_environment(0));
    bool? leavingInBuild;
    bool? inertInBuild;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          session.leave(DismissTrigger.interaction, null);
          leavingInBuild = session.isLeaving;
          inertInBuild = session.inert.value;
          return const SizedBox();
        },
      ),
    );
    expect(leavingInBuild, isTrue);
    expect(inertInBuild, isFalse);
    await tester.pump();
    expect(session.inert.value, isTrue);
    session.dispose();
  });
}
