import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/preset_store.dart';

Animation<double> useRotatingAnimationController() {
  return useAnimationController(
    duration: const Duration(seconds: 5),
    upperBound: 2 * pi,
  )..repeat();
}

// Apple’s loupe is a clear lens: its backdrop is enlarged, but it does not
// inherit the toolbar’s milky tint or frost. Keep the edge optics and contour
// from the matched toolbar while neutralizing transmission for this example.
const _clearLoupeSettings = LiquidGlassSettings(
  thickness: 12,
  edgeRefraction: 27.42,
  frost: 0,
  chromaticAberration: 0.005,
  saturation: 1,
  // Keep only a hairline dielectric rim. The lens body must remain the
  // magnified backdrop, not a translucent white fill.
  highlight: 0.25,
  contourStrength: 0.08,
  contourWidth: 0.75,
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
    var isBlack = true;

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
  const ImagePageView({required this.child, super.key});

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
    required this.settings,
    super.key,
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
    assert(
      magnificationScale >= 1.0,
      'Magnification cannot shrink its source.',
    );
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
              clipBehavior: Clip.hardEdge,
            ),
            LiquidGlass.withOwnLayer(
              settings: settings,
              shape: LiquidRoundedRectangle(borderRadius: size.height / 2),
              // There is intentionally no child fill or glow here: Apple’s
              // loupe is a clear magnified lens with only its edge optics.
              child: const SizedBox.expand(),
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
    return const CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar.large(
        largeTitle: Text('Loupe composition'),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: Grid()),
          Center(
            child: ExampleLoupe(
              settings: _clearLoupeSettings,
              focalPointOffset: Offset(0, 64),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsSheet extends HookWidget {
  const SettingsSheet({
    required this.onClose,
    required this.blendNotifier,
    required this.settingsNotifier,
    required this.outerShadowAlphaNotifier,
    required this.fakeNotifier,
    super.key,
    this.backgroundNotifier,
  });

  final VoidCallback onClose;
  final ValueNotifier<double> blendNotifier;
  final ValueNotifier<LiquidGlassSettings> settingsNotifier;
  final ValueNotifier<double> outerShadowAlphaNotifier;
  final ValueNotifier<bool> fakeNotifier;

  final ValueNotifier<String>? backgroundNotifier;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    final settings = useValueListenable(settingsNotifier);
    final blend = useValueListenable(blendNotifier);
    final outerShadowAlpha = useValueListenable(outerShadowAlphaNotifier);
    final fake = useValueListenable(fakeNotifier);
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

    return ColoredBox(
      key: const ValueKey('settings-panel-surface'),
      color: Colors.black,
      child: SafeArea(
        top: !isCompact,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 15),
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Settings',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        CupertinoButton.tinted(
                          minimumSize: const Size(44, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          onPressed: onClose,
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                    const _SettingsSection(title: 'Background'),
                    CupertinoSlidingSegmentedControl<String>(
                      groupValue: backgroundNotifier?.value,
                      backgroundColor: const Color(0xff1c1c1e),
                      thumbColor: const Color(0xff48484a),
                      onValueChanged: (value) {
                        if (value != null && backgroundNotifier != null) {
                          backgroundNotifier!.value = value;
                        }
                      },
                      children: const {
                        'image': Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Text('Image'),
                        ),
                        'black': Text('Black'),
                        'white': Text('White'),
                        'grid': Text('Grid'),
                      },
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
                                tint: CupertinoTheme.of(
                                  context,
                                ).barBackgroundColor.withValues(alpha: .1),
                                contourStrength: .3,
                                contourWidth: 1,
                              );
                              blendNotifier.value = 10;
                              outerShadowAlphaNotifier.value = 0;
                            },
                            child: const Text('Previous demo'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CupertinoButton.tinted(
                            onPressed: () {
                              const matchedToolbar =
                                  LiquidGlassSettings.ios27ToolbarLight();
                              settingsNotifier.value = matchedToolbar;
                              blendNotifier.value = 10;
                              outerShadowAlphaNotifier.value = .03;
                            },
                            child: const Text('Matched toolbar'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _SettingsSlider(
                      label: 'Blend group',
                      fullRendererOnly: true,
                      fullRendererInactive: fake,
                      value: blend,
                      min: 0,
                      max: 200,
                      onChanged: (value) => blendNotifier.value = value,
                    ),
                    _SettingsSlider(
                      label: 'Outer shadow',
                      value: outerShadowAlpha,
                      min: 0,
                      max: 1,
                      fractionDigits: 3,
                      onChanged: (value) =>
                          outerShadowAlphaNotifier.value = value,
                    ),
                    _SettingsSlider(
                      label: 'Thickness',
                      value: settings.thickness,
                      min: 0,
                      max: 160,
                      onChanged: (value) => settingsNotifier.value = settings
                          .copyWith(thickness: value),
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
                      onChanged: (value) => settingsNotifier.value = settings
                          .copyWith(highlight: value),
                    ),
                    _SettingsSlider(
                      label: 'Highlight wrap',
                      value: settings.highlightWrap,
                      min: 0,
                      max: 1,
                      onChanged: (value) => settingsNotifier.value = settings
                          .copyWith(highlightWrap: value),
                    ),
                    _SettingsSlider(
                      label: 'Opposite highlight',
                      value: settings.highlightOppositeStrength,
                      min: 0,
                      max: 1,
                      onChanged: (value) => settingsNotifier.value = settings
                          .copyWith(highlightOppositeStrength: value),
                    ),
                    _SettingsSlider(
                      label: 'Highlight width',
                      value: settings.highlightWidth,
                      min: 0,
                      max: 8,
                      onChanged: (value) => settingsNotifier.value = settings
                          .copyWith(highlightWidth: value),
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
                      onChanged: (value) => settingsNotifier.value = settings
                          .copyWith(contourWidth: value),
                    ),
                    _SettingsSlider(
                      label: 'Contour offset',
                      value: settings.contourOffset,
                      min: -4,
                      max: 4,
                      onChanged: (value) => settingsNotifier.value = settings
                          .copyWith(contourOffset: value),
                    ),
                    _SettingsSlider(
                      label: 'Contour transmission',
                      value: settings.contourTransmittance,
                      min: 0,
                      max: 1,
                      onChanged: (value) =>
                          settingsNotifier.value = settings.copyWith(
                            contourTransmittance: value,
                          ),
                    ),
                    _SettingsSlider(
                      label: 'Inner bevel shadow',
                      value: settings.bevelShadowStrength,
                      min: 0,
                      max: .2,
                      fractionDigits: 3,
                      onChanged: (value) =>
                          settingsNotifier.value = settings.copyWith(
                            bevelShadowStrength: value,
                          ),
                    ),
                    _SettingsSlider(
                      label: 'Bevel shadow depth',
                      value: settings.bevelShadowDepth,
                      min: 0,
                      max: 40,
                      onChanged: (value) => settingsNotifier.value = settings
                          .copyWith(bevelShadowDepth: value),
                    ),
                    _SettingsSlider(
                      label: 'Inner shadow offset',
                      value: settings.bevelShadowOffset,
                      min: 0,
                      max: 24,
                      onChanged: (value) => settingsNotifier.value = settings
                          .copyWith(bevelShadowOffset: value),
                    ),
                    _SettingsSlider(
                      label: 'Inner shadow size response',
                      value: settings.bevelShadowSizeResponse,
                      min: 0,
                      max: 1,
                      onChanged: (value) => settingsNotifier.value = settings
                          .copyWith(bevelShadowSizeResponse: value),
                    ),
                    _SettingsSlider(
                      label: 'Outer shadow size response',
                      value: settings.exteriorShadowSizeResponse,
                      min: 0,
                      max: 1,
                      onChanged: (value) => settingsNotifier.value = settings
                          .copyWith(exteriorShadowSizeResponse: value),
                    ),
                    _SettingsSlider(
                      label: 'Bevel shadow directionality',
                      value: settings.bevelShadowDirectionality,
                      min: 0,
                      max: 1,
                      onChanged: (value) =>
                          settingsNotifier.value = settings.copyWith(
                            bevelShadowDirectionality: value,
                          ),
                    ),
                    const _SettingsSection(title: 'Material transfer'),
                    _SettingsSlider(
                      label: 'Transmission gamma',
                      fullRendererOnly: true,
                      fullRendererInactive: fake,
                      value: settings.transmissionGamma,
                      min: .5,
                      max: 1.5,
                      onChanged: (value) => settingsNotifier.value = settings
                          .copyWith(transmissionGamma: value),
                    ),
                    _SettingsSlider(
                      label: 'Vibrancy',
                      fullRendererOnly: true,
                      fullRendererInactive: fake,
                      value: settings.vibrancy,
                      min: 0,
                      max: 1,
                      onChanged: (value) => settingsNotifier.value = settings
                          .copyWith(vibrancy: value),
                    ),
                    const _SettingsSection(title: 'Optics'),
                    _SettingsSlider(
                      label: 'Frost',
                      value: settings.frost,
                      min: 0,
                      max: 40,
                      onChanged: (value) => settingsNotifier.value = settings
                          .copyWith(frost: value),
                    ),
                    _SettingsSlider(
                      label: 'Chromatic aberration',
                      fullRendererOnly: true,
                      fullRendererInactive: fake,
                      value: settings.chromaticAberration,
                      min: 0,
                      max: 1,
                      fractionDigits: 3,
                      onChanged: (value) => settingsNotifier.value = settings
                          .copyWith(chromaticAberration: value),
                    ),
                    _SettingsSlider(
                      label: 'Saturation',
                      value: settings.saturation,
                      min: 0,
                      max: 2,
                      onChanged: (value) => settingsNotifier.value = settings
                          .copyWith(saturation: value),
                    ),
                    _SettingsSlider(
                      label: 'Peak displacement (px)',
                      fullRendererOnly: true,
                      fullRendererInactive: fake,
                      value: settings.edgeRefraction,
                      min: 0,
                      max: 160,
                      onChanged: (value) => settingsNotifier.value = settings
                          .copyWith(edgeRefraction: value),
                    ),
                    _SettingsSlider(
                      label: 'Face reach',
                      fullRendererOnly: true,
                      fullRendererInactive: fake,
                      value: settings.refractionSpread,
                      min: 0,
                      max: 1,
                      onChanged: (value) => settingsNotifier.value = settings
                          .copyWith(refractionSpread: value),
                    ),
                    _SettingsSlider(
                      label: 'Backdrop scale',
                      fullRendererOnly: true,
                      fullRendererInactive: fake,
                      value: settings.backdropScale,
                      min: .5,
                      max: 1.5,
                      onChanged: (value) => settingsNotifier.value = settings
                          .copyWith(backdropScale: value),
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
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xff8e8e93),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: .6,
        ),
      ),
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
    this.fullRendererOnly = false,
    this.fullRendererInactive = false,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int fractionDigits;
  final bool fullRendererOnly;
  final bool fullRendererInactive;

  @override
  Widget build(BuildContext context) {
    final sliderValue = value.clamp(min, max);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xff1c1c1e),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xff2c2c2e)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(label, overflow: TextOverflow.ellipsis),
                        ),
                        if (fullRendererOnly) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Available with the full renderer',
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: fullRendererInactive
                                    ? const Color(0x3329a9ff)
                                    : const Color(0xff2c2c2e),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                child: Text(
                                  'FULL',
                                  style: TextStyle(
                                    color: fullRendererInactive
                                        ? const Color(0xff64d2ff)
                                        : const Color(0xff8e8e93),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.35,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    value.toStringAsFixed(fractionDigits),
                    style: const TextStyle(
                      color: Color(0xffaeaeb2),
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              CupertinoSlider(
                value: sliderValue,
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Grid extends StatelessWidget {
  const Grid({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFCEC5B4), Color(0xFFF2F0EA)],
        ),
      ),
      child: GridPaper(
        color: const Color(0xFF0F0B0A).withValues(alpha: 0.2),
      ),
    );
  }
}
