import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/stand/music_page.dart';
import 'package:apple_liquid_glass_example/stand/video_page.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

/// Menus that grow out of their buttons, and every presentation: alerts,
/// action sheets, popovers, sheets and context menus.
class PresentPage extends StatefulWidget {
  const PresentPage({super.key});

  @override
  State<PresentPage> createState() => _PresentPageState();
}

enum _Sort { date, name, size }

enum _Tag {
  red('Red', Color(0xFFFF3B30)),
  orange('Orange', Color(0xFFFF9500)),
  yellow('Yellow', Color(0xFFFFCC00)),
  green('Green', Color(0xFF34C759)),
  blue('Blue', Color(0xFF007AFF)),
  purple('Purple', Color(0xFFAF52DE));

  const _Tag(this.title, this.color);

  final String title;
  final Color color;
}

class _PresentPageState extends State<PresentPage> {
  var _sort = _Sort.date;
  var _ascending = false;
  var _tag = _Tag.blue;
  var _favorite = false;
  var _more = false;
  var _status = 'Hold a photo or open a menu';

  void _say(String status) => setState(() {
    _status = status;
    _more = false;
  });

  GlassMenuItemState _on(bool on) =>
      on ? GlassMenuItemState.on : GlassMenuItemState.off;

  List<GlassMenuEntry> _moreMenu() => [
    GlassMenuSection(
      elementSize: GlassMenuElementSize.medium,
      children: [
        GlassMenuItem(
          title: 'Copy',
          icon: const Icon(CupertinoIcons.doc_on_doc),
          onPressed: () => _say('Copied'),
        ),
        GlassMenuItem(
          title: 'Share',
          icon: const Icon(CupertinoIcons.share),
          onPressed: () => _say('Shared'),
        ),
        GlassMenuItem(
          title: _favorite ? 'Unfavorite' : 'Favorite',
          icon: const Icon(CupertinoIcons.heart),
          selectedIcon: const Icon(CupertinoIcons.heart_fill),
          state: _on(_favorite),
          onPressed: () => setState(() => _favorite = !_favorite),
        ),
      ],
    ),
    GlassMenuItem(
      title: 'Select',
      icon: const Icon(CupertinoIcons.checkmark_circle),
      onPressed: () => _say('Selecting'),
    ),
    GlassMenuItem(
      title: 'New Folder',
      icon: const Icon(CupertinoIcons.folder_badge_plus),
      onPressed: () => _say('New folder'),
    ),
    if (_more) ...[
      GlassMenuItem(
        title: 'Duplicate',
        icon: const Icon(CupertinoIcons.plus_square_on_square),
        onPressed: () => _say('Duplicated'),
      ),
      GlassMenuItem(
        title: 'Rename',
        icon: const Icon(CupertinoIcons.pencil),
        onPressed: () => _say('Renamed'),
      ),
      GlassMenuItem(
        title: 'Show Less',
        icon: const Icon(CupertinoIcons.chevron_up),
        keepsMenuOpen: true,
        onPressed: () => setState(() => _more = false),
      ),
    ] else
      GlassMenuItem(
        title: 'Show More',
        icon: const Icon(CupertinoIcons.chevron_down),
        keepsMenuOpen: true,
        onPressed: () => setState(() => _more = true),
      ),
    GlassSubmenu(
      title: 'Sort By',
      subtitle: switch (_sort) {
        _Sort.date => 'Date',
        _Sort.name => 'Name',
        _Sort.size => 'Size',
      },
      icon: const Icon(CupertinoIcons.arrow_up_arrow_down),
      children: [
        GlassMenuSection(
          singleSelection: true,
          children: [
            for (final sort in _Sort.values)
              GlassMenuItem(
                title: switch (sort) {
                  _Sort.date => 'Date',
                  _Sort.name => 'Name',
                  _Sort.size => 'Size',
                },
                state: _on(sort == _sort),
                onPressed: () => setState(() => _sort = sort),
              ),
          ],
        ),
        GlassMenuSection(
          singleSelection: true,
          children: [
            GlassMenuItem(
              title: 'Ascending',
              state: _on(_ascending),
              onPressed: () => setState(() => _ascending = true),
            ),
            GlassMenuItem(
              title: 'Descending',
              state: _on(!_ascending),
              onPressed: () => setState(() => _ascending = false),
            ),
          ],
        ),
      ],
    ),
    GlassMenuSection(
      title: 'Tag',
      palette: true,
      singleSelection: true,
      children: [
        for (final tag in _Tag.values)
          GlassMenuItem(
            title: tag.title,
            icon: const Icon(CupertinoIcons.circle_fill),
            iconColor: tag.color,
            state: _on(tag == _tag),
            onPressed: () => setState(() => _tag = tag),
          ),
      ],
    ),
    GlassSubmenu(
      title: 'Send To',
      icon: const Icon(CupertinoIcons.paperplane),
      children: [
        GlassMenuDeferred(
          () async {
            await Future<void>.delayed(const Duration(milliseconds: 900));
            return [
              for (final name in const ['Maya', 'Leo', 'Ines', 'Theo'])
                GlassMenuItem(
                  title: name,
                  icon: const Icon(CupertinoIcons.person_crop_circle),
                  onPressed: () => _say('Sent to $name'),
                ),
            ];
          },
          loadingTitle: 'Finding people...',
        ),
      ],
    ),
    GlassMenuSection(
      children: [
        GlassMenuItem(
          title: 'Delete',
          icon: const Icon(CupertinoIcons.trash),
          destructive: true,
          onPressed: () => unawaited(_confirmDelete()),
        ),
      ],
    ),
  ];

