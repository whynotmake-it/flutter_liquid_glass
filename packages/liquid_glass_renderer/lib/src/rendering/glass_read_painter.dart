part of 'liquid_glass_layer.dart';

List<(RenderLiquidGlassLayer, PainterRole, Rect)> _glassIn(
  GlassRead read,
) => [
  for (final member in read.glassMembers)
    if (member.ask.role
        case final PainterRole role &&
            PainterRole(painter: _GlassPainter(:final layer)))
      (layer, role, member.ask.drawn),
];

BandLook? _bandOf(GlassRead read) => switch (read.lead.ask.role) {
  BandSiteRole(:final look) => look,
  _ => null,
};

final class _GlassPainter implements ReadPainter {
  _GlassPainter(this.layer);

  final RenderLiquidGlassLayer layer;

  GroupAtlas? _groupAtlas;

  GlassDraw? _debugDraw;

  static const int _leadAndHeldReads = 2;
  final List<(GlassDraw, ImageFilter)> _inSceneFilters = [];

  void beginRead(GlassRead read) {
    if (read.geometryKind is! SharedAtlas) return;
    final members = _glassIn(read);
    final (first, _, _) = members.first;
    (_groupAtlas ??= GroupAtlas(layer._glass.geometryRenderer())).gather(
      [
        for (final (glass, role, drawn) in members)
          (
            shapes: glass._shapes,
            onScreen: glass._shapesOnScreen(role.originOnScreen),
            drawn: drawn,
            appearance: glass._uniformAppearance ?? glass.defaultWornByNone,
          ),
      ],
      first._need,
    );
  }

  (Matrix4, Rect?) _readMapping(GlassRead read, _Frame frame) {
    final origin = switch (read.geometryKind) {
      SharedAtlas() => _groupAtlas?.origin,
      ComputedShape() || OwnAtlas() => null,
    };
    return origin == null
        ? (Matrix4.inverted(frame.screen), layer._backdropBounds)
        : (
            Matrix4.translationValues(-origin.dx, -origin.dy, 0),
            read.footprint.shift(-origin),
          );
  }

  GlassDraw _readDraw(GlassRead read, _Frame frame, PlacedCopy copy) {
    final sampling = copy.glassSampling(frame.shaderFrost);
    final look = _bandOf(read);
    final kind = read.geometryKind;
    assert(
      kind is SharedAtlas ||
          (kind is ComputedShape) == (layer._geometry is ComputedGeometry),
      'A read of one glass draws the geometry that glass encoded.',
    );
    final group = kind is SharedAtlas ? _groupAtlas! : null;
    final (binding, groupTints) = switch (group) {
      null => (layer._ownBinding, false),
      GroupAtlas(:final lease!, :final bounds) => (
        layer._bindingOf(AtlasGeometry(lease), bounds: bounds),
        lease.looks.isNotEmpty,
      ),
    };
    final variant = layer._variant(
      binding.source,
      band: look != null,
      groupTints: groupTints,
    );
    final (globalToMatte, backdropBounds) = _readMapping(read, frame);
    final holds = sampling.holds;
    final within = holds == null
        ? null
        : MatrixUtils.transformRect(globalToMatte, holds);
    final draw = GlassDraw(
      variant: variant,
      face: read.layout.haze == null
          ? layer._glassFace
          : layer._hazedFace ??= layer._glassFace.hazed,
      glow: layer._glowNow,
      geometry: binding,
      mapping: MatteMapping.of(
        globalToMatte,
        devicePixelRatio: layer.devicePixelRatio,
        origin: sampling.origin,
        targetShare: sampling.targetShare.toDouble(),
        backdropBounds: within == null
            ? backdropBounds
            : backdropBounds?.intersect(within) ?? within,
      ),
      reading: CopyReading(sampling),
      band: look != null && FinalShaderVariant.all[variant].band
          ? BandUniforms.of(
              look,
              origin: sampling.origin,
              targetShare: sampling.targetShare,
              shown: copy.place.fragmentsOf(look.shown) ?? Rect.zero,
              whole: copy.place.residual(look.sigma),
              held: copy.heldFrost,
            )
          : null,
    );
    if (!kReleaseMode) _debugDraw = draw;
    return draw;
  }

