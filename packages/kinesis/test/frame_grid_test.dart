import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/src/motion/frame_grid.dart';

void main() {
  test('the frame grid snaps within its reach and restarts outside it', () {
    final grid = FrameGrid();
    var t = 1.0;
    for (var i = 0; i < 4; i++) {
      expect(grid.snap(t), t);
      t += 0.016;
    }
    expect(grid.period, moreOrLessEquals(0.016, epsilon: 1e-12));
    final anchor = t - 0.016;
    expect(
      grid.snap(t + 0.0004),
      moreOrLessEquals(anchor + 0.016, epsilon: 1e-12),
    );
    expect(
      grid.snap(t + 0.032 - 0.0003),
      moreOrLessEquals(anchor + 0.048, epsilon: 1e-12),
    );
    expect(grid.snap(t + 0.032 + 0.016 + 0.004), t + 0.052);
    expect(grid.snap(t + 0.5), t + 0.5);
    final period = grid.period!;
    expect(
      grid.snap(t + 0.5 + period + 0.0002),
      moreOrLessEquals(t + 0.5 + period, epsilon: 1e-12),
    );
  });
}
