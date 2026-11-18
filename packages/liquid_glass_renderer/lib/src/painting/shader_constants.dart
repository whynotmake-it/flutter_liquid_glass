import 'dart:math';

import 'package:liquid_glass_renderer/src/painting/liquid_glass_settings.dart';
import 'package:meta/meta.dart';

/// A layer draws this many glass shapes in one cluster, the shapes whose
/// edges reach the same 16-pixel tile of the layer, and any number of
/// clusters; a field whose shapes carry their own appearances is one draw, so
/// it holds this many in all. Shapes beyond it are not drawn and debug builds
/// print a warning. Split the glass across several layers to draw more.
const int geometryMaxShapesPerDraw = 16;

/// The edge distance of a geometry atlas's outside tile: past every
/// outward reach, and within a 16-bit float.
@internal
const double kFarOutside = -4096;

/// The edge distance of a geometry atlas's deep tile: past every inward
/// reach, and within a 16-bit float.
@internal
const double kDeepInward = 4096;

@internal
enum RawShapeType {
  // 0 is no shape, which the CPU never encodes.
  squircle(1),
  ellipse(2),
  roundedRectangle(3),

  /// A squircle whose two bottom corners have a different radius from its two
  /// top ones, drawn as two halves that meet on the split line (sdf.glsl's
  /// resolvePairHalf).
  squirclePair(4);

  const RawShapeType(this.shaderIndex);

  final double shaderIndex;

  String get _macro => 'SHAPE_${_screaming(name)}';
}

/// `LiquidGlassField.opticalCornerScale`.
@internal
const double opticalCornerRadiusScale = 1.5;

/// The edge of a tile of a geometry atlas, in buffer pixels.
@internal
const int atlasTileSize = 16;

/// What the ramp of a quad of a geometry atlas says (gpu/tile_fill.glsl,
/// gpu/tile_shapes_fragment.glsl), in its first float.
@internal
abstract final class AtlasRamp {
  /// A quad at or above this writes constants: a tile wholly outside or deep
  /// inside, or the atlas's table.
  static const double fill = 128;

  /// A strip at or above this, less it, names the first of a run of shape
  /// rows; below, its four floats list the rows it evaluates.
  static const double run = 64;

  /// Added to a listed row where it starts its blend group.
  static const double startsGroup = geometryMaxShapesPerDraw * 1.0;

  /// A listed row past the last.
  static const double none = geometryMaxShapesPerDraw * 2.0;
}

/// The floats of a shape's row of the geometry draw, as the GPU shaders read
/// them in three vec4s: its primitive, its inverse basis, its placement.
@internal
enum ShapeLane {
  type,
  width,
  height,

  /// The corner radius as the shape asks for it, a pair's top one: every
  /// reader clamps it to half the shorter side (`_ShapeBounds.of`,
  /// `sdf.glsl`), since a pair's corner can be as tall as its box.
  radius,
  inverseXX,
  inverseXY,
  inverseYX,
  inverseYY,
  centerX,
  centerY,
  distanceScale,

  /// The blend group's radius, negative (less one) where the shape starts
  /// its group.
  blendMarker,
}

/// The floats of a row of [lanes], in their order, from [values], which
/// names each lane once.
@internal
List<double> laneRow<L extends Enum>(List<L> lanes, Map<L, double> values) {
  assert(values.length == lanes.length, 'every lane of the row, once');
  return [for (final lane in lanes) values[lane]!];
}

/// The floats of a rounded superellipse's row (`sdfSquircle`), in three
/// vec4s: degrees and `1 - cos(span)` of its two octants, their circle
/// centers, their semi-axes and circle radii. A pair's bottom half holds its
/// bottom radius in [topAxis].
@internal
enum SquircleLane {
  topDegree,
  rightDegree,
  topSpan,
  rightSpan,
  topCenterX,
  topCenterY,
  rightCenterX,
  rightCenterY,
  topAxis,
  rightAxis,
  topRadius,
  rightRadius,
}

/// The glint's profile, which the final shader and FakeGlass draw and the
/// reach of glass's geometry follows.
///
/// iOS 27 recolors the glint, measured on the pinned solid-palette probes in
/// both appearances: it mixes the lit face toward a bright target whose
/// luminance sits above SDR white and whose chroma is the face's amplified.
@internal
abstract final class GlassGlint {
  /// The weight of the faint bleed inward of the glint line: a fifth of the
  /// line's.
  static const double bleed = 0.21;