  static final ImageFilter _drawsNothing = ImageFilter.matrix(
    Matrix4.identity().storage,
  );

  static const Object _noImageKey = Object();

  @override
  ImageFilter readFilter(GlassRead read, CornerRead corner) {
    final frame = layer._drawingFrame;
    return frame == null ? _drawsNothing : _readFilter(read, frame, corner);
  }

  ImageFilter _readFilter(GlassRead read, _Frame frame, CornerRead corner) {
    final draw = _readDraw(read, frame, corner);
    for (final (held, filter) in _inSceneFilters) {
      if (held == draw) return filter;
    }
    final filter = layer._shading.filter(draw);
    if (_inSceneFilters.length == _leadAndHeldReads) {
      _inSceneFilters.removeAt(0);
    }
    _inSceneFilters.add((draw, filter));
    return filter;
  }

  (GlassDraw, Rect) _imageDraw(GlassRead read, _Frame frame, ImageCopy copy) {
    final draw = _readDraw(read, frame, copy);
    final dpr = layer.devicePixelRatio;
    final logical = _glassIn(read).length == 1 && _bandOf(read) == null
        ? frame.logical
        : ViewPixels(dpr).bucket(read.quad);
    return (draw, logical.scaled(dpr));
  }

  @override
  Object imageKey(GlassRead read, ImageCopy copy) {
    final frame = layer._drawingFrame;
    return frame == null ? _noImageKey : _imageDraw(read, frame, copy);
  }

  @override
  ui.Picture recordImage(
    GlassRead read,
    ImageCopy copy,
    Matrix4 screenToCanvas,
  ) {
    final frame = layer._drawingFrame;
    if (!kReleaseMode) GlassWork.pictures++;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..transform(screenToCanvas.storage);
    if (frame != null) {
      final (draw, device) = _imageDraw(read, frame, copy);
      layer._shading.paintRect(canvas, device, draw);
    }
    return recorder.endRecording();
  }

  Matrix4 _screenToCanvas(_Frame frame) {
    final canvasToScreen = frame.screen.clone()
      ..multiply(
        Matrix4.translationValues(
          -layer._filterPaintOffset.dx,
          -layer._filterPaintOffset.dy,
          0,
        ),
      );
    return Matrix4.tryInvert(canvasToScreen)!..multiply(
      Matrix4.diagonal3Values(
        1 / layer.devicePixelRatio,
        1 / layer.devicePixelRatio,
        1,
      ),
    );
  }

  List<(ui.Picture, Offset)> _shadowsOfOthers(GlassRead read, _Frame frame) {
    if (_bandOf(read) != null) return const [];
    final storage = frame.screen.storage;
    final canvas = layer._canvasOnScreen(Offset(storage[12], storage[13]));
    return [
      for (final (glass, role, _) in _glassIn(read))
        if (!identical(glass, layer))
          if (glass._shadowUnderRead() case final picture?)
            (picture, glass._canvasOnScreen(role.originOnScreen) - canvas),
    ];
  }

  // The hard edge around glass far apart, in the screen's device pixels, or
  // null where it fills most of [copyLayer]: rejecting the pixels no glass
  // paints saved 0.6 ms of GPU time over twelve buttons on the Pixel 6a.
  //
  // A pixel at two corners keeps the edge's bounds at the layer's: Impeller
  // would cut the layer, and the fragment coordinates the glass reads start
  // at the cut (see [ImpellerLayers]).
  ui.Path? _clipIn(GlassRead read, Rect copyLayer) {
    if (read.members.length < 2 || _bandOf(read) != null) return null;
    double area(Rect rect) => rect.width * rect.height;
    var sum = 0.0;
    for (final member in read.members) {
      sum += area(member.ask.drawn);
    }
    if (area(read.quad) <= sum * 1.3) return null;
    final dpr = layer.devicePixelRatio;
    final path = ui.Path();
    void add(Rect rect) => path.addRect(rect.scaled(dpr));
    for (final member in read.members) {
      add(member.ask.drawn.inflate(2 / dpr));
    }
    final (topLeft, bottomRight) = ImpellerLayers.pinsOf(copyLayer, dpr);
    add(topLeft);
    add(bottomRight);
    return path;
  }

