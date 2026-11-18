import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

/// A music app of its own: its tab bar tucks away as the page scrolls down
/// and carries a mini player.
class MusicPage extends StatefulWidget {
  const MusicPage({super.key});

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> {
  static const _tabs = [
    ('Home', CupertinoIcons.house, CupertinoIcons.house_fill),
    (
      'New',
      CupertinoIcons.square_grid_2x2,
      CupertinoIcons.square_grid_2x2_fill,
    ),
    ('Radio', CupertinoIcons.dot_radiowaves_left_right, null),
    ('Library', CupertinoIcons.music_albums, CupertinoIcons.music_albums_fill),
  ];

  var _tab = 0;

  @override
  Widget build(BuildContext context) => GlassTabScaffold(
    tabBar: GlassTabBar(
      destinations: [
        for (final (name, icon, selected) in _tabs)
          GlassTabDestination(
            icon: Icon(icon),
            selectedIcon: selected == null ? null : Icon(selected),
            label: Text(name),
          ),
      ],
      selectedIndex: _tab,
      onDestinationSelected: (index) => setState(() => _tab = index),
      minimizeBehavior: GlassTabBarMinimizeBehavior.onScrollDown,
      bottomAccessory: const _NowPlaying(),
    ),
    tabBuilder: (context, index) => GlassPageScaffold(
      navigationBar: GlassNavigationBar(
        largeTitle: Text(_tabs[index].$1),
        previousPageTitle: 'Present',
      ),
      child: GlassContentScroll(
        child: Builder(
          builder: (context) => GridView.builder(
            padding:
                MediaQuery.paddingOf(context) +
                const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.8,
            ),
            itemCount: 24,
            itemBuilder: (context, i) => _Album(index: i + index * 5),
          ),
        ),
      ),
    ),
  );
}

class _Album extends StatelessWidget {
  const _Album({required this.index});

  static const _titles = [
    'Liquid Dreams',
    'Refraction',
    'Glass Choir',
    'Specular',
    'Lensing',
    'Frost',
    'Meniscus',
  ];

  final int index;

  @override
  Widget build(BuildContext context) {
    final wallpaper = Wallpaper.values[index % Wallpaper.values.length];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRSuperellipse(
            borderRadius: BorderRadius.circular(12),
            child: Image(
              image: wallpaper.image,
              fit: BoxFit.cover,
              width: double.infinity,
              alignment: Alignment((index % 3) - 1.0, (index % 2) * 2 - 1.0),
            ),
          ),
        ),
        const SizedBox(height: 6),
        GlassDefaultTextStyle(
          role: GlassTextRole.subheadline,
          child: Text(
            _titles[index % _titles.length],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// A mini player in the tab bar's accessory, like Music's.
class _NowPlaying extends StatefulWidget {
  const _NowPlaying();

  @override
  State<_NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<_NowPlaying> {
  var _playing = true;

  @override
  Widget build(BuildContext context) {
    final inline =
        GlassTabBar.accessoryPlacementOf(context) ==
        GlassTabAccessoryPlacement.inline;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image(
              image: Wallpaper.bloom.image,
              width: 30,
              height: 30,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: GlassDefaultTextStyle(
              role: GlassTextRole.subheadline,
              child: Text(
                'Liquid Dreams',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _playing = !_playing),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                _playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
              ),
            ),
          ),
          if (!inline)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(CupertinoIcons.forward_fill),
            ),
        ],
      ),
    );
  }
}