  /// How many glint widths deep the bleed reaches.
  static const double bleedReach = 4;

  /// The line's strength at a glint of 1: the simulator captures give a
  /// mix weight of 0.14, and an iPhone renders the same glass 1.8 times
  /// stronger.
  static const double peak = 0.252;

  /// The luminance of the target the direct model's glint pulls toward.
  static const double directLuminance = 1.6;

  /// How strongly the direct model's glint amplifies the face's chroma.
  static const double directVibrancy = 2.85;
}

/// How far the final shader shifts the backdrop at a glass's edge, which the
/// reach of the copy it reads follows.
@internal
abstract final class GlassShift {
  /// How far clear glass may shift the backdrop at its edge, in half its
  /// short side; glass whose refraction fits its shape shifts it at most that
  /// far.
  static const double clearRatio = 1.3;

  /// The fraction of the dispersion the outer colors move apart by.
  static const double dispersionSpread = 0.5;
}

/// The widest frost, in pixels of the copy, eight taps serve
/// (`frostEight` in frost.glsl): past it they speckle, and sixteen take over.
@internal
const double frostEightMost = 2.8;

/// The offsets of `frostEight`'s taps (frost.glsl), in sigmas: centered and
/// scaled to a variance of one.
@internal
const List<(double, double)> frostEightTaps = [
  (0.48914, 0.12110),
  (-0.36984, 0.56920),
  (0.19721, -0.76661),
  (0.79118, 0.99744),
  (-1.18410, -0.10946),
  (1.44405, -0.72160),
  (-0.36967, 1.94006),
  (-0.99796, -2.03012),
];

/// The offsets of `frostSixteen`'s taps (frost.glsl), as [frostEightTaps].
@internal
const List<(double, double)> frostSixteenTaps = [
  (0.29397, 0.08599),
  (-0.29282, 0.38966),
  (0.09030, -0.50235),
  (0.47182, 0.65096),
  (-0.77215, -0.05743),
  (0.82330, -0.41313),
  (-0.22990, 1.08504),
  (-0.48656, -0.92531),
  (1.21020, 0.51383),
  (-1.21835, 0.60487),
  (0.66623, -1.25508),
  (0.52164, 1.62580),
  (-1.48966, -0.79971),
  (1.94532, -0.33318),
  (-1.22920, 1.88940),
  (-0.30413, -2.55934),
];

/// How many taps `frostTaps` (frost.glsl) reads along its spiral.
@internal
const int frostSpiralTaps = 12;

/// How many sigmas out the farthest tap of any frost in frost.glsl lies.
@internal
final double frostTapReach = [
  for (final (x, y) in [...frostEightTaps, ...frostSixteenTaps])
    sqrt(x * x + y * y),
  sqrt(-2 * log(1 - (frostSpiralTaps - 0.5) / frostSpiralTaps)),
].reduce(max);

/// How deep inside and how far outside its edge fake glass reads the
/// distance of a field body, in logical pixels: the range its 8-bit node
/// image holds, an eighth of a point a level. The bevel reaches about 22
/// points in and the contour a point or two out.
@internal
const double fakeFieldInside = 24;

/// See [fakeFieldInside].
@internal
const double fakeFieldOutside = 8;

/// The reads along a side of a cell that backdrop_haze_strip.frag has room
/// for.
@internal
const int hazeMostReads = 32;

/// Rec.709's luminance weights, the material's luminance basis: a
/// color-card fit on the host's Metal shows less blue and cyan transfer error
/// with them than with Rec.601's.
@internal
const lumaWeights = (0.2126, 0.7152, 0.0722);

/// The mirror that turns an edge's outward normal into the way glass parts
/// colors along, as the rows (x, y) and (y, z): the reflection across the
/// line 52.5 degrees from the right to the bottom, cos 105 and sin 105.
@internal
const partingMirror = (-0.258819, 0.965926, 0.258819);

