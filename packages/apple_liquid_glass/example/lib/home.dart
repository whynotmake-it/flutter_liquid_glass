import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/components/components_page.dart';
import 'package:apple_liquid_glass_example/glass/glass_page.dart';
import 'package:apple_liquid_glass_example/motion/motion_page.dart';
import 'package:apple_liquid_glass_example/search_page.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

/// The gallery's tabs.
enum GalleryTab {
  /// Every component, live, with its parameters to try.
  components,

  /// The material, a property at a time.
  glass,

  /// Springs, layouts that animate and morphs.
  motion,
}

/// The gallery: a catalog of components first, the material and the motion
/// beside it, and a search over all of it.
class GalleryHome extends StatefulWidget {
  const GalleryHome({super.key});

  @override
  State<GalleryHome> createState() => _GalleryHomeState();
}

class _GalleryHomeState extends State<GalleryHome> {
  var _tab = GalleryTab.components;
  final _search = GlassSearchController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(GalleryTab tab) {
    _search.closeView();
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) => GlassTabScaffold(
    tabBar: GlassTabBar(
      destinations: const [
        GlassTabDestination(
          icon: Icon(CupertinoIcons.square_grid_2x2),
          selectedIcon: Icon(CupertinoIcons.square_grid_2x2_fill),
          label: Text('Components'),
        ),
        GlassTabDestination(
          icon: Icon(CupertinoIcons.drop),
          selectedIcon: Icon(CupertinoIcons.drop_fill),
          label: Text('Glass'),
        ),
        GlassTabDestination(
          icon: Icon(CupertinoIcons.wind),
          label: Text('Motion'),
        ),
      ],
      selectedIndex: _tab.index,
      onDestinationSelected: (index) =>
          setState(() => _tab = GalleryTab.values[index]),
      searchController: _search,
    ),
    tabBuilder: (context, index) => switch (GalleryTab.values[index]) {
      GalleryTab.components => const ComponentsPage(),
      GalleryTab.glass => const GlassPage(),
      GalleryTab.motion => const MotionPage(),
    },
    searchBuilder: (context) =>
        GallerySearchPage(controller: _search, onOpen: _open),
  );
}
