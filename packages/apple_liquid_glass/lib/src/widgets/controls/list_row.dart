part of 'list.dart';

/// A row of an inset grouped list: a title with an optional subtitle,
/// symbol, value, control and accessory.
///
/// UIKit: a `UITableViewCell` with a `UIListContentConfiguration` (cell,
/// subtitle cell, value cell). SwiftUI: a row of a `List`. Flutter:
/// `CupertinoListTile`.
///
/// Pass a [title], or a [child] that fills the text area instead. Add a
/// [subtitle], a [leading] symbol, a [detail] value, a [trailing] control
/// such as a `GlassSwitch`, and an [accessory] such as the disclosure
/// chevron. With [onPressed] the row is a button; [enabled] false turns it
/// off. Put rows in a [GlassListSection], which draws the card and the
/// separators.
///
/// ```dart
/// GlassListRow(
///   leading: const Icon(CupertinoIcons.bell),
///   title: const Text('Notifications'),
///   subtitle: const Text('Sounds, badges'),
///   accessory: GlassListAccessory.disclosureIndicator,
///   onPressed: () => debugPrint('open notifications'),
/// )
/// ```
///
/// It draws no glass on any renderer: a row looks the same under the
/// liquid, fake and flat renderers and with no `GlassScope` above.
///
/// The [title] reads 17 points in the label color with an optional 15
/// point [subtitle] below it; a [detail] sits at the trailing edge in the
/// secondary color, taking at most half the text area; a [leading] symbol
/// is centered 28 points from the card's edge and moves the text and the
/// separator to 56 points; a leading image wider than the symbol's 24
/// point slot widens it from the card's 16 point inset and moves the text
/// and separator along. A [trailing] control and the [accessory] end 20
/// points from the card's edge, centered in the row as UIKit centers an
/// accessory view. A single-line row is 53 points tall, and each line of
/// text is as tall as UIKit makes a label: its line height rounded up to
/// the device pixel.
///
/// A pressable row fills with its overlay color while a finger is down on
/// it, with UIKit's timing: inside a scroll view after its 0.15 s touch
/// delay, gone at once when a scroll takes the touch, faded out over 0.5 s
/// after a tap. Space and Enter press it. Focused from the keyboard it
/// draws Flutter's Cupertino focus ring inside its edge, where the card
/// clips, and a mouse over it fills it with half its overlay color; its
/// info button does the same around its circle. A disabled row ignores
/// touches and keeps its look. Inside a section the row draws the
/// separator below itself, except on the section's last row. Right-to-left
/// text mirrors the row and the chevron.
///
/// Fidelity. The sizes, insets and press timing are measured on iOS 27.
/// Not measured: the place of a leading image wider than 24 points, the
/// disabled look, and the focus ring and hover response, which are
/// approximations of the platform.
class GlassListRow extends StatefulWidget {
  /// Creates a row.
  const GlassListRow({
    this.title,
    this.subtitle,
    this.detail,
    this.leading,
    this.trailing,
    this.accessory,
    this.onAccessoryPressed,
    this.child,
    this.onPressed,
    this.enabled = true,
    this.style,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.accessorySemanticLabel,
    super.key,
  }) : assert(
         title != null || child != null,
         'A row needs a title or a child.',
       );

  /// The primary text, usually a [Text].
  final Widget? title;

  /// The secondary line below [title].
  final Widget? subtitle;

  /// The value at the trailing edge, in the secondary color.
  final Widget? detail;

  /// The symbol or image before the text, usually an [Icon]; 22 points in
  /// the icon color unless it sets its own. It keeps its own size.
  final Widget? leading;

  /// A control at the trailing edge, such as a switch.
  final Widget? trailing;

  /// The standard accessory at the trailing edge, after [trailing]; null
  /// shows none.
  final GlassListAccessory? accessory;

  /// Called when the info button of a [GlassListAccessory.detailButton] or
  /// [GlassListAccessory.detailDisclosureButton] is pressed (UIKit
  /// `accessoryButtonTappedForRowWith`).
  final VoidCallback? onAccessoryPressed;

