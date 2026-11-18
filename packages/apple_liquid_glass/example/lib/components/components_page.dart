import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/components/bars.dart';
import 'package:apple_liquid_glass_example/components/controls.dart';
import 'package:apple_liquid_glass_example/components/lists.dart';
import 'package:apple_liquid_glass_example/components/menus.dart';
import 'package:apple_liquid_glass_example/components/pickers.dart';
import 'package:apple_liquid_glass_example/components/presentations.dart';
import 'package:apple_liquid_glass_example/components/surfaces.dart';
import 'package:apple_liquid_glass_example/gallery_bar.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

/// A component of the catalog: its icon, its plain name, the classes it is
/// in the package, and its page.
typedef Component = (IconData, Color, String, String, Widget Function());

/// The gallery's home: every component of the package, each a row that
/// opens the component live, with its parameters to try and what can be
/// made of it.
class ComponentsPage extends StatelessWidget {
  const ComponentsPage({super.key});

  static const sections = <(String, List<Component>)>[
    (
      'Material',
      [
        (
          CupertinoIcons.drop_fill,
          GlassColors.systemBlue,
          'Surface',
          'GlassSurface, GlassGroup, Glass',
          SurfacePage.new,
        ),
      ],
    ),
    (
      'Controls',
      [
        (
          CupertinoIcons.capsule_fill,
          GlassColors.systemBlue,
          'Button',
          'GlassButton',
          ButtonPage.new,
        ),
        (
          CupertinoIcons.power,
          GlassColors.systemGreen,
          'Switch',
          'GlassSwitch',
          SwitchPage.new,
        ),
        (
          CupertinoIcons.slider_horizontal_3,
          GlassColors.systemOrange,
          'Slider',
          'GlassSlider',
          SliderPage.new,
        ),
        (
          CupertinoIcons.plus_slash_minus,
          GlassColors.systemGray,
          'Stepper',
          'GlassStepper',
          StepperPage.new,
        ),
        (
          CupertinoIcons.rectangle_split_3x1_fill,
          Color(0xFF5E5CE6),
          'Segmented control',
          'GlassSegmentedControl',
          SegmentedPage.new,
        ),
        (
          CupertinoIcons.ellipsis,
          Color(0xFF40C8E0),
          'Page control',
          'GlassPageControl',
          PageControlPage.new,
        ),
      ],
    ),
    (
      'Content',
      [
        (
          CupertinoIcons.list_bullet,
          GlassColors.systemGray,
          'List',
          'GlassListSection, GlassListRow, GlassSwipeActions',
          ListPage.new,
        ),
        (
          CupertinoIcons.calendar,
          GlassColors.systemRed,
          'Date picker',
          'GlassCompactDatePicker, GlassDatePicker',
          DatePickerPage.new,
        ),
        (
          CupertinoIcons.search,
          GlassColors.systemGray,
          'Search field',
          'GlassSearchField',
          SearchFieldPage.new,
        ),
        (
          CupertinoIcons.app_badge_fill,
          GlassColors.systemRed,
          'Badge',
          'GlassBadge',
          BadgePage.new,
        ),
      ],
    ),
    (
      'Menus and presentations',
      [
        (
          CupertinoIcons.ellipsis_circle_fill,
          Color(0xFF5E5CE6),
          'Menu',
          'GlassMenuAnchor, GlassMenuItem, GlassSubmenu, GlassContextMenu',
          MenuPage.new,
        ),
        (
          CupertinoIcons.exclamationmark_bubble_fill,
          Color(0xFFFF375F),
          'Alert',
          'showGlassAlert, showGlassActionSheet',
          AlertPage.new,
        ),
        (
          CupertinoIcons.rectangle_stack_fill,
          Color(0xFF40C8E0),
          'Sheet',
          'showGlassSheet',
          SheetPage.new,
        ),
        (
          CupertinoIcons.bubble_middle_bottom_fill,
          GlassColors.systemOrange,
          'Popover',
          'showGlassPopover',
          PopoverPage.new,
        ),
      ],
    ),
    (
      'Bars',
      [
        (
          CupertinoIcons.rectangle_dock,
          Color(0xFFBF5AF2),
          'Navigation bar and toolbar',
          'GlassNavigationBar, GlassToolbar, GlassPageScaffold',
          NavigationBarPage.new,
        ),
        (
          CupertinoIcons.square_split_1x2_fill,
          GlassColors.systemBlue,
          'Tab bar',
          'GlassTabBar, GlassTabScaffold',
          TabBarPage.new,
        ),
      ],
    ),
  ];

  /// Every component, in the catalog's order.
  static List<Component> get all => [
    for (final (_, components) in sections) ...components,
  ];

  @override
  Widget build(BuildContext context) => GlassPageScaffold(
    backgroundColor: GlassColors.systemGroupedBackground,
    navigationBar: GlassNavigationBar(
      largeTitle: const Text('Components'),
      trailing: galleryItems(context),
    ),
    child: GlassContentScroll(
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              'Open one to try it: the component itself, its parameters '
              'to turn, and what can be made of it. The drop in the bar '
              'draws everything flat or in glass.',
              style: TextStyle(
                color: GlassDynamicColor.resolve(
                  GlassColors.secondaryLabel,
                  context,
                ),
                fontSize: 16,
                height: 1.3,
              ),
            ),
          ),
          for (final (header, components) in sections)
            GlassListSection(
              header: Text(header),
              children: [
                for (final (icon, color, title, classes, page) in components)
                  GlassListRow(
                    leading: SettingsIcon(icon: icon, color: color),
                    title: Text(title),
                    subtitle: Text(classes),
                    accessory: GlassListAccessory.disclosureIndicator,
                    onPressed: () => Navigator.of(
                      context,
                    ).push(GlassPageRoute<void>(builder: (context) => page())),
                  ),
              ],
            ),
        ],
      ),
    ),
  );
}
