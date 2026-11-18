import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

class _Toggle extends StatefulWidget {
  const _Toggle({super.key});

  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  bool shown = false;

  void toggle() => setState(() => shown = !shown);

  @override
  Widget build(BuildContext context) => shown
      ? const LiquidGlass(
          shape: LiquidRoundedSuperellipse(radius: 20),
          child: SizedBox(width: 80, height: 40),
        )
      : const SizedBox(width: 80, height: 40);
}

int _shapes(RenderLiquidGlassLayer layer) =>
    layer.frameShapes.geometries.fold(0, (n, e) => n + e.cache.shapes.length);

void main() {
  testWidgets('a shape that joins or leaves under a repaint boundary of its '
      'own is drawn in that frame', (tester) async {
    final toggle = GlobalKey<_ToggleState>();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: LiquidGlassLayer(
          settings: const LiquidGlassSettings.ios27Regular(
            brightness: Brightness.light,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LiquidGlass(
                shape: LiquidRoundedSuperellipse(radius: 20),
                child: SizedBox(width: 80, height: 40),
              ),
              // Tight constraints stop the toggle's relayout at the boundary,
              // so neither layout nor paint reaches the layer on its own.
              SizedBox(
                width: 80,
                height: 40,
                child: RepaintBoundary(child: _Toggle(key: toggle)),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final layer = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .single;
    // ignore: invalid_use_of_protected_member
    expect(layer.frameShapes.geometries, hasLength(1));

    toggle.currentState!.toggle();
    await tester.pump();
    // ignore: invalid_use_of_protected_member
    expect(layer.frameShapes.geometries, hasLength(2));

    toggle.currentState!.toggle();
    await tester.pump();
    // ignore: invalid_use_of_protected_member
    expect(layer.frameShapes.geometries, hasLength(1));
  }, skip: skipProperGlassTests);

  testWidgets('a grouped shape that joins or leaves its blend group under a '
      'repaint boundary of its own is drawn in that frame', (tester) async {
    final toggle = GlobalKey<_ToggleState>();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: LiquidGlassLayer(
          settings: const LiquidGlassSettings.ios27Regular(
            brightness: Brightness.light,
          ),
          // The group sits under a repaint boundary of its own too, so its
          // repaint does not reach the layer either.
          child: SizedBox(
            width: 80,
            height: 80,
            child: RepaintBoundary(
              child: LiquidGlassBlendGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const LiquidGlass(
                      shape: LiquidRoundedSuperellipse(radius: 20),
                      child: SizedBox(width: 80, height: 40),
                    ),
                    SizedBox(
                      width: 80,
                      height: 40,
                      child: RepaintBoundary(
                        child: _Toggle(key: toggle),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final layer = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .single;
    expect(_shapes(layer), 1);

    toggle.currentState!.toggle();
    await tester.pump();
    expect(_shapes(layer), 2);

    toggle.currentState!.toggle();
    await tester.pump();
    expect(_shapes(layer), 1);
  }, skip: skipProperGlassTests);
}
