import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/fake_glass.dart';
import 'package:liquid_glass_renderer/src/internal/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/rendering/consolidated_fake_glass_layer.dart';

void main() {
  const settings = LiquidGlassSettings(
    frost: 4,
    saturation: 1.1,
  );

  testWidgets('fake shapes share one parent backdrop filter', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LiquidGlassLayer(
          fake: true,
          settings: settings,
          child: Row(
            children: [
              LiquidGlass(
                shape: LiquidOval(),
                child: SizedBox(width: 80, height: 60),
              ),
              LiquidGlass(
                shape: LiquidRoundedRectangle(borderRadius: 16),
                child: SizedBox(width: 100, height: 60),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final layer = tester.renderObject<RenderConsolidatedFakeGlassLayer>(
      find.byType(ConsolidatedFakeGlassLayer).last,
    );
    expect(layer.debugBackdropFilterLayer, isNotNull);
    expect(find.byType(FakeGlass), findsNWidgets(2));
    expect(
      find.byType(RawFakeGlass),
      findsNWidgets(2),
      reason: 'Shape-local lighting remains retained while backdrop is shared.',
    );
  });

  testWidgets('shared fake composition preserves material paint order', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LiquidGlassLayer(
          fake: true,
          settings: settings,
          child: LiquidGlass(
            shape: LiquidRoundedRectangle(borderRadius: 16),
            shadows: [
              BoxShadow(offset: Offset(0, 8), blurRadius: 12),
            ],
            child: SizedBox(width: 100, height: 60),
          ),
        ),
      ),
    );
    await tester.pump();

    final layer = tester.renderObject<RenderConsolidatedFakeGlassLayer>(
      find.byType(ConsolidatedFakeGlassLayer).last,
    );
    expect(
      layer.debugLastPaintStages,
      const [
        'shadows',
        'backdrop',
        'surfaces',
        'contents',
      ],
    );
    final raw = tester.renderObject<RenderFakeGlass>(find.byType(RawFakeGlass));
    expect(raw.paintSurface, isFalse);
  });

  testWidgets('contained fake content remains below the analytic surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LiquidGlassLayer(
          fake: true,
          settings: settings,
          child: LiquidGlass(
            glassContainsChild: true,
            shape: LiquidRoundedSuperellipse(borderRadius: 24),
            child: ColoredBox(
              color: Colors.red,
              child: SizedBox(width: 120, height: 70),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final layer = tester.renderObject<RenderConsolidatedFakeGlassLayer>(
      find.byType(ConsolidatedFakeGlassLayer).last,
    );
    expect(
      layer.debugLastPaintStages,
      const [
        'shadows',
        'backdrop',
        'insideContents',
        'surfaces',
        'contents',
      ],
    );
  });

  testWidgets('nested fake own layer remains above its parent surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LiquidGlassLayer(
          fake: true,
          settings: settings,
          child: LiquidGlass(
            shape: LiquidRoundedRectangle(borderRadius: 24),
            child: SizedBox(
              width: 180,
              height: 80,
              child: Center(
                child: LiquidGlass.withOwnLayer(
                  fake: true,
                  settings: LiquidGlassSettings(frost: 0),
                  shape: LiquidOval(),
                  child: SizedBox.square(dimension: 48),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final layers = tester
        .renderObjectList<RenderConsolidatedFakeGlassLayer>(
          find.byType(ConsolidatedFakeGlassLayer),
        )
        .toList();
    expect(layers, hasLength(1));
    expect(
      layers.single.debugLastPaintStages.indexOf('surfaces') <
          layers.single.debugLastPaintStages.indexOf('contents'),
      isTrue,
    );
    final ownSurface = tester.allRenderObjects
        .whereType<RenderFakeGlass>()
        .where((surface) => surface.paintSurface)
        .toSet();
    expect(ownSurface, hasLength(1));
    expect(ownSurface.single.surfaceShader, isNotNull);
    expect(ownSurface.single.debugPaintCount, greaterThan(0));
  });

  testWidgets('fake backdrop transfer leaves tint in the surface pass', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LiquidGlassLayer(
          fake: true,
          settings: LiquidGlassSettings(
            frost: 4,
            saturation: 0.8,
            tint: Color.fromARGB(96, 220, 240, 255),
          ),
          child: LiquidGlass(
            shape: LiquidOval(),
            child: SizedBox(width: 80, height: 60),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RawFakeGlass), findsOneWidget);
  });

  testWidgets('tint alone never adds a backdrop sample', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LiquidGlassLayer(
          fake: true,
          settings: LiquidGlassSettings(
            frost: 0,
            saturation: 1,
            tint: Color.fromARGB(96, 220, 240, 255),
          ),
          child: LiquidGlass(
            shape: LiquidOval(),
            child: SizedBox(width: 80, height: 60),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final layer = tester.renderObject<RenderConsolidatedFakeGlassLayer>(
      find.byType(ConsolidatedFakeGlassLayer).last,
    );
    expect(layer.debugBackdropFilterLayer, isNull);
  });

  testWidgets('fake parent updates and releases its backdrop filter', (
    tester,
  ) async {
    final value = ValueNotifier(settings);
    addTearDown(value.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<LiquidGlassSettings>(
          valueListenable: value,
          builder: (_, settings, __) => LiquidGlassLayer(
            fake: true,
            settings: settings,
            child: const LiquidGlass(
              shape: LiquidOval(),
              child: SizedBox(width: 80, height: 60),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final layer = tester.renderObject<RenderConsolidatedFakeGlassLayer>(
      find.byType(ConsolidatedFakeGlassLayer).last,
    );
    final initialFilterLayer = layer.debugBackdropFilterLayer;
    final initialClipPath = layer.debugClipPath;
    expect(initialFilterLayer, isNotNull);
    expect(initialClipPath, isNotNull);

    value.value = settings.copyWith(frost: 8);
    await tester.pump();
    expect(layer.debugBackdropFilterLayer, same(initialFilterLayer));
    expect(
      layer.debugClipPath,
      same(initialClipPath),
      reason: 'Material-only changes must reuse transformed shape geometry.',
    );

    value.value = settings.copyWith(frost: 0, saturation: 1);
    await tester.pump();
    expect(layer.debugBackdropFilterLayer, isNull);
  });

  testWidgets('resizing a fake layer reuses its coordinate-free filter', (
    tester,
  ) async {
    final size = ValueNotifier(const Size(180, 120));
    addTearDown(size.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ValueListenableBuilder<Size>(
            valueListenable: size,
            builder: (_, value, __) => SizedBox.fromSize(
              size: value,
              child: const LiquidGlassLayer(
                fake: true,
                settings: settings,
                child: Center(
                  child: LiquidGlass(
                    shape: LiquidOval(),
                    child: SizedBox(width: 80, height: 60),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final layer = tester.renderObject<RenderConsolidatedFakeGlassLayer>(
      find.byType(ConsolidatedFakeGlassLayer).last,
    );
    final initialFilter = layer.debugBackdropFilterLayer!.filter;

    size.value = const Size(260, 180);
    await tester.pump();

    expect(layer.debugBackdropFilterLayer!.filter, same(initialFilter));
  });

  test('native color matrix matches tint-then-saturation algebra', () {
    const tint = Color.fromARGB(104, 220, 240, 255);
    const saturation = 0.8;
    final matrix = fakeGlassColorMatrix(
      saturation: saturation,
      tint: tint,
    );
    const background = (0.17, 0.53, 0.91);

    double channel(int row) =>
        matrix[row * 5] * background.$1 +
        matrix[row * 5 + 1] * background.$2 +
        matrix[row * 5 + 2] * background.$3 +
        matrix[row * 5 + 4] / 255;

    final mixed = (
      background.$1 * (1 - tint.a) + tint.r * tint.a,
      background.$2 * (1 - tint.a) + tint.g * tint.a,
      background.$3 * (1 - tint.a) + tint.b * tint.a,
    );
    final luminance = mixed.$1 * 0.299 + mixed.$2 * 0.587 + mixed.$3 * 0.114;
    final expected = (
      luminance + (mixed.$1 - luminance) * saturation,
      luminance + (mixed.$2 - luminance) * saturation,
      luminance + (mixed.$3 - luminance) * saturation,
    );
    expect(channel(0), closeTo(expected.$1, 1e-12));
    expect(channel(1), closeTo(expected.$2, 1e-12));
    expect(channel(2), closeTo(expected.$3, 1e-12));
  });

  test('native color matrix approximates transmission gamma at midtones', () {
    final matrix = fakeGlassColorMatrix(
      saturation: 1,
      tint: const Color(0x00000000),
      transmissionGamma: 0.9,
    );

    double channel(double input) => matrix[0] * input + matrix[4] / 255;

    expect(channel(0.25), closeTo(math.pow(0.25, 0.9), 1e-12));
    expect(channel(0.75), closeTo(math.pow(0.75, 0.9), 1e-12));
    expect(channel(0.5), greaterThan(0.5));
  });

  testWidgets('shape movement reuses its analytic fake shader', (
    tester,
  ) async {
    final offset = ValueNotifier(Offset.zero);
    final settings = ValueNotifier(
      const LiquidGlassSettings(frost: 0, saturation: 1),
    );
    addTearDown(offset.dispose);
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<LiquidGlassSettings>(
          valueListenable: settings,
          builder: (_, value, __) => LiquidGlassLayer(
            fake: true,
            settings: value,
            child: ValueListenableBuilder<Offset>(
              valueListenable: offset,
              builder: (_, value, __) => Transform.translate(
                offset: value,
                child: const LiquidGlass(
                  shape: LiquidOval(),
                  child: SizedBox(width: 80, height: 60),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surface = tester.allRenderObjects.whereType<RenderFakeGlass>().last;
    final layer = tester.renderObject<RenderConsolidatedFakeGlassLayer>(
      find.byType(ConsolidatedFakeGlassLayer).last,
    );
    final initialShader = layer.debugSurfaceShader;
    expect(initialShader, isNotNull);
    expect(surface.surfaceShader, isNull);

    offset.value = const Offset(32, 18);
    await tester.pump();
    expect(layer.debugSurfaceShader, same(initialShader));

    settings.value = settings.value.copyWith(highlight: 0.75);
    await tester.pump();
    expect(layer.debugSurfaceShader, same(initialShader));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('fake parent clip follows a shape moving inside the layer', (
    tester,
  ) async {
    final offset = ValueNotifier(Offset.zero);
    addTearDown(offset.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: LiquidGlassLayer(
          fake: true,
          settings: settings,
          child: ValueListenableBuilder<Offset>(
            valueListenable: offset,
            builder: (_, value, __) => Align(
              alignment: Alignment.topLeft,
              child: Transform.translate(
                offset: value,
                child: const LiquidGlass(
                  shape: LiquidOval(),
                  child: SizedBox(width: 80, height: 60),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final layer = tester.renderObject<RenderConsolidatedFakeGlassLayer>(
      find.byType(ConsolidatedFakeGlassLayer).last,
    );
    final initialBounds = layer.debugClipBounds!;
    final initialClipPath = layer.debugClipPath;

    offset.value = const Offset(48, 27);
    await tester.pump();
    await tester.pump();

    expect(
      layer.debugClipBounds!.topLeft - initialBounds.topLeft,
      const Offset(48, 27),
    );
    expect(layer.debugClipBounds!.size, initialBounds.size);
    expect(
      layer.debugClipPath,
      isNot(same(initialClipPath)),
      reason: 'A shape-local transform must rebuild the union clip.',
    );
  });

  testWidgets('moving the complete fake layer preserves its local clip', (
    tester,
  ) async {
    final offset = ValueNotifier(Offset.zero);
    addTearDown(offset.dispose);

    Widget build(Offset value) => MaterialApp(
      home: Transform.translate(
        offset: value,
        child: const LiquidGlassLayer(
          fake: true,
          settings: settings,
          child: Align(
            alignment: Alignment.topLeft,
            child: LiquidGlass(
              shape: LiquidOval(),
              child: SizedBox(width: 80, height: 60),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(build(offset.value));
    await tester.pump();
    final layer = tester.renderObject<RenderConsolidatedFakeGlassLayer>(
      find.byType(ConsolidatedFakeGlassLayer).last,
    );
    final initialLocalBounds = layer.debugClipBounds!;
    final initialWorldBounds = MatrixUtils.transformRect(
      layer.getTransformTo(null),
      initialLocalBounds,
    );

    offset.value = const Offset(35, 21);
    await tester.pumpWidget(build(offset.value));
    await tester.pump();

    expect(layer.debugClipBounds, initialLocalBounds);
    final movedWorldBounds = MatrixUtils.transformRect(
      layer.getTransformTo(null),
      layer.debugClipBounds!,
    );
    expect(
      movedWorldBounds.topLeft - initialWorldBounds.topLeft,
      const Offset(35, 21),
    );
  });
}
