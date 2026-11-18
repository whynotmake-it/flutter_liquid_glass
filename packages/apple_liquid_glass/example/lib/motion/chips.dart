import 'dart:math' as math;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

/// A cloud of tags that reorders on a `MotionLayout`: a tapped tag moves to
/// the front and every tag slides to its new place in the wrap, on the
/// planner's own spring, with no `withSpring` at the change.
class ChipsSection extends StatefulWidget {
  const ChipsSection({super.key});

  @override
  State<ChipsSection> createState() => _ChipsSectionState();
}

class _ChipsSectionState extends State<ChipsSection> {
  static const _planner = LayoutPlanner.flip(spring: Spring.snappy);

  final _random = math.Random(3);
  final _tags = [
    'Flutter',
    'Springs',
    'Glass',
    'UIKit',
    'Layout',
    'Gestures',
    'Sheets',
    'Menus',
    'Toolbars',
    'Accessibility',
    'Replay',
    'Physics',
  ];

  void _front(String tag) => setState(() {
    _tags.remove(tag);
    _tags.insert(0, tag);
  });

  void _shuffle() => setState(() => _tags.shuffle(_random));

  @override
  Widget build(BuildContext context) {
    final tint = GlassDynamicColor.resolve(GlassColors.systemBlue, context);
    return GlassListSection(
      header: const Text('Chips'),
      footer: const Text('Tap a tag to move it to the front.'),
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: MotionLayout(
            planner: _planner,
            layoutBuilder: (context, children) =>
                Wrap(spacing: 8, runSpacing: 8, children: children),
            children: [
              for (final tag in _tags)
                GestureDetector(
                  key: ValueKey(tag),
                  onTap: () => _front(tag),
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: tint.withValues(alpha: 0.14),
                      shape: const StadiumBorder(),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Text(tag, style: TextStyle(color: tint)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        GlassListRow(
          leading: const Icon(CupertinoIcons.shuffle),
          title: const Text('Shuffle'),
          onPressed: _shuffle,
        ),
      ],
    );
  }
}
