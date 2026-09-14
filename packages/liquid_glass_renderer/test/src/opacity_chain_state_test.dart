import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/retained_glass_opacity_probe.dart';

void main() {
  test(
    'Exact presentation endpoint does not round a near-one fade to opaque',
    () {
      final scope = RenderOpacity(opacity: .99931);
      addTearDown(scope.dispose);
      expect(Color.getAlphaFromOpacity(scope.opacity), 255);
      expect(glassOpacityChainState([scope]), 255);
      expect(glassOpacityChainState([scope], exactOpaque: true), 128);
      expect(areGlassOpacityScopesOpaque([scope], exactOpaque: true), isFalse);
      scope.opacity = 1;
      expect(glassOpacityChainState([scope], exactOpaque: true), 255);
      expect(areGlassOpacityScopesOpaque([scope], exactOpaque: true), isTrue);
      scope.opacity = .001;
      expect(glassOpacityChainState([scope], exactOpaque: true), 0);
    },
  );
  test('Visible nested scopes are not culled by rounded product alpha', () {
    final outer = RenderOpacity(opacity: .01);
    final inner = RenderOpacity(opacity: .01);
    addTearDown(outer.dispose);
    addTearDown(inner.dispose);

    expect(Color.getAlphaFromOpacity(.01 * .01), 0);
    expect(glassOpacityChainState([outer, inner]), 128);
    inner.opacity = .001;
    expect(glassOpacityChainState([outer, inner]), 0);
    inner.opacity = 1;
    expect(glassOpacityChainState([outer, inner]), 128);
    outer.opacity = 1;
    expect(glassOpacityChainState([outer, inner]), 255);
  });

  test('Common ancestry is excluded from original-branch local scopes', () {
    final outer = RenderOpacity(opacity: .5);
    final left = RenderOpacity();
    final right = RenderOpacity();
    for (final scope in [outer, left, right]) {
      addTearDown(scope.dispose);
    }
    final local = independentGlassOpacityScopes([
      [left, outer],
      [right, outer],
    ]);
    expect(local, [left, right]);
    expect(areGlassOpacityScopesOpaque(local), isTrue);
    left.opacity = .5;
    expect(areGlassOpacityScopesOpaque(local), isFalse);
  });
}