  late CornerRead _shownCorner;
  late ImageFilter _shownFilter;
  ui.Path? _shownClip;
  late Matrix4 _shownToCanvas;
  List<(ui.Picture, Offset)> _shownUnder = const [];
  Object? _shownKey;

  void showScene(GlassRead read, _Frame frame, CornerRead corner) {
    final inPlace = corner.inPlace.filter;
    final filter = _readFilter(read, frame, corner);
    final toCanvas = _screenToCanvas(frame);
    final under = _shadowsOfOthers(read, frame);
    final copyLayer = read.layout.layerRect;
    final clip = _clipIn(read, copyLayer);
    final key = [
      filter,
      inPlace,
      toCanvas,
      copyLayer,
      if (clip != null) ...[
        for (final member in read.members) member.ask.drawn,
      ],
      for (final (picture, offset) in under) ...[picture, offset],
    ];
    final readLayer = layer._rig.readLayer;
    final held = _shownKey;
    final changed =
        read.changed ||
        readLayer.parent == null ||
        held is! List<Object?> ||
        !listEquals(held, key);
    _shownCorner = corner;
    _shownFilter = filter;
    _shownClip = clip;
    _shownToCanvas = toCanvas;
    _shownUnder = under;
    _shownKey = key;
    // Shadows added beside the engine layer are not in what it retains.
    readLayer.show(_addRead, changed: changed || under.isNotEmpty);
    layer._rig.show(
      readLayer,
      under: layer._shadowsUnder,
    );
  }

  ui.TransformEngineLayer? _addRead(ui.SceneBuilder builder) {
    for (final (picture, offset) in _shownUnder) {
      builder.addPicture(offset, picture);
    }
    return _shownCorner.addToScene(
      builder,
      _shownFilter,
      _shownToCanvas,
      layer._rig.readLayer.held,
      clip: _shownClip,
    );
  }

  void showImage(GlassRead read, _Frame frame, ImageCopy copy) {
    layer._debugImageCopy = copy;
    final toCanvas = _screenToCanvas(frame);
    final under = _shadowsOfOthers(read, frame);
    final dpr = layer.devicePixelRatio;
    final quad = read.quad;
    final bounds = MatrixUtils.transformRect(
      toCanvas,
      quad.scaled(dpr),
    ).inflate(1);
    final key = (
      copy.image,
      copy.placement,
      copy.rect,
      imageKey(read, copy),
      toCanvas,
      Object.hashAll([
        for (final (picture, offset) in under) ...[picture, offset],
      ]),
    );
    layer._rig.show(
      layer._rig.imagePicture(key, bounds, () {
        final body = recordImage(read, copy, toCanvas);
        if (under.isEmpty) return body;
        if (!kReleaseMode) GlassWork.pictures++;
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        for (final (shadow, offset) in under) {
          canvas
            ..save()
            ..translate(offset.dx, offset.dy)
            ..drawPicture(shadow)
            ..restore();
        }
        canvas.drawPicture(body);
        body.dispose();
        return recorder.endRecording();
      }),
      under: layer._shadowsUnder,
    );
  }

  void addOutput(SceneOut out, ReadCopy outer, GlassRead read) {
    if (layer._shadowsUnder?.picture case final shadow?) out.picture(shadow);
    if (read.source is ImageRead) {
      if (layer._rig.imageShown case final picture?) out.picture(picture);
      return;
    }
    final corner = outer.cornerOf(read);
    if (corner == null) return;
    final frame = layer._drawingFrame;
    if (frame == null) return;
    for (final (picture, offset) in _shadowsOfOthers(read, frame)) {
      out
        ..mark()
        ..at += offset
        ..picture(picture)
        ..leave();
    }
    final filter = _readFilter(read, frame, corner);
    out.settle();
    corner.addToScene(out.builder, filter, _screenToCanvas(frame), out.held);
  }

  void dispose() {
    _groupAtlas?.dispose();
    _groupAtlas = null;
  }
}
