part of 'date_picker.dart';

class _CompactLabel extends StatefulWidget {
  const _CompactLabel({
    required this.text,
    required this.height,
    required this.open,
    required this.enabled,
    required this.look,
    required this.semanticLabel,
    required this.onOpen,
    super.key,
  });

  final String text;
  final double height;
  final bool open;
  final bool enabled;
  final GlassDatePickerStyle look;
  final String? semanticLabel;
  final void Function(BuildContext anchor) onOpen;

  @override
  State<_CompactLabel> createState() => _CompactLabelState();
}

class _CompactLabelState extends State<_CompactLabel> {
  final _motion = DatePickerLabelMotion();
  late final _dim = _motion.select((m) => m.highlight.clamp(0.0, 1.0));
  final _states = WidgetStatesController();
  late final List<Interaction> _press = [
    PressInteraction(
      onHighlightChanged: (double t, {required bool highlighted}) =>
          highlighted ? _motion.press(t) : _motion.release(t),
      onTap: (_) => widget.onOpen(context),
    ),
  ];

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final loc = GlassLocalizations.of(context);
    final scale = GlassTextScale.of(context, max: 2);
    final label = widget.semanticLabel;
    final color = widget.open ? look.accentColor! : look.labelColor!;
    final dim = widget.enabled ? _motion.highlight.clamp(0.0, 1.0) : 1.0;
    return MotionScope(
      motion: _motion,
      child: InputRegion(
        interactions: _press,
        enabled: widget.enabled,
        statesController: _states,
        semantics: SemanticsProperties(
          label: label == null
              ? widget.text
              : loc.compactDatePickerLabel(label, widget.text),
          button: true,
          expanded: widget.open,
          hint: loc.compactDatePickerHint,
        ),
        child: ExcludeSemantics(
          child: glassDatePickerHighlight(
            look.highlightsAt(context),
            states: _states,
            child: Container(
              constraints: BoxConstraints(minHeight: widget.height),
              padding: const EdgeInsets.symmetric(
                horizontal: _DatePickerLook.labelPadding,
              ),
              decoration: widget.enabled
                  ? ShapeDecoration(
                      color: look.labelFillColor,
                      shape: const StadiumBorder(),
                    )
                  : null,
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: _Dimmed(
                  opacity: widget.enabled ? _dim : null,
                  color: color,
                  child: Text(
                    widget.text,
                    maxLines: 1,
                    textScaler: scale.scaler,
                    style: scale
                        .resolve(look.labelTextStyle!)
                        .copyWith(
                          color: dim >= 1
                              ? color
                              : color.withValues(alpha: color.a * dim),
                        ),
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

/// Sets the alpha of its paragraph's text color to [color]'s times
/// [opacity] as the opacity changes, without a rebuild or a layer.
class _Dimmed extends SingleChildRenderObjectWidget {
  const _Dimmed({
    required this.opacity,
    required this.color,
    required super.child,
  });

  final MotionSelection<double>? opacity;
  final Color color;

  @override
  _RenderDimmed createRenderObject(BuildContext context) =>
      _RenderDimmed(opacity: opacity, color: color);

  @override
  void updateRenderObject(BuildContext context, _RenderDimmed renderObject) {
    renderObject.opacity = opacity;
    renderObject.color = color;
  }
}

class _RenderDimmed extends RenderProxyBox {
  _RenderDimmed({required this._opacity, required this.color});

  Color color;

  MotionSelection<double>? _opacity;
  MotionSelection<double>? get opacity => _opacity;
  set opacity(MotionSelection<double>? value) {
    if (identical(value, _opacity)) return;
    if (attached) _opacity?.removeRenderListener(_changed);
    _opacity = value;
    if (attached) {
      value?.addRenderListener(_changed);
      _changed();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _opacity?.addRenderListener(_changed);
  }

  @override
  void detach() {
    _opacity?.removeRenderListener(_changed);
    super.detach();
  }

  void _changed() {
    final paragraph = child;
    if (paragraph is! RenderParagraph) return;
    final text = paragraph.text;
    if (text is! TextSpan) return;
    final opacity = _opacity?.value ?? 1;
    final next = opacity >= 1
        ? color
        : color.withValues(alpha: color.a * opacity);
    if (text.style?.color == next) return;
    paragraph.text = TextSpan(
      text: text.text,
      children: text.children,
      style: (text.style ?? const TextStyle()).copyWith(color: next),
      recognizer: text.recognizer,
      semanticsLabel: text.semanticsLabel,
      locale: text.locale,
      spellOut: text.spellOut,
    );
  }
}
