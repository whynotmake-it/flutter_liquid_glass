import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/consolidated_fake_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

Widget _glass() => const Directionality(
  textDirection: TextDirection.ltr,
  child: LiquidGlassLayer(
    child: Center(
      child: LiquidGlass(
        shape: LiquidRoundedSuperellipse(radius: 20),
        child: SizedBox.square(dimension: 100),
      ),
    ),
  ),
);

bool _drawsReal(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().isNotEmpty;

bool _drawsFake(WidgetTester tester) => tester.allRenderObjects
    .whereType<RenderConsolidatedFakeGlassLayer>()
    .isNotEmpty;

void main() {
  tearDown(() => debugOverrideLiquidGlassSupport(null));

  testWidgets('precache says full glass draws, and on what GPU', (
    tester,
  ) async {
    final support = (await tester.runAsync(precacheLiquidGlass))!;
    expect(support, isA<LiquidGlassAvailableSupport>());
    expect(await tester.runAsync(precacheLiquidGlass), support);
    expect(liquidGlassSupport.value, support);
  }, skip: skipProperGlassTests);

  test('a support equals one of its state with its values', () {
    LiquidGlassSupport available(LiquidGlassDeviceClass deviceClass) =>
        LiquidGlassSupport.available(deviceClass: deviceClass);
    final supports = [
      () => const LiquidGlassSupport.pending(),
      () => available(LiquidGlassDeviceClass.capable),
      () => available(LiquidGlassDeviceClass.gles),
      () => LiquidGlassSupport.unavailable(['No shader filters.'].single),
      () => LiquidGlassSupport.unavailable(['For the test.'].single),
    ];
    for (final (i, a) in supports.indexed) {
      for (final (j, b) in supports.indexed) {
        expect(a() == b(), i == j, reason: '${a()} and ${b()}');
        if (i == j) expect(a().hashCode, b().hashCode);
      }
    }
    expect('${supports[0]()}', 'LiquidGlassSupport.pending()');
    expect(
      '${supports[1]()}',
      'LiquidGlassSupport.available(deviceClass: capable)',
    );
    expect(
      '${supports[4]()}',
      'LiquidGlassSupport.unavailable(For the test.)',
    );
  });

  test('only a load makes full glass ready', () {
    final before = liquidGlassSupport.value;
    expect(
      () => debugOverrideLiquidGlassSupport(
        const LiquidGlassSupport.available(
          deviceClass: LiquidGlassDeviceClass.capable,
        ),
      ),
      throwsArgumentError,
    );
    expect(liquidGlassSupport.value, before);
  });

  test('a load under way when the support is overridden leaves the '
      'override, and what it found comes back after it', () async {
    debugOverrideLiquidGlassSupport(const LiquidGlassSupport.pending());
    final loading = precacheLiquidGlass();
    const unavailable = LiquidGlassSupport.unavailable('For the test.');
    debugOverrideLiquidGlassSupport(unavailable);
    final found = await loading;
    expect(found, isA<LiquidGlassAvailableSupport>());
    expect(liquidGlassSupport.value, unavailable);
    debugOverrideLiquidGlassSupport(null);
    expect(liquidGlassSupport.value, found);
  }, skip: skipProperGlassTests);

  testWidgets('a layer draws fake glass while full glass loads and real '
      'glass once it has, never a frame without glass', (tester) async {
    debugOverrideLiquidGlassSupport(const LiquidGlassSupport.pending());
    final supports = <LiquidGlassSupport>[];
    void listen() => supports.add(liquidGlassSupport.value);
    liquidGlassSupport.addListener(listen);
    addTearDown(() => liquidGlassSupport.removeListener(listen));

    await tester.pumpWidget(_glass());
    expect(_drawsFake(tester), isTrue);
    expect(_drawsReal(tester), isFalse);
    for (var frame = 0; frame < 4 && !_drawsReal(tester); frame++) {
      await tester.pump();
      expect(
        _drawsFake(tester) || _drawsReal(tester),
        isTrue,
        reason: 'frame $frame draws no glass',
      );
    }
    expect(_drawsReal(tester), isTrue);
    expect(_drawsFake(tester), isFalse);
    expect(supports, [isA<LiquidGlassAvailableSupport>()]);
  }, skip: skipProperGlassTests);

  testWidgets('a layer draws fake glass where full glass is unavailable, '
      'and real glass from the frame it is', (tester) async {
    debugOverrideLiquidGlassSupport(
      const LiquidGlassSupport.unavailable('For the test.'),
    );
    await tester.pumpWidget(_glass());
    await tester.pump();
    expect(_drawsFake(tester), isTrue);
    expect(_drawsReal(tester), isFalse);

    debugOverrideLiquidGlassSupport(null);
    await tester.pump();
    expect(_drawsReal(tester), isTrue);
    expect(_drawsFake(tester), isFalse);
  }, skip: skipProperGlassTests);
}
