import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

void main() {
  test('lands the velocity times the rate ahead', () {
    const sheet = Spring.response(0.3441, projection: 0.143);
    expect(Projection.of(sheet).landing(100, 1000), 100 + 1000 * 0.143);
    expect(
      Projection.of(Spring.smooth).landing(0, -10),
      -10 * Spring.normalProjection,
    );
  });

  test('a projected travel shorter than minDistance is dropped', () {
    const p = Projection(rate: 0.1, minDistance: 10);
    expect(p.landing(5, 50), 5);
    expect(p.landing(5, 100), 15);
  });

  test('chooses the stop nearest the landing, the lower one on a tie', () {
    const p = Projection(rate: 0.1);
    final near = p.choose(0, 400, stops: [0, 30, 60]);
    expect(near, isA<ProjectionStop>());
    expect((near as ProjectionStop).index, 1);
    expect(near.value, 30);
    final tie = p.choose(0, 150, stops: [0, 30]) as ProjectionStop;
    expect(tie.index, 0);
  });

  test('an exit the landing passes, or a flick toward it, wins over the '
      'stops', () {
    const p = Projection(rate: 0.1);
    const dismiss = ProjectionExit(threshold: 200, flickVelocity: 1000);
    const back = ProjectionExit(threshold: -50, sign: -1);
    final stops = <double>[0, 100];
    expect(
      p.choose(150, 600, stops: stops, exits: [dismiss]),
      isA<ProjectionExited>(),
    );
    expect(
      (p.choose(
        10,
        1001,
        stops: stops,
        exits: [dismiss],
      ) as ProjectionExited).exit,
      dismiss,
    );
    expect(
      p.choose(10, 900, stops: stops, exits: [dismiss]),
      isA<ProjectionStop>(),
    );
    expect(
      (p.choose(
        0,
        -600,
        stops: stops,
        exits: [dismiss, back],
      ) as ProjectionExited).exit,
      back,
    );
  });
}
