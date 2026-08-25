import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/preset_store.dart';
import 'package:stupid_simple_sheet/stupid_simple_sheet.dart';

Animation<double> useRotatingAnimationController() {
  return useAnimationController(
    duration: const Duration(seconds: 5),
    lowerBound: 0,
    upperBound: 2 * pi,
  )..repeat();
}

// Apple’s loupe is a clear lens: its backdrop is enlarged, but it does not
// inherit the toolbar’s milky tint or frost. Keep the edge optics and contour
// from the matched toolbar while neutralizing transmission for this example.
const _clearLoupeSettings = LiquidGlassSettings(
  tint: Color.fromARGB(0, 255, 255, 255),
  thickness: 12,
  edgeRefraction: 27.42,
  refractionSpread: 0,
  frost: 0,
  chromaticAberration: 0.005,
  saturation: 1,
  transmissionGamma: 1,
  vibrancy: 0,
  highlight: 0.5,
  contourStrength: 0.1,
  contourWidth: 1,
);

class VerticalStripes extends StatelessWidget {
  const VerticalStripes({super.key, this.stripeThickness = 100.0});

  final double stripeThickness;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _VerticalStripesPainter(stripeThickness: stripeThickness),
      size: Size.infinite,
    );
  }
}

class _VerticalStripesPainter extends CustomPainter {
  const _VerticalStripesPainter({required this.stripeThickness});

  final double stripeThickness;

  @override
  void paint(Canvas canvas, Size size) {
    final blackPaint = Paint()..color = Colors.black;
    final whitePaint = Paint()..color = Colors.white;

    double currentX = 0;
    bool isBlack = true;

    while (currentX < size.width) {
      final rect = Rect.fromLTWH(currentX, 0, stripeThickness, size.height);

      canvas.drawRect(rect, isBlack ? blackPaint : whitePaint);

      currentX += stripeThickness;
      isBlack = !isBlack;
    }
  }

  @override
  bool shouldRepaint(covariant _VerticalStripesPainter oldDelegate) {
    return oldDelegate.stripeThickness != stripeThickness;
  }
}

class ImagePageView extends HookWidget {
  const ImagePageView({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageView.builder(
          itemBuilder: (context, index) {
            return switch (index) {
              <= 0 => Image.asset('assets/wallpaper.webp', fit: BoxFit.cover),
              1 => const Grid(),
              2 => const VerticalStripes(),
              _ => LayoutBuilder(
                builder: (context, constraints) => Image.network(
                  'https://picsum.photos/2000/2000?random=$index',
                  fit: BoxFit.cover,
                ),
              ),
            };
          },
        ),
        child,
      ],
    );
  }
}

/// Example-only loupe composition.
///
/// Flutter's [RawMagnifier] paints a higher-resolution view of the already
/// painted backdrop first. The liquid-glass layer is then composited above
/// that result, so its ordinary edge refraction and lighting operate on the
/// magnified pixels without introducing a shader-level zoom or another public
/// renderer setting.
class ExampleLoupe extends StatelessWidget {
  const ExampleLoupe({
    super.key,
    required this.settings,
    this.size = const Size(116, 86),
    this.magnificationScale = 1.55,
    this.alignment = Alignment.center,
    this.focalPointOffset = Offset.zero,
  });

  final LiquidGlassSettings settings;
  final Size size;
  final double magnificationScale;
  final Alignment alignment;
  final Offset focalPointOffset;

