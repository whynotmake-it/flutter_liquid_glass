import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/components/component_page.dart';
import 'package:apple_liquid_glass_example/stand/video_page.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

void _open(BuildContext context, Widget page) => unawaited(
  Navigator.of(
    context,
    rootNavigator: true,
  ).push(GlassPageRoute<void>(builder: (context) => page)),
);

enum _Items { icons, labels, prominent }

class NavigationBarPage extends StatefulWidget {
  const NavigationBarPage({super.key});

  @override
  State<NavigationBarPage> createState() => _NavigationBarPageState();
}

class _NavigationBarPageState extends State<NavigationBarPage> {
  var _large = true;
  var _search = false;
  var _toolbar = true;
  var _items = _Items.icons;
  var _back = GlassBackButtonDisplayMode.title;

  @override
  Widget build(BuildContext context) => ComponentPage(
    name: 'GlassNavigationBar',
    summary:
        'The bar at the top of this page, and GlassToolbar at the bottom '
        'of one: capsules of glass whose items travel when they change, '
        'and a large title that folds into the bar as the page scrolls.',
    backdrop: Wallpaper.dunes,
    stageHeight: 130,
    stage: GlassButton.prominent(
      onPressed: () => _open(
        context,
        _Journal(
          large: _large,
          search: _search,
          toolbar: _toolbar,
          items: _items,
          back: _back,
        ),
      ),
      child: const Text('Open the journal'),
    ),
    knobs: [
      ToggleKnob(
        'Large title',
        value: _large,
        onChanged: (on) => setState(() => _large = on),
      ),
      ToggleKnob(
        'Search field under the title',
        value: _search,
        onChanged: (on) => setState(() => _search = on),
      ),
      ToggleKnob(
        'Toolbar at the bottom',
        value: _toolbar,
        onChanged: (on) => setState(() => _toolbar = on),
      ),
      ChoiceKnob<_Items>(
        'Items',
        value: _items,
        options: const {
          _Items.icons: 'Icons',
          _Items.labels: 'Labels',
          _Items.prominent: 'Prominent',
        },
        onChanged: (items) => setState(() => _items = items),
      ),
      ChoiceKnob<GlassBackButtonDisplayMode>(
        'Back button',
        value: _back,
        options: const {
          GlassBackButtonDisplayMode.title: 'Title',
          GlassBackButtonDisplayMode.generic: 'Back',
          GlassBackButtonDisplayMode.minimal: 'Chevron',
        },
        onChanged: (back) => setState(() => _back = back),
      ),
    ],
    ideas: [
      Idea(
        'Bars over a film',
        'The same bars and buttons over a playing picture: the glass '
            'reads what moves under it every frame.',
        flush: true,
        child: GlassListSection(
          children: [
            GlassListRow(
              leading: const SettingsIcon(
                icon: CupertinoIcons.play_rectangle_fill,
                color: GlassColors.systemGray,
              ),
              title: const Text('A film'),
              accessory: GlassListAccessory.disclosureIndicator,
              onPressed: () => _open(context, const VideoPage()),
            ),
          ],
        ),
      ),
    ],
  );
}

/// A page that is all bars: what the knobs chose, and a Select item that
/// swaps the items of both bars where they stand.
class _Journal extends StatefulWidget {
  const _Journal({
    required this.large,
    required this.search,
    required this.toolbar,
    required this.items,
    required this.back,
  });

  final bool large;
  final bool search;
  final bool toolbar;
  final _Items items;
  final GlassBackButtonDisplayMode back;

  @override
  State<_Journal> createState() => _JournalState();
}

class _JournalState extends State<_Journal> {
  static const _entries = [
    ('Repotted the monstera', 'Its roots had circled the pot twice.'),
    ('First flower on the lily', 'White, and gone by Thursday.'),
    ('Moved the fern', 'Away from the radiator, toward the bath.'),
    ('Cuttings in water', 'Four of pothos, one of jade.'),
    ('Aphids', 'On the new leaves. Soap and patience.'),
    ('A new pot', 'Glazed, blue, a little too big.'),
    ('The fig dropped a leaf', 'It does this when it is moved.'),
    ('Fed everything', 'Half strength, as the bottle says.'),
    ('Roots on the cuttings', 'The pothos first, as always.'),
    ('Turned the pots', 'A quarter each, toward the window.'),
    ('The aloe has pups', 'Three, at the foot of it.'),
    ('Dusted the leaves', 'The rubber plant shines again.'),
    ('Rain water', 'A bucket of it, for the calathea.'),
    ('Nothing happened', 'Which is how plants like it.'),
  ];

  final _query = TextEditingController();
  final _picked = <int>{};
  var _selecting = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _select() => setState(() => _selecting = true);

  void _done() => setState(() {
    _selecting = false;
    _picked.clear();
  });

