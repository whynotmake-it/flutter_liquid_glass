import 'package:cupertino_ui/cupertino_ui.dart';
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
/// ambient [LiquidGlassLayer].
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
    this.fake = false,
    this.loupeSettings = LoupeTabBar.defaultLoupeSettings,
    super.key,
  });

  static const barHeight = 62.0;
  static const accessoryHeight = 48.0;
  static const spacing = 8.0;
  static const accessorySpacing = 8.0;

  /// Below both gaps even while the tab bar swells under the finger, so
  /// segments only merge once pulled toward each other.
  static const blend = 5.0;

  final List<BottomBarTab> tabs;
  final int initialIndex;
  final ValueChanged<int>? onSelected;

  /// Content of the accessory capsule above the tab bar.
  final Widget? accessory;
  final VoidCallback? onAccessoryTap;

  final IconData trailingIcon;
  final VoidCallback? onTrailingTap;

  /// Whether the parent layer renders fake glass.
  final bool fake;

  /// See [LoupeTabBar.loupeSettings].
  final LiquidGlassSettings loupeSettings;

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    return LiquidGlassBlendGroup(
      blend: blend,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (accessory case final accessory?) ...[
            _GlassButton(
              shape: const LiquidRoundedSuperellipse(
                radius: accessoryHeight / 2,
              ),
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
                  shadows: glassShadows,
                  fake: fake,
                  loupeSettings: loupeSettings,
                  tint: theme.primaryColor,
                  tintBrightness: CupertinoTheme.brightnessOf(context),
                ),
              ),
              const SizedBox(width: spacing),
              _GlassButton(
                shape: const LiquidOval(),
                onTap: onTrailingTap,
                child: SizedBox.square(
                  dimension: barHeight,
                  child: Icon(trailingIcon, size: 28),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.shape,
    required this.child,
    this.onTap,
  });

  final LiquidShape shape;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: TouchGlass(
        shape: shape,
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
