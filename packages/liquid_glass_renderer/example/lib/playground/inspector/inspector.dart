import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/playground/backdrops.dart';
import 'package:liquid_glass_renderer_example/playground/inspector/grouped_list.dart';
import 'package:liquid_glass_renderer_example/playground/inspector/material_sections.dart';
import 'package:liquid_glass_renderer_example/playground/playground_state.dart';
import 'package:liquid_glass_renderer_example/playground/presets.dart';

/// The settings list that drives the stage.
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
      padding: padding.add(const EdgeInsets.only(top: 24, bottom: 16)),
      children: [
        const _Header(),
        _SceneSection(state: state),
        _StyleSection(material: state.material, adaptive: state.adaptive),
        _RendererSection(fake: state.fake),
        _BlendSection(scene: state.scene, blend: state.blend),
        MaterialSections(material: state.material),
        _BackdropSection(backdrop: state.backdrop),
        _ActionsSection(material: state.material),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Liquid Glass',
            style: TextStyle(
              color: CupertinoColors.label.resolveFrom(context),
              fontSize: 34,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
            ),
          ),
          Text(
            'liquid_glass_renderer playground',
            style: TextStyle(
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _SceneSection extends StatelessWidget {
  const _SceneSection({required this.state});

  final PlaygroundState state;

  static const _footers = {
    StageScene.controls:
        'Everyday controls. Each is its own glass shape, and all of them '
        'share one layer and one backdrop capture.',
    StageScene.blend:
        'Drag the shapes into each other. Shapes in a LiquidGlassBlendGroup '
        'merge like liquid.',
    StageScene.colors:
        'Light, dark, clear and tinted glass in a single layer. Appearance is '
        'per shape, and colors blend where shapes merge.',
    StageScene.lens:
        'Drag the lenses across the backdrop to judge refraction, '
        'magnification and blur.',
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: state.scene,
      builder: (context, scene, _) => InspectorSection(
        footer: _footers[scene],
        children: [
          SegmentedRow(
            value: scene,
            segments: {for (final s in StageScene.values) s: s.label},
            onChanged: (value) => state.scene.value = value,
          ),
        ],
      ),
    );
  }
}

enum _Appearance { light, dark, auto }

class _StyleSection extends StatelessWidget {
  const _StyleSection({required this.material, required this.adaptive});

  final ValueNotifier<GlassMaterial> material;
  final ValueNotifier<bool> adaptive;

  static const _autoNote =
      'Auto: each control samples the backdrop behind it and switches '
      'between light and dark glass (experimental).';
  static const _invariantNote =
      'Clear glass and the loupe look the same in light and dark.';
  static const _sliderNote =
      'The Liquid Glass slider works like the one in iOS 27 Settings.';

  void _setAppearance(_Appearance appearance) {
    adaptive.value = appearance == _Appearance.auto;
    if (appearance == _Appearance.auto) return;
    material.value = material.value.withBrightness(
      appearance == _Appearance.dark ? Brightness.dark : Brightness.light,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([material, adaptive]),
      builder: (context, _) {
        final value = material.value;
        final appearance = adaptive.value
            ? _Appearance.auto
            : value.brightness == Brightness.dark
            ? _Appearance.dark
            : _Appearance.light;
        return InspectorSection(
          header: 'Material',
          footer: [
            if (adaptive.value) _autoNote,
            if (!value.style.followsBrightness) _invariantNote,
            _sliderNote,
          ].join(' '),
          children: [
            SegmentedRow(
              value: value.style,
              segments: {for (final s in GlassStyle.values) s: s.label},
              onChanged: (style) => material.value = value.withStyle(style),
            ),
            SegmentedRow(
              value: appearance,
              segments: const {
                _Appearance.light: 'Light',
                _Appearance.dark: 'Dark',
                _Appearance.auto: 'Auto',
              },
              onChanged: _setAppearance,
            ),
            SliderRow(
              title: 'Liquid Glass',
              value: value.tintAmount,
              min: 0,
              max: 1,
              minLabel: 'Clear',
              maxLabel: 'Tinted',
              onChanged: (amount) =>
                  material.value = material.value.withTintAmount(amount),
            ),
          ],
        );
      },
    );
  }
}

class _RendererSection extends StatelessWidget {
  const _RendererSection({required this.fake});

  final ValueNotifier<bool> fake;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: fake,
      builder: (context, value, _) => InspectorSection(
        header: 'Renderer',
        footer: value
            ? 'FakeGlass approximates the material with a backdrop blur. It '
                  'has no refraction, but it is cheap and also runs on Skia '
                  'and the web.'
            : 'The full renderer refracts the backdrop through each shape’s '
                  'bevel on the GPU.',
        children: [
          SegmentedRow(
            value: value,
            segments: const {false: 'Liquid Glass', true: 'FakeGlass'},
            onChanged: (value) => fake.value = value,
          ),
        ],
      ),
    );
  }
}

class _BlendSection extends StatelessWidget {
  const _BlendSection({required this.scene, required this.blend});

  final ValueListenable<StageScene> scene;
  final ValueNotifier<double> blend;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: scene,
      builder: (context, scene, section) =>
          scene.usesBlending ? section! : const SizedBox.shrink(),
      child: ValueListenableBuilder(
        valueListenable: blend,
        builder: (context, value, _) => InspectorSection(
          header: 'Blending',
          footer: 'The distance at which grouped shapes start to merge.',
          children: [
            SliderRow(
              title: 'Blend',
              value: value,
              min: 0,
              max: 60,
              format: (v) => '${v.toStringAsFixed(0)} pt',
              onChanged: (v) => blend.value = v,
            ),
          ],
        ),
      ),
    );
  }
}

class _BackdropSection extends StatelessWidget {
  const _BackdropSection({required this.backdrop});

  final ValueNotifier<Backdrop> backdrop;

  @override
  Widget build(BuildContext context) {
    return InspectorSection(
      header: 'Backdrop',
      children: [
        ValueListenableBuilder(
          valueListenable: backdrop,
          builder: (context, selected, _) => Padding(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
            child: Row(
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
          ),
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoTheme.of(context).primaryColor;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Column(
          children: [
            DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? accent : const Color(0x00000000),
                  width: 2.5,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 0.78,
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
      ),
    );
  }
}

class _ActionsSection extends StatefulWidget {
  const _ActionsSection({required this.material});

  final ValueNotifier<GlassMaterial> material;

  @override
  State<_ActionsSection> createState() => _ActionsSectionState();
}

class _ActionsSectionState extends State<_ActionsSection> {
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
    final accent = CupertinoTheme.of(context).primaryColor;
    return ValueListenableBuilder(
      valueListenable: widget.material,
      builder: (context, material, _) => InspectorSection(
        children: [
          InspectorRow(
            title: _copiedTimer == null ? 'Copy Settings as Dart' : 'Copied',
            titleColor: accent,
            onTap: _copy,
          ),
          InspectorRow(
            title: 'Reset ${material.style.label} Glass',
            titleColor: material.edited
                ? accent
                : CupertinoColors.tertiaryLabel.resolveFrom(context),
            onTap: material.edited
                ? () => widget.material.value = material.reset()
                : null,
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
