import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_read.dart';
import 'package:liquid_glass_renderer/src/rendering/pinned_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_filter.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_programs.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';

/// The need of a copy `backdrop_frost.frag` frosts by [sigma] logical
/// pixels, or null where it cannot: shader frost is off, the renderer is not
/// Impeller (its program is built for Impeller alone), the frost is too wide
/// for it, or the program is not loaded yet.
@internal
CopyNeed? frostNeed(double sigma, {required double devicePixelRatio}) {
  if (!GlassCopyTuning.shaderFrost || !ui.ImageFilter.isShaderFilterSupported) {
    return null;
  }
  if (!GlassShaderPrograms.isCached(ShaderKeys.backdropFrost)) {
    unawaited(GlassShaderPrograms.precacheShader(ShaderKeys.backdropFrost));
    return null;
  }
  return CopyNeed.edgeFrost(sigma, devicePixelRatio: devicePixelRatio);
}

/// A filtered [copy] drawn into coordinates that [origin] shifts to the
/// screen's: the part [shown], in screen coordinates, cut to [outline], in
/// the drawn coordinates, when there is one.
///
/// The copy already holds the filtered backdrop composited over the
/// backdrop: it replaces what lies under it. With a [dissolve], in the
/// screen's logical rows, it dissolves into what lies under it between the
/// rows.
@internal
ui.Picture recordFilteredCopy(
  PageCopy copy,
  Rect shown,
  Offset origin, {
  Path? outline,
  FrostDissolve dissolve = FrostDissolve.none,
}) {
  if (!kReleaseMode) GlassWork.pictures++;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (outline != null) canvas.clipPath(outline);
  canvas.translate(-origin.dx, -origin.dy);
  final paint = Paint()
    ..blendMode = BlendMode.src
    ..filterQuality = FilterQuality.none;
  if (dissolve.isNone) {
    canvas.drawImageRect(copy.image, copy.readOf(shown).source, shown, paint);
  } else {
    // No bounds: a layer cut to the part would cover the pixel its edge
    // splits only in part, where the copy drawn alone replaces it.
    canvas
      ..saveLayer(null, Paint())
      ..drawImageRect(copy.image, copy.readOf(shown).source, shown, paint);
    paintFrostDissolve(canvas, shown, dissolve);
    canvas.restore();
  }
  return recorder.endRecording();
}

/// Erases what the layer [canvas] draws into holds over [rect] as far as
/// [dissolve], in the canvas's rows, says the frost is gone there: what
/// `backdrop_frost.frag` does to a frost it draws, for a frost Impeller
/// drew.
@internal
void paintFrostDissolve(Canvas canvas, Rect rect, FrostDissolve dissolve) {
  // A gradient is straight between its stops: enough of them that no change
  // of slope shows as a line.
  const steps = 32;
  canvas.drawRect(
    rect,
    Paint()
      ..blendMode = BlendMode.dstIn
      ..isAntiAlias = false
      ..shader = ui.Gradient.linear(
        Offset(0, dissolve.gone),
        Offset(0, dissolve.whole),
        [
          for (var i = 0; i <= steps; i++)
            Color.fromRGBO(
              0,
              0,
              0,
              dissolve.at(
                dissolve.gone + (dissolve.whole - dissolve.gone) * i / steps,
              ),
            ),
        ],
        [for (var i = 0; i <= steps; i++) i / steps],
      ),
  );
}

/// The shader [recordFrostedCopy] frosts with; its owner disposes it.
@internal
ui.FragmentShader newFrostShader() =>
    GlassShaderPrograms.cached(ShaderKeys.backdropFrost)!.fragmentShader();

/// [frost] drawn from the unblurred [copy] by [shader], into
/// coordinates that [origin] shifts to the screen's: the part [shown], in
/// screen coordinates, composited with [blendMode] and cut to [outline],
/// in the drawn coordinates, when there is one.
///
/// A rect drawn in the copy image's pixels, so that the shader's fragment
/// coordinate is the pixel of the image it frosts around.
@internal
ui.Picture recordFrostedCopy(
  PageCopy copy,
  Rect shown,
  Offset origin, {
  required LiquidGlassBackdropFrost frost,
  required ui.FragmentShader shader,
  BlendMode blendMode = BlendMode.srcOver,
  Path? outline,
  FrostDissolve dissolve = FrostDissolve.none,
}) {
  final read = copy.readOf(shown);
  _setFrost(
    shader,
    read.frostSampling(frost.sigma, dissolve: dissolve),
    frost.colorMatrix,
  );
  shader.setImageSampler(0, copy.image, filterQuality: FilterQuality.low);
  if (!kReleaseMode) GlassWork.pictures++;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (outline != null) canvas.clipPath(outline);
  canvas.translate(-origin.dx, -origin.dy);
  read.toImage(canvas);
  final source = read.source;
  final paint = Paint()
    ..shader = shader
    ..blendMode = blendMode
    ..isAntiAlias = false;
  canvas.drawRect(source, paint);
  return recorder.endRecording();
}

