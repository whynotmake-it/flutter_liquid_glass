import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';

/// The rows of a list by id in a sliver: a change of [ids] inside
/// `withSpring` slides the rows that stay to their new places, fades new
/// rows in and gone rows out where they were, and moves reordered rows;
/// outside one it jumps.
///
/// UIKit: `UITableView` `performBatchUpdates` with `insertRows`,
/// `deleteRows` and `moveRow`. SwiftUI: `ForEach` in a `List`. Flutter:
/// `SliverAnimatedList`.
///
/// It has no look of its own: `GlassSliverListSection` gives rows its
/// card. Rows are built lazily by id ([SliverMotionList]). Not measured:
/// UIKit's row animations were not captured; the rows move on the app's
/// spring with [planner]'s effects.
class RawGlassList extends StatelessWidget {
  /// Creates a list of the rows [itemBuilder] builds for [ids].
  const RawGlassList({
    required this.ids,
    required this.itemBuilder,
    this.planner = const LayoutPlanner.flip(),
    super.key,
  });

  /// What identifies each row, in order.
  final List<Object> ids;

  /// Builds the row of an id.
  final Widget Function(BuildContext context, Object id) itemBuilder;

  /// How a change of the rows animates.
  final LayoutPlanner planner;

  @override
  Widget build(BuildContext context) =>
      SliverMotionList(ids: ids, planner: planner, itemBuilder: itemBuilder);
}
