import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:motor/motor.dart';

/// Responsive, in-layout settings panel inspired by ClickUp's split scaffold.
///
/// Wide windows reserve space on the trailing edge. Compact windows reserve
/// space at the bottom, so opening the panel moves the example up instead of
/// covering it.
class SettingsSplitScaffold extends StatefulWidget {
  const SettingsSplitScaffold({
    required this.open,
    required this.onOpenChanged,
    required this.child,
    required this.panel,
    super.key,
    this.sidebarWidth = 360,
    this.compactBreakpoint = 700,
  });

  final bool open;
  final ValueChanged<bool> onOpenChanged;
  final Widget child;
  final Widget panel;
  final double sidebarWidth;
  final double compactBreakpoint;

  @override
  State<SettingsSplitScaffold> createState() => _SettingsSplitScaffoldState();
}

class _SettingsSplitScaffoldState extends State<SettingsSplitScaffold>
    with SingleTickerProviderStateMixin {
  late final BoundedSingleMotionController _controller =
      BoundedSingleMotionController(
        motion: const Motion.smoothSpring(snapToEnd: true),
        vsync: this,
        initialValue: widget.open ? 1 : 0,
      );

  @override
  void didUpdateWidget(covariant SettingsSplitScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open != widget.open) {
      _controller.animateTo(widget.open ? 1 : 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < widget.compactBreakpoint;
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final progress = _controller.value.clamp(0.0, 1.0);
            if (compact) {
              final panelHeight = math
                  .min(440, constraints.maxHeight * 0.56)
                  .toDouble();
              return Column(
                children: [
                  Expanded(child: widget.child),
                  _AnimatedPanelExtent(
                    key: const ValueKey('settings-bottom-panel'),
                    axis: Axis.vertical,
                    extent: panelHeight * progress,
                    fullExtent: panelHeight,
                    alignment: Alignment.topCenter,
                    child: ClipRSuperellipse(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      child: ColoredBox(
                        color: CupertinoColors.black,
                        child: Column(
                          children: [
                            _MobileDragHandle(
                              onVerticalDragStart: _onVerticalDragStart,
                              onVerticalDragUpdate: (details) =>
                                  _onVerticalDragUpdate(details, panelHeight),
                              onVerticalDragEnd: (details) =>
                                  _onVerticalDragEnd(details, panelHeight),
                            ),
                            Expanded(child: widget.panel),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: widget.child),
                _AnimatedPanelExtent(
                  key: const ValueKey('settings-sidebar-panel'),
                  axis: Axis.horizontal,
                  extent: widget.sidebarWidth * progress,
                  fullExtent: widget.sidebarWidth,
                  alignment: Alignment.centerLeft,
                  child: widget.panel,
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _controller.stop();
  }

  void _onVerticalDragUpdate(
    DragUpdateDetails details,
    double panelHeight,
  ) {
    _controller.value -= details.delta.dy / panelHeight;
  }

  void _onVerticalDragEnd(DragEndDetails details, double panelHeight) {
    final velocity = -details.velocity.pixelsPerSecond.dy / panelHeight;
    final shouldOpen = velocity.abs() > 0.35
        ? velocity > 0
        : _controller.value >= 0.5;
    widget.onOpenChanged(shouldOpen);
    _controller.animateTo(shouldOpen ? 1 : 0, withVelocity: velocity);
  }
}

class _MobileDragHandle extends StatelessWidget {
  const _MobileDragHandle({
    required this.onVerticalDragStart,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
  });

  final GestureDragStartCallback onVerticalDragStart;
  final GestureDragUpdateCallback onVerticalDragUpdate;
  final GestureDragEndCallback onVerticalDragEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('settings-drag-handle'),
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: onVerticalDragStart,
      onVerticalDragUpdate: onVerticalDragUpdate,
      onVerticalDragEnd: onVerticalDragEnd,
      child: ColoredBox(
        color: CupertinoColors.black,
        child: SizedBox(
          height: 36,
          width: double.infinity,
          child: Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xff636366),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedPanelExtent extends StatelessWidget {
  const _AnimatedPanelExtent({
    required this.axis,
    required this.extent,
    required this.fullExtent,
    required this.alignment,
    required this.child,
    super.key,
  });

  final Axis axis;
  final double extent;
  final double fullExtent;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox(
        width: axis == Axis.horizontal ? extent : double.infinity,
        height: axis == Axis.vertical ? extent : double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) => OverflowBox(
            alignment: alignment,
            minWidth: axis == Axis.horizontal
                ? fullExtent
                : constraints.maxWidth,
            maxWidth: axis == Axis.horizontal
                ? fullExtent
                : constraints.maxWidth,
            minHeight: axis == Axis.vertical
                ? fullExtent
                : constraints.maxHeight,
            maxHeight: axis == Axis.vertical
                ? fullExtent
                : constraints.maxHeight,
            child: child,
          ),
        ),
      ),
    );
  }
}
