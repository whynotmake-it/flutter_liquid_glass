import 'package:apple_liquid_glass/src/motions/flex_integrator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlexIntegrator', () {
    test('filters the rate of change of speed with weight 0.3', () {
      final flex = FlexIntegrator();
      flex.reset(0);
      final af = flex.step(10, 0.5);
      expect(flex.pf, 3);
      expect(flex.vf, closeTo(1.8, 1e-12));
      expect(af, closeTo(1.08, 1e-12));
      expect(flex.af, af);
    });

    test('an unprimed filter starts at rest on the first position', () {
      final flex = FlexIntegrator();
      expect(flex.step(5, 1 / 60), 0);
      expect(flex.pf, 5);
      expect(flex.vf, 0);
    });
  });
}
