part of 'backdrop_rig.dart';

/// A [BackdropRig] that also draws a filter a fake glass layer gives it over
/// a copy of what lies under it, as the frame's plan says.
@internal
class FakeBackdropRig extends BackdropRig {
  /// Creates a rig whose backdrop reads share the backdrop of [key], if any.
  FakeBackdropRig({super.key});

  _Asked? _asked;
  ui.FragmentShader? _frostShader;

  /// Paints [filter], [frost]'s blur and whatever follows it, over the
  /// backdrop inside [outline], whose bounds are [bounds], reading past them
  /// as far as the blur reaches.
  void paint(
    PaintingContext context,
    Offset offset, {
    required ui.ImageFilter filter,
    required Rect bounds,
    required Path outline,
    PlanSite? site,
    LiquidGlassBackdropFrost? frost,
  }) {
    bindFilter(filter);
    _asked = site != null
        ? (
            filter: filter,
            frost: frost,
            clip: bounds.shift(offset),
          )
        : null;
    paintSite(
      context,
      offset,
      site: site,
      backdrop: (backdropContext, backdropOffset) => paintBackdrop(
        backdropContext,
        backdropOffset,
        bounds: bounds,
        outline: outline,
      ),
    );
  }

  /// What the frame's plan reads of the filter this rig last painted, which
  /// reads an image whenever it reads a copy: the backdrop filter reads the
  /// whole backdrop, not the backdrop cut at the clip, so a filtered copy is
  /// filtered over all it holds.
  SiteAsk ask(ViewPixels view) {
    final asked = _asked;
    final anchor = _slot.layer;
    _frosts = false;
    if (anchor == null || asked == null || _clipPath.layer == null) {
      return SiteAsk.none;
    }
    final dpr = view.devicePixelRatio;
    final place = screenPlaceOf(anchor, dpr);
    _origin = place is Shifted ? place.offset : null;
    final ask = backdropFilterAsk(
      clip: asked.clip,
      place: place,
      toScreen: () => _toScreen(anchor, dpr),
      filter: asked.filter,
      frost: asked.frost,
      blendMode: BlendMode.src,
      devicePixelRatio: dpr,
    );
    _frosts = ask.look.need.shaderFrost > 0;
    return ask;
  }

  Offset? _origin;
  bool _frosts = false;

  /// Fills the slot with the filter drawn over [copy].
  void showImage(ImageCopy copy) {
    final asked = _asked!;
    final outline = _clipPath.layer!.clipPath!;
    final origin = _origin!;
    final frost = _frosts ? asked.frost : null;
    final shown = asked.clip.shift(origin).intersect(copy.rect);
    show(
      imagePicture(
        (copy.image, copy.placement, shown, origin, outline, frost),
        asked.clip,
        () => switch (frost) {
          final frost? => recordFrostedCopy(
            copy,
            shown,
            origin,
            frost: frost,
            shader: _frostShader ??= newFrostShader(),
            outline: outline,
          ),
          null => recordFilteredCopy(copy, shown, origin, outline: outline),
        },
      ),
    );
  }

  @override
  void clear() {
    _asked = null;
    super.clear();
  }

  @override
  void dispose() {
    super.dispose();
    _frostShader?.dispose();
    _frostShader = null;
  }
}

typedef _Asked = ({
  ui.ImageFilter filter,
  LiquidGlassBackdropFrost? frost,
  Rect clip,
});
