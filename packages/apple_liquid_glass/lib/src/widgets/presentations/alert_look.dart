part of 'alert.dart';

/// An action's capsule and label. Its zone of the alert's [InputZones]
/// takes its input and speaks for it to assistive technology, so a label
/// that is plain text is not read twice.
class _AlertButton extends StatelessWidget {
  const _AlertButton({
    required this.action,
    required this.states,
    required this.highlight,
    required this.label,
    required this.fill,
  });

  final GlassAlertAction action;
  final ValueListenable<Set<WidgetState>> states;
  final GlassHighlight highlight;
  final TextStyle label;
  final Color fill;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _CapsulePainter(states: states, highlight: highlight, fill: fill),
    child: SizedBox(
      height: _AlertLook.buttonHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _AlertLook.buttonTextInset,
        ),
        child: Center(
          child: ExcludeSemantics(
            excluding: glassLabelTextOf(action.child) != null,
            child: DefaultTextStyle(
              style: label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              child: action.child,
            ),
          ),
        ),
      ),
    ),
  );
}

/// An action's capsule: its fill at [_AlertLook.pressedFillOpacity] of
/// itself while pressed, and at [GlassHighlights.hoverGain] of that change
/// under the pointer, and the focus ring outside it. The hover look is an
/// approximation by the rule of [GlassHighlights], not measured on the
/// platform.
class _CapsulePainter extends CustomPainter {
  _CapsulePainter({
    required this.states,
    required this.highlight,
    required this.fill,
  }) : super(repaint: Listenable.merge([states, highlight]));

  final ValueListenable<Set<WidgetState>> states;
  final GlassHighlight highlight;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final press = states.value.contains(WidgetState.pressed)
        ? 1.0
        : GlassHighlights.hoverGain * highlight.hovered;
    final paint = Paint();
    paint.color = fill.withValues(
      alpha: fill.a * (1 + (_AlertLook.pressedFillOpacity - 1) * press),
    );
    final body = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, Radius.circular(size.shortestSide / 2)),
      paint,
    );
    highlight.paint(
      canvas,
      shape: LiquidRoundedSuperellipse.capsule,
      body: body,
      wash: false,
    );
  }

  @override
  bool shouldRepaint(_CapsulePainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.highlight != highlight ||
      oldDelegate.states.value != states.value;
}

abstract final class _AlertLook {
  static const double dimmingOpacity = 0.2;

  /// The alert text size in points, from the UIKit layout captures.
  static const double textFontSize = 17;

  /// The 17-point text line height in the UIKit layout captures.
  static const double textLineHeight = 20.33;

  /// The line-height multiplier of 17-point alert text.
  static const double textHeight = textLineHeight / textFontSize;

  /// The message line-height multiplier from the UIKit layout captures.
  static const double messageHeight = 1.2;

  /// The preferred action's semibold weight from the UIKit layout captures.
  static const FontWeight preferredWeight = FontWeight.w600;

  /// The single header's regular weight from the UIKit layout captures.
  static const FontWeight singleHeaderWeight = FontWeight.w400;

  /// The button's horizontal text inset from the UIKit layout captures.
  static const double buttonTextInset = 12;

  /// The screen-side alert margin, an engineering layout default.
  static const double screenMargin = 20;

  /// The text scale cap, an engineering layout default.
  static const double maxTextScale = 2;

  static const double cornerRadius = 34;

  /// The space between the top of an alert and its first text label.
  ///
  /// UIKit's view dumps of iOS 27 alerts on an iPhone 16 Pro (kept outside
  /// this repo): the title `UILabel`
  /// rests 22 points under the platter's top in a column alert (313 in a
  /// platter at 291) and in a row alert with a text field (218 in 196).
  static const double headerTop = 22;

  /// The horizontal space between an alert's edge and its text.
  static const double textInset = 30;

  /// The space between the title and the message labels.
  ///
  /// UIKit's view dumps (see [headerTop]): the message `UILabel` starts at
  /// 340.67 under a title label of 20.33 points ending at 333.33 (22
  /// pixels at 3x; 245.67 under 238.33 in the row alert). The labels are
  /// as tall as UIKit makes them.
  static const double titleGap = 22 / 3;

  /// The space below the header text when both a title and a message
  /// show.
  ///
  /// UIKit's view dumps (see [headerTop]): the header scroll view ends at
  /// 363 under a message label ending at 358.67 (13 pixels at 3x), so a
  /// title and a one-line message make a 72 point header, as the
  /// recorded platters (264 points with three actions) and the action
  /// sheet popover's header (floored to 72 in the device tree) hold.
  static const double headerBottom = 13 / 3;

  /// The space below the header text when only one line of text shows.
  ///
  /// Not measured (11 pixels at 3x): no capture holds an alert with a
  /// title or a message alone, so the 46 point header it gives under a
  /// 20.33 point label is not replayed.
  static const double singleHeaderBottom = 11 / 3;

  static const double buttonInset = 16;

  static const double buttonHeight = 48;

  static const double buttonGap = 8;

  /// The opacity of a pressed button's fill, relative to its normal fill.
  static const double pressedFillOpacity = 0.4;

  static const double popoverWidth = 240;
}
