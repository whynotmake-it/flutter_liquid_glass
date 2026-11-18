part of 'list.dart';

/// Paints a row's highlight under it and its separator over it, following
/// the highlight's strength without building.
class _RowSurface extends SingleChildRenderObjectWidget {
  const _RowSurface({
    required this.strength,
    required this.fill,
    required this.separator,
    required this.separatorStart,
    required this.direction,
    required super.child,
  });

  final ValueListenable<double> strength;
  final Color fill;
  final Color? separator;
  final ValueListenable<double>? separatorStart;
  final TextDirection direction;

  @override
  _RenderRowSurface createRenderObject(BuildContext context) =>
      _RenderRowSurface(
        strength: strength,
        fill: fill,
        separator: separator,
        separatorStart: separatorStart,
        direction: direction,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRowSurface renderObject,
  ) {
    renderObject.strength = strength;
    renderObject.fill = fill;
    renderObject.separator = separator;
    renderObject.separatorStart = separatorStart;
    renderObject.direction = direction;
  }
}

class _RenderRowSurface extends RenderProxyBox {
  _RenderRowSurface({
    required this._strength,
    required this._fill,
    required this._separator,
    required this._separatorStart,
    required this._direction,
  });

  ValueListenable<double> _strength;
  ValueListenable<double> get strength => _strength;
  set strength(ValueListenable<double> value) {
    if (identical(value, _strength)) return;
    if (attached) _strength.removeListener(markNeedsPaint);
    _strength = value;
    if (attached) _strength.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  Color _fill;
  Color get fill => _fill;
  set fill(Color value) {
    if (value == _fill) return;
    _fill = value;
    markNeedsPaint();
  }

  Color? _separator;
  Color? get separator => _separator;
  set separator(Color? value) {
    if (value == _separator) return;
    _separator = value;
    markNeedsPaint();
  }

  ValueListenable<double>? _separatorStart;
  ValueListenable<double>? get separatorStart => _separatorStart;
  set separatorStart(ValueListenable<double>? value) {
    if (identical(value, _separatorStart)) return;
    if (attached) _separatorStart?.removeListener(markNeedsPaint);
    _separatorStart = value;
    if (attached) _separatorStart?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  TextDirection _direction;
  TextDirection get direction => _direction;
  set direction(TextDirection value) {
    if (value == _direction) return;
    _direction = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _strength.addListener(markNeedsPaint);
    _separatorStart?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _strength.removeListener(markNeedsPaint);
    _separatorStart?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final shown = _strength.value;
    if (shown > 0) {
      final paint = Paint();
      paint.color = _fill.withValues(alpha: _fill.a * shown.clamp(0.0, 1.0));
      context.canvas.drawRect(offset & size, paint);
    }
    super.paint(context, offset);
    final separator = _separator;
    if (separator == null) return;
    const end = _Metrics.contentInset;
    final ltr = _direction == TextDirection.ltr;
    final start = _separatorStart?.value ?? _Metrics.contentInset;
    final left = ltr ? start : end;
    final right = size.width - (ltr ? end : start);
    final line = Paint();
    line.color = separator;
    context.canvas.drawRect(
      Rect.fromLTRB(
        left,
        size.height - _Metrics.separatorThickness,
        right,
        size.height,
      ).shift(offset),
      line,
    );
  }
}

/// A row's leading slot: [_Metrics.leadingWidth] wide with the symbol
/// centered, or as wide as a wider image, which it never squeezes.
class _LeadingSlot extends SingleChildRenderObjectWidget {
  const _LeadingSlot({required super.child});

  @override
  _RenderLeadingSlot createRenderObject(BuildContext context) =>
      _RenderLeadingSlot();
}

class _RenderLeadingSlot extends RenderShiftedBox {
  _RenderLeadingSlot() : super(null);

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(const Size(_Metrics.leadingWidth, 0));
      return;
    }
    child.layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.constrain(
      Size(
        math.max(_Metrics.leadingWidth, child.size.width),
        child.size.height,
      ),
    );
    (child.parentData! as BoxParentData).offset = Offset(
      (size.width - child.size.width) / 2,
      (size.height - child.size.height) / 2,
    );
  }
}

/// Sizes a label as tall as a `UILabel` with its text: each line's height
/// rounded up to the device pixel, where the text engine rounds it to a
/// whole point (20.33 points for 17 point SF Pro at 3x).
class _LabelHeight extends SingleChildRenderObjectWidget {
  const _LabelHeight({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLabelHeight(GlassTraits.of(context).viewPixelRatio);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderLabelHeight).pixelRatio = GlassTraits.of(context)
        .viewPixelRatio;
  }
}

class _RenderLabelHeight extends RenderProxyBox {
  _RenderLabelHeight(this._pixelRatio);

  // The engine reports line heights in single precision: a line of
  // exactly 47 pixels can come back a millionth of a pixel over.
  static const double _pixelTolerance = 1e-3;

  double _pixelRatio;
  double get pixelRatio => _pixelRatio;
  set pixelRatio(double value) {
    if (value == _pixelRatio) return;
    _pixelRatio = value;
    markNeedsLayout();
  }

  double? _line;

  double _height(double height) {
    final line = _line;
    if (line == null) return height;
    final rounded = line.roundToDouble();
    if (rounded <= 0) return height;
    final lines = (height / rounded).round();
    if (lines < 1 || (lines * rounded - height).abs() > 0.01) return height;
    return (lines * line * _pixelRatio - _pixelTolerance).ceilToDouble() /
        _pixelRatio;
  }

  static RenderParagraph? _paragraph(RenderBox child) {
    RenderObject? box = child;
    while (box is RenderProxyBox) {
      box = box.child;
    }
    return box is RenderParagraph && box.size == child.size ? box : null;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _height(super.computeMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _height(super.computeMaxIntrinsicHeight(width));

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    final size = child.getDryLayout(constraints);
    return constraints.constrain(Size(size.width, _height(size.height)));
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      _line = null;
      size = constraints.smallest;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    _line = _paragraph(
      child,
    )?.getFullHeightForCaret(const TextPosition(offset: 0));
    size = constraints.constrain(
      Size(child.size.width, _height(child.size.height)),
    );
  }
}
