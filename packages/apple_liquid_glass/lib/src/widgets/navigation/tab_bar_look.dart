part of 'tab_bar.dart';

class _TabContent extends StatelessWidget {
  const _TabContent({
    required this.destination,
    required this.look,
    required this.states,
    required this.morph,
  });

  final GlassTabDestination destination;
  final GlassTabBarStyle look;
  final Set<WidgetState> states;
  final MotionSelection<double>? morph;

  @override
  Widget build(BuildContext context) {
    final color = StateColors(context, states)(look.foregroundColor);
    final selected = states.contains(WidgetState.selected);
    final badge = destination.badge;
    final icon = IconTheme.merge(
      data: IconThemeData(color: color, size: GlassTabBar.iconSize),
      child: selected
          ? destination.selectedIcon ?? destination.icon
          : destination.icon,
    );
    final glyph = badge == null ? icon : _Badged(badge: badge, child: icon);
    final scale = GlassTextScale.of(context, max: GlassTabBar.maxTextScale);
    final content = scale.apply(
      _TabItem(
        morph: morph,
        titleGoneAt: selected
            ? TabBarMinimizeMotion.lensGoneAt
            : TabBarMinimizeMotion.titlesGoneAt,
        children: [
          glyph,
          DefaultTextStyle.merge(
            style: scale.resolve(
              look.textStyle!.resolve(states)!.copyWith(color: color),
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            child: destination.label,
          ),
        ],
      ),
    );
    return GlassHighlightPaint.of(
      context,
      heldStates: states,
      focusColor: look.focusColor,
      hoverColor: look.hoverColor,
      inside: true,
      wash: true,
      child: SizedBox.expand(
        child: Center(
          child: destination.enabled
              ? content
              : Opacity(opacity: 0.5, child: content),
        ),
      ),
    );
  }
}

/// A badge at the top trailing corner of a tab's glyph: its leading edge 5
/// points inside the glyph's trailing edge and its top 6 points above the
/// glyph's, by eye (UIKit places it 2 points below the tab button's top).
class _Badged extends StatelessWidget {
  const _Badged({required this.badge, required this.child});

  final Widget badge;
  final Widget child;

  static const double _inset = 5;
  static const double _rise = 6;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      child,
      PositionedDirectional(
        start: GlassTabBar.iconSize - _inset,
        top: -_rise,
        child: badge,
      ),
    ],
  );
}
