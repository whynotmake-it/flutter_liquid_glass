import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
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
    super.key,
  });

  final ValueListenable<bool> adaptive;
  final ValueListenable<GlassStyle> style;
  final LiquidGlassBrightnessSource source;

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
          child: const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              children: [
                Row(
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
                Spacer(),
                _MiniPlayer(),
                SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _TabBar()),
                    SizedBox(width: 10),
                    _CircleButton(icon: CupertinoIcons.search, size: 62),
                  ],
                ),
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
  const _CircleButton({required this.icon, this.size = 48});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return _ControlGlass(
      shape: const LiquidOval(),
      child: SizedBox.square(dimension: size, child: Icon(icon)),
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

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer();

  @override
  Widget build(BuildContext context) {
    return _ControlGlass(
      shape: const LiquidRoundedSuperellipse(borderRadius: 28),
      child: Builder(
        builder: (context) => SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
            child: Row(
              children: [
                const _Artwork(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Refraction',
                        maxLines: 1,
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'The Bevels',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  width: 44,
                  child: Icon(CupertinoIcons.play_fill),
                ),
                const SizedBox(
                  width: 44,
                  child: Icon(CupertinoIcons.forward_fill),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 38,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(8)),
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

class _TabBar extends StatefulWidget {
  const _TabBar();

  @override
  State<_TabBar> createState() => _TabBarState();
}

class _TabBarState extends State<_TabBar> {
  static const _tabs = [
    (icon: CupertinoIcons.house_fill, label: 'Home'),
    (icon: CupertinoIcons.square_grid_2x2_fill, label: 'New'),
    (icon: CupertinoIcons.dot_radiowaves_left_right, label: 'Radio'),
    (icon: CupertinoIcons.music_albums_fill, label: 'Library'),
  ];

  var _selected = 0;

  @override
  Widget build(BuildContext context) {
    return _ControlGlass(
      shape: const LiquidRoundedSuperellipse(borderRadius: 31),
      child: Builder(builder: _buildTabs),
    );
  }

  Widget _buildTabs(BuildContext context) {
    final accent = CupertinoTheme.of(context).primaryColor;
    final platter = CupertinoDynamicColor.resolve(
      const CupertinoDynamicColor.withBrightness(
        color: Color(0x14000000),
        darkColor: Color(0x24FFFFFF),
      ),
      context,
    );
    return SizedBox(
      height: 62,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final (index, tab) in _tabs.indexed)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _selected = index),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: index == _selected ? platter : null,
                      borderRadius: BorderRadius.circular(27),
                    ),
                    child: _TabItem(
                      icon: tab.icon,
                      label: tab.label,
                      color: index == _selected ? accent : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}
