import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/components/component_page.dart';
import 'package:apple_liquid_glass_example/components/controls.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

enum _AlertKind { two, destructive, three, sheet }

class AlertPage extends StatefulWidget {
  const AlertPage({super.key});

  @override
  State<AlertPage> createState() => _AlertPageState();
}

class _AlertPageState extends State<AlertPage> {
  var _kind = _AlertKind.two;
  var _message = true;
  var _brand = Brand.system;
  var _answer = 'Nothing answered yet';

  Future<void> _show() async {
    final keep = GlassAlertAction(
      isDefaultAction: true,
      child: const Text('Keep'),
      onPressed: () => setState(() => _answer = 'Kept'),
    );
    final compost = GlassAlertAction.destructive(
      child: const Text('Compost'),
      onPressed: () => setState(() => _answer = 'Composted'),
    );
    final give = GlassAlertAction(
      child: const Text('Give away'),
      onPressed: () => setState(() => _answer = 'Given away'),
    );
    final cancel = GlassAlertAction.cancel(
      child: const Text('Cancel'),
      onPressed: () => setState(() => _answer = 'Cancelled'),
    );
    const title = Text('The fern has dried out');
    final message = _message
        ? const Text('It has had no water for three weeks.')
        : null;
    if (_kind == _AlertKind.sheet) {
      await showGlassActionSheet(
        context,
        title: title,
        message: message,
        actions: [keep, give, compost, cancel],
      );
      return;
    }
    await showGlassAlert(
      context,
      title: title,
      message: message,
      style: _brand.color == null
          ? null
          : GlassAlertStyle(
              actionColor: _brand.color,
              defaultActionFillColor: _brand.color,
            ),
      actions: switch (_kind) {
        _AlertKind.two => [cancel, keep],
        _AlertKind.destructive => [cancel, compost],
        _ => [keep, give, compost],
      },
    );
  }

  @override
  Widget build(BuildContext context) => ComponentPage(
    name: 'showGlassAlert',
    summary:
        'A panel of glass in the middle of the screen that asks one '
        'question; showGlassActionSheet raises the same actions from the '
        'bottom edge.',
    backdrop: Wallpaper.bloom,
    stageHeight: 150,
    stage: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassButton.prominent(
          onPressed: () => unawaited(_show()),
          child: const Text('Ask'),
        ),
        const SizedBox(height: 12),
        PhotoText(_answer),
      ],
    ),
    knobs: [
      ChoiceKnob<_AlertKind>(
        'Kind',
        value: _kind,
        options: const {
          _AlertKind.two: 'Two',
          _AlertKind.destructive: 'Destructive',
          _AlertKind.three: 'Three',
          _AlertKind.sheet: 'Sheet',
        },
        onChanged: (kind) => setState(() => _kind = kind),
      ),
      ToggleKnob(
        'Message',
        value: _message,
        onChanged: (on) => setState(() => _message = on),
      ),
      ChoiceKnob<Brand>(
        "The alert's colors",
        value: _brand,
        options: Brand.names,
        onChanged: (brand) => setState(() => _brand = brand),
      ),
    ],
  );
}

enum _Detents { medium, both, fitted }

class SheetPage extends StatefulWidget {
  const SheetPage({super.key});

  @override
  State<SheetPage> createState() => _SheetPageState();
}

class _SheetPageState extends State<SheetPage> {
  var _detents = _Detents.both;
  var _handle = true;
  var _undimmed = true;
  var _dismissible = true;
  var _tinted = false;

  Future<void> _show() => showGlassSheet<void>(
    context,
    detents: switch (_detents) {
      _Detents.medium => const [GlassSheetDetent.medium],
      _Detents.both => const [GlassSheetDetent.medium, GlassSheetDetent.large],
      _Detents.fitted => const [GlassSheetDetent.fitted],
    },
    largestUndimmedDetent: _undimmed && _detents != _Detents.fitted
        ? GlassSheetDetent.medium
        : null,
    showDragHandle: _handle,
    isDismissible: _dismissible,
    style: _tinted
        ? const GlassSheetStyle(
            backgroundColor: GlassDynamicColor.withBrightness(
              color: Color(0xFFE8F6EF),
              darkColor: Color(0xFF12342A),
            ),
            dragHandleColor: Color(0xFF1FB58F),
          )
        : null,
    builder: (context) =>
        _detents == _Detents.fitted ? const _Note() : const _Plants(),
  );

