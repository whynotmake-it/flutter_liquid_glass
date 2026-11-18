import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/src/motion/timeline.dart';

void main() {
  group('MotionTimeline', () {
    test('runs due actions in time order, each at its own time', () {
      final timeline = MotionTimeline();
      final log = <String>[];
      timeline.insert(0.3, (t) => log.add('c@$t'));
      timeline.insert(0.1, (t) => log.add('a@$t'));
      timeline.insert(0.2, (t) => log.add('b@$t'));
      expect(timeline.nextDue, 0.1);
      timeline.runDue(0.25);
      expect(log, ['a@0.1', 'b@0.2']);
      timeline.runDue(1);
      expect(log, ['a@0.1', 'b@0.2', 'c@0.3']);
      expect(timeline.isEmpty, isTrue);
    });

    test('keeps insertion order for equal times', () {
      final timeline = MotionTimeline();
      final log = <int>[];
      for (var i = 0; i < 5; i++) {
        timeline.insert(0.5, (t) => log.add(i));
      }
      timeline.insert(0.4, (t) => log.add(-1));
      timeline.runDue(0.5);
      expect(log, [-1, 0, 1, 2, 3, 4]);
    });

    test('an action that schedules a due one runs it in the same call', () {
      final timeline = MotionTimeline();
      final log = <double>[];
      timeline.insert(0.1, (t) {
        log.add(t);
        timeline.insert(t + 0.05, log.add);
      });
      timeline.runDue(0.2);
      expect(log, [0.1, closeTo(0.15, 1e-12)]);
    });

    test('remove drops every pending run of an action', () {
      final timeline = MotionTimeline();
      final log = <double>[];
      final action = log.add;
      timeline.insert(1, action);
      timeline.insert(2, action);
      timeline.remove(action);
      timeline.runDue(10);
      expect(log, isEmpty);
    });
  });
}
