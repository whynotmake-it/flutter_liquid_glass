part of 'page_route.dart';

/// A page in a slide, as a card with the display's corners: the page on
/// top when [top], moved by its progress, with a light shadow while it
/// moves; otherwise the page below, moved aside and dimmed with the page
/// above's progress. Under a cross-fade either fades instead.
class _Card extends SingleChildRenderObjectWidget {
  const _Card({
    required this.presence,
    required this.fades,
    required this.top,
    super.child,
  });

  final ValueListenable<double> presence;
  final ValueListenable<bool> fades;
  final bool top;

  @override
  _RenderCard createRenderObject(BuildContext context) => _RenderCard(
    presence: presence,
    fades: fades,
    radius: _cardRadius(context),
    rtl: context.isRightToLeft,
    top: top,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderCard renderObject) {
    renderObject.presence = presence;
    renderObject.fades = fades;
    renderObject.radius = _cardRadius(context);
    renderObject.rtl = context.isRightToLeft;
  }
}

/// Paints the card from the progress without building or laying out.
class _RenderCard extends RenderProxyBox with ListenableFollower {
  _RenderCard({
    required this._presence,
    required this._fades,
    required this._radius,
    required this._rtl,
    required this.top,
  });

  final bool top;
  final _clip = LayerHandle<ClipRRectLayer>();
  final _offset = LayerHandle<OffsetLayer>();
  final _opacity = LayerHandle<OpacityLayer>();

  // Null for a page below with no glass page above it: it paints as it is.
  ValueListenable<double>? _presence;
  ValueListenable<double>? get presence => _presence;
  set presence(ValueListenable<double>? value) {
    if (identical(value, _presence)) return;
    if ((value == null) != (_presence == null)) {
      markNeedsCompositingBitsUpdate();
    }
    refollow(() => _presence = value);
    markNeedsPaint();
  }

  ValueListenable<bool>? _fades;
  ValueListenable<bool>? get fades => _fades;
  set fades(ValueListenable<bool>? value) {
    if (identical(value, _fades)) return;
    refollow(() => _fades = value);
    markNeedsPaint();
  }

  @override
  List<(Listenable, VoidCallback)> get followed => [
    if (_presence case final presence?) (presence, markNeedsPaint),
    if (_fades case final fades?) (fades, markNeedsPaint),
  ];

  bool get _fading => _fades?.value ?? false;

  BorderRadius _radius;
  BorderRadius get radius => _radius;
  set radius(BorderRadius value) {
    if (value == _radius) return;
    _radius = value;
    markNeedsPaint();
  }

  bool _rtl;
  bool get rtl => _rtl;
  set rtl(bool value) {
    if (value == _rtl) return;
    _rtl = value;
    markNeedsPaint();
  }

  @override
  void dispose() {
    _clip.layer = null;
    _offset.layer = null;
    _opacity.layer = null;
    super.dispose();
  }

  double get _shift {
    final p = _presence?.value;
    if (p == null) return 0;
    final width = size.width;
    if (top) return (1 - p) * width * (_rtl ? -1 : 1);
    final aside = width - (_underneathKeeps * width).round();
    return -aside * p.clamp(0.0, 1.0) * (_rtl ? -1 : 1);
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _presence != null;

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (!_fading) transform.translateByDouble(_shift, 0, 0, 1);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: _fading ? Offset.zero : Offset(_shift, 0),
        position: position,
        hitTest: (result, local) => super.hitTest(result, position: local),
      );

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    final p = _presence?.value;
    if (child == null) return;
    if (p == null) {
      _clip.layer = null;
      _offset.layer = null;
      _opacity.layer = null;
      super.paint(context, offset);
      return;
    }
    if (_fading) {
      _clip.layer = null;
      _offset.layer = null;
      final shown = top ? p : 1 - p;
      _opacity.layer = context.pushOpacity(
        offset,
        Color.getAlphaFromOpacity(shown.clamp(0.0, 1.0)),
        super.paint,
        oldLayer: _opacity.layer,
      );
      return;
    }
    _opacity.layer = null;
    final resting = top ? p >= 1 : p <= 0;
    if (resting) {
      _clip.layer = null;
      _offset.layer = null;
      super.paint(context, offset);
      return;
    }
    final box = Offset.zero & size;
    final card = _radius.toRRect(box);
    final at = offset.translate(_shift, 0);
    final layer = _offset.layer ??= OffsetLayer();
    layer.offset = at;
    context.pushLayer(layer, (context, offset) {
      if (top) {
        final shadow = Paint();
        shadow.color = const Color(0xFF000000).withValues(
          alpha: _cardShadowOpacity,
        );
        shadow.maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          _cardShadowRadius / 2,
        );
        context.canvas.drawRRect(
          card.shift(
            offset + const Offset(0, _cardShadowOffset),
          ),
          shadow,
        );
      }
      _clip.layer = context.pushClipRRect(
        needsCompositing,
        offset,
        box,
        card,
        (context, offset) {
          context.paintChild(child, offset);
          if (!top) {
            final dim = Paint();
            dim.color = const Color(0xFF000000).withValues(
              alpha: _underDimOpacity * p.clamp(0.0, 1.0),
            );
            context.canvas.drawRect(offset & size, dim);
          }
        },
        oldLayer: _clip.layer,
      );
    }, Offset.zero);
  }
}

/// The page under the card of a glass page pushed above it, moved aside
/// and dimmed with that page's progress, or as it is while none is: the
/// page keeps its place in the tree as pages above it come and go.
class _Covered extends SingleChildRenderObjectWidget {
  const _Covered({required this.cover, super.child});

  final ValueListenable<GlassPageRoute<Object?>?> cover;

  @override
  _RenderCovered createRenderObject(BuildContext context) => _RenderCovered(
    cover: cover,
    radius: _cardRadius(context),
    rtl: context.isRightToLeft,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderCovered renderObject) {
    renderObject.cover = cover;
    renderObject.radius = _cardRadius(context);
    renderObject.rtl = context.isRightToLeft;
  }
}

class _RenderCovered extends _RenderCard {
  _RenderCovered({
    required ValueListenable<GlassPageRoute<Object?>?> cover,
    required super.radius,
    required super.rtl,
  }) : _cover = cover,
       super(
         presence: cover.value?._progress,
         fades: cover.value?._fades,
         top: false,
       );

  ValueListenable<GlassPageRoute<Object?>?> _cover;
  ValueListenable<GlassPageRoute<Object?>?> get cover => _cover;
  set cover(ValueListenable<GlassPageRoute<Object?>?> value) {
    if (identical(value, _cover)) return;
    if (attached) _cover.removeListener(_covered);
    _cover = value;
    if (attached) _cover.addListener(_covered);
    _covered();
  }

  void _covered() {
    final cover = _cover.value;
    presence = cover?._progress;
    fades = cover?._fades;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _cover.addListener(_covered);
    _covered();
  }

  @override
  void detach() {
    _cover.removeListener(_covered);
    super.detach();
  }
}
