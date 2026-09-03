import 'package:flutter/cupertino.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/widgets/glass_button.dart';
import 'package:liquid_glass_renderer_example/widgets/glass_segmented_control.dart';
import 'package:liquid_glass_renderer_example/widgets/glass_slider.dart';
import 'package:liquid_glass_renderer_example/widgets/glass_switch.dart';

/// The widget showcase: every control below is carved from the single shared
/// [LiquidGlassLayer] around the whole app, so the entire page costs one
/// backdrop sample (plus the small on-glass lenses).
class ShowcasePage extends HookWidget {
  const ShowcasePage({super.key});

  @override
  Widget build(BuildContext context) {
    final volume = useState(0.7);
    final wifi = useState(true);
    final drink = useState('Coffee');
    final playback = useState(0.35);
    final playing = useState(false);

    return CupertinoPageScaffold(
      backgroundColor: const Color(0x00000000),
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _ShowcaseHeader()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 220),
              sliver: SliverList.list(
                children: [
                  const _SectionLabel('Controls'),
                  _ControlPanel(
                    children: [
                      _LabeledRow(
                        label: 'Volume',
                        trailing: Text(
                          '${(volume.value * 100).round()}',
                          style: _valueTextStyle(context),
                        ),
                      ),
                      GlassSlider(
                        value: volume.value,
                        onChanged: (value) => volume.value = value,
                      ),
                      const SizedBox(height: 8),
                      _LabeledRow(
                        label: 'Wi-Fi',
                        trailing: GlassSwitch(
                          value: wifi.value,
                          onChanged: (value) => wifi.value = value,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GlassSegmentedControl<String>(
                    segments: const ['Coffee', 'Tea', 'Cocoa'],
                    labels: const {
                      'Coffee': 'Coffee',
                      'Tea': 'Tea',
                      'Cocoa': 'Cocoa',
                    },
                    selected: drink.value,
                    onSelected: (value) => drink.value = value,
                  ),
                  const SizedBox(height: 28),
                  const _SectionLabel('Buttons'),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      GlassButton(
                        label: 'Continue',
                        icon: CupertinoIcons.arrow_right,
                        tint: const Color(0x592563eb),
                        onPressed: () {},
                      ),
                      GlassIconButton(
                        icon: CupertinoIcons.bell,
                        onPressed: () {},
                      ),
                      GlassIconButton(
                        icon: CupertinoIcons.mic_fill,
                        onPressed: () {},
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  const _SectionLabel('Now playing'),
                  GlassSlider(
                    value: playback.value,
                    onChanged: (value) => playback.value = value,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      GlassIconButton(
                        icon: playing.value
                            ? CupertinoIcons.pause_fill
                            : CupertinoIcons.play_fill,
                        size: 52,
                        onPressed: () => playing.value = !playing.value,
                      ),
                      const Spacer(),
                      GlassIconButton(
                        icon: CupertinoIcons.forward_end_fill,
                        size: 52,
                        onPressed: () {},
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

  TextStyle _valueTextStyle(BuildContext context) => TextStyle(
    fontSize: 15,
    fontFeatures: const [FontFeature.tabularFigures()],
    color: CupertinoColors.secondaryLabel.resolveFrom(context),
  );
}

class _ShowcaseHeader extends StatelessWidget {
  const _ShowcaseHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Liquid Glass',
            style: CupertinoTheme.of(context).textTheme.navLargeTitleTextStyle
                .copyWith(shadows: _headerShadows),
          ),
          const SizedBox(height: 4),
          Text(
            'One glass layer. Every widget.',
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

/// A grouped glass panel that hosts plain rows and controls.
class _ControlPanel extends StatelessWidget {
  const _ControlPanel({required this.children});

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
          spacing: 12,
          children: children,
        ),
      ),
    );
  }
}

class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.trailing});

  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xf2ffffff),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        trailing,
      ],
    );
  }
}

const _headerShadows = [
  Shadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 2)),
];
