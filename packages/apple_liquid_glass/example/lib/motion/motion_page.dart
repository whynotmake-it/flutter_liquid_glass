import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/gallery_bar.dart';
import 'package:apple_liquid_glass_example/motion/chips.dart';
import 'package:apple_liquid_glass_example/motion/grid_list.dart';
import 'package:apple_liquid_glass_example/motion/notes.dart';
import 'package:apple_liquid_glass_example/motion/own_control.dart';
import 'package:apple_liquid_glass_example/motion/peek.dart';
import 'package:apple_liquid_glass_example/motion/two_lines.dart';
import 'package:flutter/widgets.dart';

/// What kinesis gives an app: layouts that animate, presentations and a
/// control of its own, and a replay of a touch.
class MotionPage extends StatefulWidget {
  const MotionPage({super.key});

  @override
  State<MotionPage> createState() => _MotionPageState();
}

class _MotionPageState extends State<MotionPage> {
  final _recording = KnobRecording(KnobMotion());
  var _reduceMotion = false;

  @override
  void dispose() {
    _recording.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MotionTraitsOverride(
    traits: _reduceMotion
        ? const MotionTraits(reduceMotion: true)
        : MotionTraits.platform(),
    child: GlassPageScaffold(
      backgroundColor: GlassColors.systemGroupedBackground,
      navigationBar: GlassNavigationBar(
        largeTitle: const Text('Motion'),
        trailing: galleryItems(context),
      ),
      child: GlassContentScroll(
        child: CustomScrollView(
          slivers: [
            SliverSafeArea(
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: TwoLines(
                      reduceMotion: _reduceMotion,
                      onReduceMotion: (on) =>
                          setState(() => _reduceMotion = on),
                    ),
                  ),
                  const NotesSection(),
                  const SliverToBoxAdapter(child: ChipsSection()),
                  const SliverToBoxAdapter(child: GridListSection()),
                  const SliverToBoxAdapter(child: PeekSection()),
                  SliverToBoxAdapter(
                    child: OwnControlSection(recording: _recording),
                  ),
                  SliverToBoxAdapter(child: Replay(recording: _recording)),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
