import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/painting/impeller_blur.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_backdrop_filter.dart';
import 'package:liquid_glass_renderer/src/painting/screen_place.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';
import 'package:liquid_glass_renderer/src/plan/band_look.dart';
import 'package:liquid_glass_renderer/src/plan/copy_place.dart';
import 'package:liquid_glass_renderer/src/plan/plan_result.dart';
import 'package:liquid_glass_renderer/src/plan/plan_site.dart';
import 'package:liquid_glass_renderer/src/rendering/backdrop_rig.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_frost.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_read.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_form.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:liquid_glass_renderer/src/rendering/scene_out.dart';

/// A backdrop filter over [clip] that, wherever it can, filters a copy of
/// what is painted under it instead of reading the backdrop, so a frame
/// whose backdrop effects all draw from copies renders straight to the
/// screen.
///
/// A backdrop filter anywhere in a frame makes Impeller render the whole
/// frame offscreen, split the root pass at every read and blit the result to
/// the screen. This layer draws what lies under [clip] again from the layer
/// tree, as the frame's plan says. For a frost the shader can draw
/// ([LiquidGlassBackdropFilter.frost] or a band), composited with
/// [BlendMode.srcOver], the copy is drawn unblurred in the frame itself and
/// frosted as it is drawn.
/// Any other copy is drawn into a small image, filtered as the backdrop
/// would be, which serves later frames while those layers are unchanged. Under
/// a texture, a platform view, a backdrop filter or a layer type the copy
/// cannot draw (see `LiquidGlassUnderlay`) it reads the backdrop like a
/// [BackdropFilterLayer].
///
/// The filter applies to the screen-aligned backdrop: under a transform that
/// scales or turns the layer, it reads the backdrop.
///
/// The render object that holds the layer mixes in
/// [LiquidGlassBackdropFilterHost].
class LiquidGlassBackdropFilterLayer extends ContainerLayer {
  /// Creates the layer that draws [filter] over what lies under [clip],
  /// composited by [blendMode].
  LiquidGlassBackdropFilterLayer({
    required this._filter,
    required this._clip,
    this._blendMode = BlendMode.srcOver,
  }) {
    _resolve();
  }

  /// What the layer does to what lies under [clip].
  ///
  /// The children of a band ([LiquidGlassFrostBand]) are left out of the
  /// frames in which glass over the band draws it in its own filter.
  LiquidGlassBackdropFilter get filter => _filter;
  LiquidGlassBackdropFilter _filter;
  set filter(LiquidGlassBackdropFilter value) {
    if (value == _filter) return;
    final dissolve = _dissolve;
    _filter = value;
    if (_resolve() || _dissolve != dissolve) markNeedsAddToScene();
  }

  /// How the filtered backdrop composites over the backdrop, as
  /// [BackdropFilterLayer.blendMode] does.
  ///
  /// Glass draws a band in its own filter, and a soft band dissolves, only
  /// with [BlendMode.srcOver]. A copy drawn in the filter's place holds the
  /// backdrop's own alpha and composites as [BlendMode.srcOver]: under a
  /// fractional opacity, whose pass starts empty, the filter's mode would
  /// find nothing to draw over.
  BlendMode get blendMode => _blendMode;
  BlendMode _blendMode;
  set blendMode(BlendMode value) {
    if (value == _blendMode) return;
    _blendMode = value;
    markNeedsAddToScene();
  }

  /// Where the filter applies, in this layer's coordinates.
  Rect get clip => _clip;
  Rect _clip;
  set clip(Rect value) {
    if (value == _clip) return;
    _clip = value;
    markNeedsAddToScene();
  }

  double _devicePixelRatio = 1;

  // What [filter] comes to at this view's pixel ratio: the filter that reads
  // the backdrop, the frost a shader may draw over a copy instead, and the
  // blur of a filter that has no such frost.
  ui.ImageFilter get _imageFilter => _resolved!;
  ui.ImageFilter? _resolved;
  LiquidGlassBackdropFrost? _frost;
  double _sigma = 0;