  List<GlassMenuEntry> _photoMenu(Wallpaper wallpaper) => [
    GlassMenuItem(
      title: 'Copy',
      icon: const Icon(CupertinoIcons.doc_on_doc),
      onPressed: () => _say('Copied ${wallpaper.title}'),
    ),
    GlassMenuItem(
      title: 'Share',
      icon: const Icon(CupertinoIcons.share),
      onPressed: () => _say('Shared ${wallpaper.title}'),
    ),
    GlassMenuItem(
      title: 'Favorite',
      icon: const Icon(CupertinoIcons.heart),
      onPressed: () => _say('${wallpaper.title} is a favorite'),
    ),
    GlassMenuSection(
      children: [
        GlassMenuItem(
          title: 'Delete',
          icon: const Icon(CupertinoIcons.trash),
          destructive: true,
          onPressed: () => _say('Deleted ${wallpaper.title}'),
        ),
      ],
    ),
  ];

  Future<void> _confirmDelete() async {
    await showGlassAlert(
      context,
      title: const Text('Delete 24 photos?'),
      message: const Text(
        'They move to Recently Deleted and stay there for 30 days.',
      ),
      actions: [
        const GlassAlertAction.cancel(child: Text('Cancel')),
        GlassAlertAction.destructive(
          child: const Text('Delete'),
          onPressed: () => _say('Deleted 24 photos'),
        ),
      ],
    );
  }

  Future<void> _alert() async {
    await showGlassAlert(
      context,
      title: const Text('Allow notifications?'),
      message: const Text('Alerts, sounds and badges about your library.'),
      actions: [
        const GlassAlertAction(child: Text("Don't Allow")),
        GlassAlertAction(
          isDefaultAction: true,
          child: const Text('Allow'),
          onPressed: () => _say('Notifications allowed'),
        ),
      ],
    );
  }

  Future<void> _styledAlert() async {
    await showGlassAlert(
      context,
      title: const Text('Join the beta?'),
      message: const Text('New features arrive a few weeks early.'),
      style: const GlassAlertStyle(
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        actionColor: Color(0xFFFF9500),
        defaultActionFillColor: Color(0xFFFF9500),
      ),
      actions: [
        const GlassAlertAction(child: Text('Not Now')),
        GlassAlertAction(
          isDefaultAction: true,
          child: const Text('Join'),
          onPressed: () => _say('Joined the beta'),
        ),
      ],
    );
  }

  Future<void> _actionSheet() async {
    await showGlassActionSheet(
      context,
      title: const Text('Save the edited photo?'),
      actions: [
        GlassAlertAction(
          child: const Text('Save as New'),
          onPressed: () => _say('Saved as new'),
        ),
        GlassAlertAction(
          child: const Text('Replace Original'),
          onPressed: () => _say('Replaced'),
        ),
        GlassAlertAction.destructive(
          child: const Text('Discard Changes'),
          onPressed: () => _say('Discarded'),
        ),
        const GlassAlertAction.cancel(child: Text('Cancel')),
      ],
    );
  }

  Future<void> _sheet() async {
    await showGlassSheet<void>(
      context,
      detents: const [GlassSheetDetent.medium, GlassSheetDetent.large],
      largestUndimmedDetent: GlassSheetDetent.medium,
      showDragHandle: true,
      builder: (context) => const _PlacesSheet(),
    );
  }

  Future<void> _styledSheet() async {
    await showGlassSheet<void>(
      context,
      detents: const [GlassSheetDetent.fitted],
      showDragHandle: true,
      style: const GlassSheetStyle(
        backgroundColor: GlassDynamicColor.withBrightness(
          color: Color(0xFFFFF4E5),
          darkColor: Color(0xFF3A2A12),
        ),
        dragHandleColor: Color(0xFFFF9500),
      ),
      builder: (context) => const _RecipeSheet(),
    );
  }

