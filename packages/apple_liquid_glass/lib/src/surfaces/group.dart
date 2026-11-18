import 'package:apple_liquid_glass/src/surfaces/renderer.dart';
import 'package:apple_liquid_glass/src/surfaces/renderer_scope.dart';
import 'package:flutter/widgets.dart';

/// How the surfaces of a [GlassGroup] fuse.
@immutable
final class GlassMerge {
  /// The members never fuse.
  const GlassMerge.none() : spacing = null;

  /// The members fuse into one body where they come within about [spacing]
  /// of each other, on real liquid glass; fake and flat glass keep them
  /// apart.
  const GlassMerge.spacing(double this.spacing);

  /// How close members come before they fuse, or null when they never do.
  final double? spacing;

  @override
  bool operator ==(Object other) =>
      other is GlassMerge && other.spacing == spacing;

  @override
  int get hashCode => spacing.hashCode;
}

/// Surfaces that belong together, such as the buttons of a toolbar.
///
/// UIKit: `UIGlassContainerEffect`. SwiftUI: `GlassEffectContainer`.
///
/// It declares belonging only; how the members are drawn together is the
/// renderer's: the liquid renderer draws them on one glass layer, so they
/// read what lies behind them once, and fuses them as [merge] says. The
/// subtree keeps its state when the renderer changes.
class GlassGroup extends StatefulWidget {
  /// Groups the surfaces in [child].
  const GlassGroup({
    required this.child,
    this.merge = const GlassMerge.none(),
    super.key,
  });

  /// How the members fuse.
  final GlassMerge merge;

  /// The subtree holding the members.
  final Widget child;

  @override
  State<GlassGroup> createState() => _GlassGroupState();
}

class _GlassGroupState extends State<GlassGroup> {
  final _child = GlobalKey(debugLabel: 'GlassGroup.child');

  @override
  Widget build(BuildContext context) =>
      GlassRendererScope.of(context).buildGroup(
        context,
        GlassGroupDetails(
          merge: widget.merge,
          child: KeyedSubtree(key: _child, child: widget.child),
        ),
      );
}
