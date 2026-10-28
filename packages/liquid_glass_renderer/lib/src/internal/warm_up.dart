import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/glass_shadow.dart';
import 'package:liquid_glass_renderer/src/internal/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/internal/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/paint_fake_glass_surface.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_field.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/liquid_shape.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

/// The draws the last completed [warmLiquidGlassPipelines] submitted, or
/// null before one completed: the backdrop filters and seeded passes of one
/// row, the shader paints (each final shader over a solid backdrop, and one
/// fake glass surface) and the shadows under them.
@visibleForTesting
({int filters, int passes, int paints, int shadows})? debugWarmUpDraws;

/// The longest the warm-up waits for its scene on the raster thread.
const Duration _sceneTimeout = Duration(seconds: 2);

/// The side of one warm-up cell, in logical pixels.
const double _cell = 24;

/// Frost sigmas, in logical pixels, spread so that at any device pixel
/// ratio from 1 up a blur pass takes each of Impeller's downsample paths:
/// the texture copy at a scale of 1/2 or more, the downsample shader below.
const List<double> _frostSigmas = [1, 2, 8, 14];

/// Draws once with each Flutter GPU pipeline of the geometry matte (shapes,
/// material map, tint map, field), then rasterizes an offscreen scene over
/// a backdrop with glass shadows: each final shader as a backdrop filter,
/// alone and over each frost sigma, in a seeded pass, and painted as a
/// layer over a solid backdrop paints it; the fake glass filters, plain,
/// source-atop in a shape and in a seeded pass; and a fake glass surface.
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
    final appearance = List<double>.filled(16 * 2 * 4, 0);
    // The matte scale is a uniform: any one draws with the same pipelines.
    ui.Image render({
      bool writeMatte = true,
      bool writeMaterials = false,
      bool writeTintOnly = false,
      LiquidGlassField? field,
    }) => geometry
        .render(
          width: 8,
          height: 8,
          shapeData: const [],
          numShapes: 1,
          refractionHeight: 1,
          refractionAmount: 1,
          offsetX: 0,
          offsetY: 0,
          matteScale: 2,
          writeMatte: writeMatte,
          writeMaterials: writeMaterials,
          writeTintOnly: writeTintOnly,
          appearanceData: appearance,
          field: field,
        )
        .image;

    final matte = render(writeMaterials: true).clone();
    images.add(matte);
    final material = geometry.materialImage!.clone();
    images.add(material);
    render(writeMatte: false, writeMaterials: true, writeTintOnly: true);
    final tint = geometry.materialImage!.clone();
    images.add(tint);
    render(
      field: LiquidGlassField(
        samples: Float32List(2 * 2 * 4),
        cols: 2,
        rows: 2,
        origin: Offset.zero,
        step: 1,
      ),
    );
    FlutterGpuGeometryRenderer.flushPendingSubmissions();

    final variants = FinalShaderVariant.all;
    final programs = await Future.wait([
      for (final variant in variants)
        ui.FragmentProgram.fromAsset(variant.assetKey),
    ]);
    final surface = (await ui.FragmentProgram.fromAsset(
      ShaderKeys.fakeGlassSurface,
    )).fragmentShader();
    final filters = <ui.ImageFilter>[];
    final passes = <_Pass>[];
    final solids = <ui.FragmentShader>[];
    for (final (index, program) in programs.indexed) {
      // Bound as a layer binds them: a draw needs every sampler its variant
      // declares.
      final shader = program.fragmentShader()
        ..setImageSampler(0, matte, filterQuality: FilterQuality.low);
      if (variants[index].kind != FinalShaderKind.analytic) {
        shader.setImageSampler(1, matte, filterQuality: FilterQuality.low);
        switch (variants[index].kind) {
          case FinalShaderKind.material:
            shader
              ..setImageSampler(2, material)
              ..setImageSampler(3, material, filterQuality: FilterQuality.low);
          case FinalShaderKind.tint:
            shader.setImageSampler(2, tint, filterQuality: FilterQuality.low);
          case FinalShaderKind.single || FinalShaderKind.analytic:
            break;
        }
      }
      final filter = ui.ImageFilter.shader(shader);
      filters.add(filter);
      for (final sigma in _frostSigmas) {
        filters.add(ui.ImageFilter.compose(inner: _blur(sigma), outer: filter));
      }
      // The passes take the frost sigmas in turn, so each downsample path
      // seeds one.
      passes.add((
        seed: _blur(_frostSigmas[index % _frostSigmas.length]),
        filter: filter,
        fake: false,
      ));
      // Uniform values pick no pipeline: painted, the filter's shader draws
      // what a layer over a solid backdrop draws, whatever they hold.
      solids.add(shader);
    }
    // A pass Impeller would not crop a blur for is seeded by an identity.
    passes.add((
      seed: fakeGlassIdentityFilter,
      filter: filters.first,
      fake: false,
    ));
    final fakes = <ui.ImageFilter>[];
    for (final brightness in Brightness.values) {
      for (final sigma in _frostSigmas) {
        final parts = fakeGlassBackdropFilterParts(
          LiquidGlassSettings.ios27Regular(
            brightness: brightness,
            frost: sigma,
          ),
          LiquidGlassAppearance.ios27Regular(brightness: brightness),
        );
        if (parts == null) continue;
        fakes.add(parts.full);
        // One pass per brightness, whose color transfer may be built of
        // other filters.
        if (sigma == _frostSigmas.last) {
          passes.add((
            seed: _blur(parts.sigma, parts.tileMode),
            filter: parts.withoutBlur,
            fake: true,
          ));
        }
      }
    }
    final draws = (
      filters: filters.length + 2 * fakes.length,
      passes: passes.length,
      paints: solids.length + 1,
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
      for (final pass in passes) {
        layers.add(_seededPass(pass, cell(layers.length), key));
      }
      // A paint reads no backdrop: the first row alone draws them.
      if (key == null) {
        for (final solid in solids) {
          layers.add(_solidPaint(solid, cell(layers.length)));
        }
        layers.add(_fakeSurface(surface, cell(layers.length)));
      }
      return layers;
    }, draws.filters + draws.passes + draws.paints);
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

