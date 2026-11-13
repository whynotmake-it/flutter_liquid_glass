import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/composer/plan_result.dart';

/// What a frame did beyond its plan, counted where it happens.
///
/// A renderer adds one to a count each time it does that work, in debug and
/// profile builds; [GlassFrameReport] reads the counts into a frame's report
/// and starts them again from zero. The counts run from the end of the last
/// reported frame to the end of this one, so they hold what paint recorded
/// and what the scene added too.
abstract final class GlassWork {
  /// Image filters made.
  static int filters = 0;

  /// Pictures recorded for glass.
  static int pictures = 0;

  /// Images drawn for reads.
  static int images = 0;

  /// Layers a read added again to the scene.
  static int replayed = 0;

  /// Repaints the composer asked for.
  static int marks = 0;

  /// Those of [marks] asked after paint, which land a frame late: the glass
  /// shows its content where it is now and its silhouette, shadows and clip
  /// where they were for one frame.
  static int lateMarks = 0;

  static void _clear() {
    filters = 0;
    pictures = 0;
    images = 0;
    replayed = 0;
    marks = 0;
    lateMarks = 0;
  }
}

/// Where a read's backdrop came from in a [GlassFrameReport].
enum GlassReadSource {
  /// Layers under the glass, added again to the scene this frame.
  scene,

  /// An image drawn this frame.
  image,

  /// An image drawn in an earlier frame, which costs one texture read.
  heldImage,

  /// The screen behind the glass, read as a backdrop filter does.
  live,
}

/// One backdrop read of a frame, and the glass that shares it.
@immutable
final class GlassReadReport {
  /// Describes a read.
  const GlassReadReport({
    required this.source,
    required this.level,
    required this.glass,
    required this.hasBand,
    required this.band,
    required this.targets,
    required this.changed,
  });

  /// Where its backdrop came from.
  final GlassReadSource source;

  /// How deep it lies: zero over pictures alone, else one more than the
  /// deepest read it holds.
  final int level;

  /// How many glass surfaces draw from it.
  final int glass;

  /// Whether a scroll edge draws from it too.
  final bool hasBand;

  /// What it holds of what lies under the glass, in logical pixels.
  final Rect band;

  /// Offscreen targets it takes this frame.
  final int targets;

  /// Whether what it holds differs from the last frame.
  final bool changed;

  @override
  String toString() {
    final who = hasBand ? 'band + $glass glass' : '$glass glass';
    final size = '${band.width.round()}x${band.height.round()}';
    return '${source.name}  lvl$level  $who  $size  targets $targets'
        '${changed ? '  changed' : ''}';
  }
}

/// What the glass planner decided for one frame and what the frame cost.
///
/// Nothing here can be tuned, because no widget has a field for a layer, a
/// copy or a group. The lines to act on are the ones naming a layer that makes
/// glass read live, such as a layer type nobody registered with
/// `LiquidGlassUnderlay.registerLayer`.
///
/// Reports exist in debug and profile builds while someone listens
/// ([addListener], `debugDumpGlassPlan`, `GlassPlanOverlay`).
@immutable
final class GlassFrameReport {
  /// Describes a frame.
  const GlassFrameReport({
    required this.frame,
    required this.planned,
    required this.reads,
    required this.targetBudget,
    required this.issuedTargets,
    required this.walk,
    required this.compile,
    required this.emit,
    required this.filtersBuilt,
    required this.picturesRecorded,
    required this.imagesDrawn,
    required this.layersReplayed,
    required this.repaintsAsked,
    required this.lateRepaints,
    required this.notes,
  });

  /// The planner's frame count for its view.
  final int frame;

  /// Whether the frame planned; a frame nothing changed in stands on the last
  /// plan and takes only the [walk].
  final bool planned;

  /// The frame's reads in paint order.
  final List<GlassReadReport> reads;

  /// Targets a frame may issue before reads move to images.
  final int targetBudget;

  /// Offscreen targets the frame takes.
  final int issuedTargets;

  /// Time spent comparing the layer tree with the last frame's.
  final Duration walk;

  /// Time spent deciding the plan.
  final Duration compile;

