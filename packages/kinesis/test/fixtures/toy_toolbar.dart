import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// The motion of a toy toolbar's three items: they slide along the bar by
/// [shift], fade by [opacity] and stop taking input while [leaving], all
/// without a rebuild.
class ToyMotion extends ChangeNotifier {
  /// The items, in reading order.
  static const List<String> items = ['a', 'b', 'c'];

  /// The size of an item as painted; below the 44 point minimum on purpose.
  static const Size itemSize = Size(40, 28);

  /// How far the items have slid, toward the end of the line.
  double shift = 0;

  /// The width of the bar, set by the bar as it lays out.
  double width = 200;

  /// Whether the bar is laid out right to left.
  bool rtl = false;

  /// Each item's painted opacity; 1 when absent.
  final Map<String, double> opacity = {};

  /// The items that are leaving and take no input.
  final Set<String> leaving = {};

  /// Each item's painted size; [itemSize] when absent.
  final Map<String, Size> sizes = {};

  /// Slides the items to [to].
  void slide(double to) {
    shift = to;
    notifyListeners();
  }

  /// Says that [opacity] or [leaving] changed.
  void changed() => notifyListeners();

  /// Where [item] is painted now.
  Rect rectOf(String item) {
    final start = 10 + items.indexOf(item) * 60 + shift;
    final size = sizes[item] ?? itemSize;
    final left = rtl ? width - start - size.width : start;
    return Offset(left, 2) & size;
  }

  /// [item]'s frame for input.
  InputZoneFrame frameOf(String item) => InputZoneFrame(
    rectOf(item),
    opacity: opacity[item] ?? 1,
    takesInput: !leaving.contains(item),
  );
}

/// How often the toy toolbar built and laid out.
class ToyCounts {
  /// Builds of the toolbar and of its painted content.
  int builds = 0;

  /// Layouts of the painted content.
  int layouts = 0;
}

/// A toolbar of three items that move inside one render object, each a
/// zone of [InputZones]: a press per item, a 44 point target, a click
/// cursor, a button label for accessibility, and the item states painted
/// from the zones' controller.
class ToyToolbar extends StatefulWidget {
  /// Creates the toolbar over [motion].
  const ToyToolbar({
    required this.motion,
    required this.controller,
    this.onPressed,
    this.disabled = const {},
    this.slides = false,
    this.extra = const {},
    this.counts,
    this.feedback,
    this.port,
    this.axis = Axis.horizontal,
    this.stops = InputZoneStops.each,
    this.current,
    this.activatesOnMove = false,
    super.key,
  });

  /// The items' motion.
  final ToyMotion motion;

  /// The items' states.
  final InputZonesController<String> controller;

  /// Called with the item a tap or a key activates.
  final ValueChanged<String>? onPressed;

  /// The items that are disabled.
  final Set<String> disabled;

  /// Whether a finger moves its press across the items.
  final bool slides;

  /// More interactions for some items, after their press.
  final Map<String, List<Interaction>> extra;

  /// Where the toolbar counts its builds and layouts.
  final ToyCounts? counts;

  /// The haptics of the items' events.
  final MotionHaptic? Function(String item, InteractionEvent event)? feedback;

  /// Where handed-on touches arrive.
  final InputPort? port;

  /// The axis of the arrows.
  final Axis? axis;

  /// Where Tab stops among the items.
  final InputZoneStops stops;

  /// The item Tab enters a single stop at.
  final String? current;

  /// Whether an arrow activates the item it moves to.
  final bool activatesOnMove;

  @override
  State<ToyToolbar> createState() => _ToyToolbarState();
}

class _ToyToolbarState extends State<ToyToolbar> {
  late final Map<String, List<Interaction>> _interactions = {
    for (final item in ToyMotion.items)
      item: [
        PressInteraction(onTap: (t) => widget.onPressed?.call(item)),
        ...?widget.extra[item],
      ],
  };

  static final MouseCursor _cursor = WidgetStateMouseCursor.resolveWith(
    (states) => states.contains(WidgetState.disabled)
        ? SystemMouseCursors.forbidden
        : SystemMouseCursors.click,
  );

  @override
  Widget build(BuildContext context) {
    widget.counts?.builds++;
    widget.motion.rtl = Directionality.of(context) == TextDirection.rtl;
    return InputZones<String>(
      zones: [
        for (final item in ToyMotion.items)
          InputZone(
            id: item,
            interactions: _interactions[item]!,
            enabled: !widget.disabled.contains(item),
            mouseCursor: _cursor,
            reach: const PressReach(minimumHit: Size.square(44)),
            semantics: SemanticsProperties(
              label: 'Item $item',
              button: true,
            ),
          ),
      ],
      frameOf: widget.motion.frameOf,
      frames: widget.motion,
      controller: widget.controller,
      slides: widget.slides,
      feedback: widget.feedback,
      port: widget.port,
      axis: widget.axis,
      stops: widget.stops,
      current: widget.current,
      activatesOnMove: widget.activatesOnMove,
      child: Semantics(
        label: 'paint',
        child: _Counted(
          counts: widget.counts,
          child: SizedBox(
            width: widget.motion.width,
            height: 32,
            child: CustomPaint(
              painter: _ToyPainter(widget.motion, widget.controller),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToyPainter extends CustomPainter {
  _ToyPainter(this.motion, this.states)
    : super(repaint: Listenable.merge([motion, states]));

  final ToyMotion motion;
  final InputZonesController<String> states;

  @override
  void paint(Canvas canvas, Size size) {
    for (final item in ToyMotion.items) {
      final pressed = states.states(item).value.contains(WidgetState.pressed);
      final paint = Paint();
      paint.color = Color.fromRGBO(
        0,
        0,
        pressed ? 255 : 128,
        motion.opacity[item] ?? 1,
      );
      canvas.drawRect(motion.rectOf(item), paint);
    }
  }

  @override
  bool shouldRepaint(_ToyPainter oldDelegate) =>
      oldDelegate.motion != motion || oldDelegate.states != states;
}

class _Counted extends SingleChildRenderObjectWidget {
  const _Counted({required this.counts, required super.child});

  final ToyCounts? counts;

  @override
  RenderObject createRenderObject(BuildContext context) {
    counts?.builds++;
    return _RenderCounted(counts);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderCounted renderObject) {
    counts?.builds++;
    renderObject.counts = counts;
  }
}

class _RenderCounted extends RenderProxyBox {
  _RenderCounted(this.counts);

  ToyCounts? counts;

  @override
  void performLayout() {
    counts?.layouts++;
    super.performLayout();
  }
}