  /// Content that fills the text area instead of [title] and [subtitle].
  final Widget? child;

  /// Called when the row is pressed; null makes the row inert.
  final VoidCallback? onPressed;

  /// Whether the row takes presses.
  final bool enabled;

  /// The look, over the section's and the theme's.
  final GlassListStyle? style;

  /// Where the row writes its states, or null for its own.
  final WidgetStatesController? statesController;

  /// The row's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the row takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the info button; the localized
  /// [GlassLocalizations.moreInfoLabel] when null.
  final String? accessorySemanticLabel;

  @override
  State<GlassListRow> createState() => _GlassListRowState();
}

class _GlassListRowState extends State<GlassListRow> {
  final _textStart = ValueNotifier<double>(_Metrics.contentInset);

  @override
  void dispose() {
    _textStart.dispose();
    super.dispose();
  }

  void _measureLeading(double t, Size size) => _textStart.value =
      _Metrics.contentInset + size.width + _Metrics.leadingGap;

  @override
  Widget build(BuildContext context) {
    final place = _RowPlace.maybeOf(context);
    final look = (widget.style ?? const GlassListStyle()).merge(
      place?.look ?? _sectionLook(context, null),
    );
    final kind = widget.accessory;
    final chevron =
        kind == GlassListAccessory.disclosureIndicator ||
        kind == GlassListAccessory.detailDisclosureButton;
    final info =
        kind == GlassListAccessory.detailButton ||
        kind == GlassListAccessory.detailDisclosureButton;
    final check = kind == GlassListAccessory.checkmark;
    return RawGlassListRow(
      onPressed: widget.onPressed,
      enabled: widget.enabled,
      selected: check,
      statesController: widget.statesController,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onInfoPressed: widget.onAccessoryPressed,
      infoSemanticLabel: widget.accessorySemanticLabel,
      infoCenterInset:
          _Metrics.accessoryInset +
          (chevron ? _Metrics.chevronSize.width + _Metrics.gap : 0) +
          _Metrics.glyphSize / 2,
      infoBuilder: info
          ? (context, details) => GlassHighlightPaint.of(
              context,
              states: details.statesListenable,
              focusColor: look.focusColor,
              hoverColor: _hover(look, details.states, context),
              shape: const LiquidOval(),
              child: _Glyph(
                painter: _InfoPainter(
                  StateColors(context, details.states)(look.iconColor),
                ),
              ),
            )
          : null,
      builder: (context, details) => _row(
        context,
        details,
        look: look,
        place: place,
        chevron: chevron,
        info: info,
        check: check,
      ),
    );
  }

  static Color _hover(
    GlassListStyle look,
    Set<WidgetState> states,
    BuildContext context,
  ) {
    final fill = StateColors(context, states)(look.overlayColor);
    return look.hoverColor ??
        fill.withValues(alpha: fill.a * GlassHighlights.hoverGain);
  }

