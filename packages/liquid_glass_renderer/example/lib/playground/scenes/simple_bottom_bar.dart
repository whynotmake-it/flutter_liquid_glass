import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/adaptive_controls.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/controls_scene.dart';

/// A mini player above a tab bar and a search button, adapting to the
/// backdrop as one group.
class SimpleBottomBar extends StatelessWidget {
  const SimpleBottomBar({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdaptiveGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniPlayer(),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _TabBar()),
              SizedBox(width: 10),
              CircleButton(icon: CupertinoIcons.search, size: 62),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer();

  @override
  Widget build(BuildContext context) {
    return ControlGlass(
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
    return ControlGlass(
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
