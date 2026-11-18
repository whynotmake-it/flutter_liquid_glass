import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/rendering/fake_glass_field_image.dart';
import 'package:liquid_glass_renderer/src/rendering/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_blur.dart';
import 'package:liquid_glass_renderer/src/rendering/paint_fake_glass_surface.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_filter.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_programs.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_uniforms.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';
import 'package:liquid_glass_renderer/src/rendering/shading.dart';
import 'package:liquid_glass_renderer/src/rendering/shape_set.dart';

/// The draws the last completed [warmLiquidGlassPipelines] submitted, or
/// null before one completed: the backdrop filters of one row, the shader
/// paints (each final shader over a solid backdrop, and the fake glass
/// surfaces of a shape and of a field) and the shadows under them.
@visibleForTesting
({int filters, int paints, int shadows})? debugWarmUpDraws;

/// The longest the warm-up waits for its scene on the raster thread.
const Duration _sceneTimeout = Duration(seconds: 2);

/// The side of one warm-up cell, in logical pixels.
const double _cell = 24;

/// Frost sigmas, in logical pixels, spread so that at any device pixel
/// ratio from 1 up a blur pass takes each of Impeller's downsample paths:
/// the texture copy at a scale of 1/2 or more, the downsample shader below.
const List<double> _frostSigmas = [1, 2, 8, 14];

final GlassFace _face = GlassFace.of(
  settings: const LiquidGlassSettings(),
  appearance: WornAppearance.plain,
  colorModels: const [],
  devicePixelRatio: 1,
  blurs: false,
);