  Widget _row(
    BuildContext context,
    GlassListRowDetails details, {
    required GlassListStyle look,
    required _RowPlace? place,
    required bool chevron,
    required bool info,
    required bool check,
  }) {
    final states = details.states;
    final color = StateColors(context, states);
    final secondary = color(look.secondaryColor);
    final icon = color(look.iconColor);
    final scale = GlassTextScale.of(context);
    final titleStyle = scale.resolve(
      _Metrics.body.copyWith(color: color(look.foregroundColor)),
    );
    final detailStyle = scale.resolve(
      _Metrics.body.copyWith(color: secondary),
    );
    final subtitleStyle = scale.resolve(
      _Metrics.subtitle.copyWith(color: secondary),
    );
    final leading = widget.leading;
    final subtitle = widget.subtitle;
    final detail = widget.detail;
    final trailing = widget.trailing;
    final mark = chevron || info || check;
    final accessory = trailing != null || mark;
    // A row that highlights has more than the card's color under its control.
    final card = place != null && widget.onPressed == null
        ? StateColors(context, const {})(place.look.backgroundColor)
        : null;
    final text = Padding(
      padding: const EdgeInsets.symmetric(vertical: _Metrics.rowPadding),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            if (leading != null) ...[
              MotionMeasure(
                onSize: _measureLeading,
                child: _LeadingSlot(
                  child: IconTheme.merge(
                    data: IconThemeData(
                      size: _Metrics.leadingIconSize,
                      color: icon,
                    ),
                    child: leading,
                  ),
                ),
              ),
              const SizedBox(width: _Metrics.leadingGap),
            ],
            Expanded(
              child: DefaultTextStyle(
                style: titleStyle,
                child:
                    widget.child ??
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.title case final title?)
                          _LabelHeight(child: title),
                        if (subtitle != null)
                          DefaultTextStyle(
                            style: subtitleStyle,
                            child: _LabelHeight(child: subtitle),
                          ),
                      ],
                    ),
              ),
            ),
            if (detail != null) ...[
              const SizedBox(width: _Metrics.gap),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth / 2,
                ),
                child: DefaultTextStyle(
                  style: detailStyle,
                  textAlign: TextAlign.end,
                  child: _LabelHeight(child: detail),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _Metrics.minRowHeight),
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: _Metrics.contentInset,
          end: accessory ? _Metrics.accessoryInset : _Metrics.contentInset,
        ),
        child: Row(
          children: [
            Expanded(child: text),
            if (accessory) const SizedBox(width: _Metrics.gap),
            if (trailing != null)
              GlassSolidBackdrop(color: card, child: trailing),
            if (trailing != null && mark) const SizedBox(width: _Metrics.gap),
            if (check) _Glyph(painter: _CheckPainter(icon)),
            if (info) const SizedBox.square(dimension: _Metrics.glyphSize),
            if (info && chevron) const SizedBox(width: _Metrics.gap),
            if (chevron) _Chevron(color: color(look.disclosureColor)),
          ],
        ),
      ),
    );
    final separated = place != null && !place.last;
    final surface = _RowSurface(
      strength: details.highlight,
      fill: color(look.overlayColor),
      separator: separated ? color(look.separatorColor) : null,
      separatorStart: leading == null ? null : _textStart,
      direction: Directionality.of(context),
      child: row,
    );
    if (widget.onPressed == null) return surface;
    return GlassHighlightPaint.of(
      context,
      states: details.statesListenable,
      focusColor: look.focusColor,
      hoverColor: _hover(look, states, context),
      shape: const LiquidRoundedRectangle(radius: 0),
      inside: true,
      child: surface,
    );
  }
}

class _RowPlace extends InheritedWidget {
  const _RowPlace({
    required this.last,
    required this.look,
    required super.child,
  });

  final bool last;
  final GlassListStyle look;

  static _RowPlace? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RowPlace>();

  @override
  bool updateShouldNotify(_RowPlace oldWidget) =>
      last != oldWidget.last || look != oldWidget.look;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel.header({required this.look, required this.label})
    : _header = true;

  const _SectionLabel.footer({required this.look, required this.label})
    : _header = false;

  final GlassListStyle look;
  final Widget? label;
  final bool _header;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    if (label == null) {
      return SizedBox(
        height: _header ? _Metrics.noHeaderTop : _Metrics.noFooterBottom,
      );
    }
    final style = GlassTextScale.of(context).resolve(
      (_header ? _Metrics.header : _Metrics.footer).copyWith(
        color: StateColors(context, const {})(look.secondaryColor),
      ),
    );
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        _Metrics.contentInset,
        _header ? _Metrics.headerTop : _Metrics.footerTop,
        _Metrics.contentInset,
        _header ? _Metrics.headerBottom : _Metrics.footerBottom,
      ),
      child: Semantics(
        header: _header,
        child: DefaultTextStyle.merge(
          style: style,
          child: _LabelHeight(child: label),
        ),
      ),
    );
  }
}