  // Whether what the filter comes to changed.
  bool _resolve() {
    final frost = switch (_filter) {
      LiquidGlassImageBackdropFilter() => null,
      final LiquidGlassBackdropFrost frost => frost,
      final LiquidGlassFrostBand band => backdropFrost(
        sigma: ImpellerBlur.halfResolution(band.sigma, _devicePixelRatio),
        colorMatrix: band.colorMatrix,
      ),
    };
    final (imageFilter, sigma) = switch (_filter) {
      LiquidGlassImageBackdropFilter(:final filter, :final sigma) => (
        filter,
        sigma,
      ),
      _ => (null, 0.0),
    };
    if (frost != null && frost == _frost) return false;
    _frost = frost;
    _sigma = sigma;
    _resolved = frost?.filter ?? imageFilter;
    return true;
  }

  LiquidGlassFrostBand? get _band => switch (_filter) {
    final LiquidGlassFrostBand band => band,
    _ => null,
  };

  // Where the frost dissolves into what lies under it, in this layer's rows:
  // where the fade over it does.
  FrostDissolve get _dissolve => switch (_band) {
    final band? when _blendMode == BlendMode.srcOver => frostDissolveOf(
      band,
      _clip,
    ),
    _ => FrostDissolve.none,
  };

  ui.Picture? _mask;
  Object? _maskKey;

  late final PlanSite _site = _FilterSite(this);

  // Where this layer's coordinates begin on the screen, while on it untouched.
  Offset? _origin;
  SiteFate _fate = const HiddenFate();

  // How this frame's read draws.
  _Scene? _scene;
  Object? _sceneKey;

  // What the read of the scene keeps between the scenes it is added to.
  final _held = HeldLayers();
  ui.ImageFilter? _frostFilter;
  Object? _frostKey;
  ui.Picture? _imagePicture;
  Object? _imageKey;
  ui.FragmentShader? _frostShader;

  ImageCopy? _debugImageCopy;

  bool get _drawsGroup => _painterOf(_fate) != null;

  bool get _serves => _scene != null || _imagePicture != null;

  Offset get _screenOrigin => _origin ?? Offset.zero;

  Rect get _shown => _clip.shift(_screenOrigin);

  /// The glass that draws this layer's frost in its filter, if any.
  static ReadPainter? _painterOf(SiteFate fate) => switch (fate) {
    LeadFate(:final read) => switch (read.bandPainter?.ask.role) {
      PainterRole(:final painter) => painter,
      _ => null,
    },
    _ => null,
  };

  SiteAsk _ask(ViewPixels view) {
    final dpr = view.devicePixelRatio;
    if (dpr != _devicePixelRatio) {
      _devicePixelRatio = dpr;
      if (_band != null && _resolve()) markNeedsAddToScene();
    }
    final screen = _site.formNode?.screenTransform(Offset.zero);
    final place = screen == null
        ? screenPlaceOf(this, dpr)
        : ScreenPlace.of(screen);
    _origin = place is Shifted ? place.offset : null;
    final frost = _frost;
    final band = _band;
    return backdropFilterAsk(
      clip: _clip,
      place: place,
      toScreen: () => screen ?? Matrix4.identity(),
      filter: _imageFilter,
      sigma: _sigma,
      frost: frost,
      blendMode: _blendMode,
      inScene: true,
      band: frost == null || band == null
          ? null
          : (shown, origin) => BandLook(
              sigma: frost.sigma,
              band: band,
              dissolve: frostDissolveOf(band, _clip),
              origin: origin,
              shown: shown,
              devicePixelRatio: dpr,
            ),
      devicePixelRatio: dpr,
      paints: (_imageFilter, frost, band, _blendMode),
    );
  }

  void _beginFate(SiteFate fate) {
    if (fate.runtimeType != _fate.runtimeType) markNeedsAddToScene();
    _fate = fate;
    if (fate is HiddenFate) _showNothing();
  }

  void _showNothing() {
    _debugImageCopy = null;
    if (_scene != null || _imagePicture != null) markNeedsAddToScene();
    _scene = null;
    _sceneKey = null;
    _imagePicture?.dispose();
    _imagePicture = null;
    _imageKey = null;
  }