/// Draws once with each Flutter GPU pipeline of the geometry (atlas tiles of
/// shapes and of a field, without looks, with the tint and with the whole
/// look), then rasterizes an offscreen scene over a backdrop with glass
/// shadows: each final shader as a backdrop filter, alone and over each
/// frost sigma, and painted as a layer over a solid backdrop paints it; the
/// fake glass filters, plain and source-atop in a shape; and the fake glass
/// surfaces of a shape and of a field.
/// The glow and every other effect of a final shader is a uniform, which
/// picks no pipeline.
///
/// Flutter GPU creates a pipeline at its first draw, on the UI thread, and
/// Impeller creates the variant a backdrop filter needs (its subpass's
/// sample count and stencil) at the filter's first draw, on the raster
/// thread; either stalls the first frame that shows glass. Nothing reaches
/// the screen. A failure is reported and leaves the layers as they would be
/// without the warm-up.
Future<void> warmLiquidGlassPipelines(
  FlutterGpuGeometryRenderer geometry,
) async {
  final images = <ui.Image>[];
  try {
    // One rounded rectangle, whose ring takes the tile pipelines.
    final shape = ShapeSet.rows(
      shapes: ShapeSet.row(
        type: RawShapeType.roundedRectangle,
        width: 8,
        height: 8,
        radius: 2,
        center: const Offset(8, 8),
      ),
      boxes: const [4, 4, 12, 12],
    );
    const reach = GlassReach(inward: 4, outward: 1);
    final field = BufferField(
      LiquidGlassField(
        samples: Float32List(2 * 2 * 4),
        columns: 2,
        rows: 2,
        origin: Offset.zero,
        step: 1,
        edge: Path()..addRect(const Rect.fromLTWH(0, 0, 1, 1)),
      ),
      layerToBuffer: (1, 0, 0, 1, 0, 0),
    );
    ui.Image? shapesAtlas;
    ui.Image? tint;
    ui.Image? material;
    for (final looks in <ShapeLooks?>[
      null,
      ShapeLooks(List.filled(8, 0), tintOnly: true),
      ShapeLooks(List.filled(8, 0), tintOnly: false),
    ]) {
      final atlas = geometry.renderAtlas(
        Tiling.shapes(
          shape,
          width: 16,
          height: 16,
          reach: reach,
          looks: looks,
        ),
      );
      switch (looks) {
        case null:
          images.add(shapesAtlas = atlas.image.clone());
        case ShapeLooks(tintOnly: true):
          images.add(tint = atlas.looks.first.clone());
        case _:
          images.add(material = atlas.looks.first.clone());
      }
      geometry.renderAtlas(
        Tiling.field(
          field,
          width: 16,
          height: 16,
          reach: reach,
          shapes: shape,
          looks: looks,
        ),
      );
    }
    FlutterGpuGeometryRenderer.flush();

    final variants = FinalShaderVariant.all;
    final programs = [
      for (final variant in variants)
        GlassShaderPrograms.cached(variant.assetKey)!,
    ];
    final fakeSurfaces = [
      for (final (key, paint) in [
        (ShaderKeys.fakeGlassSurface, _fakeSurface),
        (ShaderKeys.fakeGlassFieldSurface, _fakeFieldBody),
      ])
        if (GlassShaderPrograms.cached(key) case final program?)
          (program.fragmentShader(), paint),
    ];
    final filters = <ui.ImageFilter>[];
    final solids = <ui.FragmentShader>[];
    for (final (index, program) in programs.indexed) {
      // Bound as a layer binds them: a draw needs every sampler its variant
      // declares.
      final shader = program.fragmentShader();
      final layout = FinalLayout(shader, variants[index]);
      putFloats(shader, layout.face, _face.face);
      shader.setImageSampler(
        layout.backdrop,
        shapesAtlas!,
        filterQuality: FilterQuality.low,
      );
      if (!variants[index].shape) {
        shader
          ..setImageSampler(
            layout.atlas,
            shapesAtlas,
            filterQuality: FilterQuality.low,
          )
          ..setImageSampler(
            layout.table,
            shapesAtlas,
            filterQuality: atlasTableFilter,
          );
      }
      final look = layout.looks == 1 ? tint : material;
      for (var at = 0; at < layout.looks; at++) {
        shader.setImageSampler(
          layout.firstLook + at,
          look!,
          filterQuality: FilterQuality.low,
        );
      }
      final filter = bilinearShaderFilter(shader);
      filters.add(filter);
      for (final sigma in _frostSigmas) {
        filters.add(ui.ImageFilter.compose(inner: _blur(sigma), outer: filter));
      }
      // Uniform values pick no pipeline: painted, the filter's shader draws
      // what a layer over a solid backdrop draws, whatever they hold.
      solids.add(shader);
    }
    final fakes = <ui.ImageFilter>[];
    for (final brightness in Brightness.values) {
      for (final sigma in _frostSigmas) {
        final parts = fakeGlassBackdropFilterParts(
          FakeGlassLook.of(
            LiquidGlassSettings.ios27Regular(
              brightness: brightness,
              frost: LiquidGlassFrost.sigma(sigma),
            ),
          ),
          LiquidGlassAppearance.ios27Regular(
            brightness: brightness,
          ).wornByNone,
        );
        if (parts == null) continue;
        fakes.add(parts.full);
      }
    }
    final draws = (
      filters: filters.length + 2 * fakes.length,
      paints: solids.length + fakeSurfaces.length,
      shadows: 2 * _shadowShapes.length,
    );
    await _rasterize((key, cell) {
      final layers = <Layer>[];
      for (final filter in [...filters, ...fakes]) {
        layers.add(
          ClipRectLayer(clipRect: cell(layers.length))..append(
            BackdropFilterLayer(filter: filter)..backdropKey = key,
          ),
        );
      }
      // A FakeGlass composites its filter source-atop inside its shape.
      for (final fake in fakes) {
        final bounds = cell(layers.length);
        layers.add(
          ClipPathLayer(clipPath: _fakeGlassShape.getOuterPath(bounds))..append(
            BackdropFilterLayer(filter: fake)
              ..blendMode = BlendMode.srcATop
              ..backdropKey = key,
          ),
        );
      }
      // A paint reads no backdrop: the first row alone draws them.
      if (key == null) {
        for (final solid in solids) {
          layers.add(_solidPaint(solid, cell(layers.length)));
        }
        for (final (shader, paint) in fakeSurfaces) {
          layers.add(paint(shader, cell(layers.length)));
        }
      }
      return layers;
    }, draws.filters + draws.paints);
    debugWarmUpDraws = draws;
  } on Object catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'liquid_glass_renderer',
        context: ErrorDescription('while warming liquid glass pipelines'),
      ),
    );
  } finally {
    for (final image in images) {
      image.dispose();
    }
  }
}

const _fakeGlassShape = LiquidRoundedSuperellipse(radius: 6);

final _fakeLook = FakeGlassLook.of(
  const LiquidGlassSettings.ios27Regular(brightness: Brightness.light),
);

ui.ImageFilter _blur(double sigma) => ui.ImageFilter.blur(
  sigmaX: sigma,
  sigmaY: sigma,
  tileMode: glassBlurTileMode,
);

