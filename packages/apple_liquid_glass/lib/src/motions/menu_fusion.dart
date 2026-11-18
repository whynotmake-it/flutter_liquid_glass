import 'dart:math' as math;
import 'dart:ui';

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/motions/menu_fusion_worker.dart';
import 'package:apple_liquid_glass/src/motions/menu_outline_math.dart';
import 'package:apple_liquid_glass/src/motions/outline_boxes.dart';
import 'package:flutter/foundation.dart';

part 'package:apple_liquid_glass/src/motions/menu_fusion_blur.dart';

/// The silhouette of a menu morph: its two shapes fused the way UIKit's
/// morph container fuses them.
///
/// The container is one SDF layer whose elements, the menu shape and the
/// button shape, are united by a plain minimum (its smoothness is 0) and
/// whose distance field is blurred by a Gaussian of standard deviation
/// `MenuMotion.fusionRadius`. The blur pulls the facing edges into
/// points and joins the shapes by a neck while they are within a few
/// radii of each other; it also rounds and narrows each shape a little,
/// by about `radius^2 / (2 r)` on an edge of curvature radius `r`. Below
/// [minimumRadius] the blur moves no edge by more than a few hundredths
/// of a point and the silhouette is the plain union of the two shapes.
///
/// The fused outline is traced on a grid whose step grows with the
/// radius (a blurred field varies no faster than its blur), and the blur
/// is evaluated only near the edge: a blur of standard deviation `s`
/// moves a distance field by at most `1.26 s`, so farther from the edge
/// the sign, all the trace needs, is the unblurred one; inside the body
/// the blur reaches [shadedDepth] deeper, as far as a renderer shades
/// it. Until a renderer reads the field it fuses the edge alone, which
/// skips that deeper blur. The last outline is reused while its inputs do
/// not change.
///
/// In profile and release builds that have isolates, a motion fuses its
/// next frame's silhouette ahead on a background isolate ([prefetch],
/// `FusionWorker`) while the current frame renders, and [outline]
/// serves that fusion when the frame's inputs are within
/// [prefetchTolerance] of the predicted ones: the exact silhouette of the
/// motion at the predicted time, a fraction of a millisecond from the
/// frame's. Otherwise the frame fuses its own.
@internal
class MenuFusion {
  /// The radius below which the silhouette is the plain union.
  static const double minimumRadius = 1;

  /// How deep inside the body the field stays blurred at least, in
  /// logical pixels (the trace itself needs only the band near the edge).
  ///
  /// A renderer bends light by the field's distance and normal within its
  /// bevel (20 points deep on the iOS 27 presets); farther in, the face is
  /// flat and only the sign matters. Blurring that deep keeps the field
  /// continuous wherever a renderer reads more than its sign.
  static const double shadedDepth = 24;

  /// How far, in logical pixels, each input of a fusion computed ahead
  /// ([prefetch]) may be from the inputs of the frame that uses it.
  ///
  /// The outline moves with its shapes and radius at most one to one, so
  /// an outline fused ahead is within this of the frame's own, 0.06 px on
  /// a 3x screen.
  static const double prefetchTolerance = 0.02;

  /// Whether motions fuse their next frame's silhouette ahead, on a
  /// background isolate: in profile and release builds where
  /// `FusionWorker.supported` (isolates and six or more cores);
  /// [debugPrefetch] overrides it.
  static bool get prefetches =>
      debugPrefetch ??
      (FusionWorker.supported && (kReleaseMode || kProfileMode));

  /// How many coming frames a motion fuses ahead ([prefetch]) each frame,
  /// so a fusion that comes back late still serves a later one.
  static const int prefetchFrames = 3;

  /// Overrides [prefetches]; null keeps the build's default.
  @visibleForTesting
  static bool? debugPrefetch;

  RRect? _menu;
  RRect? _source;
  double _radius = 0;
  GlassOutline? _outline;
  bool _prefetched = false;
  final Float64List _inputs = Float64List(inputCount);

  /// Whether a renderer has read the field of one of this fusion's
  /// outlines: from then on the fusion computes the field with the edge,
  /// here and ahead. Before, it fuses the edge alone, which is all a
  /// renderer that only fills the body reads.
  bool shades = false;

