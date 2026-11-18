import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/components/component_page.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

const _white = Color(0xFFFFFFFF);

/// The looks the pages restyle a control in, to show how far a style goes.
enum Brand {
  system('System', null),
  mint('Mint', Color(0xFF1FB58F)),
  coral('Coral', Color(0xFFFF6B5E)),
  ink('Ink', Color(0xFF2B2F4A));

  const Brand(this.title, this.color);

  final String title;
  final Color? color;

  static Map<Brand, String> get names => {
    for (final brand in values) brand: brand.title,
  };
}

enum _ButtonKind { glass, prominent, clear, tinted }

class ButtonPage extends StatefulWidget {
  const ButtonPage({super.key});

  @override
  State<ButtonPage> createState() => _ButtonPageState();
}

class _ButtonPageState extends State<ButtonPage> {
  var _kind = _ButtonKind.glass;
  var _icon = false;
  var _enabled = true;
  var _sort = 'Thirst';
  final _lit = <int>{1};

  Widget _sortButton() => GlassMenuAnchor(
    menuChildren: [
      GlassMenuSection(
        singleSelection: true,
        children: [
          for (final sort in const ['Thirst', 'Name', 'Room'])
            GlassMenuItem(
              title: sort,
              state: sort == _sort
                  ? GlassMenuItemState.on
                  : GlassMenuItemState.off,
              onPressed: () => setState(() => _sort = sort),
            ),
        ],
      ),
    ],
    builder: (context, controller, child) => GlassButton(
      onPressed: controller.open,
      child: Text('Sort by $_sort'),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final onPressed = _enabled ? () {} : null;
    final child = _icon
        ? const Icon(CupertinoIcons.drop_fill)
        : const Text('Water now');
    return ComponentPage(
      name: 'GlassButton',
      summary:
          'A capsule of glass that sinks and glows under the finger and '
          'springs back with its momentum.',
      backdrop: Wallpaper.coast,
      stage: switch (_kind) {
        _ButtonKind.glass => GlassButton(
          onPressed: onPressed,
          semanticLabel: 'Water now',
          child: child,
        ),
        _ButtonKind.prominent => GlassButton.prominent(
          onPressed: onPressed,
          semanticLabel: 'Water now',
          child: child,
        ),
        _ButtonKind.clear => GlassButton.clear(
          onPressed: onPressed,
          semanticLabel: 'Water now',
          child: child,
        ),
        _ButtonKind.tinted => GlassButton.prominentClear(
          onPressed: onPressed,
          semanticLabel: 'Water now',
          child: child,
        ),
      },
      knobs: [
        ChoiceKnob<_ButtonKind>(
          'Kind',
          value: _kind,
          options: const {
            _ButtonKind.glass: 'Glass',
            _ButtonKind.prominent: 'Prominent',
            _ButtonKind.clear: 'Clear',
            _ButtonKind.tinted: 'Tinted',
          },
          onChanged: (kind) => setState(() => _kind = kind),
        ),
        ToggleKnob(
          'Icon',
          value: _icon,
          onChanged: (on) => setState(() => _icon = on),
        ),
        ToggleKnob(
          'Enabled',
          value: _enabled,
          onChanged: (on) => setState(() => _enabled = on),
        ),
      ],
      ideas: [
        Idea(
          'It grows into a menu',
          'In a GlassMenuAnchor a tap opens the menu out of the button, and '
              'the finger can slide straight on to an item.',
          child: Stage(
            backdrop: Wallpaper.dunes,
            height: 96,
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _sortButton(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GlassMenuAnchor(
                  menuChildren: [
                    for (final (title, icon) in const [
                      ('Plant', CupertinoIcons.tree),
                      ('Room', CupertinoIcons.house),
                      ('Reminder', CupertinoIcons.bell),
                    ])
                      GlassMenuItem(
                        title: title,
                        icon: Icon(icon),
                        onPressed: () {},
                      ),
                  ],
                  builder: (context, controller, child) =>
                      GlassButton.prominent(
                        onPressed: controller.open,
                        semanticLabel: 'Add',
                        child: const Icon(CupertinoIcons.plus),
                      ),
                ),
              ],
            ),
          ),
        ),
        Idea(
          'In your colors',
          'GlassButton.styleFrom sets the fill, the label and the padding; '
              'the press, the glow and the spring stay.',
          child: Stage(
            backdrop: Wallpaper.bloom,
            height: 96,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final brand in Brand.values.skip(1))
                  GlassButton(
                    onPressed: () {},
                    style: GlassButton.styleFrom(
                      backgroundColor: brand.color!.withValues(alpha: 0.82),
                      foregroundColor: _white,
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: Text(brand.title),
                  ),
              ],
            ),
          ),
        ),
        Idea(
          'A look of your own',
          'RawGlassButton gives the press, the glow and the semantics of a '
              'button to anything: here round glass that fills with a color.',
          child: Stage(
            backdrop: Wallpaper.aurora,
            height: 110,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final (index, (name, icon, color)) in const [
                  ('Light', CupertinoIcons.sun_max_fill, 0xFFFFD60A),
                  ('Favorite', CupertinoIcons.heart_fill, 0xFFFF375F),
                  ('Water', CupertinoIcons.drop_fill, 0xFF0A84FF),
                  ('Mute', CupertinoIcons.bell_slash_fill, 0xFFFF9F0A),
                ].indexed)
                  SizedBox.square(
                    dimension: 62,
                    child: RawGlassButton(
                      onPressed: () => setState(() {
                        if (!_lit.remove(index)) _lit.add(index);
                      }),
                      shape: const LiquidOval(),
                      semanticLabel: name,
                      builder: (context, details) => GlassSurface.live(
                        frame: details.body,
                        glass: Glass.clear(
                          tint: _lit.contains(index) ? Color(color) : null,
                        ),
                        child: Center(child: details.label),
                      ),
                      child: Icon(icon, color: _white, size: 26),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class SwitchPage extends StatefulWidget {
  const SwitchPage({super.key});

  @override
  State<SwitchPage> createState() => _SwitchPageState();
}

class _SwitchPageState extends State<SwitchPage> {
  var _on = true;
  var _enabled = true;
  var _brand = Brand.system;
  final _rows = {'Water reminders': true, 'Mist at dawn': false};

  GlassSwitchStyle? _style(Brand brand) => brand.color == null
      ? null
      : GlassSwitch.styleFrom(activeTrackColor: brand.color);

  @override
  Widget build(BuildContext context) => ComponentPage(
    name: 'GlassSwitch',
    summary:
        'A switch whose knob lifts into a lens of glass while a finger '
        'holds it, and can be dragged across.',
    stage: GlassSwitch(
      value: _on,
      style: _style(_brand),
      semanticLabel: 'Switch',
      onChanged: _enabled ? (on) => setState(() => _on = on) : null,
    ),
    stageHeight: 120,
    knobs: [
      ToggleKnob(
        'Enabled',
        value: _enabled,
        onChanged: (on) => setState(() => _enabled = on),
      ),
      ChoiceKnob<Brand>(
        'Colors',
        value: _brand,
        options: Brand.names,
        onChanged: (brand) => setState(() => _brand = brand),
      ),
    ],
    ideas: [
      Idea(
        'In a list',
        'The trailing end of a row; a tap on the row turns it too.',
        flush: true,
        child: GlassListSection(
          children: [
            for (final MapEntry(key: title, value: on) in _rows.entries)
              GlassListRow(
                leading: SettingsIcon(
                  icon: title.startsWith('Water')
                      ? CupertinoIcons.drop_fill
                      : CupertinoIcons.cloud_fog_fill,
                  color: GlassColors.systemBlue,
                ),
                title: Text(title),
                trailing: GlassSwitch(
                  value: on,
                  semanticLabel: title,
                  onChanged: (on) => setState(() => _rows[title] = on),
                ),
                onPressed: () => setState(() => _rows[title] = !on),
              ),
          ],
        ),
      ),
    ],
  );
}

class SliderPage extends StatefulWidget {
  const SliderPage({super.key});

  @override
  State<SliderPage> createState() => _SliderPageState();
}

class _SliderPageState extends State<SliderPage> {
  var _value = 0.6;
  var _ticks = 0;
  var _brand = Brand.system;
  var _light = 0.4;

  @override
  Widget build(BuildContext context) => ComponentPage(
    name: 'GlassSlider',
    summary:
        'A slider whose knob is a lens over its track. Pulled past an end, '
        'the track stretches and springs back.',
    stage: GlassSlider(
      value: _value,
      ticks: _ticks,
      style: _brand.color == null
          ? null
          : GlassSlider.styleFrom(activeTrackColor: _brand.color),
      semanticLabel: 'Slider',
      onChanged: (value) => setState(() => _value = value),
    ),
    stageHeight: 120,
    knobs: [
      ChoiceKnob<int>(
        'Ticks',
        value: _ticks,
        options: const {0: 'None', 3: '3', 5: '5', 9: '9'},
        onChanged: (ticks) => setState(() => _ticks = ticks),
      ),
      ChoiceKnob<Brand>(
        'Colors',
        value: _brand,
        options: Brand.names,
        onChanged: (brand) => setState(() => _brand = brand),
      ),
    ],
    ideas: [
      Idea(
        'Between two ends',
        'An icon at each end says what the track runs between.',
        flush: true,
        child: GlassListSection(
          children: [
            GlassListRow(
              child: Row(
                children: [
                  const Icon(CupertinoIcons.moon_fill, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassSlider(
                      value: _light,
                      semanticLabel: 'Light',
                      onChanged: (value) => setState(() => _light = value),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(CupertinoIcons.sun_max_fill, size: 20),
                ],
              ),
            ),
          ],
        ),
      ),
      Idea(
        'Over a photo',
        'The knob is glass, so it shows what the track lies on.',
        child: Stage(
          backdrop: Wallpaper.alpine,
          height: 96,
          child: GlassSlider(
            value: _light,
            semanticLabel: 'Light over a photo',
            onChanged: (value) => setState(() => _light = value),
          ),
        ),
      ),
    ],
  );
}

class StepperPage extends StatefulWidget {
  const StepperPage({super.key});

  @override
  State<StepperPage> createState() => _StepperPageState();
}

class _StepperPageState extends State<StepperPage> {
  var _value = 4.0;
  var _step = 1.0;
  var _brand = Brand.system;
  var _days = 7.0;
  var _pots = 3.0;

  @override
  Widget build(BuildContext context) => ComponentPage(
    name: 'GlassStepper',
    summary:
        'Two halves that count down and up. A held half repeats, faster '
        'the longer it is held.',
    stage: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            '${_value.round()}',
            style: TextStyle(
              color: GlassDynamicColor.resolve(GlassColors.label, context),
              fontSize: 34,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        GlassStepper(
          value: _value,
          max: 40,
          step: _step,
          style: _brand.color == null
              ? null
              : GlassStepper.styleFrom(
                  backgroundColor: _brand.color!.withValues(alpha: 0.22),
                  foregroundColor: _brand.color,
                ),
          onChanged: (value) => setState(() => _value = value),
        ),
      ],
    ),
    stageHeight: 120,
    knobs: [
      ChoiceKnob<double>(
        'Step',
        value: _step,
        options: {1.0: '1', 2.0: '2', 5.0: '5'},
        onChanged: (step) => setState(() => _step = step),
      ),
      ChoiceKnob<Brand>(
        'Colors',
        value: _brand,
        options: Brand.names,
        onChanged: (brand) => setState(() => _brand = brand),
      ),
    ],
    ideas: [
      Idea(
        'In a list',
        'A row shows the count as its detail and steps it at its end.',
        flush: true,
        child: GlassListSection(
          children: [
            GlassListRow(
              title: const Text('Days between watering'),
              detail: Text('${_days.round()}'),
              trailing: GlassStepper(
                value: _days,
                min: 1,
                max: 30,
                onChanged: (value) => setState(() => _days = value),
              ),
            ),
            GlassListRow(
              title: const Text('Pots'),
              detail: Text('${_pots.round()}'),
              trailing: GlassStepper(
                value: _pots,
                max: 12,
                onChanged: (value) => setState(() => _pots = value),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class SegmentedPage extends StatefulWidget {
  const SegmentedPage({super.key});

  @override
  State<SegmentedPage> createState() => _SegmentedPageState();
}

class _SegmentedPageState extends State<SegmentedPage> {
  static const _names = ['Shade', 'Half', 'Sun', 'Hot', 'Any'];
  static const _icons = [
    CupertinoIcons.cloud_fill,
    CupertinoIcons.cloud_sun_fill,
    CupertinoIcons.sun_max_fill,
    CupertinoIcons.flame_fill,
    CupertinoIcons.circle_grid_3x3_fill,
  ];
  static const _more = ['Kitchen', 'Hall', 'Balcony', 'Study'];

  var _count = 3.0;
  var _picked = 0;
  var _usesIcons = false;
  var _proportional = false;
  var _brand = Brand.system;
  final _rooms = ['Bedroom', 'Kitchen'];
  var _room = 'Bedroom';

  @override
  Widget build(BuildContext context) {
    final count = _count.round();
    return ComponentPage(
      name: 'GlassSegmentedControl',
      summary:
          'A lens that slides between segments of text or icons, under a '
          'tap or a finger dragged across.',
      stage: GlassSegmentedControl<int>(
        segments: [
          for (var i = 0; i < count; i++)
            GlassSegment(
              value: i,
              label: _usesIcons ? Icon(_icons[i]) : Text(_names[i]),
              semanticLabel: _names[i],
            ),
        ],
        groupValue: _picked.clamp(0, count - 1),
        proportionalWidth: _proportional,
        style: _brand.color == null
            ? null
            : GlassSegmentedControl.styleFrom(
                backgroundColor: _brand.color!.withValues(alpha: 0.2),
                thumbColor: _brand.color,
                foregroundColor: GlassDynamicColor.resolve(
                  GlassColors.label,
                  context,
                ),
              ),
        onChanged: (picked) => setState(() => _picked = picked),
      ),
      stageHeight: 120,
      knobs: [
        AmountKnob(
          'Segments',
          value: _count,
          min: 2,
          max: 5,
          ticks: 4,
          onChanged: (count) => setState(() => _count = count),
        ),
        ToggleKnob(
          'Icons',
          value: _usesIcons,
          onChanged: (on) => setState(() => _usesIcons = on),
        ),
        ToggleKnob(
          'Widths by content',
          value: _proportional,
          onChanged: (on) => setState(() => _proportional = on),
        ),
        ChoiceKnob<Brand>(
          'Colors',
          value: _brand,
          options: Brand.names,
          onChanged: (brand) => setState(() => _brand = brand),
        ),
      ],
      ideas: [
        Idea(
          'Segments that come and go',
          'Inside withSpring a segment added or taken makes the others '
              'move over on the spring.',
          child: Stage(
            height: 96,
            child: Row(
              children: [
                Expanded(
                  child: GlassSegmentedControl<String>(
                    segments: [
                      for (final room in _rooms)
                        GlassSegment(value: room, label: Text(room)),
                    ],
                    groupValue: _room,
                    onChanged: (room) => setState(() => _room = room),
                  ),
                ),
                const SizedBox(width: 10),
                GlassButton(
                  onPressed: _rooms.length > 1
                      ? () => withSpring(
                          Spring.snappy,
                          () => setState(
                            () => _rooms.remove(
                              _rooms.lastWhere((room) => room != _room),
                            ),
                          ),
                        )
                      : null,
                  semanticLabel: 'Take a room',
                  child: const Icon(CupertinoIcons.minus),
                ),
                const SizedBox(width: 6),
                GlassButton(
                  onPressed: _rooms.length < 4
                      ? () => withSpring(
                          Spring.snappy,
                          () => setState(
                            () => _rooms.add(
                              _more.firstWhere(
                                (room) => !_rooms.contains(room),
                              ),
                            ),
                          ),
                        )
                      : null,
                  semanticLabel: 'Add a room',
                  child: const Icon(CupertinoIcons.plus),
                ),
              ],
            ),
          ),
        ),
        Idea(
          'Over a photo',
          'The track is glass too.',
          child: Stage(
            backdrop: Wallpaper.bloom,
            height: 96,
            child: GlassSegmentedControl<int>(
              segments: [
                for (var i = 0; i < 3; i++)
                  GlassSegment(value: i, label: Text(_names[i])),
              ],
              groupValue: _picked.clamp(0, 2),
              onChanged: (picked) => setState(() => _picked = picked),
            ),
          ),
        ),
      ],
    );
  }
}

class PageControlPage extends StatefulWidget {
  const PageControlPage({super.key});

  @override
  State<PageControlPage> createState() => _PageControlPageState();
}

class _PageControlPageState extends State<PageControlPage> {
  final _pages = PageController();
  var _count = 6.0;
  var _page = 0;
  var _background = GlassPageControlBackground.prominent;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = _count.round();
    return ComponentPage(
      name: 'GlassPageControl',
      summary:
          'Dots that follow a pager as it turns. A finger held on them '
          'lifts a platter and scrubs through the pages.',
      knobs: [
        AmountKnob(
          'Pages',
          value: _count,
          min: 2,
          max: 6,
          ticks: 5,
          onChanged: (count) => setState(() {
            _count = count;
            _page = _page.clamp(0, count.round() - 1);
          }),
        ),
        ChoiceKnob<GlassPageControlBackground>(
          'Background',
          value: _background,
          options: const {
            GlassPageControlBackground.automatic: 'Automatic',
            GlassPageControlBackground.prominent: 'Prominent',
            GlassPageControlBackground.minimal: 'Minimal',
          },
          onChanged: (background) => setState(() => _background = background),
        ),
      ],
      ideas: [
        Idea(
          'Over a pager',
          "Given the pager's position as progress, the dots move with the "
              'page under the finger.',
          child: ClipRSuperellipse(
            borderRadius: BorderRadius.circular(28),
            child: SizedBox(
              height: 220,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PageView(
                    controller: _pages,
                    onPageChanged: (page) => setState(() => _page = page),
                    children: [
                      for (final wallpaper in Wallpaper.values.take(count))
                        Image(image: wallpaper.image, fit: BoxFit.cover),
                    ],
                  ),
                  Align(
                    alignment: const Alignment(0, 0.86),
                    child: AnimatedBuilder(
                      animation: _pages,
                      builder: (context, _) => GlassPageControl(
                        count: count,
                        page: _page,
                        progress: _pages.hasClients ? _pages.page : null,
                        backgroundStyle: _background,
                        onChanged: (page) => _pages.animateToPage(
                          page,
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