  GlassBarItem _selectIcon() => GlassBarItem(
    icon: const Icon(CupertinoIcons.checkmark_circle),
    semanticLabel: 'Select',
    onPressed: _select,
  );

  List<GlassBarEntry> _trailing() => _selecting
      ? [GlassBarItem.prominent(label: const Text('Done'), onPressed: _done)]
      : switch (widget.items) {
          _Items.icons => [
            GlassBarItem(
              icon: const Icon(CupertinoIcons.line_horizontal_3_decrease),
              semanticLabel: 'Filter',
              onPressed: () {},
            ),
            _selectIcon(),
          ],
          _Items.labels => [
            GlassBarItem(label: const Text('Select'), onPressed: _select),
          ],
          _Items.prominent => [
            _selectIcon(),
            const GlassBarSpacer(),
            GlassBarItem.prominent(
              icon: const Icon(CupertinoIcons.plus),
              semanticLabel: 'Add',
              onPressed: () {},
            ),
          ],
        };

  GlassBarItem _status(String text) => GlassBarItem.custom(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    ),
  );

  GlassToolbar _toolbar() => GlassToolbar(
    items: _selecting
        ? [
            GlassBarItem(
              icon: const Icon(CupertinoIcons.share),
              semanticLabel: 'Share',
              onPressed: () {},
            ),
            const GlassBarSpacer.flexible(),
            _status('${_picked.length} picked'),
            const GlassBarSpacer.flexible(),
            GlassBarItem(
              icon: const Icon(CupertinoIcons.trash),
              semanticLabel: 'Delete',
              onPressed: () {},
            ),
          ]
        : [
            GlassBarItem(
              icon: const Icon(CupertinoIcons.camera),
              semanticLabel: 'Add a photo',
              onPressed: () {},
            ),
            const GlassBarSpacer.flexible(),
            _status('${_entries.length} entries'),
            const GlassBarSpacer.flexible(),
            GlassBarItem(
              icon: const Icon(CupertinoIcons.square_pencil),
              semanticLabel: 'Write',
              onPressed: () {},
            ),
          ],
  );

  @override
  Widget build(BuildContext context) => GlassPageScaffold(
    navigationBar: GlassNavigationBar(
      title: widget.large ? null : const Text('Journal'),
      largeTitle: widget.large ? const Text('Journal') : null,
      previousPageTitle: 'Bar',
      backButtonDisplayMode: widget.back,
      trailing: _trailing(),
      searchField: widget.search
          ? GlassSearchField(
              controller: _query,
              placeholder: const Text('Search the journal'),
            )
          : null,
    ),
    toolbar: widget.toolbar ? _toolbar() : null,
    child: GlassContentScroll(
      child: ListenableBuilder(
        listenable: _query,
        builder: (context, _) {
          final query = _query.text.trim().toLowerCase();
          return ListView(
            children: [
              for (final (index, (title, note)) in _entries.indexed)
                if ('$title $note'.toLowerCase().contains(query))
                  GlassListRow(
                    leading: _selecting
                        ? Icon(
                            _picked.contains(index)
                                ? CupertinoIcons.checkmark_circle_fill
                                : CupertinoIcons.circle,
                            color: GlassDynamicColor.resolve(
                              _picked.contains(index)
                                  ? GlassColors.systemBlue
                                  : GlassColors.tertiaryLabel,
                              context,
                            ),
                          )
                        : null,
                    title: Text(title),
                    subtitle: Text(note),
                    detail: Text('${index + 1} d'),
                    onPressed: () {
                      if (!_selecting) return;
                      setState(() {
                        if (!_picked.remove(index)) _picked.add(index);
                      });
                    },
                  ),
            ],
          );
        },
      ),
    ),
  );
}

class TabBarPage extends StatefulWidget {
  const TabBarPage({super.key});

  @override
  State<TabBarPage> createState() => _TabBarPageState();
}

class _TabBarPageState extends State<TabBarPage> {
  var _tabs = 4.0;
  var _badges = true;
  var _minimizes = true;
  var _accessory = false;
  var _search = false;

