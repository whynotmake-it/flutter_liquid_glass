import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';

enum GalleryRenderer {
  liquid('Liquid'),
  fake('Fake'),
  flat('Flat');

  const GalleryRenderer(this.title);

  final String title;

  GlassRenderer get renderer => switch (this) {
    liquid => const LiquidGlassRenderer(),
    fake => const FakeGlassRenderer(),
    flat => const FlatGlassRenderer(),
  };
}

enum GalleryAccent {
  blue('Blue', GlassColors.systemBlue),
  purple(
    'Purple',
    GlassDynamicColor.withBrightness(
      color: Color(0xFFAF52DE),
      darkColor: Color(0xFFBF5AF2),
    ),
  ),
  pink(
    'Pink',
    GlassDynamicColor.withBrightness(
      color: Color(0xFFFF2D55),
      darkColor: Color(0xFFFF375F),
    ),
  ),
  orange('Orange', GlassColors.systemOrange),
  green('Green', GlassColors.systemGreen),
  teal(
    'Teal',
    GlassDynamicColor.withBrightness(
      color: Color(0xFF00C3D0),
      darkColor: Color(0xFF00D2E0),
    ),
  );

  const GalleryAccent(this.title, this.color);

  final String title;
  final Color color;

  /// The light color, for what reads a color outside the glass theme.
  Color get light => switch (color) {
    GlassDynamicColor(:final color) => color,
    _ => color,
  };
}

@immutable
class GallerySettings {
  const GallerySettings({
    this.renderer = GalleryRenderer.liquid,
    this.brightness,
    this.accent = GalleryAccent.blue,
    this.reduceTransparency = false,
    this.showBorders = false,
    this.crossFade = false,
    this.glassTint,
    this.frameMeter = false,
  });

  final GalleryRenderer renderer;

  /// Null follows the platform.
  final Brightness? brightness;
  final GalleryAccent accent;
  final bool reduceTransparency;
  final bool showBorders;
  final bool crossFade;

  /// The Liquid Glass slider's position, or null to follow the system's.
  final double? glassTint;

  /// Whether the frames a second and the time of a frame show over the app.
  final bool frameMeter;

  GallerySettings copyWith({
    GalleryRenderer? renderer,
    Brightness? Function()? brightness,
    GalleryAccent? accent,
    bool? reduceTransparency,
    bool? showBorders,
    bool? crossFade,
    double? Function()? glassTint,
    bool? frameMeter,
  }) => GallerySettings(
    renderer: renderer ?? this.renderer,
    brightness: brightness == null ? this.brightness : brightness(),
    accent: accent ?? this.accent,
    reduceTransparency: reduceTransparency ?? this.reduceTransparency,
    showBorders: showBorders ?? this.showBorders,
    crossFade: crossFade ?? this.crossFade,
    glassTint: glassTint == null ? this.glassTint : glassTint(),
    frameMeter: frameMeter ?? this.frameMeter,
  );
}

class GallerySettingsScope
    extends InheritedNotifier<ValueNotifier<GallerySettings>> {
  const GallerySettingsScope({
    required ValueNotifier<GallerySettings> super.notifier,
    required super.child,
    super.key,
  });

  static ValueNotifier<GallerySettings> of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<GallerySettingsScope>()!
      .notifier!;

  static void update(
    BuildContext context,
    GallerySettings Function(GallerySettings settings) change,
  ) {
    final notifier = context
        .getInheritedWidgetOfExactType<GallerySettingsScope>()!
        .notifier!;
    notifier.value = change(notifier.value);
  }
}