/// From the screen's device pixels to a frost's coordinates, which begin at
/// [origin] of the screen.
@internal
Matrix4 frostToLocal(Offset origin, double devicePixelRatio) =>
    Matrix4.translationValues(-origin.dx, -origin.dy, 0)
      ..scaleByDouble(1 / devicePixelRatio, 1 / devicePixelRatio, 1, 1);

/// The filter that frosts as [sampling] says, through [colorMatrix].
@internal
ui.ImageFilter frostFilter(
  FrostSampling sampling,
  List<double>? colorMatrix,
  ui.FragmentShader shader,
) {
  _setFrost(shader, sampling, colorMatrix);
  shader.setImageSampler(0, transparentPixel, filterQuality: FilterQuality.low);
  return shaderFilterNow(shader);
}

ui.FragmentShader? _inPlaceFrost;

/// The frost drawn into a copy at the copy's own pixels: the layers the
/// copy is drawn in, one with the whole frost for its filter or one for
/// each axis of it.
@internal
final class CopyFrost {
  const CopyFrost._(this._passes);

  // The filters, outermost first.
  final List<ui.ImageFilter> _passes;

  /// Pushes the frost's layers, each pinned to [size] from [origin]; what
  /// is drawn until [pop] comes out frosted.
  ///
  /// A layer an axis, not one layer with both filters: each is then cut by
  /// a clip above it as the copy is, where the second of two filters on one
  /// layer takes what the first left for the whole of it.
  void push(ui.SceneBuilder builder, Offset origin, Size size) {
    for (final pass in _passes) {
      PinnedLayers.push(builder, pass, origin, size);
    }
  }

  /// Ends what [push] began.
  void pop(ui.SceneBuilder builder) {
    for (var i = 0; i < _passes.length; i++) {
      builder.pop();
    }
  }
}

/// What a copy holds of a frost drawn into it at its own pixels: the layers
/// that draw it, and the frost they draw.
@internal
typedef InPlaceFrost = ({CopyFrost? filter, double sigma});

/// What frosts a copy at its own pixels for Impeller's blur by [sigma]
/// logical pixels, its taps as [sampling] gives them, and the frost the copy
/// then holds.
///
/// The one place a copy comes to hold a frost: [sigma] where a filter draws
/// it, none where [sigma] is 0 or the frost's program is not loaded yet, and
/// the glass over the copy frosts it fragment by fragment.
@internal
InPlaceFrost frostInPlace(double sigma, FrostSampling Function() sampling) {
  if (sigma <= 0) return (filter: null, sigma: 0);
  final filter = _frostFilterOf(sampling());
  return (filter: filter, sigma: filter == null ? 0 : sigma);
}

// What frosts a layer as [sampling] says, or null before its shader is
// loaded.
CopyFrost? _frostFilterOf(FrostSampling sampling) {
  final shader = _inPlaceFrost ??= GlassShaderPrograms.cached(
    ShaderKeys.backdropFrost,
  )?.fragmentShader();
  if (shader == null) {
    // An app that warms nothing up still gets its copies frosted: until
    // the program loads the glass frosts them itself, with sparse taps.
    unawaited(GlassShaderPrograms.precacheShader(ShaderKeys.backdropFrost));
    return null;
  }
  final key = (sampling.size, sampling.bounds, sampling.frost, sampling.shown);
  if (_inPlaceFilters[key] case final held?) return held;
  if (_inPlaceFilters.length >= 32) _inPlaceFilters.clear();
  final lattice = _latticeOf(sampling);
  if (lattice != null) return _inPlaceFilters[key] = lattice;
  _setFrost(shader, sampling, null);
  shader.setImageSampler(0, transparentPixel, filterQuality: FilterQuality.low);
  // The one shader holds other uniforms by the time a scene takes this.
  final sparse = CopyFrost._([shaderFilterNow(shader)]);
  // Sparse taps that stand in until the lattice's program loads are not
  // kept.
  final standsIn = frostLatticeOf(sampling.frost) != null;
  return standsIn ? sparse : _inPlaceFilters[key] = sparse;
}