/// The weights of the reads 1, 2 and 3 thirds of a parting's reach ahead
/// that red takes, and behind that blue takes: each weighted toward its far
/// end.
@internal
const partingSideWeights = (1 / 6, 1 / 3, 1 / 2);

/// The weights of the reads green takes, the point itself and 1 and 2
/// thirds of the parting's reach each way: each weighted toward the point.
@internal
const partingMiddleWeights = (1 / 3, 2 / 9, 1 / 9);

/// How much more of the backdrop's chroma a lifted face keeps than its cap
/// on luminance alone keeps ([chromaKeep]).
@internal
const double chromaKeepRise = 0.3;

/// The fraction of the backdrop's chroma a face keeps where its cap on
/// luminance keeps [keep]: iOS 27 keeps more of it the more the cap takes.
@internal
double chromaKeep(double keep) => keep * (1 + chromaKeepRise * (1 - keep));

/// A lane of the floats a pubspec shader reads, in an enum whose order is
/// the order Dart writes them in. The generated file of the enum names each
/// lane in the shader.
@internal
abstract interface class UniformLane implements Enum {
  /// How many floats the lane takes.
  int get width;
}

/// A lane the final shader may read through a global of its own.
@internal
abstract interface class GlobalLane implements UniformLane {
  /// Whether the shader copies the lane into a mediump global, which it can
  /// then change per fragment, rather than reading the uniform in place.
  bool get global;
}

/// Where [lane] starts among the floats of [lanes].
@internal
int laneOffset(List<UniformLane> lanes, UniformLane lane) {
  var offset = 0;
  for (var i = 0; i < lane.index; i++) {
    offset += lanes[i].width;
  }
  return offset;
}

/// The floats [lanes] take in whole vec4s.
@internal
int laneBlockFloats(List<UniformLane> lanes) =>
    (laneOffset(lanes, lanes.last) + lanes.last.width + 3) ~/ 4 * 4;

/// The floats of every lane of [lanes] from [values], which names each lane
/// once, in whole vec4s: what a shader reads of the block.
@internal
List<double> laneBlock<L extends UniformLane>(
  List<L> lanes,
  Map<L, List<double>> values,
) {
  assert(values.length == lanes.length, 'every lane of the block, once');
  final block = List<double>.filled(laneBlockFloats(lanes), 0);
  var offset = 0;
  for (final lane in lanes) {
    final floats = values[lane]!;
    assert(floats.length == lane.width, '$lane takes ${lane.width} floats');
    block.setRange(offset, offset += lane.width, floats);
  }
  return List.unmodifiable(block);
}

/// The floats fake_glass_surface.frag reads after its size.
@internal
enum FakeSurfaceLane implements UniformLane {
  shapeType,
  cornerRadius,
  tint(4),
  glintStrength,
  contourStrength,
  contourWidth,
  contourDirectionality,
  bevelStrength,

  /// The logical size of one device pixel.
  pixelSize,

  /// 1 draws only the border ring outside the shape's clip.
  exteriorOnly,

  /// The luminance of the neutral glint target.
  glintLuminance,

  /// The premultiplied emission of the face the backdrop filter produced.
  faceEmission(3),

  /// The face's fraction of the glint target, as the color model's
  /// glintFaceGain.
  glintFaceGain,
  glintVibrancy,

  /// 1 draws only the additive glint pass.
  glintOnly,

  /// A pair's bottom corner radius, or -1 for one radius.
  bottomRadius;

  const FakeSurfaceLane([this.width = 1]);

  @override
  final int width;
}

/// The floats bent_content.frag reads.
@internal
enum BentContentLane implements UniformLane {
  size(2),
  radius,

  /// 0 draws what the content takes of what lies under it, 1 the content.
  pass,

  /// Where the picture of the content starts in the shape's coordinates.
  pictureOrigin(2),

  /// One over the picture's size.
  pictureScale(2),

  /// The amount and height of the first bend, then of the second.
  bends(4),

  /// How far the colors part and how deep from the rim the parting fades.
  parting(2),

  /// Logical pixels per device pixel.
  pixel;

  const BentContentLane([this.width = 1]);

  @override
  final int width;
}

/// The way light travels across glass, in layer space: down the screen.
@internal
const lightDirection = (0.0, 1.0);