const _fakeGlassShape = LiquidRoundedSuperellipse(borderRadius: 6);

ui.ImageFilter _blur(double sigma, [TileMode tileMode = TileMode.mirror]) =>
    ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: tileMode);

/// A seeded pass: the seed, the glass's filter without its blur, and
/// whether it is a fake glass's.
typedef _Pass = ({ui.ImageFilter seed, ui.ImageFilter filter, bool fake});

/// [pass] as a SeededBackdropPassLayer adds it: the seed reads the backdrop
/// into a pass of [bounds], the glass's filter replaces the pass inside
/// the glass's clip (a rect for glass, the shape for fake glass), and the
/// rest of the pass is cleared.
ClipRectLayer _seededPass(_Pass pass, Rect bounds, BackdropKey? key) {
  final shape = _fakeGlassShape.getOuterPath(bounds);
  final recorder = ui.PictureRecorder();
  Canvas(recorder, bounds).drawPath(
    Path.combine(PathOperation.difference, Path()..addRect(bounds), shape),
    Paint()
      ..blendMode = BlendMode.clear
      ..isAntiAlias = pass.fake,
  );
  final clip = pass.fake
      ? ClipPathLayer(clipPath: shape)
      : ClipRectLayer(clipRect: bounds.deflate(2));
  return ClipRectLayer(clipRect: bounds)..append(
    BackdropFilterLayer(filter: pass.seed)
      ..backdropKey = key
      ..append(
        clip..append(
          BackdropFilterLayer(filter: pass.filter)..blendMode = BlendMode.src,
        ),
      )
      ..append(PictureLayer(bounds)..picture = recorder.endRecording()),
  );
}

/// A FakeGlass surface with its highlight and its exterior border ring,
/// painted as a FakeGlass paints them.
PictureLayer _fakeSurface(ui.FragmentShader shader, Rect bounds) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, bounds);
  final settings = LiquidGlassSettings.ios27Regular(
    brightness: Brightness.light,
  );
  const appearance = LiquidGlassAppearance.ios27RegularLight();
  final local = Offset.zero & bounds.size;
  void paint({bool exteriorOnly = false, bool highlightOnly = false}) =>
      paintFakeGlassSurface(
        canvas,
        shader: shader,
        size: bounds.size,
        shape: _fakeGlassShape,
        settings: settings,
        appearance: appearance,
        devicePixelRatio: 1,
        exteriorOnly: exteriorOnly,
        highlightOnly: highlightOnly,
      );
  canvas
    ..save()
    ..translate(bounds.left, bounds.top)
    ..save()
    ..clipPath(_fakeGlassShape.getOuterPath(local));
  paint();
  paint(highlightOnly: true);
  canvas
    ..restore()
    ..clipPath(
      Path.from(_fakeGlassShape.getOuterPath(local))
        ..addRect(local.inflate(fakeGlassSurfaceOutset(settings)))
        ..fillType = PathFillType.evenOdd,
    );
  paint(exteriorOnly: true);
  canvas.restore();
  return PictureLayer(bounds)..picture = recorder.endRecording();
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
  LiquidRoundedSuperellipse(borderRadius: 6),
  LiquidRoundedRectangle(borderRadius: 6),
  LiquidOval(),
];

/// A backdrop for the filters to read, with the shadows of each glass shape
/// over it, each in a cell of its own, as a layer draws them: offset and
/// blurred, clipped to outside the glass, and blurred outside the shape
/// only.
ui.Picture _backdropPicture(Rect bounds) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, bounds)
    ..drawRect(bounds, Paint()..color = const Color(0xFF3A6EA5));
  var index = 0;
  for (final shape in _shadowShapes) {
    for (final style in [BlurStyle.normal, BlurStyle.outer]) {
      final rect = Rect.fromLTWH(index++ * _cell + 4, 4, _cell - 8, _cell - 8);
      final shadow = Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = MaskFilter.blur(style, 4);
      canvas.save();
      if (style == BlurStyle.normal) {
        canvas.clipPath(
          Path.combine(
            PathOperation.difference,
            Path()..addRect(rect.inflate(8)),
            shape.getOuterPath(rect),
          ),
        );
        drawGlassShape(canvas, shape, rect.shift(const Offset(0, 2)), shadow);
      } else {
        drawGlassShape(canvas, shape, rect, shadow);
      }
      canvas.restore();
    }
  }
  return recorder.endRecording();
}