ui.FragmentShader? _axisFrost;
ui.FragmentShader? _squareFrost;

/// The reads of one axis of the frost drawn into a copy by [frost] of the
/// copy's pixels, seen from the center of a pixel: where each lies, in
/// pixels from it, and its weight; eight of each, the ones a narrower frost
/// leaves out weighing nothing. The weights add up to one.
///
/// The one place the frost's shape is worked out. It is a Gaussian over the
/// copy's own pixels, every one it reaches weighed: three, four, six or
/// eight reads, by the frost's width, each standing for two pixels and read
/// between them by their weights. A sparse frost reads a few points of a
/// wide Gaussian, so a bright point under it comes out as that many points
/// and an edge as steps: on the iPhone stars under clear glass were small
/// flowers and a crescent had stairs.
///
/// Every weight is cut by the Gaussian's value at the edge of the pixels
/// read, so nothing steps where a pixel enters or leaves them. The cut
/// narrows the Gaussian, so the one weighed is as much wider as makes what
/// is left the width asked; the widest the pixels read can hold is what the
/// cut leaves of a flat one, and a frost that asks for more gets that.
/// [frost] is what a bilinear read of the copy leaves for the taps; a sixth
/// of a pixel squared more is the Gaussian over the pixels themselves.
@internal
({List<double> offsets, List<double> weights}) latticeTaps(double frost) {
  // A page's glass asks for a few widths, and a copy that changes size asks
  // again every frame.
  if (_tapsOf[frost] case final held?) return held;
  if (_tapsOf.length >= 32) _tapsOf.clear();
  return _tapsOf[frost] = _latticeTaps(frost);
}

final _tapsOf = <double, ({List<double> offsets, List<double> weights})>{};

({List<double> offsets, List<double> weights}) _latticeTaps(double frost) {
  final wide = frost * frost + 1 / 6;
  // n pairs hold a Gaussian up to 1.3 / 3 of n wide.
  final asked = sqrt(wide) * 2.3077;
  final pairs = asked <= 3
      ? 3
      : asked <= 4
      ? 4
      : asked <= 6
      ? 6
      : 8;
  final edge = pairs * pairs;
  // The weight of the pixel [pixel] from the center under exp(k x^2) cut at
  // the edge; as k goes to nothing, the parabola the cut leaves of a flat
  // Gaussian.
  double weightAt(int pixel, double k) => k == 0
      ? (edge - pixel * pixel).toDouble()
      : max(exp(k * pixel * pixel) - exp(k * edge), 0);
  double widthOf(double k) {
    var total = 0.0;
    var spread = 0.0;
    for (var pixel = 1 - pairs; pixel < pairs; pixel++) {
      final weight = weightAt(pixel, k);
      total += weight;
      spread += weight * pixel * pixel;
    }
    return spread / total;
  }

  // The flatter the Gaussian, the wider what the cut leaves of it.
  var k = 0.0;
  if (widthOf(0) > wide) {
    var narrow = -64.0;
    var flat = 0.0;
    for (var i = 0; i < 48; i++) {
      final middle = (narrow + flat) / 2;
      if (widthOf(middle) < wide) {
        narrow = middle;
      } else {
        flat = middle;
      }
    }
    k = (narrow + flat) / 2;
  }
  final offsets = List<double>.filled(8, 0);
  final weights = List<double>.filled(8, 0);
  var total = 0.0;
  for (var i = 0; i < pairs; i++) {
    final first = 2 * i - (pairs - 1);
    final near = weightAt(first, k);
    final far = weightAt(first + 1, k);
    final both = near + far;
    offsets[i] = first + far / max(both, 1e-6);
    weights[i] = both;
    total += both;
  }
  for (var i = 0; i < pairs; i++) {
    weights[i] /= total;
  }
  return (offsets: offsets, weights: weights);
}