  /// Time spent drawing the plan into layers and images.
  final Duration emit;

  /// Image filters made in the frame.
  final int filtersBuilt;

  /// Pictures recorded for glass in the frame.
  final int picturesRecorded;

  /// Images drawn for reads in the frame.
  final int imagesDrawn;

  /// Layers reads added again to the scene in the frame.
  final int layersReplayed;

  /// Repaints the planner asked for in the frame.
  final int repaintsAsked;

  /// Those of [repaintsAsked] that land in the next frame.
  final int lateRepaints;

  /// Why glass stays apart or reads live.
  final List<String> notes;

  /// How many reads take the screen behind the glass.
  int get liveReads =>
      reads.where((read) => read.source == GlassReadSource.live).length;

  /// How many reads draw from an image.
  int get imageReads => reads
      .where(
        (read) =>
            read.source == GlassReadSource.image ||
            read.source == GlassReadSource.heldImage,
      )
      .length;

  @override
  String toString() {
    final head =
        'frame $frame${planned ? '' : ' (as planned before)'}  '
        'reads ${reads.length}  targets $issuedTargets/'
        '$targetBudget  images $imageReads  live $liveReads  '
        'walk ${walk.inMicroseconds}us  compile ${compile.inMicroseconds}us  '
        'emit ${emit.inMicroseconds}us';
    final made =
        'made: filters $filtersBuilt  pictures $picturesRecorded  '
        'images $imagesDrawn  replayed $layersReplayed  '
        'repaints $repaintsAsked (late $lateRepaints)';
    final lines = <String>[
      head,
      made,
      for (var i = 0; i < reads.length; i++) 'R$i ${reads[i]}',
      if (notes.isNotEmpty) 'why apart:',
      for (final note in notes) '  $note',
    ];
    return lines.join('\n');
  }

  static final _listeners = <ValueChanged<GlassFrameReport>>[];

  /// Calls [listener] after every frame with glass, in debug and profile
  /// builds. Listening costs the frame the report.
  static void addListener(ValueChanged<GlassFrameReport> listener) {
    if (kReleaseMode) return;
    if (_listeners.isEmpty) GlassWork._clear();
    _listeners.add(listener);
  }

  /// Stops calling [listener].
  static void removeListener(ValueChanged<GlassFrameReport> listener) {
    _listeners.remove(listener);
  }

  /// Whether a frame should report.
  static bool get listening => !kReleaseMode && _listeners.isNotEmpty;

  static final _pending = <GlassFrameReport Function()>[];

  /// Hands the frame's report to the listeners once the frame is over, when
  /// [GlassWork] holds what its scene did as well.
  static void deliver(GlassFrameReport Function() report) {
    _pending.add(report);
    if (_pending.length > 1) return;
    // After the frame: a report counts the scene, which is built after paint.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final reports = [for (final build in _pending) build()];
      _pending.clear();
      GlassWork._clear();
      for (final report in reports) {
        for (final listener in [..._listeners]) {
          listener(report);
        }
      }
    });
  }

  /// Describes a [read] of the frame's plan, or of the last one where that
  /// [stands].
  static GlassReadReport readOf(GlassRead read, {required bool stands}) =>
      GlassReadReport(
        source: switch (read.source) {
          SceneRead() => GlassReadSource.scene,
          ImageRead(:final held) =>
            held || stands ? GlassReadSource.heldImage : GlassReadSource.image,
          LiveRead() => GlassReadSource.live,
        },
        level: read.level,
        glass: read.members.where((site) => !site.isBand).length,
        hasBand: read.lead.isBand,
        band: read.band,
        targets: read.targets,
        changed: !stands && read.changed,
      );
}

/// Prints the next frame's [GlassFrameReport], in debug and profile builds.
void debugDumpGlassPlan() {
  if (kReleaseMode) return;
  late final ValueChanged<GlassFrameReport> listener;
  listener = (report) {
    GlassFrameReport.removeListener(listener);
    debugPrint('$report');
  };
  GlassFrameReport.addListener(listener);
  SchedulerBinding.instance.scheduleFrame();
}