  // The frost of the part [corner] holds, as a filter: a band over a scroll
  // keeps its place, so its filter too.
  ui.ImageFilter? _frostOf(CornerRead corner) {
    final frosting = _frost!;
    final sampling = corner.frostSampling(
      _shown,
      frosting.sigma,
      dissolve: _dissolve.mapped(_screenOrigin.dy, 1),
    );
    if (sampling == null) return null;
    final key = (
      sampling.size,
      sampling.bounds,
      sampling.frost,
      sampling.texelsPerFragment,
      sampling.shown,
      sampling.dissolve,
      frosting.colorMatrix,
    );
    if (key != _frostKey || _frostFilter == null) {
      _frostFilter = frostFilter(
        sampling,
        frosting.colorMatrix,
        _frostShader ??= newFrostShader(),
      );
      _frostKey = key;
    }
    return _frostFilter;
  }

  _Scene? _sceneOf(GlassRead read, CornerRead corner) {
    if (_painterOf(_fate) case final painter?) {
      return (corner: corner, filter: painter.readFilter(read, corner));
    }
    // A band alone has its frost drawn into the copy, at the copy's pixels.
    final filter = _frostOf(corner);
    return filter == null ? null : (corner: corner, filter: filter);
  }

  void _show(GlassRead read, ReadPixels pixels) {
    switch (pixels) {
      case ScenePixels(:final corner):
        _showScene(read, corner);
      case ImagePixels(:final copy):
        _showImage(read, copy);
      case BackdropPixels():
        _showNothing();
    }
  }

  void _showScene(GlassRead read, CornerRead corner) {
    final scene = _sceneOf(read, corner);
    if (scene == null) {
      _showNothing();
      return;
    }
    _debugImageCopy = null;
    _imagePicture?.dispose();
    _imagePicture = null;
    _imageKey = null;
    final key = (
      scene.filter,
      scene.corner.inPlace.filter,
      read.layout.layer,
      _origin,
    );
    if (read.changed || key != _sceneKey || _scene == null) {
      markNeedsAddToScene();
    }
    _scene = scene;
    _sceneKey = key;
  }

  void _showImage(GlassRead read, ImageCopy copy) {
    _debugImageCopy = copy;
    final painter = _painterOf(_fate);
    final origin = _screenOrigin;
    final region = _shown.intersect(copy.rect);
    final key = (
      copy.image,
      copy.placement,
      region,
      origin,
      _frost,
      _dissolve,
      painter?.imageKey(read, copy),
    );
    _scene = null;
    _sceneKey = null;
    if (key == _imageKey && _imagePicture != null) return;
    _imagePicture?.dispose();
    _imageKey = key;
    _imagePicture = switch (painter) {
      final painter? => painter.recordImage(
        read,
        copy,
        frostToLocal(origin, _devicePixelRatio),
      ),
      null when read.lead.ask.look.imageRead?.key == null => recordFrostedCopy(
        copy,
        region,
        origin,
        frost: _frost!,
        shader: _frostShader ??= newFrostShader(),
        dissolve: _dissolve.mapped(origin.dy, 1),
      ),
      null => recordFilteredCopy(
        copy,
        region,
        origin,
        dissolve: _dissolve.mapped(origin.dy, 1),
      ),
    };
    markNeedsAddToScene();
  }

  void _addOutput(SceneOut out, ReadCopy outer) {
    final fate = _fate;
    if (fate is! LeadFate) return;
    final read = fate.read;
    if (read.source is ImageRead) {
      if (_imagePicture case final picture?) out.picture(picture);
      return;
    }
    final corner = outer.cornerOf(read);
    final scene = corner == null ? null : _sceneOf(read, corner);
    if (scene == null) return;
    out.settle();
    scene.corner.addToScene(
      out.builder,
      scene.filter,
      frostToLocal(_screenOrigin, _devicePixelRatio),
      out.held,
    );
  }