  @override
  Widget build(BuildContext context) {
    assert(magnificationScale >= 1.0);
    final radius = BorderRadius.circular(size.height / 2);
    return Align(
      alignment: alignment,
      child: SizedBox.fromSize(
        size: size,
        child: Stack(
          children: [
            RawMagnifier(
              size: size,
              magnificationScale: magnificationScale,
              focalPointOffset: focalPointOffset,
              decoration: MagnifierDecoration(
                shape: RoundedRectangleBorder(borderRadius: radius),
              ),
            ),
            LiquidGlass.withOwnLayer(
              settings: settings,
              shape: LiquidRoundedRectangle(borderRadius: size.height / 2),
              child: GlassGlow(child: const SizedBox.expand()),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small interactive page used by the example app's add button.
class LoupeExamplePage extends StatelessWidget {
  const LoupeExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar.large(
        largeTitle: Text('Loupe composition'),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: Grid()),
          Center(
            child: ExampleLoupe(
              settings: _clearLoupeSettings,
              focalPointOffset: const Offset(0, 64),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsSheet extends HookWidget {
  const SettingsSheet({
    super.key,
    required this.blendNotifier,
    required this.settingsNotifier,
    required this.fake,
    this.backgroundNotifier,
  });

  final ValueNotifier<double> blendNotifier;
  final ValueNotifier<LiquidGlassSettings> settingsNotifier;

  final bool fake;
  final ValueNotifier<String>? backgroundNotifier;

  Future<void> show(BuildContext context) {
    return Navigator.push(
      context,
      StupidSimpleSheetRoute(barrierColor: Colors.black26, child: this),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = useValueListenable(settingsNotifier);
    final blend = useValueListenable(blendNotifier);
    final presetStore = useMemoized(PresetStore.new);
    final presetNames = useState<List<String>>(<String>[]);
    final presetNameController = useTextEditingController();
    useEffect(() {
      var disposed = false;
      presetStore.names().then((names) {
        if (!disposed) presetNames.value = names;
      });
      return () {
        disposed = true;
      };
    }, [presetStore]);

    Future<void> refreshPresets() async {
      presetNames.value = await presetStore.names();
    }

    Future<void> savePreset() async {
      final requestedName = presetNameController.text.trim();
      final name = requestedName.isEmpty ? 'custom' : requestedName;
      await presetStore.save(name, settingsNotifier.value);
      presetNameController.text = name;
      await refreshPresets();
    }

    Future<void> loadPreset(String name) async {
      final loaded = await presetStore.load(name);
      if (loaded != null) settingsNotifier.value = loaded;
    }

    return LiquidStretch(
      interactionScale: 1.005,
      stretch: .1,
      child: SafeArea(
        minimum: const EdgeInsets.all(16.0),
        child: LiquidGlass.auto(
          fake: fake,
          settings: LiquidGlassSettings.figma(
            depth: 50,
            refraction: 100,
            dispersion: 4,
            frost: 2,
            tint: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.8),
          ),
          shape: LiquidRoundedSuperellipse(borderRadius: 32),
          child: GlassGlow(
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.bodyLarge!,
              child: Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Settings',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const _SettingsSection(title: 'Background'),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final option in [
                              'image',
                              'black',
                              'white',
                              'grid',
                            ])
                              CupertinoButton.tinted(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                onPressed: backgroundNotifier == null
                                    ? null
                                    : () => backgroundNotifier!.value = option,
                                child: Text(option),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: CupertinoButton.tinted(
                                onPressed: () {
                                  settingsNotifier.value = LiquidGlassSettings(
                                    thickness: 30,
                                    frost: 1,
                                    saturation: 1.2,
                                    tint: CupertinoTheme.of(context)
                                        .barBackgroundColor
                                        .withValues(alpha: .1),
                                    contourStrength: .3,
                                    contourWidth: 1,
                                  );
                                  blendNotifier.value = 10;
                                },
                                child: const Text('Previous demo'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: CupertinoButton.tinted(
                                onPressed: () {
                                  settingsNotifier.value =
                                      const LiquidGlassSettings.ios27ToolbarLight();
                                  blendNotifier.value = 10;
                                },
                                child: const Text('Matched toolbar'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _SettingsSlider(
                          label: 'Blend group',
                          value: blend,
                          min: 0,
                          max: 200,
                          onChanged: (value) => blendNotifier.value = value,
                        ),
                        _SettingsSlider(
                          label: 'Thickness',
                          value: settings.thickness,
                          min: 0,
                          max: 160,
                          onChanged: (value) => settingsNotifier.value =
                              settings.copyWith(thickness: value),
                        ),
                        _SettingsSlider(
                          label: 'Glass opacity',
                          value: settings.tint.a,
                          min: 0,
                          max: 1,
                          onChanged: (value) =>
                              settingsNotifier.value = settings.copyWith(
                                tint: settings.tint.withValues(
                                  alpha: value,
                                ),
                              ),
                        ),
                        const _SettingsSection(title: 'Lighting and rim'),
                        _SettingsSlider(
                          label: 'Highlight',
                          value: settings.highlight,
                          min: 0,
                          max: 2,
                          onChanged: (value) => settingsNotifier.value =
                              settings.copyWith(highlight: value),
                        ),
                        _SettingsSlider(
                          label: 'Contour strength',
                          value: settings.contourStrength,
                          min: 0,
                          max: 1,
                          onChanged: (value) =>
                              settingsNotifier.value = settings.copyWith(
                                contourStrength: value,
                              ),
                        ),
                        _SettingsSlider(
                          label: 'Contour width',
                          value: settings.contourWidth,
                          min: 0,
                          max: 8,
                          onChanged: (value) => settingsNotifier.value =
                              settings.copyWith(contourWidth: value),
                        ),
                        const _SettingsSection(title: 'Material transfer'),
                        _SettingsSlider(
                          label: 'Transmission gamma',
                          value: settings.transmissionGamma,
                          min: .5,
                          max: 1.5,
                          onChanged: (value) => settingsNotifier.value =
                              settings.copyWith(transmissionGamma: value),
                        ),
                        _SettingsSlider(
                          label: 'Vibrancy',
                          value: settings.vibrancy,
                          min: 0,
                          max: 1,
                          onChanged: (value) => settingsNotifier.value =
                              settings.copyWith(vibrancy: value),
                        ),
                        const _SettingsSection(title: 'Optics'),
                        _SettingsSlider(
                          label: 'Frost',
                          value: settings.frost,
                          min: 0,
                          max: 40,
                          onChanged: (value) => settingsNotifier.value =
                              settings.copyWith(frost: value),
                        ),
                        _SettingsSlider(
                          label: 'Chromatic aberration',
                          value: settings.chromaticAberration,
                          min: 0,
                          max: .1,
                          fractionDigits: 3,
                          onChanged: (value) => settingsNotifier.value =
                              settings.copyWith(chromaticAberration: value),
                        ),
                        _SettingsSlider(
                          label: 'Saturation',
                          value: settings.saturation,
                          min: 0,
                          max: 2,
                          onChanged: (value) => settingsNotifier.value =
                              settings.copyWith(saturation: value),
                        ),
                        _SettingsSlider(
                          label: 'Peak displacement (px)',
                          value: settings.edgeRefraction,
                          min: 0,
                          max: 160,
                          onChanged: (value) => settingsNotifier.value =
                              settings.copyWith(edgeRefraction: value),
                        ),
                        _SettingsSlider(
                          label: 'Face reach',
                          value: settings.refractionSpread,
                          min: 0,
                          max: 1,
                          onChanged: (value) => settingsNotifier.value =
                              settings.copyWith(refractionSpread: value),
                        ),
                        const _SettingsSection(title: 'Presets'),
                        CupertinoTextField(
                          controller: presetNameController,
                          placeholder: 'Preset name',
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => savePreset(),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: CupertinoButton.tinted(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                onPressed: savePreset,
                                child: const Text('Save current'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: CupertinoButton.tinted(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                onPressed: refreshPresets,
                                child: const Text('Refresh'),
                              ),
                            ),
                          ],
                        ),
                        if (presetNames.value.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              for (final name in presetNames.value)
                                CupertinoButton.tinted(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  onPressed: () => loadPreset(name),
                                  child: Text(name),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _SettingsSlider extends StatelessWidget {
  const _SettingsSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.fractionDigits = 2,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int fractionDigits;

  @override
  Widget build(BuildContext context) {
    final sliderValue = value.clamp(min, max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(label, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            Text(value.toStringAsFixed(fractionDigits)),
          ],
        ),
        CupertinoSlider(
          value: sliderValue,
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class Grid extends StatelessWidget {
  const Grid({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFCEC5B4), Color(0xFFF2F0EA)],
        ),
      ),
      child: GridPaper(
        color: Color(0xFF0F0B0A).withValues(alpha: 0.2),
        interval: 100,
      ),
    );
  }
}