  Future<void> _formSheet() async {
    await showGlassSheet<void>(
      context,
      isDismissible: false,
      onDismissAttempt: () => unawaited(_discard()),
      builder: (context) => const _ComposeSheet(),
    );
  }

  Future<void> _discard() async {
    const discard = GlassAlertAction.destructive(
      child: Text('Discard Changes'),
    );
    final action = await showGlassActionSheet(
      context,
      actions: [
        discard,
        const GlassAlertAction.cancel(child: Text('Keep Editing')),
      ],
    );
    if (action == discard && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => GlassPageScaffold(
    backgroundColor: GlassColors.systemGroupedBackground,
    navigationBar: GlassNavigationBar(
      largeTitle: const Text('Present'),
      trailing: [settingsItem(context)],
    ),
    child: GlassContentScroll(
      child: ListView(
        children: [
          _hero(),
          GlassListSection(
            header: const Text('Context menus'),
            footer: const Text(
              'Hold a photo: it lifts out of the page and its menu grows '
              'beside it.',
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    for (final wallpaper in const [
                      Wallpaper.bloom,
                      Wallpaper.dunes,
                      Wallpaper.alpine,
                    ]) ...[
                      Expanded(
                        child: GlassContextMenu(
                          menuChildren: _photoMenu(wallpaper),
                          child: ClipRSuperellipse(
                            borderRadius: BorderRadius.circular(16),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Image(
                                image: wallpaper.image,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (wallpaper != Wallpaper.alpine)
                        const SizedBox(width: 10),
                    ],
                  ],
                ),
              ),
            ],
          ),
          GlassListSection(
            header: const Text('Alerts'),
            children: [
              _row(
                CupertinoIcons.bell_fill,
                GlassColors.systemRed,
                'Alert',
                _alert,
              ),
              _row(
                CupertinoIcons.trash_fill,
                GlassColors.systemOrange,
                'Destructive alert',
                _confirmDelete,
              ),
              _row(
                CupertinoIcons.square_arrow_up_fill,
                GlassColors.systemGreen,
                'Action sheet',
                _actionSheet,
              ),
              _row(
                CupertinoIcons.paintbrush_fill,
                GlassColors.systemOrange,
                'Styled alert',
                _styledAlert,
              ),
            ],
          ),
          GlassListSection(
            header: const Text('Pages'),
            footer: const Text(
              'A page with a tab bar of its own that tucks away on scroll and '
              'carries a mini player, and a video playing under glass.',
            ),
            children: [
              _row(
                CupertinoIcons.music_note_2,
                GlassColors.systemRed,
                'Music app',
                () => Navigator.of(context).push(
                  GlassPageRoute<void>(
                    builder: (context) => const MusicPage(),
                  ),
                ),
              ),
              _row(
                CupertinoIcons.play_rectangle_fill,
                GlassColors.systemBlue,
                'Video',
                () => Navigator.of(context).push(
                  GlassPageRoute<void>(
                    builder: (context) => const VideoPage(),
                  ),
                ),
              ),
            ],
          ),
          GlassListSection(
            header: const Text('Sheets'),
            footer: const Text(
              'The first sheet leaves the page live under its medium '
              'detent; the second asks before it lets you swipe it away; '
              'the third is as tall as its content and follows it.',
            ),
            children: [
              _row(
                CupertinoIcons.map_fill,
                GlassColors.systemBlue,
                'Sheet with detents',
                _sheet,
              ),
              _row(
                CupertinoIcons.square_pencil,
                GlassColors.systemGray,
                'Form sheet',
                _formSheet,
              ),
              _row(
                CupertinoIcons.book_fill,
                GlassColors.systemOrange,
                'Styled sheet',
                _styledSheet,
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _row(
    IconData icon,
    Color color,
    String title,
    Future<void> Function() onPressed,
  ) => GlassListRow(
    leading: SettingsIcon(icon: icon, color: color),
    title: Text(title),
    accessory: GlassListAccessory.disclosureIndicator,
    onPressed: () => unawaited(onPressed()),
  );

  Widget _hero() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: ClipRSuperellipse(
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        height: 260,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(image: Wallpaper.city.image, fit: BoxFit.cover),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  GlassMenuAnchor(
                    menuChildren: _moreMenu(),
                    builder: (context, controller, child) => GlassButton(
                      onPressed: controller.open,
                      semanticLabel: 'More',
                      child: const Icon(CupertinoIcons.ellipsis),
                    ),
                  ),
                  const Spacer(),
                  Builder(
                    builder: (context) => GlassButton(
                      onPressed: () => unawaited(_popover(context)),
                      child: const Text('Popover'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GlassMenuAnchor(
                    menuChildren: [
                      GlassMenuItem(
                        title: 'Photo',
                        icon: const Icon(CupertinoIcons.photo),
                        onPressed: () => _say('New photo'),
                      ),
                      GlassMenuItem(
                        title: 'Album',
                        icon: const Icon(CupertinoIcons.rectangle_stack),
                        onPressed: () => _say('New album'),
                      ),
                      GlassMenuItem(
                        title: 'Shared Album',
                        icon: const Icon(CupertinoIcons.person_2),
                        onPressed: () => _say('New shared album'),
                      ),
                    ],
                    builder: (context, controller, child) =>
                        GlassButton.prominent(
                          onPressed: controller.open,
                          semanticLabel: 'New',
                          child: const Icon(CupertinoIcons.plus),
                        ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PhotoText(
                    'Menus',
                    size: 28,
                    weight: FontWeight.w700,
                  ),
                  const SizedBox(height: 4),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: PhotoText(_status, key: ValueKey(_status)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _popover(BuildContext anchor) async {
    await showGlassPopover<void>(
      context,
      anchor: anchor,
      adaptsToSheet: false,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 240,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const GlassDefaultTextStyle(
                role: GlassTextRole.headline,
                child: Text('Popover'),
              ),
              const SizedBox(height: 6),
              const Text(
                'Points at the button it came from and adapts its arrow '
                'to the room it has.',
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: GlassButton.prominent(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlacesSheet extends StatelessWidget {
  const _PlacesSheet();

  static const _places = [
    ('Golden Gate Park', 'Park', CupertinoIcons.tree),
    ('Ferry Building', 'Market', CupertinoIcons.cart_fill),
    ('Coit Tower', 'Landmark', CupertinoIcons.building_2_fill),
    ('Lands End', 'Trail', CupertinoIcons.map),
    ('Ocean Beach', 'Beach', CupertinoIcons.sun_max_fill),
    ('Mission Dolores', 'Park', CupertinoIcons.tree),
    ('Twin Peaks', 'Viewpoint', CupertinoIcons.eye_fill),
    ('Palace of Fine Arts', 'Landmark', CupertinoIcons.building_2_fill),
    ('Baker Beach', 'Beach', CupertinoIcons.sun_max_fill),
    ('Presidio', 'Park', CupertinoIcons.tree),
    ('Chinatown', 'Neighborhood', CupertinoIcons.house_fill),
    ('Alcatraz', 'Island', CupertinoIcons.location_solid),
  ];

  @override
  Widget build(BuildContext context) => ListView(
    controller: GlassSheet.scrollControllerOf(context),
    padding: const EdgeInsets.only(top: 24, bottom: 40),
    children: [
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: GlassDefaultTextStyle(
          role: GlassTextRole.title2,
          child: Text('Places', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
      GlassListSection(
        children: [
          for (final (name, kind, icon) in _places)
            GlassListRow(
              leading: SettingsIcon(icon: icon, color: GlassColors.systemBlue),
              title: Text(name),
              subtitle: Text(kind),
              accessory: GlassListAccessory.disclosureIndicator,
              onPressed: () {},
            ),
        ],
      ),
    ],
  );
}

class _ComposeSheet extends StatelessWidget {
  const _ComposeSheet();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            GlassButton(
              onPressed: () => Navigator.of(context).pop(),
              semanticLabel: 'Close',
              child: const Icon(CupertinoIcons.xmark),
            ),
            const Expanded(
              child: GlassDefaultTextStyle(
                role: GlassTextRole.headline,
                child: Text('New Note', textAlign: TextAlign.center),
              ),
            ),
            GlassButton.prominent(
              onPressed: () => Navigator.of(context).pop(),
              semanticLabel: 'Save',
              child: const Icon(CupertinoIcons.checkmark),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const GlassDefaultTextStyle(
          role: GlassTextRole.title2,
          child: Text(
            'Swipe me down',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'This sheet refuses to go away on a swipe and asks first, the way '
          'a compose sheet guards a draft.',
        ),
      ],
    ),
  );
}

class _RecipeSheet extends StatefulWidget {
  const _RecipeSheet();

  @override
  State<_RecipeSheet> createState() => _RecipeSheetState();
}

class _RecipeSheetState extends State<_RecipeSheet> {
  var _steps = false;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GlassDefaultTextStyle(
          role: GlassTextRole.title2,
          child: Text(
            'Lemon pasta',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 6),
        const Text('20 minutes, serves two.'),
        if (_steps) ...[
          const SizedBox(height: 16),
          for (final step in const [
            'Boil the pasta in salted water.',
            'Melt butter, add lemon zest and juice.',
            'Toss with the pasta and a splash of its water.',
            'Finish with parmesan and black pepper.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(step),
            ),
        ],
        const SizedBox(height: 16),
        GlassButton.prominent(
          onPressed: () => setState(() => _steps = !_steps),
          child: Text(_steps ? 'Hide Steps' : 'Show Steps'),
        ),
      ],
    ),
  );
}
