import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/fake_glass.dart';
import 'package:liquid_glass_renderer/src/internal/fake_glass_shader_slots.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/rendering/consolidated_fake_glass_layer.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

// On the web (CanvasKit) every draw recorded with one FragmentShader reads
// the uniforms that shader holds at raster time, so draws must not share a
// shader whose uniforms another draw rewrites before the frame is shown.
void main() {
  test('each draw gets its own shader, kept while it is drawn', () {
    final program = MultiShaderBuilder.cachedProgram(
      ShaderKeys.fakeGlassSurface,
    )!;
    final base = program.fragmentShader();
    addTearDown(base.dispose);
    final slots = FakeGlassShaderSlots();
    addTearDown(slots.dispose);

    final a = slots.shaderFor('a', base);
    final b = slots.shaderFor('b', base);
    expect(a, isNot(same(base)));
    expect(b, isNot(same(a)));
    expect(slots.shaderFor('a', base), same(a));
    expect(slots.debugCount, 2);

    // a paint that only draws 'a' lets go of 'b'
    slots
      ..beginPaint()
      ..shaderFor('a', base)
      ..endPaint();
    expect(slots.debugCount, 1);
    expect(slots.shaderFor('a', base), same(a));

    slots.dispose();
    expect(slots.debugCount, 0);
  });

  testWidgets('a fake layer draws every shape and pass with its own shader', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LiquidGlassLayer(
          fake: true,
          settings: LiquidGlassSettings(highlight: 1),
          child: Row(
            children: [
              LiquidGlass(
                shape: LiquidRoundedSuperellipse(borderRadius: 31),
                child: SizedBox(width: 220, height: 62),
              ),
              LiquidGlass(
                shape: LiquidOval(),
                child: SizedBox(width: 62, height: 62),
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
    // two shapes, each with a surface and a glint pass
    expect(layer.debugShaderSlots.debugCount, 4);

    // one shape gone: its shaders are released on the next paint
    await tester.pumpWidget(
      const MaterialApp(
        home: LiquidGlassLayer(
          fake: true,
          settings: LiquidGlassSettings(highlight: 1),
          child: Row(
            children: [
              LiquidGlass(
                shape: LiquidOval(),
                child: SizedBox(width: 62, height: 62),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(layer.debugShaderSlots.debugCount, 2);
  });

  testWidgets('standalone FakeGlass draws surface and glint separately', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: FakeGlass(
            shape: LiquidOval(),
            settings: LiquidGlassSettings(highlight: 1),
            child: SizedBox(width: 62, height: 62),
          ),
        ),
      ),
    );
    await tester.pump();

    final fake = tester.renderObject<RenderFakeGlass>(
      find.byType(RawFakeGlass),
    );
    expect(fake.debugShaderSlots.debugCount, greaterThanOrEqualTo(2));
  });
}