  /// The fused outline of [menu] and [source] blurred by [radius], or
  /// null when [radius] is under [minimumRadius] and the silhouette is
  /// their plain union.
  ///
  /// The outline always has a field; one fused without it ([shades]
  /// false) computes it when a renderer first reads it.
  ///
  /// When the fusion was computed ahead ([prefetch]) for inputs within
  /// [prefetchTolerance] of these, that outline is the one returned.
  GlassOutline? outline(RRect menu, RRect source, double radius) {
    if (radius < minimumRadius) return null;
    if (menu == _menu && source == _source && radius == _radius) {
      return _outline;
    }
    _menu = menu;
    _source = source;
    _radius = radius;
    final frame = encode(menu, source, radius, _inputs, withField: shades);
    final ahead = prefetches
        ? FusionWorker.take(frame, prefetchTolerance)
        : null;
    if (ahead != null) {
      debugServedAhead++;
    } else {
      debugFusedHere++;
    }
    return _outline = outlineFromParts(
      ahead ?? menuSilhouetteParts(menu, source, radius, withField: shades),
      shaded: () {
        shades = true;
        return menuSilhouetteParts(menu, source, radius);
      },
    );
  }

  /// The outlines [outline] has served from a fusion computed ahead, over
  /// the isolate's life.
  @visibleForTesting
  static int debugServedAhead = 0;

  /// The outlines [outline] has fused where they were needed, over the
  /// isolate's life.
  @visibleForTesting
  static int debugFusedHere = 0;

  /// Starts fusing [menu] and [source] blurred by [radius] on a
  /// background isolate, for a later [outline] call to pick up.
  ///
  /// Until the fusion [shades], the worker fuses the edge alone.
  void prefetch(RRect menu, RRect source, double radius) {
    if (!prefetches || radius < minimumRadius) return;
    _prefetched = true;
    FusionWorker.request(
      encode(
        menu,
        source,
        radius,
        Float64List(inputCount),
        withField: shades,
      ),
      owner: this,
    );
  }

  /// Drops the fusions this fusion computed ahead that no frame has taken
  /// yet, and its requests still waiting, once its motion stops fusing: no
  /// worker then computes a silhouette nobody reads. Another menu's
  /// fusions stay. Does nothing when this fusion requested none since the
  /// last call.
  void settle() {
    if (!_prefetched) return;
    _prefetched = false;
    FusionWorker.reset(owner: this);
  }

  /// The grid step of the fusion at [radius], in logical pixels: a third
  /// of the radius, between 2 and 6.
  static double stepOf(double radius) => (radius / 3).clamp(2.0, 6.0);

  /// The nodes on each side of the center tap of the blur's kernel at
  /// [radius]: as many grid steps as reach three radii.
  ///
  /// Where the step is a third of the radius that is nine; the division
  /// lands a rounding error either side of nine, which the ceiling must
  /// not turn into ten.
  static int reachOf(double radius) =>
      (3 * radius / stepOf(radius) - 1e-9).ceil();

  /// Whether fusions at radii [a] and [b] sample the same grid with the
  /// same kernel: one grid stride and one kernel reach.
  static bool sameGrid(double a, double b) =>
      strideOf(a) == strideOf(b) && reachOf(a) == reachOf(b);

  /// The grid stride of a fusion at [radius]: every second node below a
  /// 4 pt step.
  static int strideOf(double radius) => stepOf(radius) < 4 ? 2 : 1;

  /// The length of [encode]'s inputs.
  static const int inputCount = 12;

  /// The inputs of a fusion as the worker receives them, written into
  /// [out] ([inputCount] long): each shape's left, top, right, bottom and
  /// corner radius, the fusion radius, then 1 when the fusion carries its
  /// field and 0 for the edge alone.
  static Float64List encode(
    RRect menu,
    RRect source,
    double radius,
    Float64List out, {
    bool withField = true,
  }) {
    out[0] = menu.left;
    out[1] = menu.top;
    out[2] = menu.right;
    out[3] = menu.bottom;
    out[4] = menu.tlRadiusX;
    out[5] = source.left;
    out[6] = source.top;
    out[7] = source.right;
    out[8] = source.bottom;
    out[9] = source.tlRadiusX;
    out[10] = radius;
    out[11] = withField ? 1 : 0;
    return out;
  }
}