// The frost of [sampling] over every pixel of the copy it reaches, or null
// where the sparse taps draw it: a frost too wide for eight pairs of the
// copy's pixels, and before the program is loaded.
//
// A frost of three pairs is one pass of nine reads. A wider one is a pass
// along x and one along y over what it left: its weights are a product of
// the axes', so they draw the same square with 2 n reads for n * n, 12 a
// pixel of the copy for 36 at six pairs. Every pixel of a copy frosted at
// its own pixels takes the same weights, so the programs are their reads.
CopyFrost? _latticeOf(FrostSampling sampling) {
  final FrostSampling(:size, :bounds, :frost) = sampling;
  final lattice = frostLatticeOf(frost);
  if (lattice == null) return null;
  final square = lattice == FrostLattice.square;
  final key = square
      ? ShaderKeys.backdropFrostSquare
      : ShaderKeys.backdropFrostAxis;
  final held = square ? _squareFrost : _axisFrost;
  final shader = held ?? GlassShaderPrograms.cached(key)?.fragmentShader();
  if (shader == null) {
    unawaited(GlassShaderPrograms.precacheShader(key));
    return null;
  }
  if (square) {
    _squareFrost = shader;
  } else {
    _axisFrost = shader;
  }
  final taps = latticeTaps(frost);
  // The uniforms by name: [rest] holds each one the pass has beside the
  // copy's size and bounds.
  ui.ImageFilter pass(Map<String, List<double>> rest) {
    _put(shader, _at(shader, 'uSize'), [size.width, size.height]);
    _put(shader, _at(shader, 'uBounds'), [
      bounds.left,
      bounds.top,
      bounds.right,
      bounds.bottom,
    ]);
    for (final MapEntry(key: name, value: values) in rest.entries) {
      _put(shader, _at(shader, name), values);
    }
    shader.setImageSampler(
      0,
      transparentPixel,
      filterQuality: FilterQuality.low,
    );
    // The one shader holds other uniforms by the time a scene takes this.
    return shaderFilterNow(shader);
  }

  if (square) {
    return CopyFrost._([
      pass({
        'uOffsets': [...taps.offsets.take(3)],
        'uWeights': [...taps.weights.take(3)],
      }),
    ]);
  }
  return CopyFrost._([
    for (final axis in const [
      [0.0, 1.0],
      [1.0, 0.0],
    ])
      pass({'uAxis': axis, 'uOffsets': taps.offsets, 'uWeights': taps.weights}),
  ]);
}

// Chrome over a scroll keeps a copy's place, so its filter too.
final _inPlaceFilters = <Object, CopyFrost>{};

// Where backdrop_frost.frag takes each uniform, read from the program by
// name: its instances share one layout.
final class _FrostLayout {
  _FrostLayout(ui.FragmentShader shader)
    : size = _at(shader, 'uSize'),
      bounds = _at(shader, 'uBounds'),
      frost = _at(shader, 'uFrost'),
      scale = _at(shader, 'uScale'),
      shown = _at(shader, 'uShown'),
      matrix = _at(shader, 'uMatrix'),
      offset = _at(shader, 'uOffset'),
      dissolve = _at(shader, 'uDissolve');

  final int size;
  final int bounds;
  final int frost;
  final int scale;
  final int shown;
  final int matrix;
  final int offset;
  final int dissolve;
}

// The float index of the uniform [name] of [shader].
int _at(ui.FragmentShader shader, String name) =>
    shader.getUniformFloat(name).shaderIndex;

// Writes [values] into [shader] from the float index [at] on.
void _put(ui.FragmentShader shader, int at, List<double> values) {
  for (var i = 0; i < values.length; i++) {
    shader.setFloat(at + i, values[i]);
  }
}

_FrostLayout? _frostLayout;

// The uniforms of backdrop_frost.frag.
void _setFrost(
  ui.FragmentShader shader,
  FrostSampling sampling,
  List<double>? colorMatrix,
) {
  final FrostSampling(:size, :bounds, frost: taps, :scale, :shown, :dissolve) =
      sampling;
  final m = colorMatrix ?? _identityMatrix;
  final layout = _frostLayout ??= _FrostLayout(shader);
  _put(shader, layout.size, [size.width, size.height]);
  _put(shader, layout.bounds, [
    bounds.left,
    bounds.top,
    bounds.right,
    bounds.bottom,
  ]);
  shader
    ..setFloat(layout.frost, taps)
    ..setFloat(layout.scale, scale);
  _put(shader, layout.shown, [
    shown.left,
    shown.top,
    shown.right,
    shown.bottom,
  ]);
  _put(shader, layout.matrix, [
    for (var column = 0; column < 4; column++)
      for (var row = 0; row < 4; row++) m[row * 5 + column],
  ]);
  _put(shader, layout.offset, [
    for (var row = 0; row < 4; row++) m[row * 5 + 4] / 255,
  ]);
  _put(shader, layout.dissolve, [dissolve.whole, dissolve.gone]);
}

/// One transparent pixel: what a sampler is bound to where a draw has no image
/// of its own for it.
final ui.Image transparentPixel = () {
  final recorder = ui.PictureRecorder();
  Canvas(recorder);
  return recorder.endRecording().toImageSync(1, 1);
}();

const _identityMatrix = <double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0,
];