/// The floats of the final shader's uFace: the glass's look under its
/// settings, the same for every draw of it.
@internal
enum FaceLane implements GlobalLane {
  /// The tint, at 8 bits a channel.
  tint(4),

  /// How far the bevel shifts what it reads, in device pixels of a
  /// fragment.
  displacementScale,
  dispersion,

  glintStrength,

  /// One less the backdrop's shrink.
  backdropScale,
  saturation,

  /// The black border's strength.
  contourAlpha.inPlace(),

  /// How deep inside the edge the rim lighting and border reach, in device
  /// pixels (`rimReach`).
  rimReach,

  /// The glint line's width, in device pixels.
  glintWidth,

  /// The border's width, in device pixels.
  edgeWidth,
  contourDirectionality,
  vibrancy,
  bevelShadowStrength,

  /// How deep the bevel shadow fades inward, in device pixels.
  bevelShadowDepth,

  /// How far the bevel shadow lies along the light, in device pixels.
  bevelShadowOffset,

  /// Which slot of uColorModelParams the glass's color model fills.
  colorModelCode.inPlace(),

  /// How much of the glass is drawn, from 0 to 1.
  visibility.inPlace(),

  /// 1 lets the material's alpha fade the frost away with the rest of the
  /// material; 0 keeps unfrosted glass opaque and fades the material to the
  /// refracted backdrop instead, so visibility 0 shows the backdrop as it is.
  blurFade,
  transmissionGamma,

  /// How deep the final shader reads the geometry, in device pixels
  /// (`readDepth`).
  readDepth;

  const FaceLane([this.width = 1]) : global = width == 1;

  const FaceLane.inPlace() : width = 1, global = false;

  @override
  final int width;

  /// Every float but the [FaceLane.inPlace] ones: a variant with looks
  /// changes some per fragment, and the Mali register counts were reviewed
  /// with the rest read that way.
  @override
  final bool global;
}

/// The floats of the final shader's uAtlasPlace: where a drawn atlas lies in
/// the texture it shares with the other atlases of its frame.
@internal
enum AtlasPlaceLane implements UniformLane {
  /// The texel of the first entry of its table.
  tableOrigin,

  /// The texture's size, in texels.
  textureSize;

  @override
  int get width => 2;
}

/// The floats of the final shader's uGeometry: where the glass's geometry lies
/// and what its settings give the bevel, in device pixels of the matte.
@internal
enum GeometryLane implements GlobalLane {
  /// Where the geometry buffer's top-left lies.
  geometryOffset(2),

  /// The geometry buffer's size, one texel a pixel.
  geometrySize(2),

  /// The material's center.
  materialCenter(2),

  /// How far in the refraction reaches.
  refractionHeight,

  /// 1 where refraction fits the shape.
  refractionFits;

  const GeometryLane([this.width = 1]);

  @override
  final int width;

  /// Every float: read in place from the highp block, its arithmetic would
  /// turn highp.
  @override
  bool get global => width == 1;
}

/// The floats of the final shader's uMapping, from fragment coordinates to
/// the matte and the backdrop the glass reads, in device pixels.
@internal
enum MappingLane implements UniformLane {
  /// The basis from fragment coordinates into the matte: x.x, y.x, x.y,
  /// y.y.
  filterToMatteBasis(4),

  /// The rect of the matte (left, top, right, bottom) the filter took the
  /// backdrop for. Outside it the filter's input is transparent or clamped,
  /// so displaced reads are mirrored back in at its edge.
  backdropBounds(4),

  /// Where fragment zero lies in the matte.
  filterToMatteOffset(2),

  /// Where fragment coordinates start on the screen: zero for a filter,
  /// whose coordinates are its input's; the origin of the copy a paint
  /// samples.
  backdropOrigin(2);

  const MappingLane(this.width);

  @override
  final int width;
}

/// How many color models one layer's glass shades besides the direct
/// model, each in a slot of uColorModelParams; more fold onto the first.
@internal
const int colorModelSlotCount = 3;

/// The floats of one slot of the final shader's uColorModelParams: an
/// adaptive color model with its curves over the slider evaluated
/// (`GlassColorParameters`).
@internal
enum ColorModelLane implements UniformLane {
  /// The untinted face's emission, premultiplied.
  emission(3),
  transmittance,