  @override
  void updateSubtreeNeedsAddToScene() {
    composeUnlessPlanned(this);
    super.updateSubtreeNeedsAddToScene();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<LiquidGlassBackdropFilter>('filter', _filter))
      ..add(DiagnosticsProperty<Rect>('clip', _clip))
      ..add(EnumProperty<BlendMode>('blendMode', _blendMode))
      ..add(
        FlagProperty(
          'serves',
          value: _serves,
          ifTrue: 'draws a copy',
          ifFalse: 'reads the backdrop',
        ),
      )
      ..add(
        FlagProperty(
          'drawsGroup',
          value: _drawsGroup,
          ifTrue: 'drawn in the filter of glass',
        ),
      );
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    if (_scene case final scene?) {
      scene.corner.addToScene(
        builder,
        scene.filter,
        frostToLocal(_screenOrigin, _devicePixelRatio),
        _held,
      );
      _held.built();
      if (!_drawsGroup) addChildrenToScene(builder);
      return;
    }
    if (_imagePicture case final picture?) {
      builder.addPicture(Offset.zero, picture);
      if (!_drawsGroup) addChildrenToScene(builder);
      return;
    }
    builder
      ..pushClipRect(_clip, clipBehavior: Clip.hardEdge)
      ..pushBackdropFilter(_imageFilter, blendMode: _blendMode);
    final dissolve = _dissolve;
    if (!dissolve.isNone) {
      final key = (_clip, dissolve);
      if (key != _maskKey || _mask == null) {
        _mask?.dispose();
        final recorder = ui.PictureRecorder();
        paintFrostDissolve(Canvas(recorder), _clip, dissolve);
        _mask = recorder.endRecording();
        _maskKey = key;
      }
      builder.addPicture(Offset.zero, _mask!);
    }
    addChildrenToScene(builder);
    builder
      ..pop()
      ..pop();
  }

  @override
  void dispose() {
    _frostShader?.dispose();
    _frostShader = null;
    _imagePicture?.dispose();
    _imagePicture = null;
    _mask?.dispose();
    _mask = null;
    _scene = null;
    _held.dispose();
    super.dispose();
  }
}

/// A render object that holds a [LiquidGlassBackdropFilterLayer].
///
/// While attached it is registered with the glass composer of its view, which
/// then plans each frame's scene before it is built, as it does for glass, and
/// lives until the last render object registered with it detaches. A view
/// whose backdrop filter layers are held by no such render object fails an
/// assertion in a debug build.
mixin LiquidGlassBackdropFilterHost on RenderObject {
  /// The [LiquidGlassBackdropFilterLayer] this render object holds, or null
  /// while it holds none.
  LiquidGlassBackdropFilterLayer? get backdropFilterLayer;

  @mustCallSuper
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    GlassComposer.host(owner, this);
  }

  @mustCallSuper
  @override
  void detach() {
    GlassComposer.unhost(owner!, this);
    super.detach();
  }
}

/// What the package and its tests read of a
/// [LiquidGlassBackdropFilterLayer].
@internal
extension ComposedBackdropFilterLayer on LiquidGlassBackdropFilterLayer {
  /// What the frame's plan reads of this layer.
  PlanSite get site => _site;

  /// Whether this frame's frost is drawn in the filter of the glass over it.
  bool get drawsGroup => _drawsGroup;

  /// Whether this frame draws a copy in place of the backdrop read.
  bool get serves => _serves;

  /// The image filter that reads the backdrop where no copy serves.
  ui.ImageFilter get imageFilter => _imageFilter;

  /// The frost a shader may draw over a copy, or null for a filter that has
  /// none.
  LiquidGlassBackdropFrost? get frost => _frost;

  /// The image copy this frame draws from, if it draws from one.
  ImageCopy? get debugImageCopy => _debugImageCopy;
}

// A frost or a group's glass drawn over a layer of the scene.
typedef _Scene = ({CornerRead corner, ui.ImageFilter filter});

final class _FilterSite implements PlanSite {
  _FilterSite(this._layer);

  final LiquidGlassBackdropFilterLayer _layer;

  @override
  SiteNode? formNode;

  @override
  SiteAsk ask(ViewPixels view) => _layer._ask(view);

  @override
  void beginFate(SiteFate fate) => _layer._beginFate(fate);

  @override
  void show(GlassRead read, ReadPixels pixels) => _layer._show(read, pixels);

  @override
  void addOutput(SceneOut out, ReadCopy outer) => _layer._addOutput(out, outer);

  @override
  bool get drawsOwnChildren => _layer._drawsGroup;

  @override
  bool get outputsInPlace => true;

  @override
  void endFrame() {}
}
