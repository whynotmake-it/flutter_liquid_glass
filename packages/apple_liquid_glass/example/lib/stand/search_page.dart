import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/stand/stand_home.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

/// The page of the tab bar's search tab: everything the gallery shows,
/// filtered as you type, each a tap away.
class SearchPage extends StatelessWidget {
  const SearchPage({required this.controller, required this.onOpen, super.key});

  final GlassSearchController controller;
  final ValueChanged<StandTab> onOpen;

  static const _features = [
    (
      'Glass drops',
      'Fusing, lift and touch glow',
      StandTab.liquid,
      CupertinoIcons.drop_fill,
    ),
    (
      'Renderers',
      'Liquid, fake and flat glass',
      StandTab.liquid,
      CupertinoIcons.cube_fill,
    ),
    (
      'Page control',
      'Over a photo carousel',
      StandTab.controls,
      CupertinoIcons.circle_grid_3x3_fill,
    ),
    (
      'Switch',
      'The liquid knob',
      StandTab.controls,
      CupertinoIcons.switch_camera_solid,
    ),
    (
      'Slider',
      'Continuous and with ticks',
      StandTab.controls,
      CupertinoIcons.slider_horizontal_3,
    ),
    (
      'Stepper',
      'Minus and plus on one glass',
      StandTab.controls,
      CupertinoIcons.plus_slash_minus,
    ),
    (
      'Segmented control',
      'A lens slides between segments',
      StandTab.controls,
      CupertinoIcons.rectangle_split_3x1_fill,
    ),
    (
      'Buttons',
      'Glass, prominent and clear',
      StandTab.controls,
      CupertinoIcons.capsule_fill,
    ),
    (
      'Date picker',
      'Compact, inline and wheels',
      StandTab.controls,
      CupertinoIcons.calendar,
    ),
    (
      'Lists',
      'Grouped rows and accessories',
      StandTab.controls,
      CupertinoIcons.list_bullet,
    ),
    (
      'Animated layouts',
      'Notes, chips, a grid and a list',
      StandTab.motion,
      CupertinoIcons.square_grid_2x2_fill,
    ),
    (
      'Own presentation',
      'A peek and a reactions bar',
      StandTab.motion,
      CupertinoIcons.rectangle_on_rectangle,
    ),
    (
      'Slow replay',
      'A touch replayed at 0.1x',
      StandTab.motion,
      CupertinoIcons.play_circle_fill,
    ),
    (
      'Menus',
      'Sections, submenus, palettes',
      StandTab.present,
      CupertinoIcons.ellipsis_circle_fill,
    ),
    (
      'Context menu',
      'Hold a photo',
      StandTab.present,
      CupertinoIcons.hand_draw_fill,
    ),
    (
      'Alert',
      'And the action sheet',
      StandTab.present,
      CupertinoIcons.exclamationmark_bubble_fill,
    ),
    (
      'Popover',
      'Anchored to its button',
      StandTab.present,
      CupertinoIcons.text_bubble_fill,
    ),
    (
      'Sheet',
      'Detents and a guarded draft',
      StandTab.present,
      CupertinoIcons.rectangle_dock,
    ),
    (
      'Zoom transition',
      'A photo grows into its page',
      StandTab.photos,
      CupertinoIcons.arrow_up_left_arrow_down_right,
    ),
    (
      'Toolbar',
      'Glass items that fuse',
      StandTab.photos,
      CupertinoIcons.rectangle_3_offgrid_fill,
    ),
    (
      'Tab bar',
      'Minimizes on scroll, with an accessory',
      StandTab.present,
      CupertinoIcons.square_grid_2x2_fill,
    ),
    (
      'Control Center',
      'Modules, toggles and tall sliders',
      StandTab.present,
      CupertinoIcons.slider_horizontal_3,
    ),
    (
      'Lock Screen',
      'Widgets and a stack of notifications',
      StandTab.present,
      CupertinoIcons.lock_fill,
    ),
    (
      'Lens',
      'Drag glass over text and a photo',
      StandTab.present,
      CupertinoIcons.search,
    ),
  ];

  @override
  Widget build(BuildContext context) => GlassPageScaffold(
    backgroundColor: GlassColors.systemGroupedBackground,
    navigationBar: const GlassNavigationBar(largeTitle: Text('Search')),
    child: GlassContentScroll(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final query = controller.text.trim().toLowerCase();
          final found = [
            for (final feature in _features)
              if ('${feature.$1} ${feature.$2}'.toLowerCase().contains(query))
                feature,
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
                    for (final (title, subtitle, tab, icon) in found)
                      GlassListRow(
                        leading: SettingsIcon(
                          icon: icon,
                          color: switch (tab) {
                            StandTab.liquid => GlassColors.systemBlue,
                            StandTab.controls => GlassColors.systemGreen,
                            StandTab.present => GlassColors.systemOrange,
                            StandTab.motion => GlassColors.systemGray,
                            StandTab.photos => GlassColors.systemRed,
                          },
                        ),
                        title: Text(title),
                        subtitle: Text(subtitle),
                        accessory: GlassListAccessory.disclosureIndicator,
                        onPressed: () => onOpen(tab),
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
