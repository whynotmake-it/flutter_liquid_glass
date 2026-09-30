import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/playground/backdrops.dart';
import 'package:liquid_glass_renderer_example/playground/inspector/capsule_segmented_control.dart';
import 'package:liquid_glass_renderer_example/playground/inspector/grouped_list.dart';
import 'package:liquid_glass_renderer_example/playground/inspector/material_sections.dart';
import 'package:liquid_glass_renderer_example/playground/playground_state.dart';
import 'package:liquid_glass_renderer_example/playground/presets.dart';

/// The settings sheet that drives the stage.
class Inspector extends StatelessWidget {
  const Inspector({
    required this.state,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final PlaygroundState state;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: padding.add(
        const EdgeInsets.fromLTRB(inspectorInset, 22, inspectorInset, 20),
      ),
      children: [
        const _Title(),
        _SceneControl(state: state),
        const SizedBox(height: 20),
        _MaterialControls(state: state),
        const SizedBox(height: 28),
        MaterialSections(material: state.material),
        _BackdropPicker(backdrop: state.backdrop),
        const SizedBox(height: 24),
        _Actions(material: state.material),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Text(
        'Liquid Glass',
        style: TextStyle(
          color: CupertinoColors.label.resolveFrom(context),
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
      ),
    );
  }
}

class _SceneControl extends StatelessWidget {
  const _SceneControl({required this.state});

  final PlaygroundState state;

  static const _hints = {
    StageScene.controls: 'Scroll the backdrop beneath the controls.',
    StageScene.blend: 'Drag the shapes into each other.',
    StageScene.colors: 'Four appearances in one layer, blending as they merge.',
    StageScene.loupe: 'Drag the loupes across the backdrop.',
  };

  void _select(StageScene scene) {
    state.scene.value = scene;
    if (scene == StageScene.loupe &&
        state.material.value.style != GlassStyle.loupe) {
      state.material.value = state.material.value.withStyle(GlassStyle.loupe);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: state.scene,
      builder: (context, scene, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CapsuleSegmentedControl(
            value: scene,
            segments: {for (final s in StageScene.values) s: s.label},
            onChanged: _select,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              _hints[scene]!,
              style: TextStyle(
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Appearance { light, dark, auto }

/// Style, appearance and the controls that apply to the current scene.
class _MaterialControls extends StatelessWidget {
  const _MaterialControls({required this.state});

  final PlaygroundState state;

  void _setAppearance(_Appearance appearance) {
    state.adaptive.value = appearance == _Appearance.auto;
    if (appearance == _Appearance.auto) return;
    state.material.value = state.material.value.withBrightness(
      appearance == _Appearance.dark ? Brightness.dark : Brightness.light,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        state.material,
        state.adaptive,
        state.scene,
        state.fake,
      ]),
      builder: (context, _) {
        final material = state.material.value;
        final scene = state.scene.value;
        final appearance = state.adaptive.value
            ? _Appearance.auto
            : material.brightness == Brightness.dark
            ? _Appearance.dark
            : _Appearance.light;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            CapsuleSegmentedControl(
              value: material.style,
              segments: {for (final s in GlassStyle.values) s: s.label},
              onChanged: (style) =>
                  state.material.value = material.withStyle(style),
            ),
            CapsuleSegmentedControl(
              value: appearance,
              segments: const {
                _Appearance.light: 'Light',
                _Appearance.dark: 'Dark',
                _Appearance.auto: 'Auto',
              },
              onChanged: _setAppearance,
            ),
            const SizedBox(height: 4),
            InspectorCard(
              children: [
                SliderRow(
                  title: 'Liquid Glass',
                  value: material.tintAmount,
                  min: 0,
                  max: 1,
                  minLabel: 'Clear',
                  maxLabel: 'Tinted',
                  onChanged: (amount) => state.material.value = state
                      .material
                      .value
                      .withTintAmount(amount),
                ),
                if (scene.usesBlending)
                  ValueListenableBuilder(
                    valueListenable: state.blend,
                    builder: (context, blend, _) => SliderRow(
                      title: 'Blend',
                      value: blend,
                      min: 0,
                      max: 60,
                      format: (v) => '${v.toStringAsFixed(0)} pt',
                      onChanged: (v) => state.blend.value = v,
                    ),
                  ),
                if (scene == StageScene.loupe)
                  ValueListenableBuilder(
                    valueListenable: state.loupeScale,
                    builder: (context, scale, _) => SliderRow(
                      title: 'Magnification',
                      value: scale,
                      min: 1,
                      max: 2,
                      format: (v) => '${v.toStringAsFixed(2)}×',
                      onChanged: (v) => state.loupeScale.value = v,
                    ),
                  ),
                SwitchRow(
                  title: 'FakeGlass',
                  value: state.fake.value,
                  onChanged: (value) => state.fake.value = value,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _BackdropPicker extends StatelessWidget {
  const _BackdropPicker({required this.backdrop});

  final ValueNotifier<Backdrop> backdrop;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: backdrop,
      builder: (context, selected, _) => Row(
        spacing: 10,
        children: [
          for (final option in Backdrop.values)
            Expanded(
              child: _BackdropOption(
                backdrop: option,
                selected: option == selected,
                onTap: () => backdrop.value = option,
              ),
            ),
        ],
      ),
    );
  }
}

class _BackdropOption extends StatelessWidget {
  const _BackdropOption({
    required this.backdrop,
    required this.selected,
    required this.onTap,
  });

  final Backdrop backdrop;
  final bool selected;
  final VoidCallback onTap;

  static const _radius = BorderRadius.all(Radius.circular(16));

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoTheme.of(context).primaryColor;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: ShapeDecoration(
              shape: RoundedSuperellipseBorder(
                borderRadius: _radius,
                side: BorderSide(
                  color: selected ? accent : const Color(0x00000000),
                  width: 2.5,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
              ),
            ),
            child: ClipRSuperellipse(
              borderRadius: _radius,
              child: AspectRatio(
                aspectRatio: 0.8,
                child: BackdropThumbnail(backdrop: backdrop),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            backdrop.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected
                  ? accent
                  : CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatefulWidget {
  const _Actions({required this.material});

  final ValueNotifier<GlassMaterial> material;

  @override
  State<_Actions> createState() => _ActionsState();
}

class _ActionsState extends State<_Actions> {
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final source = settingsSource(widget.material.value.settings);
    await Clipboard.setData(ClipboardData(text: source));
    if (!mounted) return;
    setState(() {
      _copiedTimer?.cancel();
      _copiedTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _copiedTimer = null);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.material,
      builder: (context, material, _) => Row(
        spacing: 10,
        children: [
          Expanded(
            child: CapsuleButton(
              label: _copiedTimer == null ? 'Copy as Dart' : 'Copied',
              prominent: true,
              onPressed: _copy,
            ),
          ),
          Expanded(
            child: CapsuleButton(
              label: 'Reset',
              onPressed: material.edited
                  ? () => widget.material.value = material.reset()
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dart source for [settings], listing only fields that differ from the
/// defaults.
String settingsSource(LiquidGlassSettings settings) {
  final defaults = const LiquidGlassSettings().toJson();
  String literal(Object value) => switch (value) {
    final double v =>
      v
          .toStringAsFixed(3)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '.0'),
    _ => '$value',
  };
  final fields = [
    for (final MapEntry(:key, :value) in settings.toJson().entries)
      if (value != defaults[key]) '  $key: ${literal(value)},',
  ];
  if (fields.isEmpty) return 'const LiquidGlassSettings()';
  return 'const LiquidGlassSettings(\n${fields.join('\n')}\n)';
}
