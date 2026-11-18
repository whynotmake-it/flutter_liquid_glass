import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/components/component_page.dart';
import 'package:apple_liquid_glass_example/components/controls.dart';
import 'package:apple_liquid_glass_example/scenes/lava_page.dart';
import 'package:apple_liquid_glass_example/scenes/lens_page.dart';
import 'package:apple_liquid_glass_example/scenes/pads_page.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

enum _Outline { capsule, squircle, rounded, oval }

class SurfacePage extends StatefulWidget {
  const SurfacePage({super.key});

  /// Pages built from surfaces alone, with no control of the package.
  static const toys = <(IconData, Color, String, String, Widget Function())>[
    (
      CupertinoIcons.flame_fill,
      Color(0xFFFF375F),
      'Lava',
      'GlassSurface.live in one GlassGroup',
      LavaPage.new,
    ),
    (
      CupertinoIcons.square_grid_3x2_fill,
      Color(0xFF5E5CE6),
      'Pads',
      'Lift, glow and tint on a spring a finger',
      PadsPage.new,
    ),
    (
      CupertinoIcons.search,
      GlassColors.systemGray,
      'Lens',
      'What glass does to the page under it',
      LensPage.new,
    ),
  ];

  @override
  State<SurfacePage> createState() => _SurfacePageState();
}

class _SurfacePageState extends State<SurfacePage> {
  var _clear = false;
  var _outline = _Outline.squircle;
  var _brand = Brand.system;
  var _fuses = true;
  var _gap = 34.0;

  Glass get _glass {
    final tint = _brand.color?.withValues(alpha: 0.55);
    return _clear ? Glass.clear(tint: tint) : Glass.regular(tint: tint);
  }

  @override
  Widget build(BuildContext context) => ComponentPage(
    name: 'GlassSurface',
    summary:
        'A piece of the material under any widget: what every control of '
        'the package is made of. Surfaces in one GlassGroup fuse when '
        'they come close, and a live one reads its frame from a motion '
        'with no rebuild.',
    backdrop: Wallpaper.coast,
    stageHeight: 210,
    stage: GlassGroup(
      merge: _fuses ? const GlassMerge.spacing(30) : const GlassMerge.none(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassSurface(
            shape: switch (_outline) {
              _Outline.capsule => LiquidRoundedSuperellipse.capsule,
              _Outline.squircle => const LiquidRoundedSuperellipse(
                radius: 34,
              ),
              _Outline.rounded => const LiquidRoundedRectangle(
                radius: 22,
              ),
              _Outline.oval => const LiquidOval(),
            },
            glass: _glass,
            child: const SizedBox(
              width: 150,
              height: 96,
              child: Center(
                child: PhotoText('Glass', size: 20, weight: FontWeight.w600),
              ),
            ),
          ),
          SizedBox(width: _gap),
          GlassSurface(
            shape: const LiquidOval(),
            glass: _glass,
            child: const SizedBox.square(
              dimension: 64,
              child: Icon(
                CupertinoIcons.drop_fill,
                color: Color(0xFFFFFFFF),
                size: 24,
              ),
            ),
          ),
        ],
      ),
    ),
    knobs: [
      ChoiceKnob<bool>(
        'Glass',
        value: _clear,
        options: const {false: 'Regular', true: 'Clear'},
        onChanged: (clear) => setState(() => _clear = clear),
      ),
      ChoiceKnob<_Outline>(
        'Shape',
        value: _outline,
        options: const {
          _Outline.capsule: 'Capsule',
          _Outline.squircle: 'Squircle',
          _Outline.rounded: 'Rounded',
          _Outline.oval: 'Oval',
        },
        onChanged: (outline) => setState(() => _outline = outline),
      ),
      ChoiceKnob<Brand>(
        'Tint',
        value: _brand,
        options: Brand.names,
        onChanged: (brand) => setState(() => _brand = brand),
      ),
      ToggleKnob(
        'The two fuse',
        value: _fuses,
        onChanged: (on) => setState(() => _fuses = on),
      ),
      AmountKnob(
        'Gap',
        value: _gap,
        max: 60,
        shows: (gap) => '${gap.round()}',
        onChanged: (gap) => setState(() => _gap = gap),
      ),
    ],
    ideas: [
      Idea(
        'Built from surfaces alone',
        'Three toys with no control of the package in them: drops with '
            'physics that fuse, pads that take every finger at once, and '
            'a lens to drag over a page.',
        flush: true,
        child: GlassListSection(
          children: [
            for (final (icon, color, title, note, page) in SurfacePage.toys)
              GlassListRow(
                leading: SettingsIcon(icon: icon, color: color),
                title: Text(title),
                subtitle: Text(note),
                accessory: GlassListAccessory.disclosureIndicator,
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    GlassPageRoute<void>(builder: (context) => page()),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
