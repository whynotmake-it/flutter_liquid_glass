import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/bottom_bar/ios_bottom_bar.dart';
import 'package:liquid_glass_renderer_example/playground/presets.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/draggable_glass.dart';

/// Everyday controls: navigation buttons, a mini player, a tab bar and a
/// search button. Every shape samples the one shared backdrop capture.
///
/// With [adaptive] on, each control estimates the brightness of the backdrop
/// behind it and switches between light and dark glass on its own.
class ControlsScene extends StatelessWidget {
  const ControlsScene({
    required this.adaptive,
    required this.style,
    required this.source,
    required this.fake,
    super.key,
  });

  final ValueListenable<bool> adaptive;
  final ValueListenable<GlassStyle> style;
  final LiquidGlassBrightnessSource source;
  final ValueListenable<bool> fake;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([adaptive, style]),
      builder: (context, controls) => _AdaptiveScope(
        source: adaptive.value ? source : null,
        style: style.value,
        child: controls!,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              children: [
                const Row(
                  children: [
                    _CircleButton(icon: CupertinoIcons.chevron_left),
                    Spacer(),
                    _ButtonCapsule(
                      icons: [
                        CupertinoIcons.square_arrow_up,
                        CupertinoIcons.ellipsis,
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                _BottomBar(fake: fake),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdaptiveScope extends InheritedWidget {
  const _AdaptiveScope({
    required this.source,
    required this.style,
    required super.child,
  });

  /// The backdrop to sample, or `null` to follow the app brightness.
  final LiquidGlassBrightnessSource? source;
  final GlassStyle style;

  static _AdaptiveScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AdaptiveScope>()!;

  @override
  bool updateShouldNotify(_AdaptiveScope oldWidget) =>
      source != oldWidget.source || style != oldWidget.style;
}

/// Glass for one control, with glyphs that stay legible on it.
///
/// Without an adaptive source the shape inherits the layer's appearance.
class _ControlGlass extends StatelessWidget {
  const _ControlGlass({required this.shape, required this.child});

  final LiquidShape shape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = _AdaptiveScope.of(context);
    final source = scope.source;
    if (source == null) return _glass(context, null);
    return LiquidGlassAdaptiveBrightness(
      source: source,
      builder: (context, estimate, _) => CupertinoTheme(
        data: CupertinoTheme.of(
          context,
        ).copyWith(brightness: estimate.brightness),
        child: Builder(
          builder: (context) =>
              _glass(context, scope.style.appearance(estimate.brightness)),
        ),
      ),
    );
  }

  Widget _glass(BuildContext context, LiquidGlassAppearance? appearance) {
    final glyph = CupertinoColors.label.resolveFrom(context);
    return LiquidStretch(
      child: LiquidGlass(
        shape: shape,
        appearance: appearance,
        shadows: glassShadows,
        child: IconTheme(
          data: IconThemeData(color: glyph, size: 22),
          child: DefaultTextStyle(
            style: TextStyle(color: glyph, fontSize: 15, letterSpacing: -0.2),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _ControlGlass(
      shape: const LiquidOval(),
      child: SizedBox.square(dimension: 48, child: Icon(icon)),
    );
  }
}

class _ButtonCapsule extends StatelessWidget {
  const _ButtonCapsule({required this.icons});

  final List<IconData> icons;

  @override
  Widget build(BuildContext context) {
    return _ControlGlass(
      shape: const LiquidRoundedSuperellipse(borderRadius: 24),
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final icon in icons) SizedBox(width: 42, child: Icon(icon)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tab bar, search button and mini player, sharing one brightness
/// estimate when adaptive.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.fake});

  final ValueListenable<bool> fake;

  static const _tabs = [
    BottomBarTab(icon: CupertinoIcons.house_fill, label: 'Home'),
    BottomBarTab(icon: CupertinoIcons.square_grid_2x2_fill, label: 'New'),
    BottomBarTab(
      icon: CupertinoIcons.dot_radiowaves_left_right,
      label: 'Radio',
    ),
    BottomBarTab(icon: CupertinoIcons.music_albums_fill, label: 'Library'),
  ];

  @override
  Widget build(BuildContext context) {
    final scope = _AdaptiveScope.of(context);
    return ValueListenableBuilder(
      valueListenable: fake,
      builder: (context, fake, _) => IosBottomBar(
        tabs: _tabs,
        accessory: const NowPlayingAccessory(),
        brightnessSource: scope.source,
        appearanceFor: scope.style.appearance,
        fake: fake,
      ),
    );
  }
}
