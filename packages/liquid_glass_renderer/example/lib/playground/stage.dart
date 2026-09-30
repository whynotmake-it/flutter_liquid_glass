import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/playground/playground_state.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/adaptive_controls.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/blend_scene.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/colors_scene.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/controls_scene.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/loupe_scene.dart';
import 'package:liquid_glass_renderer_example/playground/sheet_avoidance.dart';

/// All glass on the stage, rendered by a single [LiquidGlassLayer], with the
/// settings button in its top trailing corner.
///
/// Material changes rebuild only the layer: the scene subtree is passed
/// through as a prebuilt child, so dragging a slider never rebuilds or
/// re-lays out the shapes themselves. Loupes bring their own glass, so the
/// loupe scene sits beneath the layer, which then only holds the settings
/// button. Empty parts of the stage let pointers through to the scrolling
/// backdrop.
///
/// While the settings sheet is open, the scenes move into the part of the
/// stage it leaves free (see [AvoidSheet]); the top controls stay put.
class Stage extends StatelessWidget {
  const Stage({required this.state, required this.onSettings, super.key});

  final PlaygroundState state;
  final VoidCallback onSettings;

  /// Height of the row of glass buttons along the top of the stage,
  /// including its padding.
  static const topControlsExtent = topControlsTop * 2 + topControlSize;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ValueListenableBuilder(
          valueListenable: state.scene,
          builder: (context, scene, _) => scene == StageScene.loupe
              ? AvoidSheet(
                  retainChild: false,
                  child: LoupeScene(
                    link: state.loupeLink,
                    loupes: state.loupes,
                    material: state.material,
                    magnification: state.loupeScale,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        ListenableBuilder(
          listenable: Listenable.merge([state.material, state.fake]),
          builder: (context, content) {
            final material = state.material.value;
            return LiquidGlassLayer(
              settings: material.settings,
              defaultAppearance: material.appearance,
              fake: state.fake.value,
              child: content!,
            );
          },
          child: Stack(
            children: [
              Positioned.fill(
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
                      StageScene.blend => AvoidSheet(
                        child: BlendScene(blend: state.blend),
                      ),
                      StageScene.colors => AvoidSheet(
                        child: ColorsScene(blend: state.blend),
                      ),
                      StageScene.loupe => const SizedBox.shrink(),
                    },
                  ),
                ),
              ),
              Positioned(
                top: topControlsTop,
                right: topControlsSide,
                child: _SettingsButton(state: state, onPressed: onSettings),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Opens the settings sheet. In Auto it adapts to the backdrop like the
/// other top controls.
class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.state, required this.onPressed});

  final PlaygroundState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([state.adaptive, state.style]),
      builder: (context, button) => AdaptiveScope(
        source: state.adaptive.value ? state.brightnessSource : null,
        style: state.style.value,
        child: button!,
      ),
      child: AdaptiveGroup(
        child: CircleButton(
          icon: CupertinoIcons.slider_horizontal_3,
          semanticLabel: 'Settings',
          onPressed: onPressed,
        ),
      ),
    );
  }
}