/// The parts, computable on any isolate, of the outline of the union of
/// [menu] and [source] whose signed distance field is blurred by a
/// Gaussian of standard deviation [radius]; [outlineFromParts] makes them
/// its zero contour as one even-odd path, with the blurred field itself
/// for a renderer that shades the body.
///
/// The half thickness each node of the field belongs to, and the turn of
/// its normal toward the optical corners of the shapes, blend from the
/// button's to the menu's over the blur radius, by which of the two shapes
/// is nearer.
///
/// The field grid (every second trace node below a 4 pt step) is sampled
/// everywhere; the trace grid only in blocks whose corners leave the edge
/// within reach. A node whose blur window sees one straight side of one
/// shape takes its unblurred distance: the kernel is symmetric, so it
/// leaves a linear field unchanged.
///
/// With [withField] false the parts are the edge alone, without samples,
/// for a body that is only filled: the same contour, crossing for
/// crossing, without the field. The blur then reaches inside the body
/// only as far as the trace and its choice of blocks need, not
/// [MenuFusion.shadedDepth], and no half thickness, optical turn or field
/// sample is computed.
@internal
@pragma('vm:unsafe:no-bounds-checks')
OutlineParts menuSilhouetteParts(
  RRect menu,
  RRect source,
  double radius, {
  bool withField = true,
}) {
  final step = MenuFusion.stepOf(radius);
  final stride = MenuFusion.strideOf(radius);
  const b = 2;
  final area = menu.outerRect
      .expandToInclude(source.outerRect)
      .inflate(2 * step);
  final cols = ((area.width / step).ceil() ~/ b) * b + b + 1;
  final rows = ((area.height / step).ceil() ~/ b) * b + b + 1;
  final reach = MenuFusion.reachOf(radius);
  final kernel = Float64List(2 * reach + 1);
  var sum = 0.0;
  for (var k = -reach; k <= reach; k++) {
    final x = k * step / radius;
    final w = math.exp(-0.5 * x * x);
    kernel[k + reach] = w;
    sum += w;
  }
  for (var k = 0; k < kernel.length; k++) {
    kernel[k] /= sum;
  }
  final boxes = OutlineBoxes([menu, source]);
  final f = _BlurredUnion(boxes, area, step, cols, rows, kernel);
  final shift = 1.26 * radius;
  final band = shift + 1.5 * step;
  final fieldCols = (cols - 1) ~/ stride + 1;
  final fieldRows = (rows - 1) ~/ stride + 1;
  final trace = _Scratch.trace(cols * rows);
  final clearance = _Scratch.field(2, fieldCols * fieldRows);
  final optics = withField
      ? _MenuOptics(
          boxes,
          area,
          step,
          radius,
          stride,
          fieldCols,
          fieldRows,
        )
      : null;
  final reachOfEdge = step * math.sqrt2 + b * step * math.sqrt1_2;
  // The field is blurred as deep as a renderer that shades the body reads
  // it; for the edge alone, only as deep as decides which blocks can hold
  // the edge (no deeper than the full fusion), so both trace the same
  // blocks.
  final double depth = math.max(
    band,
    optics == null
        ? math.min(MenuFusion.shadedDepth, shift + reachOfEdge)
        : MenuFusion.shadedDepth,
  );
  for (var fj = 0; fj < fieldRows; fj++) {
    final j = fj * stride;
    optics?.row(fj, area.top + j * step);
    for (var fi = 0; fi < fieldCols; fi++) {
      final i = fi * stride;
      final at = fj * fieldCols + fi;
      final dg = f.menuDistance(i, j);
      final ds = f.sourceDistance(i, j);
      final double raw = math.min(dg, ds);
      f.remember(i, j, raw);
      final exact = raw <= band && raw >= -depth;
      final value = exact ? f.smoothed(i, j, dg, ds) : raw;
      // The blur moves the field by at most `shift`, so where it is not
      // evaluated the unblurred distance less `shift` bounds the clearance
      // from below: no block that holds the edge is left out, and below
      // `depth` the bound and the blurred clearance both exceed
      // `reachOfEdge`, so the edge alone and the full fusion flag the same
      // blocks.
      clearance[at] = exact ? value.abs() : raw.abs() - shift;
      trace[j * cols + i] = value;
      optics?.node(fi, at, value, dg, ds);
    }
  }
  final blockCols = (cols - 1) ~/ b;
  final blockRows = (rows - 1) ~/ b;
  final near = Uint8List(blockCols * blockRows);
  final span = b ~/ stride;
  for (var bj = 0; bj < blockRows; bj++) {
    for (var bi = 0; bi < blockCols; bi++) {
      final corner = bj * span * fieldCols + bi * span;
      final double nearest = math.min(
        math.min(clearance[corner], clearance[corner + span]),
        math.min(
          clearance[corner + span * fieldCols],
          clearance[corner + span * fieldCols + span],
        ),
      );
      if (nearest <= reachOfEdge) {
        near[bj * blockCols + bi] = 1;
        if (stride == 1) continue;
        final topDone = bj > 0 && near[(bj - 1) * blockCols + bi] != 0;
        final leftDone = bi > 0 && near[bj * blockCols + bi - 1] != 0;
        for (var j = bj * b; j <= bj * b + b; j++) {
          if (topDone && j == bj * b) continue;
          for (var i = bi * b; i <= bi * b + b; i++) {
            if (((i | j) & 1) == 0 || (leftDone && i == bi * b)) continue;
            final dg = f.menuDistance(i, j);
            final ds = f.sourceDistance(i, j);
            final double raw = math.min(dg, ds);
            f.remember(i, j, raw);
            trace[j * cols + i] = raw.abs() > band
                ? raw
                : f.smoothed(i, j, dg, ds);
          }
        }
      }
    }
  }
  if (optics == null) {
    return outlineEdgeParts(
      trace: trace,
      cols: cols,
      rows: rows,
      near: near,
      blockCols: blockCols,
      block: b,
      left: area.left,
      top: area.top,
      step: step,
    );
  }
  return outlinePartsFromFields(
    trace: trace,
    cols: cols,
    rows: rows,
    near: near,
    blockCols: blockCols,
    block: b,
    distance: optics.distance,
    halfMinor: optics.halfMinor,
    turn: optics.turn,
    stride: stride,
    left: area.left,
    top: area.top,
    step: step,
  );
}

