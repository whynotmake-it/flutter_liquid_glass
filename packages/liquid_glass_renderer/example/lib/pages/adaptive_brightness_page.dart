import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// Glass chrome that flips between light and dark as content scrolls beneath.
///
/// The scrolling content is the only sampled backdrop. The tab bar samples its
/// whole capsule; each top button samples just its own circle, so they can
/// disagree over content that is light on one side and dark on the other.
class AdaptiveBrightnessPage extends StatefulWidget {
  const AdaptiveBrightnessPage({super.key});

  @override
  State<AdaptiveBrightnessPage> createState() => _AdaptiveBrightnessPageState();
}

class _AdaptiveBrightnessPageState extends State<AdaptiveBrightnessPage> {
  final _source = LiquidGlassBrightnessSource();
  int _tab = 0;

  static const _tabs = [
    CupertinoIcons.house_fill,
    CupertinoIcons.search,
    CupertinoIcons.heart_fill,
    CupertinoIcons.person_fill,
  ];

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return ColoredBox(
      color: const Color(0xffffffff),
      child: Stack(
        children: [
          Positioned.fill(
            child: LiquidGlassBrightnessBackdrop(
              source: _source,
              child: const _Content(),
            ),
          ),
          Positioned.fill(
            child: LiquidGlassLayer(
              useBackdropGroup: true,
              child: Stack(
                children: [
                  Positioned(
                    top: padding.top + 12,
                    left: 16,
                    child: _AdaptiveCircle(
                      source: _source,
                      icon: CupertinoIcons.chevron_back,
                    ),
                  ),
                  Positioned(
                    top: padding.top + 12,
                    right: 16,
                    child: _AdaptiveCircle(
                      source: _source,
                      icon: CupertinoIcons.ellipsis,
                    ),
                  ),
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: padding.bottom + 20,
                    child: _AdaptiveTabBar(
                      source: _source,
                      icons: _tabs,
                      selected: _tab,
                      onSelected: (tab) => setState(() => _tab = tab),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Glyph color that keeps contrast with the backdrop, animated across flips.
class _AdaptiveGlyphs extends StatelessWidget {
  const _AdaptiveGlyphs({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final backdrop = LiquidGlassAdaptiveBrightness.of(context).brightness;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(
        end: backdrop == Brightness.light
            ? const Color(0xff000000)
            : const Color(0xffffffff),
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (context, color, child) => IconTheme(
        data: IconThemeData(color: color, size: 24),
        child: DefaultTextStyle(
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          child: child!,
        ),
      ),
      child: child,
    );
  }
}

class _AdaptiveCircle extends StatelessWidget {
  const _AdaptiveCircle({required this.source, required this.icon});

  final LiquidGlassBrightnessSource source;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassAdaptiveBrightness(
      source: source,
      child: LiquidGlass(
        shape: const LiquidOval(),
        child: SizedBox.square(
          dimension: 48,
          child: _AdaptiveGlyphs(child: Center(child: Icon(icon))),
        ),
      ),
    );
  }
}

class _AdaptiveTabBar extends StatelessWidget {
  const _AdaptiveTabBar({
    required this.source,
    required this.icons,
    required this.selected,
    required this.onSelected,
  });

  final LiquidGlassBrightnessSource source;
  final List<IconData> icons;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassAdaptiveBrightness(
      source: source,
      child: LiquidGlass(
        shape: const LiquidRoundedSuperellipse(borderRadius: 32),
        child: SizedBox(
          height: 64,
          child: _AdaptiveGlyphs(
            child: Row(
              children: [
                for (var i = 0; i < icons.length; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSelected(i),
                      child: AnimatedOpacity(
                        opacity: i == selected ? 1 : .55,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(icons[i]),
                      ),
                    ),
                  ),
                const _LuminanceReadout(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LuminanceReadout extends StatelessWidget {
  const _LuminanceReadout();

  @override
  Widget build(BuildContext context) {
    final estimate = LiquidGlassAdaptiveBrightness.of(context);
    return SizedBox(
      width: 56,
      child: Text(
        'L ${estimate.luminance.toStringAsFixed(2)}\n'
        '${estimate.brightness.name}',
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Alternating light, dark, photo and split sections.
class _Content extends StatelessWidget {
  const _Content();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: const [
        _Section(
          color: Color(0xfff6f5f2),
          title: 'Light article',
          body: _lorem,
        ),
        _Section(
          color: Color(0xff0d0d10),
          title: 'Dark section',
          body: _lorem,
          dark: true,
        ),
        _PhotoSection(),
        _SplitSection(),
        _Section(
          color: Color(0xff7f8084),
          title: 'Mid grey (inside the hysteresis band)',
          body: _lorem,
        ),
        _GradientSection(),
        _Section(
          color: Color(0xffffffff),
          title: 'White',
          body: _lorem,
        ),
        _Section(
          color: Color(0xff1a2a6c),
          title: 'Deep blue',
          body: _lorem,
          dark: true,
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.color,
    required this.title,
    required this.body,
    this.dark = false,
  });

  final Color color;
  final String title;
  final String body;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final text = dark ? const Color(0xffffffff) : const Color(0xff111111);
    return Container(
      color: color,
      padding: const EdgeInsets.fromLTRB(24, 96, 24, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: text,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            body,
            style: TextStyle(color: text, fontSize: 16, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _PhotoSection extends StatelessWidget {
  const _PhotoSection();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/wallpaper.webp',
      height: 640,
      fit: BoxFit.cover,
    );
  }
}

class _SplitSection extends StatelessWidget {
  const _SplitSection();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 560,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: ColoredBox(color: Color(0xff000000))),
          Expanded(child: ColoredBox(color: Color(0xffffffff))),
        ],
      ),
    );
  }
}

class _GradientSection extends StatelessWidget {
  const _GradientSection();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 900,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xff000000), Color(0xffffffff)],
          ),
        ),
      ),
    );
  }
}

const _lorem =
    'Liquid Glass flips small elements between light and dark to keep '
    'glyphs legible. This demo estimates the luminance beneath each piece of '
    'chrome from a tiny, asynchronously read-back rasterization of the '
    'scrolling content and never touches the glass shader. Scroll slowly '
    'across the grey section: hysteresis keeps the glyphs from flickering.\n\n'
    'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod '
    'tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim '
    'veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea '
    'commodo consequat.';