  @override
  Widget build(BuildContext context) => ComponentPage(
    name: 'showGlassSheet',
    summary:
        'A sheet that rests at detents, follows the finger between them, '
        'and hands a scroll over to its list once it stands at the top '
        'one.',
    backdrop: Wallpaper.coast,
    stageHeight: 130,
    stage: GlassButton.prominent(
      onPressed: () => unawaited(_show()),
      child: const Text('Open the sheet'),
    ),
    knobs: [
      ChoiceKnob<_Detents>(
        'Detents',
        value: _detents,
        options: const {
          _Detents.medium: 'Medium',
          _Detents.both: 'Medium, large',
          _Detents.fitted: 'Fitted',
        },
        onChanged: (detents) => setState(() => _detents = detents),
      ),
      ToggleKnob(
        'Drag handle',
        value: _handle,
        onChanged: (on) => setState(() => _handle = on),
      ),
      ToggleKnob(
        'Page stays live at medium',
        value: _undimmed,
        onChanged: (on) => setState(() => _undimmed = on),
      ),
      ToggleKnob(
        'A swipe down dismisses it',
        value: _dismissible,
        onChanged: (on) => setState(() => _dismissible = on),
      ),
      ToggleKnob(
        'Its own colors',
        value: _tinted,
        onChanged: (on) => setState(() => _tinted = on),
      ),
    ],
  );
}

class _Plants extends StatelessWidget {
  const _Plants();

  static const _plants = [
    ('Monstera', 'Living room', CupertinoIcons.tree),
    ('Jade plant', 'Study', CupertinoIcons.circle_fill),
    ('Peace lily', 'Bedroom', CupertinoIcons.drop_fill),
    ('Boston fern', 'Bathroom', CupertinoIcons.cloud_fog_fill),
    ('Pothos', 'Kitchen', CupertinoIcons.tree),
    ('Snake plant', 'Hall', CupertinoIcons.arrow_up),
    ('Calathea', 'Living room', CupertinoIcons.tree),
    ('Fiddle-leaf fig', 'Study', CupertinoIcons.tree),
    ('String of pearls', 'Kitchen', CupertinoIcons.circle_grid_3x3_fill),
    ('Aloe', 'Balcony', CupertinoIcons.sun_max_fill),
    ('Rubber plant', 'Hall', CupertinoIcons.tree),
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
          child: Text('Plants', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
      GlassListSection(
        children: [
          for (final (name, room, icon) in _plants)
            GlassListRow(
              leading: SettingsIcon(icon: icon, color: GlassColors.systemGreen),
              title: Text(name),
              subtitle: Text(room),
              accessory: GlassListAccessory.disclosureIndicator,
              onPressed: () {},
            ),
        ],
      ),
      if (Navigator.of(context).canPop())
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GlassButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ),
    ],
  );
}

class _Note extends StatelessWidget {
  const _Note();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const GlassDefaultTextStyle(
          role: GlassTextRole.title2,
          child: Text(
            'Watering day',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Four plants are thirsty today. The sheet is as tall as these '
          'lines and no taller.',
        ),
        const SizedBox(height: 18),
        GlassButton.prominent(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

class PopoverPage extends StatefulWidget {
  const PopoverPage({super.key});

  @override
  State<PopoverPage> createState() => _PopoverPageState();
}

class _PopoverPageState extends State<PopoverPage> {
  var _adapts = false;

  Future<void> _show(BuildContext anchor) => showGlassPopover<void>(
    context,
    anchor: anchor,
    adaptsToSheet: _adapts,
    builder: (context) => Padding(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 230,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const GlassDefaultTextStyle(
              role: GlassTextRole.headline,
              child: Text('Light'),
            ),
            const SizedBox(height: 6),
            const Text(
              'Bright, but out of the noon sun. It grew out of the button '
              'and goes back into it.',
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

  @override
  Widget build(BuildContext context) => ComponentPage(
    name: 'showGlassPopover',
    summary:
        'A bubble of glass that grows out of what it is about, points at '
        'it and fits its arrow to the room there is.',
    backdrop: Wallpaper.alpine,
    stageHeight: 170,
    stage: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final name in const ['From here', 'Or here'])
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Builder(
                    builder: (anchor) => GlassButton(
                      onPressed: () => unawaited(_show(anchor)),
                      child: Text(name),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        Builder(
          builder: (anchor) => GlassButton(
            onPressed: () => unawaited(_show(anchor)),
            semanticLabel: 'From the middle',
            child: const Icon(CupertinoIcons.info),
          ),
        ),
      ],
    ),
    knobs: [
      ToggleKnob(
        'Becomes a sheet on a phone',
        value: _adapts,
        onChanged: (on) => setState(() => _adapts = on),
      ),
    ],
  );
}