/// What a renderer shades a menu fusion from, per node of its field grid:
/// the blurred distance, the half thickness of the shape the node belongs
/// to and the turn of its normal toward the shapes' optical corners.
class _MenuOptics {
  _MenuOptics(
    OutlineBoxes boxes,
    Rect area,
    double step,
    double radius,
    int stride,
    int fieldCols,
    int fieldRows,
  ) : _boxes = boxes,
      _halfMenu = boxes.halfMinor(0),
      _halfSource = boxes.halfMinor(1),
      _blend = math.max(radius, step),
      distance = _Scratch.field(0, fieldCols * fieldRows),
      halfMinor = _Scratch.field(1, fieldCols * fieldRows),
      turn = _Scratch.field(3, 2 * fieldCols * fieldRows),
      _cornerColumns = _Scratch.columns(fieldCols),
      _menuOptics = _OpticalCorners(boxes, 0, fieldCols, fieldRows),
      _sourceOptics = _OpticalCorners(boxes, 1, fieldCols, fieldRows) {
    _menuTurns = _boxes.turns(0);
    _sourceTurns = _boxes.turns(1);
    _sourceTurn[0] = 1;
    for (var fi = 0; fi < fieldCols; fi++) {
      final x = area.left + fi * stride * step;
      _cornerColumns[fi] =
          (_menuTurns && _boxes.inOpticalCornerColumns(0, x) ? 1 : 0) |
          (_sourceTurns && _boxes.inOpticalCornerColumns(1, x) ? 2 : 0);
      _menuOptics.column(fi, x);
      _sourceOptics.column(fi, x);
    }
  }

  final OutlineBoxes _boxes;
  final double _halfMenu;
  final double _halfSource;
  final double _blend;

  /// The blurred distance at each field node.
  final Float64List distance;

  /// The half thickness of the shape each field node belongs to.
  final Float64List halfMinor;

  /// The optical turn of the normal at each field node, (cos, sin).
  final Float64List turn;

  final Uint8List _cornerColumns;
  final _OpticalCorners _menuOptics;
  final _OpticalCorners _sourceOptics;
  final Float64List _sourceTurn = Float64List(2);
  bool _menuTurns = false;
  bool _sourceTurns = false;
  int _fj = 0;
  int _cornerRow = 0;

