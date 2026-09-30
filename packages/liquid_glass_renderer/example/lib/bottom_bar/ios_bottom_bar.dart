import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/bottom_bar/loupe_tab_bar.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/draggable_glass.dart';
import 'package:motor/motor.dart';

export 'package:liquid_glass_renderer_example/bottom_bar/loupe_tab_bar.dart'
    show BottomBarTab;

/// The iOS 27 bottom bar: an optional accessory capsule (a mini player, say)
/// above a [LoupeTabBar] and a round trailing button.
///
/// All segments are grouped glass in one [LiquidGlassBlendGroup] on the
/// ambient [LiquidGlassLayer]. At rest the gaps are wider than the blend
/// distance so the segments stay apart; pulling one toward another stretches
/// it across the gap and they merge.
///
/// With a [brightnessSource], the whole bar is one adaptive brightness group:
/// a single [LiquidGlassAdaptiveBrightness] samples the bounds of every
/// segment together, so the accessory, the tab bar and the button always
/// flip between light and dark at the same time, as they do on iOS.
///
/// Tab bar interaction details (the loupe, masked tint and icon scale) are
/// informed by `GlassTabBar` in
/// [liquid_glass_widgets](https://github.com/sdegenaar/liquid_glass_widgets)
/// by Sebastian Degenaar, reimplemented here on paint-time listenables.
class IosBottomBar extends StatelessWidget {
  const IosBottomBar({
    required this.tabs,
    this.initialIndex = 0,
    this.onSelected,
    this.accessory,
    this.onAccessoryTap,
    this.trailingIcon = CupertinoIcons.search,
    this.onTrailingTap,
    this.brightnessSource,
    this.appearanceFor,
    this.fake = false,
    this.loupeSettings = LoupeTabBar.defaultLoupeSettings,
    super.key,
  });

  static const barHeight = 62.0;
  static const accessoryHeight = 48.0;
  static const spacing = 14.0;
  static const accessorySpacing = 10.0;

  /// Below both gaps even while the tab bar swells under the finger, so
  /// segments only merge once pulled toward each other.
  static const blend = 5.0;

  static const shadows = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, 8)),
  ];

  final List<BottomBarTab> tabs;
  final int initialIndex;
  final ValueChanged<int>? onSelected;

  /// Content of the accessory capsule above the tab bar.
  final Widget? accessory;
  final VoidCallback? onAccessoryTap;

  final IconData trailingIcon;
  final VoidCallback? onTrailingTap;

  /// The backdrop the bar estimates its brightness from, or `null` to follow
  /// the ambient brightness and inherit the layer's appearance.
  final LiquidGlassBrightnessSource? brightnessSource;

  /// Appearance of every segment for an estimated backdrop brightness.
  final LiquidGlassAppearance Function(Brightness brightness)? appearanceFor;

  /// Whether the parent layer renders fake glass.
  final bool fake;

  /// See [LoupeTabBar.loupeSettings].
  final LiquidGlassSettings loupeSettings;

  @override
  Widget build(BuildContext context) {
    // The selected tab's tint blends with the glass per pixel, so it keeps
    // the app's appearance instead of following the lagging estimate.
    final theme = CupertinoTheme.of(context);
    final tint = (theme.primaryColor, CupertinoTheme.brightnessOf(context));
    final source = brightnessSource;
    if (source == null) return _buildBar(null, tint);
    return LiquidGlassAdaptiveBrightness(
      source: source,
      builder: (context, estimate, _) => CupertinoTheme(
        data: CupertinoTheme.of(
          context,
        ).copyWith(brightness: estimate.brightness),
        child: _buildBar(
          appearanceFor?.call(estimate.brightness),
          tint,
        ),
      ),
    );
  }

  Widget _buildBar(
    LiquidGlassAppearance? appearance,
    (Color, Brightness) tint,
  ) {
    return LiquidGlassBlendGroup(
      blend: blend,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (accessory case final accessory?) ...[
            _GlassButton(
              shape: const LiquidRoundedSuperellipse(
                borderRadius: accessoryHeight / 2,
              ),
              appearance: appearance,
              interactionScale: 1.02,
              onTap: onAccessoryTap,
              child: SizedBox(height: accessoryHeight, child: accessory),
            ),
            const SizedBox(height: accessorySpacing),
          ],
          Row(
            children: [
              Expanded(
                child: LoupeTabBar(
                  tabs: tabs,
                  selectedIndex: initialIndex,
                  onSelected: onSelected,
                  appearance: appearance,
                  shadows: shadows,
                  fake: fake,
                  loupeSettings: loupeSettings,
                  tint: tint.$1,
                  tintBrightness: tint.$2,
                ),
              ),
              const SizedBox(width: spacing),
              _GlassButton(
                shape: const LiquidOval(),
                appearance: appearance,
                onTap: onTrailingTap,
                child: SizedBox.square(
                  dimension: barHeight,
                  child: Icon(trailingIcon, size: 24),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A grouped glass segment that swells and stretches under the finger.
class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.shape,
    required this.appearance,
    required this.child,
    this.interactionScale = 1.05,
    this.onTap,
  });

  final LiquidShape shape;
  final LiquidGlassAppearance? appearance;
  final double interactionScale;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: LiquidStretch(
        interactionScale: interactionScale,
        child: LiquidGlass.grouped(
          shape: shape,
          appearance: appearance,
          shadows: IosBottomBar.shadows,
          child: GlowContent(
            child: MotionBuilder(
              motion: const CupertinoMotion.smooth(),
              converter: const ColorRgbMotionConverter(),
              value: CupertinoColors.label.resolveFrom(context),
              builder: (context, glyph, child) => IconTheme(
                data: IconThemeData(color: glyph, size: 22),
                child: DefaultTextStyle(
                  style: TextStyle(
                    color: glyph,
                    fontSize: 15,
                    letterSpacing: -0.2,
                  ),
                  child: child!,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Mini player content for the bottom bar accessory.
class NowPlayingAccessory extends StatelessWidget {
  const NowPlayingAccessory({
    this.title = 'Refraction',
    this.subtitle = 'The Bevels',
    super.key,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 6, 0),
      child: Row(
        children: [
          const _Artwork(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 40, child: Icon(CupertinoIcons.play_fill)),
          const SizedBox(width: 40, child: Icon(CupertinoIcons.forward_fill)),
        ],
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 32,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(7)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF6A3D), Color(0xFFD9236B), Color(0xFF5B2BE0)],
          ),
        ),
      ),
    );
  }
}
