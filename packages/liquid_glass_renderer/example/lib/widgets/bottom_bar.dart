// ignore_for_file: deprecated_member_use

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:motor/motor.dart';

/// Creates a jelly transform matrix based on velocity for organic squash and stretch effect
Matrix4 buildJellyTransform({
  required Offset velocity,
  double maxDistortion = 0.7,
  double velocityScale = 1000.0,
}) {
  // Calculate the magnitude of velocity to determine distortion intensity
  final speed = velocity.distance;

  // Normalize velocity direction
  final direction = speed > 0 ? velocity / speed : Offset.zero;

  // Apply a scaling factor to make the effect more pronounced
  final distortionFactor =
      (speed / velocityScale).clamp(0.0, 1.0) * maxDistortion;

  if (distortionFactor == 0) {
    return Matrix4.identity();
  }

  // Create squash and stretch effect
  // Squash in the direction of movement, stretch perpendicular to it
  final squashX = 1.0 - (direction.dx.abs() * distortionFactor * 0.5);
  final squashY = 1.0 - (direction.dy.abs() * distortionFactor * 0.5);
  final stretchX = 1.0 + (direction.dy.abs() * distortionFactor * 0.3);
  final stretchY = 1.0 + (direction.dx.abs() * distortionFactor * 0.3);

  // Combine squash and stretch effects
  final scaleX = squashX * stretchX;
  final scaleY = squashY * stretchY;

  // Build the transformation matrix
  final matrix = Matrix4.identity();

  // Apply scale transformation
  matrix.scale(scaleX, scaleY);

  return matrix;
}

class LiquidGlassBottomBar extends StatefulWidget {
  const LiquidGlassBottomBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onTabSelected,
    this.extraButton,
    this.spacing = 8,
    this.horizontalPadding = 20,
    this.bottomPadding = 20,
    this.barHeight = 64,
    this.glassSettings,
    this.showIndicator = true,
    this.indicatorColor,
    this.fake = false,
  });

  final List<LiquidGlassBottomBarTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final LiquidGlassBottomBarExtraButton? extraButton;
  final double spacing;
  final double horizontalPadding;
  final double bottomPadding;
  final double barHeight;
  final LiquidGlassSettings? glassSettings;
  final bool showIndicator;
  final Color? indicatorColor;
  final bool fake;

  @override
  State<LiquidGlassBottomBar> createState() => _LiquidGlassBottomBarState();
}

class _LiquidGlassBottomBarState extends State<LiquidGlassBottomBar> {
  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;

    final glassSettings =
        widget.glassSettings ??
        LiquidGlassSettings(
          refractiveIndex: 1.21,
          thickness: 30,
          blur: 8,
          saturation: 1.5,
          blend: 10,
          lightIntensity: isDark ? .7 : 1,
          ambientStrength: isDark ? .2 : .5,
          lightAngle: math.pi / 4,
          glassColor: CupertinoTheme.of(
            context,
          ).barBackgroundColor.withValues(alpha: 0.6),
        );

