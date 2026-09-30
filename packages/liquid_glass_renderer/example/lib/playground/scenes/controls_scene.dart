import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/bottom_bar/ios_bottom_bar.dart';
import 'package:liquid_glass_renderer_example/playground/presets.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/adaptive_controls.dart';

/// Everyday controls: navigation buttons at the top and a bottom bar. Every
/// shape samples the one shared backdrop capture.
///
/// With [adaptive] on, the top controls and the bottom bar each switch
/// between light and dark glass as a group, following the backdrop behind
/// them.
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

  /// Whether the stage renders fake glass, which the bottom bar's loupe
  /// layer has to match.
  final ValueListenable<bool> fake;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([adaptive, style]),
      builder: (context, controls) => AdaptiveScope(
        source: adaptive.value ? source : null,
        style: style.value,
        child: controls!,
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
              topControlsSide,
              topControlsTop,
              topControlsSide + topControlSize + topControlsSpacing,
              0,
            ),
            child: AdaptiveGroup(
              child: Row(
                children: [
                  CircleButton(icon: CupertinoIcons.chevron_left),
                  Spacer(),
                  _ButtonCapsule(
                    icons: [
                      CupertinoIcons.square_arrow_up,
                      CupertinoIcons.ellipsis,
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: _BottomBar(fake: fake),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Distance of the row of glass buttons along the top of the stage from the
/// top of the stage's safe area.
const topControlsTop = 12.0;

/// Distance of the row of glass buttons along the top of the stage from the
/// sides of the stage's safe area.
const topControlsSide = 16.0;

/// Height of the glass buttons along the top of the stage.
const topControlSize = 48.0;

/// Gap between neighboring glass buttons along the top of the stage.
const topControlsSpacing = 8.0;

/// The mini player, tab bar and search button, adapting to the backdrop as
/// one group.
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
    final scope = AdaptiveScope.of(context);
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

class CircleButton extends StatelessWidget {
  const CircleButton({
    required this.icon,
    this.size = topControlSize,
    this.onPressed,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final double size;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final glass = ControlGlass(
      shape: const LiquidOval(),
      child: SizedBox.square(
        dimension: size,
        child: Icon(icon, semanticLabel: semanticLabel),
      ),
    );
    if (onPressed == null) return glass;
    return Semantics(
      button: true,
      child: GestureDetector(onTap: onPressed, child: glass),
    );
  }
}

class _ButtonCapsule extends StatelessWidget {
  const _ButtonCapsule({required this.icons});

  final List<IconData> icons;

  @override
  Widget build(BuildContext context) {
    return ControlGlass(
      shape: const LiquidRoundedSuperellipse(borderRadius: 24),
      child: SizedBox(
        height: topControlSize,
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
