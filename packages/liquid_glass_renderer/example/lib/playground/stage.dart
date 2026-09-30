import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/playground/playground_state.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/blend_scene.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/colors_scene.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/controls_scene.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/loupe_scene.dart';

/// All glass on the stage, rendered by a single [LiquidGlassLayer].
///
/// Material changes rebuild only the layer: the scene subtree is passed
/// through as a prebuilt child, so dragging a slider never rebuilds or
/// re-lays out the shapes themselves. Loupes bring their own glass, so the
/// loupe scene replaces the layer. Empty parts of the stage let pointers
/// through to the scrolling backdrop.
class Stage extends StatelessWidget {
  const Stage({required this.state, super.key});

  final PlaygroundState state;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: state.scene,
      builder: (context, scene, layer) => scene == StageScene.loupe
          ? LoupeScene(
              link: state.loupeLink,
              loupes: state.loupes,
              material: state.material,
              magnification: state.loupeScale,
            )
          : layer!,
      child: ListenableBuilder(
        listenable: Listenable.merge([state.material, state.fake]),
        builder: (context, scenes) {
          final material = state.material.value;
          return LiquidGlassLayer(
            settings: material.settings,
            defaultAppearance: material.appearance,
            fake: state.fake.value,
            child: scenes!,
          );
        },
        child: ValueListenableBuilder(
          valueListenable: state.scene,
          builder: (context, scene, _) => KeyedSubtree(
            key: ValueKey(scene),
            child: switch (scene) {
              StageScene.controls => ControlsScene(
                adaptive: state.adaptive,
                style: state.style,
                source: state.brightnessSource,
                fake: state.fake,
              ),
              StageScene.blend => BlendScene(blend: state.blend),
              StageScene.colors => ColorsScene(blend: state.blend),
              StageScene.loupe => const SizedBox(),
            },
          ),
        ),
      ),
    );
  }
}