  @override
  Widget build(BuildContext context) => ComponentPage(
    name: 'GlassTabBar',
    summary:
        'The bar at the bottom of an app: a lens of glass that slides '
        'between two to five tabs and follows the finger. In a '
        'GlassTabScaffold it tucks away as the page scrolls, carries an '
        'accessory, or opens into a search.',
    backdrop: Wallpaper.aurora,
    stageHeight: 130,
    stage: GlassButton.prominent(
      onPressed: () => _open(
        context,
        _Greenhouse(
          tabs: _tabs.round(),
          badges: _badges,
          minimizes: _minimizes && !_search,
          accessory: _accessory && !_search,
          search: _search,
        ),
      ),
      child: const Text('Open the greenhouse'),
    ),
    knobs: [
      AmountKnob(
        'Tabs',
        value: _tabs,
        min: 2,
        max: 5,
        ticks: 4,
        shows: (tabs) => '${tabs.round()}',
        onChanged: (tabs) => setState(() => _tabs = tabs.roundToDouble()),
      ),
      ToggleKnob(
        'Badges',
        value: _badges,
        onChanged: (on) => setState(() => _badges = on),
      ),
      ToggleKnob(
        'A search tab',
        value: _search,
        onChanged: (on) => setState(() => _search = on),
      ),
      if (!_search) ...[
        ToggleKnob(
          'Tucks away on a scroll down',
          value: _minimizes,
          onChanged: (on) => setState(() => _minimizes = on),
        ),
        ToggleKnob(
          'An accessory above it',
          value: _accessory,
          onChanged: (on) => setState(() => _accessory = on),
        ),
      ],
    ],
  );
}

/// An app of its own under the tab bar the knobs chose.
class _Greenhouse extends StatefulWidget {
  const _Greenhouse({
    required this.tabs,
    required this.badges,
    required this.minimizes,
    required this.accessory,
    required this.search,
  });

  final int tabs;
  final bool badges;
  final bool minimizes;
  final bool accessory;
  final bool search;

  @override
  State<_Greenhouse> createState() => _GreenhouseState();
}

class _GreenhouseState extends State<_Greenhouse> {
  static const _tabs = [
    ('Plants', CupertinoIcons.tree, null),
    ('Rooms', CupertinoIcons.house, CupertinoIcons.house_fill),
    ('Journal', CupertinoIcons.book, CupertinoIcons.book_fill),
    ('Wishes', CupertinoIcons.heart, CupertinoIcons.heart_fill),
    ('Shop', CupertinoIcons.cart, CupertinoIcons.cart_fill),
  ];

  static const _rows = [
    'Monstera',
    'Jade plant',
    'Peace lily',
    'Boston fern',
    'Pothos',
    'Snake plant',
    'Calathea',
    'Fiddle-leaf fig',
    'String of pearls',
    'Aloe',
    'Rubber plant',
    'Spider plant',
    'Olive tree',
    'Maidenhair',
    'Hoya',
    'Begonia',
  ];

  final _search = GlassSearchController();
  var _tab = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Widget _page(String title, Iterable<String> rows) => GlassPageScaffold(
    backgroundColor: GlassColors.systemGroupedBackground,
    navigationBar: GlassNavigationBar(
      largeTitle: Text(title),
      previousPageTitle: 'Tab bar',
    ),
    child: GlassContentScroll(
      child: ListView(
        children: [
          GlassListSection(
            children: [
              for (final row in rows)
                GlassListRow(
                  leading: const SettingsIcon(
                    icon: CupertinoIcons.tree,
                    color: GlassColors.systemGreen,
                  ),
                  title: Text(row),
                  subtitle: Text(title),
                  onPressed: () {},
                ),
            ],
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => GlassTabScaffold(
    backgroundColor: GlassColors.systemGroupedBackground,
    tabBar: GlassTabBar(
      destinations: [
        for (final (index, (name, icon, selected)) in _tabs.indexed.take(
          widget.tabs,
        ))
          GlassTabDestination(
            icon: Icon(icon),
            selectedIcon: selected == null ? null : Icon(selected),
            label: Text(name),
            badge: switch (index) {
              _ when !widget.badges => null,
              1 => const GlassBadge.indicator(),
              2 => const GlassBadge.count(3),
              _ => null,
            },
          ),
      ],
      selectedIndex: _tab,
      onDestinationSelected: (index) => setState(() => _tab = index),
      minimizeBehavior: widget.minimizes
          ? GlassTabBarMinimizeBehavior.onScrollDown
          : GlassTabBarMinimizeBehavior.automatic,
      bottomAccessory: widget.accessory ? const _Reminder() : null,
      searchController: widget.search ? _search : null,
    ),
    tabBuilder: (context, index) => _page(_tabs[index].$1, _rows),
    searchBuilder: widget.search
        ? (context) => ListenableBuilder(
            listenable: _search,
            builder: (context, _) {
              final query = _search.text.trim().toLowerCase();
              return _page('Search', [
                for (final row in _rows)
                  if (row.toLowerCase().contains(query)) row,
              ]);
            },
          )
        : null,
  );
}

class _Reminder extends StatelessWidget {
  const _Reminder();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 14),
    child: Row(
      children: [
        Icon(CupertinoIcons.drop_fill, size: 18),
        SizedBox(width: 10),
        Expanded(
          child: GlassDefaultTextStyle(
            role: GlassTextRole.subheadline,
            child: Text(
              'The fern is thirsty',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    ),
  );
}