  /// Starts field row [fj] at [y].
  @pragma('vm:prefer-inline')
  void row(int fj, double y) {
    _fj = fj;
    _cornerRow =
        (_menuTurns && _boxes.inOpticalCornerRows(0, y) ? 1 : 0) |
        (_sourceTurns && _boxes.inOpticalCornerRows(1, y) ? 2 : 0);
    _menuOptics.row(fj, y);
    _sourceOptics.row(fj, y);
  }

  /// Records field node [at], column [fi] of the current row, whose
  /// blurred distance is [value], the menu's distance [dg] and the
  /// button's [ds].
  @pragma('vm:prefer-inline')
  @pragma('vm:unsafe:no-bounds-checks')
  void node(int fi, int at, double value, double dg, double ds) {
    final turn = this.turn;
    final sourceTurn = _sourceTurn;
    final corner = _cornerRow & _cornerColumns[fi];
    distance[at] = value;
    final share = 0.5 + (ds - dg) / (2 * _blend);
    final towardMenu = share < 0
        ? 0
        : share > 1
        ? 1
        : share;
    halfMinor[at] = _halfSource + (_halfMenu - _halfSource) * towardMenu;
    final menuCorner = corner & 1 != 0;
    final sourceCorner = corner & 2 != 0;
    if (menuCorner) {
      _menuOptics.turn(fi, _fj, turn, at * 2);
    } else {
      turn[at * 2] = 1;
      turn[at * 2 + 1] = 0;
    }
    if (sourceCorner) {
      _sourceOptics.turn(fi, _fj, sourceTurn, 0);
    } else {
      sourceTurn[0] = 1;
      sourceTurn[1] = 0;
    }
    if ((menuCorner || sourceCorner) && towardMenu < 1) {
      turn[at * 2] =
          sourceTurn[0] + (turn[at * 2] - sourceTurn[0]) * towardMenu;
      turn[at * 2 + 1] =
          sourceTurn[1] + (turn[at * 2 + 1] - sourceTurn[1]) * towardMenu;
      normalizeTurn(turn, at * 2);
    }
  }
}

/// The optical turn of one rounded box (`OutlineBoxes.opticalTurn`)
/// over the field grid, its per-axis terms computed once per column and
/// once per row.
class _OpticalCorners {
  _OpticalCorners(OutlineBoxes boxes, int i, int cols, int rows)
    : _centerX = boxes.centerX(i),
      _centerY = boxes.centerY(i),
      _halfX = boxes.halfX(i),
      _halfY = boxes.halfY(i),
      _exact = boxes.radius(i),
      _optical = boxes.opticalRadius(i),
      _columns = _Scratch.optics(i * 2, cols * 3),
      _rows = _Scratch.optics(i * 2 + 1, rows * 3);

  final double _centerX;
  final double _centerY;
  final double _halfX;
  final double _halfY;
  final double _exact;
  final double _optical;
  final Float64List _columns;
  final Float64List _rows;

  /// Records field column [fi] at [x].
  @pragma('vm:prefer-inline')
  void column(int fi, double x) {
    final p = x - _centerX;
    final a = p.abs() - _halfX;
    _columns[fi * 3] = p;
    _columns[fi * 3 + 1] = a + _optical;
    _columns[fi * 3 + 2] = a + _exact;
  }

  /// Records field row [fj] at [y].
  @pragma('vm:prefer-inline')
  void row(int fj, double y) {
    final p = y - _centerY;
    final a = p.abs() - _halfY;
    _rows[fj * 3] = p;
    _rows[fj * 3 + 1] = a + _optical;
    _rows[fj * 3 + 2] = a + _exact;
  }

  /// The rotation from the exact normal at field node ([fi], [fj]) to
  /// the optical one, as (cos, sin) written into [out] at [at].
  @pragma('vm:unsafe:no-bounds-checks')
  void turn(int fi, int fj, Float64List out, int at) => writeOpticalTurn(
    exact: _exact,
    optical: _optical,
    ox: _columns[fi * 3 + 1],
    oy: _rows[fj * 3 + 1],
    ex: _columns[fi * 3 + 2],
    ey: _rows[fj * 3 + 2],
    mirrored: (_columns[fi * 3] < 0) != (_rows[fj * 3] < 0),
    out: out,
    at: at,
  );
}
