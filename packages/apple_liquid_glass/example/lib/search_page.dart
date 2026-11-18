import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/components/components_page.dart';
import 'package:apple_liquid_glass_example/components/surfaces.dart';
import 'package:apple_liquid_glass_example/home.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

/// Everything in the gallery, found by a component's name or a class
/// name: the components, the toys built from surfaces, and the two tabs
/// that explain.
class GallerySearchPage extends StatelessWidget {
  const GallerySearchPage({
    required this.controller,
    required this.onOpen,
    super.key,
  });

  final GlassSearchController controller;

  /// Opens a tab.
  final ValueChanged<GalleryTab> onOpen;

  @override
  Widget build(BuildContext context) {
    void push(Widget page) => Navigator.of(
      context,
      rootNavigator: true,
    ).push(GlassPageRoute<void>(builder: (context) => page));
    final entries = <(IconData, Color, String, String, VoidCallback)>[
      for (final (icon, color, title, classes, page) in ComponentsPage.all)
        (icon, color, title, classes, () => push(page())),
      for (final (icon, color, title, note, page) in SurfacePage.toys)
        (icon, color, title, note, () => push(page())),
      (
        CupertinoIcons.drop_fill,
        GlassColors.systemBlue,
        'Glass',
        'Refraction, clear and regular, tint, outlines, fusing, renderers',
        () => onOpen(GalleryTab.glass),
      ),
      (
        CupertinoIcons.wind,
        GlassColors.systemGray,
        'Motion',
        'Springs, layouts that animate, a control of your own, a replay',
        () => onOpen(GalleryTab.motion),
      ),
    ];
    return GlassPageScaffold(
      backgroundColor: GlassColors.systemGroupedBackground,
      navigationBar: const GlassNavigationBar(largeTitle: Text('Search')),
      child: GlassContentScroll(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final query = controller.text.trim().toLowerCase();
            final found = [
              for (final entry in entries)
                if ('${entry.$3} ${entry.$4}'.toLowerCase().contains(query))
                  entry,
            ];
            return ListView(
              children: [
                if (found.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Text('No Results', textAlign: TextAlign.center),
                  )
                else
                  GlassListSection(
                    header: Text(query.isEmpty ? 'Everything' : 'Results'),
                    children: [
                      for (final (icon, color, title, subtitle, open) in found)
                        GlassListRow(
                          leading: SettingsIcon(icon: icon, color: color),
                          title: Text(title),
                          subtitle: Text(subtitle),
                          accessory: GlassListAccessory.disclosureIndicator,
                          onPressed: open,
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
