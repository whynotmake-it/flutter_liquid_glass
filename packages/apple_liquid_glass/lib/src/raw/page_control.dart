import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';

/// When a page control shows the platter behind its dots.
///
/// UIKit: `UIPageControl.BackgroundStyle`.
enum GlassPageControlBackground {
  /// Only while the user interacts with the control.
  automatic,

  /// Always.
  prominent,

  /// Never.
  minimal,
}

/// Builds a page control from [details]; it runs again when the control's
/// states or progress change, never while it moves.
typedef GlassPageControlBuilder = Widget Function(
  BuildContext context,
  GlassPageControlDetails details,
);

/// What a [GlassPageControlBuilder] builds a page control from.
@immutable
final class GlassPageControlDetails {
  /// Describes a page control.
  const GlassPageControlDetails({
    required this.pose,
    required this.progress,
    required this.states,
    this.statesListenable,
  });

  /// Where the indicators sit and how they show, as the control moves.
  final MotionSelection<GlassPageControlPose> pose;

  /// How far the current page has progressed, 0 to 1, or null for plain
  /// dots.
  final double? progress;

  /// The states the control is in: [WidgetState.disabled] while it ignores
  /// input, and what its input region writes (pressed, hovered, focused).
  final Set<WidgetState> states;

  /// The control's states as they change, or null for a look that shows
  /// neither focus nor hover: a builder hands it to the `GlassSurface` of
  /// the platter, whose renderer then draws the focus ring and the hover
  /// response.
  final ValueListenable<Set<WidgetState>>? statesListenable;
}

/// A page control's indicators at one moment, in the control's box.
@immutable
final class GlassPageControlPose {
  /// Describes the indicators.
  const GlassPageControlPose({
    required this.indicators,
    required this.fills,
    required this.platter,
    required this.page,
  });

  factory GlassPageControlPose._of(
    PageControlMotion motion, {
    required GlassPageControlBackground background,
    required bool rtl,
  }) {
    return GlassPageControlPose(
      indicators: motion.indicatorRects(rtl: rtl),
      fills: [for (var i = 0; i < motion.count; i++) motion.fillOpacity(i)],
      platter: switch (background) {
        GlassPageControlBackground.prominent => 1,
        GlassPageControlBackground.minimal => 0,
        GlassPageControlBackground.automatic => motion.platter,
      },
      page: motion.page,
    );
  }

  /// Each page's indicator box, a dot tall and as wide as the indicator, in
  /// which a look draws a capsule; mirrored in a right-to-left context.
  final List<Rect> indicators;

  /// How far each indicator's fill shows, 0 to 1: 1 on the current page,
  /// fading on the page just left, 0 elsewhere. A look draws the fill only
  /// while the control shows a progress.
  final List<double> fills;

  /// How far the platter behind the indicators shows, 0 to 1.
  final double platter;

  /// The page the indicators show as current.
  final int page;

  @override
  bool operator ==(Object other) =>
      other is GlassPageControlPose &&
      other.platter == platter &&
      other.page == page &&
      listEquals(other.indicators, indicators) &&
      listEquals(other.fills, fills);

  @override
  int get hashCode => Object.hash(
    platter,
    page,
    Object.hashAll(indicators),
    Object.hashAll(fills),
  );
}