    return LiquidGlassLayer(
      settings: glassSettings,
      fake: widget.fake,
      child: Padding(
        padding: EdgeInsets.only(
          right: widget.horizontalPadding,
          left: widget.horizontalPadding,
          bottom: widget.bottomPadding,
          top: widget.bottomPadding,
        ),
        child: Row(
          spacing: widget.spacing,
          children: [
            Expanded(
              child: _TabIndicator(
                fake: widget.fake,
                visible: widget.showIndicator,
                tabIndex: widget.selectedIndex,
                tabCount: widget.tabs.length,
                indicatorColor: widget.indicatorColor,
                onTabChanged: widget.onTabSelected,
                child: LiquidGlass.inLayer(
                  clipBehavior: Clip.none,
                  shape: const LiquidRoundedSuperellipse(
                    borderRadius: Radius.circular(32),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    height: widget.barHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        for (var i = 0; i < widget.tabs.length; i++)
                          Expanded(
                            child: _BottomBarTab(
                              tab: widget.tabs[i],
                              selected: widget.selectedIndex == i,
                              onTap: () => widget.onTabSelected(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (widget.extraButton != null)
              _ExtraButton(config: widget.extraButton!, fake: widget.fake),
          ],
        ),
      ),
    );
  }
}

class LiquidGlassBottomBarTab {
  const LiquidGlassBottomBarTab({
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.glowColor,
  });

  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final Color? glowColor;
}

class LiquidGlassBottomBarExtraButton {
  const LiquidGlassBottomBarExtraButton({
    required this.icon,
    required this.onTap,
    required this.label,
    this.size = 64,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String label;
  final double size;
}

class _BottomBarTab extends StatelessWidget {
  const _BottomBarTab({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final LiquidGlassBottomBarTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    final iconColor = selected
        ? theme.primaryColor
        : theme.textTheme.textStyle.color;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        label: tab.label,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (tab.glowColor != null)
                      Positioned(
                        top: -24,
                        right: -24,
                        left: -24,
                        bottom: -24,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          transformAlignment: Alignment.center,
                          curve: Curves.easeOutCirc,
                          transform: selected
                              ? Matrix4.identity()
                              : (Matrix4.identity()
                                  ..scale(0.4)
                                  ..rotateZ(-math.pi)),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: selected ? 1 : 0,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: tab.glowColor!.withOpacity(
                                      selected ? 0.6 : 0,
                                    ),
                                    blurRadius: 32,
                                    spreadRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    AnimatedScale(
                      scale: 1,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        selected ? (tab.selectedIcon ?? tab.icon) : tab.icon,
                        color: iconColor,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tab.label,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: iconColor,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExtraButton extends StatefulWidget {
  const _ExtraButton({required this.config, this.fake = false});

  final LiquidGlassBottomBarExtraButton config;
  final bool fake;

  @override
  State<_ExtraButton> createState() => _ExtraButtonState();
}

class _ExtraButtonState extends State<_ExtraButton> {
  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    return GestureDetector(
      onTap: widget.config.onTap,
      child: LiquidStretch(
        child: Semantics(
          button: true,
          label: widget.config.label,
          child: LiquidGlass.inLayer(
            shape: const LiquidOval(),
            child: GlassGlow(
              child: Container(
                height: widget.config.size,
                width: widget.config.size,
                child: Center(
                  child: Icon(
                    widget.config.icon,
                    size: 24,
                    color: theme.textTheme.textStyle.color,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabIndicator extends StatefulWidget {
  const _TabIndicator({
    required this.child,
    required this.tabIndex,
    required this.tabCount,
    required this.onTabChanged,
    this.visible = true,
    this.indicatorColor,
    this.fake = false,
  });

  final int tabIndex;
  final int tabCount;
  final bool visible;
  final Widget child;
  final Color? indicatorColor;
  final ValueChanged<int> onTabChanged;
  final bool fake;

  @override
  State<_TabIndicator> createState() => _TabIndicatorState();
}

class _TabIndicatorState extends State<_TabIndicator>
    with SingleTickerProviderStateMixin {
  bool _isDown = false;
  bool _isDragging = false;

  late double xAlign = computeXAlignmentForTab(widget.tabIndex);

  @override
  void initState() {
    super.initState();
  }

  double computeXAlignmentForTab(int tabIndex) {
    final relativeTabIndex = (tabIndex / (widget.tabCount - 1)).clamp(0.0, 1.0);
    return (relativeTabIndex * 2) - 1; // -1 to 1
  }

  @override
  void didUpdateWidget(covariant _TabIndicator oldWidget) {
    if (oldWidget.tabIndex != widget.tabIndex ||
        oldWidget.tabCount != widget.tabCount) {
      setState(() {
        xAlign = computeXAlignmentForTab(widget.tabIndex);
      });
    }
    super.didUpdateWidget(oldWidget);
  }

  double _getAlignmentFromGlobalPostition(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox;
    final localPosition = box.globalToLocal(globalPosition);

    // Calculate the effective draggable range
    // The indicator moves within the tab bar, but has its own width (1/tabCount of total)
    final indicatorWidth = 1.0 / widget.tabCount; // Relative width of indicator
    final draggableRange =
        1.0 - indicatorWidth; // Range the indicator center can move
    final padding = indicatorWidth / 2; // Padding on each side

    // Map the drag position to the draggable range
    final rawRelativeX = (localPosition.dx / box.size.width).clamp(0.0, 1.0);
    final normalizedX = (rawRelativeX - padding) / draggableRange;

    // Apply rubber band resistance for overdrag
    final adjustedRelativeX = _applyRubberBandResistance(normalizedX);
    return (adjustedRelativeX * 2) - 1; // Convert to -1:1 range
  }

  void _onDragDown(DragDownDetails details) {
    setState(() {
      _isDown = true;
      xAlign = _getAlignmentFromGlobalPostition(details.globalPosition);
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _isDragging = true;
      xAlign = _getAlignmentFromGlobalPostition(details.globalPosition);
    });
  }

  // Apply rubber band resistance similar to iOS scroll views
  double _applyRubberBandResistance(double value) {
    const double resistance = 0.4; // Lower values = more resistance
    const double maxOverdrag =
        0.3; // Maximum overdrag as fraction of normal range

    if (value < 0) {
      // Overdrag to the left
      final overdrag = -value;
      final resistedOverdrag = overdrag * resistance;
      return -resistedOverdrag.clamp(0.0, maxOverdrag);
    } else if (value > 1) {
      // Overdrag to the right
      final overdrag = value - 1;
      final resistedOverdrag = overdrag * resistance;
      return 1 + resistedOverdrag.clamp(0.0, maxOverdrag);
    } else {
      // Normal range, no resistance
      return value;
    }
  }

  void _onDragEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
      _isDown = false;
    });

    final box = context.findRenderObject() as RenderBox;
    final currentRelativeX = (xAlign + 1) / 2; // Convert from -1:1 to 0:1
    final tabWidth = 1.0 / widget.tabCount;

    // Calculate velocity in relative units, adjusted for the draggable range
    final indicatorWidth = 1.0 / widget.tabCount;
    final draggableRange = 1.0 - indicatorWidth;
    final velocityX =
        (details.velocity.pixelsPerSecond.dx / box.size.width) / draggableRange;

    // Determine target tab based on position and velocity
    int targetTabIndex;

    // Handle overdrag scenarios first
    if (currentRelativeX < 0) {
      // Overdragged to the left - snap to first tab
      targetTabIndex = 0;
    } else if (currentRelativeX > 1) {
      // Overdragged to the right - snap to last tab
      targetTabIndex = widget.tabCount - 1;
    } else {
      // Normal range - consider velocity
      const velocityThreshold = 0.5; // Adjust this threshold as needed
      if (velocityX.abs() > velocityThreshold) {
        // High velocity - project where we would end up
        final projectedX = (currentRelativeX + velocityX * 0.3).clamp(
          0.0,
          1.0,
        ); // 0.3s projection
        targetTabIndex = (projectedX / tabWidth).round().clamp(
          0,
          widget.tabCount - 1,
        );

        // Ensure we move at least one tab if velocity is strong enough
        final currentTabIndex = (currentRelativeX / tabWidth).round().clamp(
          0,
          widget.tabCount - 1,
        );
        if (velocityX > velocityThreshold &&
            targetTabIndex <= currentTabIndex &&
            currentTabIndex < widget.tabCount - 1) {
          targetTabIndex = currentTabIndex + 1;
        } else if (velocityX < -velocityThreshold &&
            targetTabIndex >= currentTabIndex &&
            currentTabIndex > 0) {
          targetTabIndex = currentTabIndex - 1;
        }
      } else {
        // Low velocity - snap to nearest tab
        targetTabIndex = (currentRelativeX / tabWidth).round().clamp(
          0,
          widget.tabCount - 1,
        );
      }
    }
    xAlign = computeXAlignmentForTab(targetTabIndex);

    // Notify parent of tab change if different from current
    if (targetTabIndex != widget.tabIndex) {
      widget.onTabChanged(targetTabIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    final indicatorColor =
        widget.indicatorColor ??
        theme.textTheme.textStyle.color?.withValues(alpha: .1);
    final targetAlignment = computeXAlignmentForTab(widget.tabIndex);

    return GestureDetector(
      onHorizontalDragDown: _onDragDown,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: () => setState(() {
        _isDragging = false;
        _isDown = false;
      }),
      child: VelocityMotionBuilder(
        converter: SingleMotionConverter(),
        value: xAlign,
        motion: _isDragging
            ? const Motion.interactiveSpring(snapToEnd: true)
            : const Motion.bouncySpring(snapToEnd: true),
        builder: (context, value, velocity, child) {
          final alignment = Alignment(value, 0);
          return SingleMotionBuilder(
            motion: const Motion.snappySpring(
              snapToEnd: true,
              duration: Duration(milliseconds: 300),
            ),
            value:
                widget.visible &&
                    (_isDown || (alignment.x - targetAlignment).abs() > 0.30)
                ? 1.0
                : 0.0,
            builder: (context, thickness, child) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  if (thickness < 1)
                    _IndicatorTransform(
                      velocity: velocity,
                      tabCount: widget.tabCount,
                      alignment: alignment,
                      thickness: thickness,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: widget.visible && thickness <= .2 ? 1 : 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: indicatorColor,
                            borderRadius: BorderRadius.circular(64),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  child!,
                  if (thickness > 0)
                    _IndicatorTransform(
                      velocity: velocity,
                      tabCount: widget.tabCount,
                      alignment: alignment,
                      thickness: thickness,
                      child: LiquidGlass(
                        fake: widget.fake,
                        settings: LiquidGlassSettings(
                          visibility: thickness,
                          glassColor: Color.from(
                            alpha: .1,
                            red: 1,
                            green: 1,
                            blue: 1,
                          ),
                          saturation: 1.5,
                          refractiveIndex: 1.15,
                          thickness: 20,
                          lightIntensity: 2,
                          chromaticAberration: .5,
                          blur: 0,
                        ),
                        shape: const LiquidRoundedSuperellipse(
                          borderRadius: Radius.circular(64),
                        ),
                        child: GlassGlow(child: const SizedBox.expand()),
                      ),
                    ),
                ],
              );
            },
            child: widget.child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _IndicatorTransform extends StatelessWidget {
  const _IndicatorTransform({
    required this.velocity,
    required this.tabCount,
    required this.alignment,
    required this.thickness,
    required this.child,
  });

  final double velocity;
  final int tabCount;
  final Alignment alignment;
  final double thickness;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rect = RelativeRect.lerp(
      RelativeRect.fill,
      const RelativeRect.fromLTRB(-14, -14, -14, -14),
      thickness,
    );
    return Positioned.fill(
      left: 4,
      right: 4,
      top: 4,
      bottom: 4,
      child: FractionallySizedBox(
        widthFactor: 1 / tabCount,
        alignment: alignment,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRelativeRect(
              rect: rect!,
              child: SingleMotionBuilder(
                motion: Motion.bouncySpring(
                  duration: const Duration(milliseconds: 600),
                ),
                value: velocity,
                builder: (context, velocity, child) {
                  return Transform(
                    alignment: Alignment.center,
                    transform: buildJellyTransform(
                      velocity: Offset(velocity, 0),
                      maxDistortion: .8,
                      velocityScale: 10,
                    ),
                    child: child,
                  );
                },
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