  /// The bleed's black, white and saturation.
  bleed(3),

  /// The bleed's opacity, negative where it takes the bright parts.
  bleedOpacity,

  /// The glint target: luminance, face gain, vibrancy.
  glint(3),

  /// How much stronger the border is for the opacity the slider adds.
  contourBoost,

  /// The tones a tint's black and white channels take over the face's
  /// luminance: the black's base and amplitude, then the white's.
  tones(4),

  /// The untinted face's luminance lift and chroma gain.
  faceTransfer(2);

  const ColorModelLane([this.width = 1]);

  @override
  final int width;
}

/// The floats of one look of a buffer's shapes, which the atlas pass reads
/// as two vec4s, the tint and the response (gpu/looks.glsl).
@internal
enum LookLane implements UniformLane {
  /// The tint, straight.
  tint(4),
  saturation,
  transmissionGamma,
  vibrancy,

  /// The visibility, from 0 to 1, plus [lookModelStride] times the color
  /// model's code (0 direct, 1 to [colorModelSlotCount] a slot).
  visibilityAndModel;

  const LookLane([this.width = 1]);

  @override
  final int width;
}

/// What a step of the color model's code adds to a look's
/// [LookLane.visibilityAndModel]: more than any visibility.
@internal
const double lookModelStride = 2;

/// A look's [LookLane.visibilityAndModel] of [visibility] and color model
/// [code].
@internal
double lookVisibilityAndModel(double visibility, double code) =>
    visibility + code * lookModelStride;

/// The floats of the final shader's uEffects, the inputs of its optional
/// effects, in one declaration: a Metal stage has 31 buffer slots, and a
/// shader past them fails to compile on Metal alone (Vulkan and GLES accept
/// it).
@internal
enum EffectsLane implements UniformLane {
  /// The opaque color the glass is shaded over when it is drawn as a paint
  /// instead of a backdrop filter: every backdrop read returns it. Alpha 0
  /// reads the backdrop.
  solidBackdrop(4),

  /// The touch glow of one lit shape (glass_glow.glsl): its spot (center,
  /// falloff, gain), in matte device pixels.
  glowSpot(4),

  /// The lit shape's box: center and half size.
  glowBox(4),

  /// How far outside itself the glass reads the backdrop at its edge and how
  /// deep from the edge that reaches, both in matte device pixels (zero pulls
  /// nothing); half the center line the pull and the aberration point away
  /// from, positive along x and negative along y; half the short side of the
  /// material.
  backdropPull(4),

  /// How far apart the outermost of the seven reads that part the colors
  /// lie, and how deep from the edge the parting fades to nothing, both in
  /// matte device pixels; zero parts nothing.
  backdropAberration(2),

  /// The glow's wash over the whole lit shape.
  glowWash,

  /// Above zero when the copy the glass samples has fewer pixels than the
  /// screen, so no glass reads its own texel; at 1 or more, the copy fills
  /// the top-left 1 / reduced of its texture along each side (a layer whose
  /// copy is drawn in its corner).
  backdropReduced,

  /// The Gaussian sigma, in device pixels, the shader frosts an unblurred
  /// copy by; zero reads it as it is.
  backdropFrost;

  const EffectsLane([this.width = 1]);

  @override
  final int width;
}

/// The floats of the final shader's uBand, the scroll edge the band variant
/// draws beside the glass, in fragment coordinates.
@internal
enum BandLane implements UniformLane {
  /// The band's rect.
  rect(4),

  /// The frost, in device pixels, the band adds to what it reads.
  frost,

  /// The fragment row where the fade and the frost are whole.
  fadeWhole,

  /// The fragment row where the fade and the frost are gone.
  fadeGone,

  /// The color's brightness.
  brightness,

  /// The fade, premultiplied. It lies over what the glass reads too.
  fade(4),

  /// The fragment rows the hairline spans.
  hairlineRows(2),
  hairlineAlpha,

  /// How much of the band is shown.
  presence,
  saturation,
  hairlineColor(3);

  const BandLane([this.width = 1]);

  @override
  final int width;
}

String _screaming(String camel) =>
    camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]}').toUpperCase();

