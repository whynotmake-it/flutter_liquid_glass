import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/components/component_page.dart';
import 'package:apple_liquid_glass_example/components/controls.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

class DatePickerPage extends StatefulWidget {
  const DatePickerPage({super.key});

  @override
  State<DatePickerPage> createState() => _DatePickerPageState();
}

class _DatePickerPageState extends State<DatePickerPage> {
  var _date = DateTime(2026, 6, 12, 8, 30);
  var _mode = GlassDatePickerMode.date;
  var _inline = false;
  var _fives = false;
  var _brand = Brand.system;
  var _repot = DateTime(2026, 8, 3);
  var _alarm = DateTime(2026, 1, 1, 7, 15);

  @override
  Widget build(BuildContext context) {
    final style = _brand.color == null
        ? null
        : GlassDatePickerStyle(accentColor: _brand.color);
    void changed(DateTime date) => setState(() => _date = date);
    return ComponentPage(
      name: 'GlassCompactDatePicker',
      summary:
          'A date, a time or both: a compact field that opens its calendar '
          'or its wheels out of itself, or GlassDatePicker, the calendar in '
          'place.',
      stageHeight: _inline ? 360 : 120,
      stage: FittedBox(
        fit: BoxFit.scaleDown,
        child: _inline
            ? GlassDatePicker(value: _date, style: style, onChanged: changed)
            : GlassCompactDatePicker(
                value: _date,
                mode: _mode,
                minuteInterval: _fives ? 5 : 1,
                style: style,
                onChanged: changed,
              ),
      ),
      knobs: [
        ChoiceKnob<bool>(
          'Form',
          value: _inline,
          options: const {false: 'Compact', true: 'Inline'},
          onChanged: (inline) => setState(() => _inline = inline),
        ),
        ChoiceKnob<GlassDatePickerMode>(
          'Mode',
          value: _mode,
          options: const {
            GlassDatePickerMode.date: 'Date',
            GlassDatePickerMode.time: 'Time',
            GlassDatePickerMode.dateAndTime: 'Both',
          },
          onChanged: (mode) => setState(() => _mode = mode),
        ),
        ToggleKnob(
          'Minutes by five',
          value: _fives,
          onChanged: (on) => setState(() => _fives = on),
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
          'The compact field at the end of a row.',
          flush: true,
          child: GlassListSection(
            children: [
              GlassListRow(
                title: const Text('Repot'),
                trailing: GlassCompactDatePicker(
                  value: _repot,
                  onChanged: (date) => setState(() => _repot = date),
                ),
              ),
              GlassListRow(
                title: const Text('Morning mist'),
                trailing: GlassCompactDatePicker(
                  value: _alarm,
                  mode: GlassDatePickerMode.time,
                  onChanged: (date) => setState(() => _alarm = date),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SearchFieldPage extends StatefulWidget {
  const SearchFieldPage({super.key});

  @override
  State<SearchFieldPage> createState() => _SearchFieldPageState();
}

class _SearchFieldPageState extends State<SearchFieldPage> {
  static const _plants = [
    'Boston fern',
    'Calathea',
    'Fiddle-leaf fig',
    'Jade plant',
    'Monstera',
    'Peace lily',
    'Pothos',
    'Snake plant',
    'String of pearls',
  ];

  final _stage = TextEditingController();
  final _filter = TextEditingController();
  var _enabled = true;

  @override
  void dispose() {
    _stage.dispose();
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ComponentPage(
    name: 'GlassSearchField',
    summary:
        'A capsule of glass to type a search into, with a button that '
        'clears it.',
    backdrop: Wallpaper.dunes,
    stageHeight: 120,
    stage: GlassSearchField(
      controller: _stage,
      placeholder: const Text('Search plants'),
      enabled: _enabled,
    ),
    knobs: [
      ToggleKnob(
        'Enabled',
        value: _enabled,
        onChanged: (on) => setState(() => _enabled = on),
      ),
    ],
    ideas: [
      Idea(
        'A list that narrows as you type',
        'onChanged gives every keystroke; the list keeps what matches.',
        child: Stage(
          height: null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassSearchField(
                controller: _filter,
                placeholder: const Text('Filter'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              for (final plant in _plants)
                if (plant.toLowerCase().contains(_filter.text.toLowerCase()))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Icon(CupertinoIcons.tree, size: 18),
                        const SizedBox(width: 10),
                        Text(plant),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    ],
  );
}

enum _BadgeKind { count, text, dot }

class BadgePage extends StatefulWidget {
  const BadgePage({super.key});

  @override
  State<BadgePage> createState() => _BadgePageState();
}

class _BadgePageState extends State<BadgePage> {
  var _kind = _BadgeKind.count;
  var _count = 3.0;
  var _brand = Brand.system;

  Widget _badge(GlassBadgeStyle? style) => switch (_kind) {
    _BadgeKind.count => GlassBadge.count(_count.round(), style: style),
    _BadgeKind.text => GlassBadge.text('New', style: style),
    _BadgeKind.dot => GlassBadge.indicator(style: style),
  };

  @override
  Widget build(BuildContext context) {
    final style = _brand.color == null
        ? null
        : GlassBadgeStyle(backgroundColor: _brand.color);
    return ComponentPage(
      name: 'GlassBadge',
      summary: 'A count, a word or a dot that asks for a look.',
      stageHeight: 120,
      stage: _badge(style),
      knobs: [
        ChoiceKnob<_BadgeKind>(
          'Kind',
          value: _kind,
          options: const {
            _BadgeKind.count: 'Count',
            _BadgeKind.text: 'Text',
            _BadgeKind.dot: 'Dot',
          },
          onChanged: (kind) => setState(() => _kind = kind),
        ),
        AmountKnob(
          'Count',
          value: _count,
          min: 1,
          max: 120,
          onChanged: (count) => setState(() => _count = count),
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
          'On an icon',
          'Laid over the corner of whatever it counts. A tab of a '
              'GlassTabBar takes one as its badge.',
          child: Stage(
            height: 110,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final icon in const [
                  CupertinoIcons.tray_fill,
                  CupertinoIcons.bell_fill,
                  CupertinoIcons.cart_fill,
                ])
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(icon, size: 40),
                      Positioned(left: 24, top: -8, child: _badge(style)),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
