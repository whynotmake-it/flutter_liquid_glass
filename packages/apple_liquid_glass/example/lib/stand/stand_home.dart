import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/motion/motion_page.dart';
import 'package:apple_liquid_glass_example/stand/controls_page.dart';
import 'package:apple_liquid_glass_example/stand/liquid_page.dart';
import 'package:apple_liquid_glass_example/stand/photos_page.dart';
import 'package:apple_liquid_glass_example/stand/present_page.dart';
import 'package:apple_liquid_glass_example/stand/search_page.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

enum StandTab { liquid, controls, present, motion, photos }

/// The pages the device benches drive (lib/perf/app_bench.dart) and the
/// glass budgets count: five tabs kept as they are, so a number measured
/// on them compares with the one before. The gallery people see is
/// `GalleryHome`.

class StandHome extends StatefulWidget {
  const StandHome({super.key});

  @override
  State<StandHome> createState() => _StandHomeState();
}

class _StandHomeState extends State<StandHome> {
  var _tab = StandTab.liquid;
  final _search = GlassSearchController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(StandTab tab) {
    _search.closeView();
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) => GlassTabScaffold(
    tabBar: GlassTabBar(
      destinations: const [
        GlassTabDestination(
          icon: Icon(CupertinoIcons.drop),
          selectedIcon: Icon(CupertinoIcons.drop_fill),
          label: Text('Liquid'),
        ),
        GlassTabDestination(
          icon: Icon(CupertinoIcons.slider_horizontal_3),
          label: Text('Controls'),
        ),
        GlassTabDestination(
          icon: Icon(CupertinoIcons.square_stack_3d_up),
          selectedIcon: Icon(CupertinoIcons.square_stack_3d_up_fill),
          label: Text('Present'),
        ),
        GlassTabDestination(
          icon: Icon(CupertinoIcons.wind),
          label: Text('Motion'),
        ),
        GlassTabDestination(
          icon: Icon(CupertinoIcons.photo_on_rectangle),
          selectedIcon: Icon(CupertinoIcons.photo_fill_on_rectangle_fill),
          label: Text('Photos'),
          badge: GlassBadge.count(6),
        ),
      ],
      selectedIndex: _tab.index,
      onDestinationSelected: (index) =>
          setState(() => _tab = StandTab.values[index]),
      searchController: _search,
    ),
    tabBuilder: (context, index) => switch (StandTab.values[index]) {
      StandTab.liquid => const LiquidPage(),
      StandTab.controls => const ControlsPage(),
      StandTab.present => const PresentPage(),
      StandTab.motion => const MotionPage(),
      StandTab.photos => const PhotosPage(),
    },
    searchBuilder: (context) => SearchPage(controller: _search, onOpen: _open),
  );
}
