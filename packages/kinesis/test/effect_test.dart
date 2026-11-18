import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

void main() {
  test('runs linearly with one progress', () {
    const effect = MotionEffect(
      opacity: (0, 1),
      scale: (0.8, 1),
      blur: (6, 0),
      offset: Offset(0, 40),
    );
    expect(effect.opacityAt(0.5), 0.5);
    expect(effect.scaleAt(0.5), closeTo(0.9, 1e-12));
    expect(effect.blurAt(0.25), 4.5);
    expect(effect.offsetAt(0.75), const Offset(0, 10));
    expect(effect.offsetAt(1), Offset.zero);
  });

  test('leaves what it does not name at rest', () {
    expect(MotionEffect.identity.opacityAt(0), 1);
    expect(MotionEffect.identity.scaleAt(0), 1);
    expect(MotionEffect.identity.blurAt(0), 0);
    expect(MotionEffect.fade.opacityAt(0), 0);
  });

  test('reduces to its opacity under Reduce Motion unless told', () {
    const effect = MotionEffect(opacity: (0, 1), scale: (0.5, 1));
    expect(effect.reduced, MotionEffect.fade);
    const custom = MotionEffect(scale: (0.5, 1), reduced: MotionEffect.fade);
    expect(custom.reduced, MotionEffect.fade);
  });
}
