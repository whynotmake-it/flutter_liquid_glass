import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/loupe/liquid_glass_loupe.dart';
import 'package:liquid_glass_renderer_example/playground/backdrops.dart';
import 'package:liquid_glass_renderer_example/playground/presets.dart';

/// The glass specimens shown on the stage.
enum StageScene {
  controls('Controls'),
  blend('Blend'),
  colors('Colors'),
  loupe('Loupe');

  const StageScene(this.label);

  final String label;

  bool get usesBlending => this == blend || this == colors;
}

/// The material every shape on the stage is rendered with.
@immutable
class GlassMaterial {
  const GlassMaterial({
    required this.style,
    required this.brightness,
    required this.tintAmount,
    required this.settings,
    required this.appearance,
    this.edited = false,
  });

  factory GlassMaterial.preset({
    required GlassStyle style,
    required Brightness brightness,
    double tintAmount = 0,
  }) => GlassMaterial(
    style: style,
    brightness: brightness,
    tintAmount: tintAmount,
    settings: withTestFrost(
      style.settings(brightness: brightness, tintAmount: tintAmount),
    ),
    appearance: style.appearance(brightness),
  );

  final GlassStyle style;
  final Brightness brightness;

  /// Position of the iOS 27 Liquid Glass slider, `0` Clear to `1` Tinted.
  final double tintAmount;

  final LiquidGlassSettings settings;
  final LiquidGlassAppearance appearance;

  /// Whether [settings] differ from the [style] preset.
  final bool edited;

  GlassMaterial withStyle(GlassStyle value) => GlassMaterial.preset(
    style: value,
    brightness: brightness,
    tintAmount: tintAmount,
  );

  GlassMaterial withBrightness(Brightness value) {
    final preset = GlassMaterial.preset(
      style: style,
      brightness: value,
      tintAmount: tintAmount,
    );
    return edited ? preset.withSettings(settings) : preset;
  }

  /// Moves the Liquid Glass slider while keeping manual edits.
  ///
  /// Clear glass carries its slider response in its blur, so that is the one
  /// field the slider owns.
  GlassMaterial withTintAmount(double value) {
    final preset = GlassMaterial.preset(
      style: style,
      brightness: brightness,
      tintAmount: value,
    );
    if (!edited) return preset;
    return preset.withSettings(
      settings.copyWith(
        tintAmount: value,
        frost: style == GlassStyle.clear ? preset.settings.frost : null,
      ),
    );
  }

  GlassMaterial withSettings(LiquidGlassSettings value) => GlassMaterial(
    style: style,
    brightness: brightness,
    tintAmount: tintAmount,
    settings: value,
    appearance: appearance,
    edited: true,
  );

  GlassMaterial reset() => GlassMaterial.preset(
    style: style,
    brightness: brightness,
    tintAmount: tintAmount,
  );
}

/// Everything the playground can change, split into independent notifiers so
/// that each part of the UI only rebuilds for the values it shows.
class PlaygroundState {
  PlaygroundState({Brightness? brightness})
    : material = ValueNotifier(
        GlassMaterial.preset(
          style: GlassStyle.toolbar,
          brightness: brightness ?? Brightness.light,
        ),
      );

  final ValueNotifier<GlassMaterial> material;

  late final SelectedValue<GlassStyle> style = material.select(
    (material) => material.style,
  );

  /// Whether controls flip between light and dark glass to match the
  /// backdrop behind them, instead of following the chosen brightness.
  final adaptive = ValueNotifier<bool>(false);

  /// The backdrop that adaptive controls estimate their brightness from.
  final brightnessSource = LiquidGlassBrightnessSource();

  /// Whether the stage renders with the lightweight [FakeGlass] fallback.
  final fake = ValueNotifier<bool>(false);

  final scene = ValueNotifier<StageScene>(StageScene.controls);

  final backdrop = ValueNotifier<Backdrop>(
    _useTestBackground ? Backdrop.grid : Backdrop.photos,
  );

  /// How much the loupes enlarge the backdrop. The iOS 27 text loupe
  /// measures 1.25.
  final loupeScale = ValueNotifier<double>(1.25);

  /// Connects the loupes to the backdrop they magnify.
  final loupeLink = LiquidGlassLoupeLink();

  /// The iOS 27 text loupe, floating above the point it shows, and a round
  /// magnifier centered on its point.
  final loupes = [
    LoupeSpec(
      size: const Size(116, 86),
      offset: const Offset(-40, -70),
      focalPointOffset: const Offset(0, 75),
    ),
    LoupeSpec(
      size: const Size.square(150),
      offset: const Offset(70, 80),
      shape: const LiquidOval(),
    ),
  ];

  /// Distance in logical pixels at which grouped shapes start to merge.
  final blend = ValueNotifier<double>(24);

  void dispose() {
    style.dispose();
    material.dispose();
    adaptive.dispose();
    fake.dispose();
    scene.dispose();
    backdrop.dispose();
    blend.dispose();
    loupeScale.dispose();
    for (final loupe in loupes) {
      loupe.offset.dispose();
    }
  }
}

/// A draggable loupe on the stage.
class LoupeSpec {
  LoupeSpec({
    required this.size,
    required Offset offset,
    this.shape,
    this.focalPointOffset = Offset.zero,
  }) : offset = ValueNotifier(offset);

  final Size size;

  /// The lens shape, or `null` for the loupe's default capsule.
  final LiquidShape? shape;

  /// Offset from the lens center to the point it magnifies.
  final Offset focalPointOffset;

  /// Offset of the lens center from the center of the stage.
  final ValueNotifier<Offset> offset;
}

/// A value derived from another listenable that only notifies when the
/// derived value changes.
class SelectedValue<T> extends ValueNotifier<T> {
  SelectedValue(this._source, this._selector)
    : super(_selector(_source.value)) {
    _source.addListener(_update);
  }

  final ValueListenable<Object?> _source;
  final T Function(Object? value) _selector;

  void _update() => value = _selector(_source.value);

  @override
  void dispose() {
    _source.removeListener(_update);
    super.dispose();
  }
}

extension SelectValueListenable<S> on ValueListenable<S> {
  /// Listens to the part of this value picked by [selector]. Dispose the
  /// result when done.
  SelectedValue<T> select<T>(T Function(S value) selector) =>
      SelectedValue(this, (value) => selector(value as S));
}

/// Replaces the blur of [settings] in deterministic harness runs.
LiquidGlassSettings withTestFrost(LiquidGlassSettings settings) =>
    _useTestBackground
    ? settings.copyWith(frost: _testBlur.toDouble())
    : settings;

/// Deterministic grid backdrop and frost for screenshots and harness runs.
const _useTestBackground = bool.fromEnvironment(
  'LIQUID_GLASS_EXAMPLE_TEST_BACKGROUND',
);
const _testBlur = int.fromEnvironment('LIQUID_GLASS_EXAMPLE_TEST_BLUR');