/// A FakeGlass surface with its glint and its contour ring,
/// painted as a FakeGlass paints them.
PictureLayer _fakeSurface(ui.FragmentShader shader, Rect bounds) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, bounds);
  final look = _fakeLook;
  final appearance =
      const LiquidGlassAppearance.ios27Regular(brightness: Brightness.light)
          .wear(
            bounds.size,
          );
  final local = Offset.zero & bounds.size;
  canvas
    ..save()
    ..translate(bounds.left, bounds.top)
    ..save()
    ..clipPath(_fakeGlassShape.getOuterPath(local));
  final shaders = FakeGlassSurfaceShaders()..begin(shader);
  paintFakeGlassSurfaceWithGlint(
    canvas,
    shaders: shaders,
    size: bounds.size,
    shape: _fakeGlassShape,
    look: look,
    appearance: appearance,
    devicePixelRatio: 1,
  );
  canvas.restore();
  paintFakeGlassContourRing(
    canvas,
    shader: shaders.next(),
    size: bounds.size,
    shape: _fakeGlassShape,
    look: look,
    appearance: appearance,
    devicePixelRatio: 1,
  );
  canvas.restore();
  final picture = recorder.endRecording();
  shaders.dispose();
  return PictureLayer(bounds)..picture = picture;
}

PictureLayer _fakeFieldBody(ui.FragmentShader shader, Rect bounds) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, bounds)..translate(bounds.left, bounds.top);
  final field = LiquidGlassField.fromPath(
    _fakeGlassShape.getOuterPath(Offset.zero & bounds.size),
  );
  final nodes = FakeGlassFieldImage();
  final shaders = FakeGlassSurfaceShaders.field()..begin(shader);
  paintFakeGlassFieldBody(
    canvas,
    shaders: shaders,
    nodes: nodes.of(field),
    field: field,
    look: _fakeLook,
    appearance:
        const LiquidGlassAppearance.ios27Regular(brightness: Brightness.light)
            .wear(
              bounds.size,
            ),
    devicePixelRatio: 1,
  );
  final picture = recorder.endRecording();
  shaders.dispose();
  nodes.dispose();
  return PictureLayer(bounds)..picture = picture;
}

/// Paints [shader] as a layer over a solid backdrop paints it: one
/// hard-edged rect, source over, into the current pass.
PictureLayer _solidPaint(ui.FragmentShader shader, Rect bounds) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder, bounds).drawRect(
    bounds,
    Paint()
      ..shader = shader
      ..isAntiAlias = false,
  );
  return PictureLayer(bounds)..picture = recorder.endRecording();
}

/// Rasterizes two rows of [count] cells: [build] fills a row for a backdrop
/// key (null for the first row, one shared key for the second), given the
/// rect of a cell index in that row.
Future<void> _rasterize(
  List<Layer> Function(BackdropKey? key, Rect Function(int index) cell) build,
  int count,
) async {
  final view = ui.PlatformDispatcher.instance.implicitView;
  final pixelRatio = view?.devicePixelRatio ?? 1;
  final bounds = Rect.fromLTWH(0, 0, _cell * count, _cell * 2);
  final root = OffsetLayer();
  final handle = LayerHandle<OffsetLayer>(root);
  try {
    root.append(PictureLayer(bounds)..picture = _backdropPicture(bounds));
    for (final (row, key) in [(0, null), (1, BackdropKey())]) {
      build(
        key,
        (index) => Rect.fromLTWH(
          index * _cell + 2,
          row * _cell + 2,
          _cell - 4,
          _cell - 4,
        ),
      ).forEach(root.append);
    }
    final pending = root.toImage(bounds, pixelRatio: pixelRatio);
    try {
      (await pending.timeout(_sceneTimeout)).dispose();
    } on TimeoutException {
      unawaited(pending.then((image) => image.dispose()));
    }
  } finally {
    handle.layer = null;
  }
}

/// The shapes glass shadows are drawn in.
const List<LiquidShape> _shadowShapes = [
  LiquidRoundedSuperellipse(radius: 6),
  LiquidRoundedRectangle(radius: 6),
  LiquidOval(),
];

/// A backdrop for the filters to read, with the shadows of each glass shape
/// over it.
ui.Picture _backdropPicture(Rect bounds) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, bounds)
    ..drawRect(bounds, Paint()..color = const Color(0xFF3A6EA5));
  var index = 0;
  for (final shape in _shadowShapes) {
    for (final offset in const [Offset(0, 2), Offset.zero]) {
      final rect = Rect.fromLTWH(index++ * _cell + 4, 4, _cell - 8, _cell - 8);
      LiquidGlassSilhouette.shape(shape, rect).paintShadows(canvas, [
        LiquidGlassShadow(
          color: const Color(0x40000000),
          offset: offset,
          blurRadius: 6,
        ),
      ]);
    }
  }
  return recorder.endRecording();
}
