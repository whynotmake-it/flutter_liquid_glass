import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/components/component_page.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

GlassMenuItemState _on(bool on) =>
    on ? GlassMenuItemState.on : GlassMenuItemState.off;

class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  var _size = GlassMenuElementSize.large;
  var _icons = true;
  var _sections = true;
  var _favorite = false;
  var _sort = 'Thirst';
  var _more = false;

  List<GlassMenuEntry> _actions() => [
    for (final (title, icon) in const [
      ('Water', CupertinoIcons.drop),
      ('Move', CupertinoIcons.arrow_right_arrow_left),
      ('Share', CupertinoIcons.share),
    ])
      GlassMenuItem(
        title: title,
        icon: Icon(icon),
        iconVisibility: _icons
            ? GlassMenuIconVisibility.automatic
            : GlassMenuIconVisibility.hidden,
        onPressed: () {},
      ),
  ];

  List<GlassMenuEntry> _menu() => [
    if (_sections)
      GlassMenuSection(elementSize: _size, children: _actions())
    else
      ..._actions(),
    GlassMenuItem(
      title: _favorite ? 'Unfavorite' : 'Favorite',
      icon: const Icon(CupertinoIcons.heart),
      selectedIcon: const Icon(CupertinoIcons.heart_fill),
      iconVisibility: _icons
          ? GlassMenuIconVisibility.automatic
          : GlassMenuIconVisibility.hidden,
      state: _on(_favorite),
      onPressed: () => setState(() => _favorite = !_favorite),
    ),
    GlassMenuItem(
      title: 'Compost',
      icon: const Icon(CupertinoIcons.trash),
      iconVisibility: _icons
          ? GlassMenuIconVisibility.automatic
          : GlassMenuIconVisibility.hidden,
      destructive: true,
      onPressed: () {},
    ),
  ];

  @override
  Widget build(BuildContext context) => ComponentPage(
    name: 'GlassMenuItem',
    summary:
        'A menu that grows out of the glass of what opened it: a control '
        'in a GlassMenuAnchor, a bar item, or anything under a '
        'GlassContextMenu.',
    backdrop: Wallpaper.city,
    stageHeight: 130,
    stage: GlassMenuAnchor(
      menuChildren: _menu(),
      builder: (context, controller, child) => GlassButton(
        onPressed: controller.open,
        child: const Text('Open the menu'),
      ),
    ),
    knobs: [
      ToggleKnob(
        'Icons',
        value: _icons,
        onChanged: (on) => setState(() => _icons = on),
      ),
      ToggleKnob(
        'Actions in a section',
        value: _sections,
        onChanged: (on) => setState(() => _sections = on),
      ),
      ChoiceKnob<GlassMenuElementSize>(
        "The section's size",
        value: _size,
        options: const {
          GlassMenuElementSize.small: 'Small',
          GlassMenuElementSize.medium: 'Medium',
          GlassMenuElementSize.large: 'Large',
        },
        onChanged: (size) => setState(() => _size = size),
      ),
    ],
    ideas: [
      Idea(
        'A menu that changes while open',
        'A row with keepsMenuOpen runs its action and stays: here it '
            'shows more rows, and the menu grows on a spring. A '
            'GlassSubmenu unfolds in place.',
        child: Stage(
          backdrop: Wallpaper.dunes,
          height: 96,
          child: GlassMenuAnchor(
            menuChildren: [
              GlassMenuItem(
                title: 'New plant',
                icon: const Icon(CupertinoIcons.plus),
                onPressed: () {},
              ),
              if (_more)
                GlassMenuItem(
                  title: 'New room',
                  icon: const Icon(CupertinoIcons.house),
                  onPressed: () {},
                ),
              GlassMenuItem(
                title: _more ? 'Show less' : 'Show more',
                icon: Icon(
                  _more
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                ),
                keepsMenuOpen: true,
                onPressed: () => setState(() => _more = !_more),
              ),
              GlassSubmenu(
                title: 'Sort by',
                subtitle: _sort,
                icon: const Icon(CupertinoIcons.arrow_up_arrow_down),
                singleSelection: true,
                children: [
                  for (final sort in const ['Thirst', 'Name', 'Room'])
                    GlassMenuItem(
                      title: sort,
                      state: _on(sort == _sort),
                      onPressed: () => setState(() => _sort = sort),
                    ),
                ],
              ),
            ],
            builder: (context, controller, child) => GlassButton(
              onPressed: controller.open,
              child: const Text('Options'),
            ),
          ),
        ),
      ),
      Idea(
        'Hold anything',
        'GlassContextMenu lifts its child out of the page under a long '
            'press and grows the menu beside it.',
        child: Stage(
          height: null,
          child: Row(
            children: [
              for (final wallpaper in const [
                Wallpaper.bloom,
                Wallpaper.dunes,
                Wallpaper.alpine,
              ]) ...[
                Expanded(
                  child: GlassContextMenu(
                    menuChildren: [
                      GlassMenuItem(
                        title: 'Share ${wallpaper.title}',
                        icon: const Icon(CupertinoIcons.share),
                        onPressed: () {},
                      ),
                      GlassMenuItem(
                        title: 'Set as cover',
                        icon: const Icon(CupertinoIcons.photo),
                        onPressed: () {},
                      ),
                      GlassMenuItem(
                        title: 'Delete',
                        icon: const Icon(CupertinoIcons.trash),
                        destructive: true,
                        onPressed: () {},
                      ),
                    ],
                    child: ClipRSuperellipse(
                      borderRadius: BorderRadius.circular(16),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Image(image: wallpaper.image, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                ),
                if (wallpaper != Wallpaper.alpine) const SizedBox(width: 10),
              ],
            ],
          ),
        ),
      ),
    ],
  );
}
