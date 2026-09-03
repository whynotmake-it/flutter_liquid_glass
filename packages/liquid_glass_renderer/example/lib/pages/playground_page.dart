import 'package:flutter/cupertino.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/preset_store.dart';
import 'package:liquid_glass_renderer_example/state.dart';
import 'package:liquid_glass_renderer_example/widgets/glass_button.dart';
import 'package:liquid_glass_renderer_example/widgets/glass_segmented_control.dart';
import 'package:liquid_glass_renderer_example/widgets/glass_slider.dart';

/// The playground: glass sliders on glass panels editing the very material
/// they are rendered with. Every change flows into [settingsNotifier], which
/// feeds the single shared [LiquidGlassLayer], so the whole app re-materializes
/// live while you drag.
class PlaygroundPage extends HookWidget {
  const PlaygroundPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = useValueListenable(settingsNotifier);
    final appearance = useValueListenable(appearanceNotifier);
    final fake = useValueListenable(fakeNotifier);
    final background = useValueListenable(backgroundNotifier);
    final presetStore = useMemoized(PresetStore.new);
    final presetNames = useState<List<String>>(const []);
    final savedCount = useState(0);

    useEffect(() {
      var disposed = false;
      presetStore.names().then((names) {
        if (!disposed) presetNames.value = names;
      });
      return () {
        disposed = true;
      };
    }, [presetStore, savedCount.value]);

    Future<void> savePreset() async {
      await presetStore.save('custom', (
        settings: settingsNotifier.value,
        appearance: appearanceNotifier.value,
      ));
      savedCount.value++;
    }

    Future<void> loadPreset(String name) async {
      final loaded = await presetStore.load(name);
      if (loaded != null) {
        settingsNotifier.value = loaded.settings;
        appearanceNotifier.value = loaded.appearance;
      }
    }

    void setSettings(LiquidGlassSettings value) =>
        settingsNotifier.value = value;

    void setAppearance(LiquidGlassAppearance value) =>
        appearanceNotifier.value = value;

    return CupertinoPageScaffold(
      backgroundColor: const Color(0x00000000),
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _PlaygroundHeader()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 220),
              sliver: SliverList.list(
                children: [
                  const _SectionLabel('Material'),
                  _SettingsPanel(
                    children: [
                      _SliderSetting(
                        label: 'Thickness',
                        value: settings.thickness,
                        min: 0,
                        max: 160,
                        onChanged: (value) =>
                            setSettings(settings.copyWith(thickness: value)),
                      ),
                      _SliderSetting(
                        label: 'Frost',
                        value: settings.frost,
                        min: 0,
                        max: 40,
                        onChanged: (value) =>
                            setSettings(settings.copyWith(frost: value)),
                      ),
                      _SliderSetting(
                        label: 'Glass opacity',
                        value: appearance.tint.a,
                        min: 0,
                        max: 1,
                        fractionDigits: 2,
                        onChanged: (value) => setAppearance(
                          appearance.copyWith(
                            tint: appearance.tint.withValues(alpha: value),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const _SectionLabel('Optics'),
                  _SettingsPanel(
                    children: [
                      _SliderSetting(
                        label: 'Edge refraction',
                        value: settings.edgeRefraction,
                        min: 0,
                        max: 160,
                        onChanged: (value) => setSettings(
                          settings.copyWith(edgeRefraction: value),
                        ),
                      ),
                      _SliderSetting(
                        label: 'Chromatic aberration',
                        value: settings.chromaticAberration,
                        min: 0,
                        max: 1,
                        fractionDigits: 3,
                        onChanged: (value) => setSettings(
                          settings.copyWith(chromaticAberration: value),
                        ),
                      ),
                      _SliderSetting(
                        label: 'Backdrop scale',
                        value: settings.backdropScale,
                        min: 0.5,
                        max: 1.5,
                        onChanged: (value) => setSettings(
                          settings.copyWith(backdropScale: value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const _SectionLabel('Lighting'),
                  _SettingsPanel(
                    children: [
                      _SliderSetting(
                        label: 'Highlight',
                        value: settings.highlight,
                        min: 0,
                        max: 2,
                        onChanged: (value) =>
                            setSettings(settings.copyWith(highlight: value)),
                      ),
                      _SliderSetting(
                        label: 'Contour',
                        value: settings.contourStrength,
                        min: 0,
                        max: 1,
                        onChanged: (value) => setSettings(
                          settings.copyWith(contourStrength: value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const _SectionLabel('Scene'),
                  GlassSegmentedControl<String>(
                    segments: const ['image', 'grid', 'black', 'white'],
                    labels: const {
                      'image': 'Wallpaper',
                      'grid': 'Grid',
                      'black': 'Black',
                      'white': 'White',
                    },
                    selected: background,
                    onSelected: (value) => backgroundNotifier.value = value,
                  ),
                  const SizedBox(height: 12),
                  GlassSegmentedControl<bool>(
                    segments: const [false, true],
                    labels: const {false: 'Full renderer', true: 'FakeGlass'},
                    selected: fake,
                    onSelected: (value) => fakeNotifier.value = value,
                  ),
                  const SizedBox(height: 20),
                  const _SectionLabel('Presets'),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      GlassButton(
                        label: 'Save current',
                        icon: CupertinoIcons.add,
                        onPressed: savePreset,
                      ),
                      for (final name in presetNames.value)
                        GlassButton(
                          label: name,
                          onPressed: () => loadPreset(name),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaygroundHeader extends StatelessWidget {
  const _PlaygroundHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Playground',
            style: CupertinoTheme.of(context).textTheme.navLargeTitleTextStyle
                .copyWith(shadows: _headerShadows),
          ),
          const SizedBox(height: 4),
          Text(
            'Drag the glass to shape the glass.',
            style: CupertinoTheme.of(context).textTheme.textStyle
                .copyWith(color: const Color(0xd9ffffff)),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Color(0x99ffffff),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: .8,
        ),
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass.grouped(
      shape: const LiquidRoundedSuperellipse(borderRadius: 27),
      appearance: const LiquidGlassAppearance(tint: Color(0x14ffffff)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: children,
        ),
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.fractionDigits = 0,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int fractionDigits;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xf2ffffff),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              value.toStringAsFixed(fractionDigits),
              style: const TextStyle(
                color: Color(0x99ffffff),
                fontSize: 14,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        SizedBox(
          height: 32,
          child: GlassSlider(
            value: value,
            min: min,
            max: max,
            trackHeight: 32,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

const _headerShadows = [
  Shadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 2)),
];