String _float(double value) {
  final text = value.toString();
  return text.contains('.') || text.contains('e') ? text : '$text.0';
}

String _taps(List<(double, double)> taps) => [
  for (final (x, y) in taps) 'TAP(${_float(x)}, ${_float(y)})',
].join(' ');

String _vec3((double, double, double) value) =>
    'vec3(${_float(value.$1)}, ${_float(value.$2)}, ${_float(value.$3)})';

String _laneValue(String Function(int) vec4, int offset, int width) {
  String float(int at) => '${vec4(at ~/ 4)}.${'xyzw'[at % 4]}';
  if (width == 1) return float(offset);
  final last = offset + width - 1;
  if (width == 4 && offset % 4 == 0) return vec4(offset ~/ 4);
  if (offset ~/ 4 == last ~/ 4) {
    return '${vec4(offset ~/ 4)}.'
        '${'xyzw'.substring(offset % 4, last % 4 + 1)}';
  }
  return 'vec$width('
      '${[for (var i = offset; i <= last; i++) float(i)].join(', ')})';
}

String _laneName(String prefix, UniformLane lane) =>
    '$prefix${lane.name[0].toUpperCase()}${lane.name.substring(1)}';

String _slotLanes(
  String block,
  List<UniformLane> lanes, {
  required int slots,
  required String prefix,
}) {
  final vec4s = laneBlockFloats(lanes) ~/ 4;
  String vec4(int i) => '$block[(slot) * $vec4s${i == 0 ? '' : ' + $i'}]';
  String define(UniformLane lane) =>
      '#define ${_laneName(prefix, lane)}(slot) '
      '${_laneValue(vec4, laneOffset(lanes, lane), lane.width)}';
  return [
    'uniform vec4 $block[${slots * vec4s}];',
    for (final lane in lanes) define(lane),
  ].join('\n');
}

String _lanes(
  String block,
  List<UniformLane> lanes, {
  bool highp = false,
  String prefix = 'u',
}) {
  final vec4s = laneBlockFloats(lanes) ~/ 4;
  String vec4(int i) => vec4s == 1 ? block : '$block[$i]';
  final count = vec4s == 1 ? '' : '[$vec4s]';
  return [
    'uniform ${highp ? 'highp ' : ''}vec4 $block$count;',
    for (final lane in lanes)
      () {
        final value = _laneValue(vec4, laneOffset(lanes, lane), lane.width);
        final name = _laneName(prefix, lane);
        if (lane case GlobalLane(global: true)) {
          assert(lane.width == 1, 'a global lane is one float');
          return 'float $name = $value;';
        }
        return '#define $name $value';
      }(),
  ].join('\n');
}

String _rows(String prefix, List<Enum> lanes, List<String> vec4s) => [
  '#define ${prefix}_ROW_VEC4S ${lanes.length ~/ 4}',
  for (var i = 0; i < vec4s.length; i++) '#define ${prefix}_${vec4s[i]} $i',
].join('\n');

String _guarded(String name, String body) {
  final guard = _screaming(name.replaceAll('.', '_'));
  return '''
// Generated from lib/src/painting/shader_constants.dart by
// test/shader_constants_test.dart: do not edit.

#ifndef $guard
#define $guard

$body

#endif
''';
}

// The weights a color model's code gives the direct model and each slot:
// 1 for its own, 0 for the others.
final String _colorModelWeights = () {
  assert(colorModelSlotCount == 3, 'The weights are a vec4.');
  final codes = [
    for (var code = 0; code <= colorModelSlotCount; code++)
      _float(code.toDouble()),
  ];
  return '''
vec4 colorModelWeightsOf(float code) {
    return vec4(equal(vec4(code), vec4(${codes.join(', ')})));
}''';
}();