/// A page control with the measured motion of iOS 27's `UIPageControl` and
/// no look of its own: [builder] decides how it looks.
///
/// UIKit: `UIPageControl`. SwiftUI: the page style of a `TabView`.
/// Flutter: none.
///
/// It has an indicator for each of [count] pages. A tap on the trailing
/// half moves to the next page and one on the leading half to the
/// previous page, on the lift, as UIKit's does; a finger that moves more
/// than 10 points scrubs to the nearest indicator and plays a selection
/// haptic each time it changes the page (read from UIKit, notes private);
/// a `MotionHapticScope` turns that off. A finger takes it within a 44 point
/// tall area around its 25.67 point box, where its parent leaves that room.
/// With [progress] the current indicator widens into a capsule
/// (`UIPageControlProgress`), and a page change grows and shrinks the
/// capsules on the measured springs. The platter shows per
/// [backgroundStyle], fading in after a touch rests 0.193 s. The value
/// commands of the arrow keys (mirrored in right-to-left), Home and End,
/// and the accessibility increase and decrease step through the pages or
/// go to the first and last; it has no larger step, so Page Up and Page
/// Down do nothing, and neither do Space and Enter, as on Flutter's
/// `Slider`. In a right-to-left context the pages run from the right.
class RawGlassPageControl extends StatefulWidget {
  /// Creates a page control of [count] pages showing [page].
  const RawGlassPageControl({
    required this.count,
    required this.page,
    required this.onChanged,
    required this.builder,
    this.progress,
    this.backgroundStyle = GlassPageControlBackground.automatic,
    this.semanticLabel,
    this.semanticValueFormatter,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  /// The number of pages.
  final int count;

  /// The current page.
  final int page;

  /// Called with the page the user picks; null disables the control. A
  /// control whose [page] does not follow returns to it.
  final ValueChanged<int>? onChanged;

  /// Builds the control's look.
  final GlassPageControlBuilder builder;

  /// How far the current page has progressed, 0 to 1, or null for plain
  /// indicators.
  final double? progress;

  /// When the platter shows.
  final GlassPageControlBackground backgroundStyle;

  /// What accessibility reads for the control.
  final String? semanticLabel;

  /// Formats the adjustable value from a one-based page and the page count;
  /// null reads [GlassLocalizations.pageValue]. An empty control has no
  /// value.
  final String Function(int page, int count)? semanticValueFormatter;

  /// Where the control publishes its states, or null for its own. The
  /// control is its only writer: what else writes to it is written over.
  final WidgetStatesController? statesController;

  /// The control's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the control takes focus when it first appears.
  final bool autofocus;

  @override
  State<RawGlassPageControl> createState() => _RawGlassPageControlState();
}

class _RawGlassPageControlState extends State<RawGlassPageControl>
    with
        ControlStates<RawGlassPageControl>,
        ControlledValue<RawGlassPageControl> {
  late PageControlMotion _motion = _create();
  late MotionSelection<GlassPageControlPose> _pose = _poseOf();
  late final _PageControlInput _input = _PageControlInput(this);
  late final List<Interaction> _interactions = [_input];

  int get _count => math.max(0, widget.count);

  int get _page => _count == 0 ? 0 : widget.page.clamp(0, _count - 1);

  PageControlMotion _create() => PageControlMotion(
    count: _count,
    page: _page,
    showsProgress: widget.progress != null,
    onEvent: _deliver,
  );

  MotionSelection<GlassPageControlPose> _poseOf() {
    final background = widget.backgroundStyle;
    final rtl = _input.rtl;
    return _motion.select(
      (m) => GlassPageControlPose._of(m, background: background, rtl: rtl),
    );
  }

  @override
  WidgetStatesController? get givenStates => widget.statesController;

  @override
  MotionClock get valueClock => _motion.clock;

  @override
  void followWidget() => _setPage(_page);

  @override
  bool get enabled => widget.onChanged != null && _count > 0;

  @override
  void didUpdateWidget(RawGlassPageControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count != oldWidget.count ||
        (widget.progress == null) != (oldWidget.progress == null)) {
      _motion = _create();
      _pose = _poseOf();
      return;
    }
    if (widget.backgroundStyle != oldWidget.backgroundStyle) _pose = _poseOf();
    followWidget();
  }

  void _setPage(int page) {
    if (page == _motion.page) return;
    _motion.setPage(_motion.clock.now, page);
  }

  void _deliver(PageControlEvent event) {
    switch (event) {
      case PageControlPicked(:final page, :final scrubbed):
        if (scrubbed) _input.feel(page);
        tellApp(() {
          if (page != _page) widget.onChanged?.call(page);
        });
    }
  }

  static MotionHaptic? _feedback(InteractionEvent event) =>
      event is ScrubChangeEvent ? MotionHaptic.selection : null;

  void _command(ValueCommand command) {
    if (!enabled) return;
    final next = switch (command) {
      ValueCommand.increase => _page + 1,
      ValueCommand.decrease => _page - 1,
      ValueCommand.toMinimum => 0,
      ValueCommand.toMaximum => _count - 1,
      ValueCommand.increaseLarge || ValueCommand.decreaseLarge => _page,
    }.clamp(0, _count - 1);
    if (next != _page) widget.onChanged?.call(next);
  }

  Size get _size => _motion.size;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    if (rtl == _input.rtl) return;
    _input.rtl = rtl;
    _pose = _poseOf();
  }

  @override
  Widget buildControl(BuildContext context) {
    final count = _count;
    final page = _page;
    final strings = GlassLocalizations.of(context);
    String value(int page) =>
        widget.semanticValueFormatter?.call(page, count) ??
        strings.pageValue(page, count);
    return MotionScope(
      motion: _motion,
      child: InputRegion(
        interactions: _interactions,
        enabled: enabled,
        statesController: widgetStates,
        feedback: _feedback,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        semantics: SemanticsProperties(
          label: widget.semanticLabel,
          value: count == 0 ? null : value(page + 1),
          increasedValue: count == 0 ? null : value(math.min(page + 2, count)),
          decreasedValue: count == 0 ? null : value(math.max(page, 1)),
        ),
        reach: glassTargetReach,
        child: SizedBox.fromSize(
          size: _size,
          child: widget.builder(
            context,
            GlassPageControlDetails(
              pose: _pose,
              progress: widget.progress,
              states: {...widgetStates.value},
              statesListenable: widgetStates,
            ),
          ),
        ),
      ),
    );
  }
}

/// A page control's touch: taps and scrubs anywhere on it, held against a
/// scroll. It adjusts: the region's value commands reach the control
/// through it. A scrub onto another page reaches the region as a
/// [ScrubChangeEvent], for its haptic.
final class _PageControlInput extends Interaction {
  _PageControlInput(this.state) : super(role: InteractionRole.control);

  final _RawGlassPageControlState state;
  bool rtl = false;
  int? _pointer;
  final List<InteractionEvent> _felt = [];

  @override
  bool get pressed => _pointer != null;

  @override
  bool get adjusts => true;

  void feel(int page) => _felt.add(
    ScrubChangeEvent(time: state._motion.now, selected: page),
  );

  double _x(Offset position) {
    return state._motion.contentX(position.dx, rtl: rtl);
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    final update = _handle(input);
    if (_felt.isEmpty) return update;
    final events = [...update.events, ..._felt];
    _felt.clear();
    return InteractionUpdate(
      claims: update.claims,
      recognizes: update.recognizes,
      fails: update.fails,
      events: events,
    );
  }

  InteractionUpdate _handle(InteractionInput input) {
    final motion = state._motion;
    switch (input) {
      case AdjustInput(:final command):
        state._command(command);
      case PointerDownInput() when _pointer == null && accepts(input):
        _pointer = input.pointer;
        motion.pointerDown(input.time, _x(input.position));
        return const InteractionUpdate(claims: true);
      case PointerMoveInput() when input.pointer == _pointer:
        motion.pointerMove(input.time, _x(input.position));
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        motion.pointerUp(
          input.time,
          _x(input.position),
          width: state._size.width,
        );
        return const InteractionUpdate(recognizes: true);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        motion.pointerCancel(input.time);
        return const InteractionUpdate(fails: true);
      default:
    }
    return InteractionUpdate.none;
  }
}