/// The GLSL files written from this table, by name in lib/assets/shaders.
@internal
final Map<String, String> generatedShaderFiles = {
  'shader_constants.glsl': _guarded(
    'shader_constants.glsl',
    '''
#define GEOMETRY_MAX_SHAPES $geometryMaxShapesPerDraw
#define SHAPE_INDEX_MASK ${geometryMaxShapesPerDraw - 1}
const float kFarOutside = ${_float(kFarOutside)};
${[for (final type in RawShapeType.values) '#define ${type._macro} ${_float(type.shaderIndex)}'].join('\n')}

#define ATLAS_TILE_SIZE ${_float(atlasTileSize.toDouble())}
#define RAMP_FILL ${_float(AtlasRamp.fill)}
#define RAMP_RUN ${_float(AtlasRamp.run)}
#define MEMBER_STARTS_GROUP ${_float(AtlasRamp.startsGroup)}
#define MEMBER_NONE ${_float(AtlasRamp.none)}

${_rows('SHAPE', ShapeLane.values, ['PRIMITIVE', 'INVERSE_BASIS', 'PLACEMENT'])}
${_rows('SQUIRCLE', SquircleLane.values, ['DEGREES_AND_SPANS', 'CIRCLE_CENTERS', 'AXES_AND_RADII'])}
const float kOpticalCornerRadiusScale = ${_float(opticalCornerRadiusScale)};

const float kGlintBleed = ${_float(GlassGlint.bleed)};
const float kGlintBleedReach = ${_float(GlassGlint.bleedReach)};
const float kGlintPeak = ${_float(GlassGlint.peak)};
const float kGlintLuminance = ${_float(GlassGlint.directLuminance)};
const float kGlintVibrancy = ${_float(GlassGlint.directVibrancy)};
const float kClearShiftRatio = ${_float(GlassShift.clearRatio)};
const float kDispersionSpread = ${_float(GlassShift.dispersionSpread)};
const float kFrostEightMost = ${_float(frostEightMost)};
#define FROST_SPIRAL_TAPS $frostSpiralTaps
#define FROST_EIGHT_TAPS(TAP) ${_taps(frostEightTaps)}
#define FROST_SIXTEEN_TAPS(TAP) ${_taps(frostSixteenTaps)}
const float kFakeFieldInside = ${_float(fakeFieldInside)};
const float kFakeFieldOutside = ${_float(fakeFieldOutside)};
#define HAZE_MOST_READS $hazeMostReads
const vec3 LUMA_WEIGHTS = ${_vec3(lumaWeights)};
const vec3 kPartingMirror = ${_vec3(partingMirror)};
const vec3 kPartingSide = ${_vec3(partingSideWeights)};
const vec3 kPartingMiddle = ${_vec3(partingMiddleWeights)};
const float kChromaKeepRise = ${_float(chromaKeepRise)};
#define COLOR_MODEL_SLOTS $colorModelSlotCount
$_colorModelWeights
const float kLookModelStride = ${_float(lookModelStride)};
const vec2 kLightDirection = vec2(${_float(lightDirection.$1)}, ${_float(lightDirection.$2)});
const float kGlintWidth = ${_float(GlassRim.glintWidth)};
const float kGlintWrap = ${_float(GlassRim.glintWrap)};
const float kGlintOppositeStrength = ${_float(GlassRim.glintOppositeStrength)};
const float kBevelShadowDepth = ${_float(GlassRim.bevelShadowDepth)};
const float kBevelShadowOffset = ${_float(GlassRim.bevelShadowOffset)};
const float kBevelShadowDirectionality = ${_float(GlassRim.bevelShadowDirectionality)};''',
  ),
  'fake_glass_lanes.glsl': _guarded(
    'fake_glass_lanes.glsl',
    _lanes('uFake', FakeSurfaceLane.values),
  ),
  'bent_content_lanes.glsl': _guarded(
    'bent_content_lanes.glsl',
    _lanes('uBent', BentContentLane.values),
  ),
  'final_lanes.glsl': _guarded('final_lanes.glsl', '''
${_lanes('uGeometry', GeometryLane.values, highp: true)}

${_lanes('uFace', FaceLane.values)}

${_lanes('uMapping', MappingLane.values, highp: true)}

${_slotLanes('uColorModelParams', ColorModelLane.values, slots: colorModelSlotCount, prefix: 'model')}

${_lanes('uEffects', EffectsLane.values, highp: true)}

#if FROST_BAND
${_lanes('uBand', BandLane.values, highp: true, prefix: 'uBand')}
#endif

#if !COMPUTED_SHAPE
${_lanes('uAtlasPlace', AtlasPlaceLane.values, highp: true, prefix: 'uAtlas')}
#endif'''),
};
