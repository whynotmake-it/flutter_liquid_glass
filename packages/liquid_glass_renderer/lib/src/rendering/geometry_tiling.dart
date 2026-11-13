import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/rendering/shape_set.dart';

part 'package:liquid_glass_renderer/src/rendering/geometry_tiling_atlas.dart';
part 'package:liquid_glass_renderer/src/rendering/geometry_tiling_bounds.dart';
part 'package:liquid_glass_renderer/src/rendering/geometry_tiling_groups.dart';
part 'package:liquid_glass_renderer/src/rendering/geometry_tiling_values.dart';

/// Which tiles of one geometry buffer need exact texels and which read a
/// constant, and which shapes each ring tile evaluates.
///
/// The buffer has one texel per buffer pixel, cut into [size] x [size]
/// tiles. Only ring tiles are drawn; outside and deep tiles point at shared
/// constant tiles. The classification uses conservative bounds of the
/// shapes, never their exact outlines: a tile is constant only when every
/// pixel in it provably is.
@internal
@immutable
final class Tiling {
  Tiling._({
    required this.reach,
    required this.shapes,
    required this.field,
    required this.columns,
    required this.rows,
    required this.kinds,
    required this.runs,
    required this.deeps,
    required this.shapeSets,
    required this.droppedShapes,
    required this.looks,
    required this.deepLooks,
    this.slack = 0,
    this._tiled,
  });

  /// Classifies a buffer of [width] x [height] pixels holding [shapes],
  /// encoded in buffer pixels, which wear [looks] where they differ. With
  /// [slack] every bound allows each shape that many pixels of movement,
  /// so the tiling still holds once they have moved ([held]).
  ///
  /// A ring that outgrows one atlas is tiled again with half the inward
  /// reach until it fits. Past the reach a read takes the deep value, so a
  /// layer with that much edge (several screens of glass outline) loses the
  /// inner part of its refraction falloff.
  factory Tiling.shapes(
    ShapeSet shapes, {
    required int width,
    required int height,
    required GlassReach reach,
    ShapeLooks? looks,
    double slack = 0,
  }) {
    final columns = _tilesOver(width);
    final rows = _tilesOver(height);
    // A read blends texels up to a texel away; past two the field's
    // curvature is gentle enough for a linear read.
    List<_ShapeBounds> over(int cell) => [
      for (var i = 0; i < shapes.count; i++)
        _ShapeBounds.of(
          shapes,
          i,
          cell: cell,
          foldMargin: 2.0 * reach.coarseTexel + slack,
          apron: reach.coarseTexel / 2,
          slack: slack,
        )..prepare((width + cell - 1) ~/ cell, (height + cell - 1) ~/ cell),
    ];
    final bounds = over(size);
    final groups = _ShapeGroups.of(shapes);
    final classifier = _Classifier(
      columns: columns,
      rows: rows,
      reach: reach,
      listable: shapes.count <= geometryMaxShapesPerDraw,
    );
    final blocks = over(size * _Classifier.blockTiles);
    for (var group = 0; group < groups.members.length; group++) {
      classifier.add(
        group,
        groups.members[group],
        tiles: bounds,
        blocks: blocks,
        smoothing: groups.smoothingOf(group),
        sharp: groups.blendOf(group) < 8.0 * reach.coarseTexel,
      );
    }
    final (kinds, fine, lists, wholes) = classifier.finish();
    final deepLooks = looks == null
        ? null
        : _lookKinds(bounds, groups, looks, columns, rows, kinds, fine);
    // A deep tile of two looks turns ring, so with looks a deep block is
    // read tile by tile.
    if (looks != null) {
      for (var block = 0; block < wholes.length; block++) {
        if (wholes[block] == _deepBlock) wholes[block] = _byTile;
      }
    }
    final (sets, tileSets, dropped) = _shapeSets(
      bounds,
      groups,
      columns,
      rows,
      reach,
      kinds,
      looks: looks != null,
    );
    final tiling = Tiling._(
      reach: reach,
      shapes: shapes,
      field: null,
      columns: columns,
      rows: rows,
      kinds: kinds,
      runs: _runs(
        columns,
        rows,
        kinds,
        tileSets,
        fine,
        reach.coarseTexel,
        lists,
        wholes,
      ),
      deeps: _deeps(columns, rows, kinds, deepLooks, wholes),
      shapeSets: List.unmodifiable(sets),
      droppedShapes: dropped,
      looks: looks,
      deepLooks: deepLooks,
      slack: slack,
    );
    if (tiling._fits || reach.inward <= 1) return tiling;
    return Tiling.shapes(
      shapes,
      width: width,
      height: height,
      reach: reach._shallower,
      looks: looks,
      slack: slack,
    );
  }

  /// Classifies a buffer of [width] x [height] pixels holding the body of
  /// [field], fitted to one atlas as [Tiling.shapes] is. Its ring tiles
  /// take coarse texels where the field's nodes lie at least a texel apart
  /// and their gradients agree. Where [looks]
  /// differ, the body takes its look from the [shapes] it grew from, at
  /// most [geometryMaxShapesPerDraw] of them.
  factory Tiling.field(
    BufferField field, {
    required int width,
    required int height,
    required GlassReach reach,
    ShapeSet shapes = ShapeSet.empty,
    ShapeLooks? looks,
  }) {
    assert(
      looks == null || shapes.count <= geometryMaxShapesPerDraw,
      'A field takes its looks from one draw of shapes.',
    );
    final columns = _tilesOver(width);
    final rows = _tilesOver(height);
    final (kinds, fine) = _fieldKinds(field, columns, rows, reach);
    final deepLooks = looks == null
        ? null
        : _lookKinds(
            [for (var i = 0; i < shapes.count; i++) _ShapeBounds.of(shapes, i)],
            _ShapeGroups.of(shapes),
            looks,
            columns,
            rows,
            kinds,
            fine,
          );
    final tiling = Tiling._(
      reach: reach,
      shapes: looks == null ? ShapeSet.empty : shapes,
      field: field,
      columns: columns,
      rows: rows,
      kinds: kinds,
      runs: _runs(
        columns,
        rows,
        kinds,
        Int32List(columns * rows),
        fine,
        reach.coarseTexel,
        Uint32List(columns * rows),
        null,
      ),
      deeps: _deeps(columns, rows, kinds, deepLooks, null),
      shapeSets: List.unmodifiable([
        if (looks == null)
          const <int>[]
        else
          List<int>.generate(shapes.count, (i) => i, growable: false),
      ]),
      droppedShapes: 0,
      looks: looks,
      deepLooks: deepLooks,
    );
    if (tiling._fits || reach.inward <= 1) return tiling;
    return Tiling.field(
      field,
      width: width,
      height: height,
      reach: reach._shallower,
      shapes: shapes,
      looks: looks,
    );
  }

  /// This tiling with [shapes] and [looks] in place of its own, where it
  /// still holds for them, else null: [shapes] are the shapes it was made
  /// for, none more than [slack] from where it was then, in a buffer of
  /// the same tiles, asked the same [reach], with looks shared out among
  /// the shapes as before. The atlas such a tiling draws holds the shapes
  /// where they are now; only which tiles are constant, which shapes a
  /// strip evaluates and how fine its texels are date from the first.
  Tiling? held(
    ShapeSet shapes, {
    required GlassReach reach,
    ShapeLooks? looks,
  }) {
    final tiled = _tiled ?? this;
    if (slack <= 0 || field != null || reach != this.reach) return null;
    final from = this.looks;
    if ((looks == null) != (from == null)) return null;
    if (looks != null &&
        from != null &&
        (looks.tintOnly != from.tintOnly ||
            !listEquals(looks.lookOf, from.lookOf))) {
      return null;
    }
    final moved = _moved(tiled.shapes, shapes);
    if (moved == null || moved > slack) return null;
    return Tiling._(
      reach: reach,
      shapes: shapes,
      field: null,
      columns: columns,
      rows: rows,
      kinds: kinds,
      runs: runs,
      deeps: deeps,
      shapeSets: shapeSets,
      droppedShapes: droppedShapes,
      looks: looks,
      deepLooks: deepLooks,
      slack: slack,
      tiled: tiled,
    );
  }

  /// How far the shape of [shapes] that moved most lies from where this
  /// tiling last drew it, in buffer pixels; null where [shapes] are not its
  /// shapes moved.
  double? motionTo(ShapeSet shapes) => _moved(this.shapes, shapes);

  // The greatest distance between the centers of [from]'s shapes and
  // [to]'s, or null unless they are the same shapes but for their centers.
  static double? _moved(ShapeSet from, ShapeSet to) {
    if (from.count != to.count) return null;
    final a = from.shapes;
    final b = to.shapes;
    var farthest = 0.0;
    for (var o = 0; o < a.length; o += 12) {
      for (var k = 0; k < 12; k++) {
        if (k == 8 || k == 9) continue;
        // A shape's transform is the difference of two transformed points,
        // which rounds differently wherever the shape lies.
        final value = a[o + k];
        if ((value - b[o + k]).abs() > 1e-6 * (1 + value.abs())) return null;
      }
      if (a[o] == RawShapeType.squirclePair.shaderIndex) {
        for (final k in const [8, 9]) {
          final value = from.superellipsesLower[o + k];
          if ((value - to.superellipsesLower[o + k]).abs() >
              1e-6 * (1 + value.abs())) {
            return null;
          }
        }
      }
      final dx = a[o + 8] - b[o + 8];
      final dy = a[o + 9] - b[o + 9];
      final distance = dx * dx + dy * dy;
      if (distance > farthest) farthest = distance;
    }
    return sqrt(farthest);
  }

  // The ring tiles as runs along each row, a run sharing one set of shapes,
  // one list of them and one density.
  static List<TileRun> _runs(
    int columns,
    int rows,
    Uint8List kinds,
    Int32List tileSets,
    Uint8List fine,
    int coarseTexel,
    Uint32List lists,
    Uint8List? wholes,
  ) {
    final runs = <TileRun>[];
    final blockColumns = (columns + blockTiles - 1) ~/ blockTiles;
    for (var row = 0; row < rows; row++) {
      var column = 0;
      while (column < columns) {
        if (wholes != null && column % blockTiles == 0) {
          final whole =
              wholes[row ~/ blockTiles * blockColumns + column ~/ blockTiles];
          if (whole == _outsideBlock || whole == _deepBlock) {
            column += blockTiles;
            continue;
          }
        }
        final tile = row * columns + column;
        if (kinds[tile] != TileKind.ring.index) {
          column++;
          continue;
        }
        final set = tileSets[tile];
        final members = lists[tile];
        final density = coarseTexel == 1 ? 1 : fine[tile];
        if (density == _inBlock) {
          // A block's tiles are one run, met at its first tile.
          if (row % blockTiles == 0 && column % blockTiles == 0) {
            runs.add(
              TileRun(
                row,
                column,
                min(blockTiles, columns - column),
                set,
                coarseTexel,
                members,
                min(blockTiles, rows - row),
              ),
            );
          }
          column += blockTiles - column % blockTiles;
          continue;
        }
        var end = column + 1;
        while (end < columns &&
            end - column < maxRunTiles &&
            kinds[tile + end - column] == TileKind.ring.index &&
            tileSets[tile + end - column] == set &&
            lists[tile + end - column] == members &&
            (coarseTexel == 1 || fine[tile + end - column] == density)) {
          end++;
        }
        final texel = density != 0 ? 1 : coarseTexel;
        runs.add(TileRun(row, column, end - column, set, texel, members));
        column = end;
      }
    }
    return List.unmodifiable(runs);
  }

  bool get _fits => layout.height <= AtlasLayout.maxSize;

  /// How far each shape may move from where it was tiled with the tiling
  /// still holding ([held]).
  final double slack;

  // The tiling this one holds for other shapes, if it is held.
  final Tiling? _tiled;

  /// Where the atlas holds this tiling's table and strips: about as wide as
  /// it is tall.
  late final AtlasLayout layout = _tiled?.layout ?? AtlasLayout._of(this);

  /// [layout] packed into an atlas [width] texels wide instead, or null
  /// where no strip or table fits that width or the atlas grows too tall.
  /// A page (FlutterGpuGeometryRenderer) asks the same width frame after
  /// frame, so the last answer is kept.
  AtlasLayout? layoutIn(int width) {
    final tiled = _tiled;
    if (tiled != null) return tiled.layoutIn(width);
    if (width == layout.width) return layout;
    if (_packed[this] case final packed? when packed.width == width) {
      return packed;
    }
    if (width < AtlasLayout._leastWidth(this)) return null;
    final packed = AtlasLayout._of(this, width: width);
    if (packed.height > AtlasLayout.maxSize) return null;
    return _packed[this] = packed;
  }

  static final Expando<AtlasLayout> _packed = Expando();

  static int _tilesOver(int pixels) => max(1, (pixels + size - 1) ~/ size);

  /// A rounded box that shape [i] of [shapes] holds, in the shape's own
  /// axes about its center: half its width, half its height and its corner
  /// radius; null where none is known to lie inside it. The bound a tile is
  /// called deep by, for a shader that works the shape out itself.
  static (double, double, double)? innerBoxOf(ShapeSet shapes, int i) {
    final bounds = _ShapeBounds.of(shapes, i);
    if (bounds._ellipse) {
      final minor = min(bounds.halfWidth, bounds.halfHeight);
      return minor > 0 ? (minor, minor, minor) : null;
    }
    if (bounds.innerRadius == double.infinity) return null;
    return (
      bounds.halfWidth - bounds.inset,
      bounds.halfHeight - bounds.inset,
      bounds.innerRadius,
    );
  }

  /// How far from the silhouette texels are exact.
  final GlassReach reach;

  /// The shapes tiled, in buffer pixels; for a [field], the shapes its looks
  /// come from, else empty.
  final ShapeSet shapes;

  /// The fused body tiled, if any.
  final BufferField? field;

  /// Tile edge in buffer pixels.
  static const int size = 16;

  /// The longest run: short strips fill an atlas row with little left over.
  static const int maxRunTiles = 8;

  /// The side of a block in tiles: smooth coarse content is tiled in
  /// blocks, each one run ([TileRun.tall]).
  static const int blockTiles = 4;

  // What a tile's density says where the tile is part of a block.
  static const int _inBlock = 2;

  // What a block is as a whole ([_Classifier.finish]): told tile by tile,
  // outside throughout, one piece of coarse texels, or deep throughout.
  static const int _byTile = 0;
  static const int _outsideBlock = 1;
  static const int _ringBlock = 2;
  static const int _deepBlock = 3;

  // The deep tiles as rectangles ([deeps]): a deep block, with the deep
  // blocks beside it, is one; elsewhere a row's deep tiles of one look.
  static Int32List _deeps(
    int columns,
    int rows,
    Uint8List kinds,
    Uint8List? deepLooks,
    Uint8List? wholes,
  ) {
    final deeps = <int>[];
    final blockColumns = (columns + blockTiles - 1) ~/ blockTiles;
    for (var row = 0; row < rows; row++) {
      var column = 0;
      while (column < columns) {
        if (wholes != null && column % blockTiles == 0) {
          final block = row ~/ blockTiles * blockColumns + column ~/ blockTiles;
          final whole = wholes[block];
          if (whole == _deepBlock) {
            var end = block + 1;
            while (end % blockColumns != 0 && wholes[end] == _deepBlock) {
              end++;
            }
            if (row % blockTiles == 0) {
              deeps
                ..add(column)
                ..add(row)
                ..add(min(columns - column, (end - block) * blockTiles))
                ..add(min(rows - row, blockTiles))
                ..add(0);
            }
            column += (end - block) * blockTiles;
            continue;
          }
          if (whole != _byTile) {
            column += blockTiles;
            continue;
          }
        }
        final tile = row * columns + column;
        if (kinds[tile] != TileKind.deep.index) {
          column++;
          continue;
        }
        final look = deepLooks?[tile] ?? 0;
        var end = column + 1;
        while (end < columns &&
            (wholes == null || end % blockTiles != 0) &&
            kinds[tile + end - column] == TileKind.deep.index &&
            (deepLooks?[tile + end - column] ?? 0) == look) {
          end++;
        }
        deeps
          ..add(column)
          ..add(row)
          ..add(end - column)
          ..add(1)
          ..add(look);
        column = end;
      }
    }
    return Int32List.fromList(deeps);
  }

  /// The most shapes a run lists ([TileRun.members]): what one vertex
  /// carries to the geometry pass.
  static const int maxListed = 4;

  /// Tiles along x.
  final int columns;

  /// Tiles along y.
  final int rows;

  /// [TileKind.index] of every tile, row-major.
  final Uint8List kinds;

  /// The ring tiles, row by row.
  final List<TileRun> runs;

  /// The deep tiles as rectangles of one look, five numbers each: column,
  /// row, width and height in tiles, and the look.
  final Int32List deeps;

  /// The shapes each run evaluates, in chain order. A buffer of at most
  /// [geometryMaxShapesPerDraw] shapes has one set: all of them.
  final List<List<int>> shapeSets;

  /// Shapes left out of a set that had more than
  /// [geometryMaxShapesPerDraw] within reach of one tile.
  final int droppedShapes;

  /// The looks the atlas carries beside the geometry, where the shapes' looks
  /// differ.
  final ShapeLooks? looks;

  /// The look of every deep tile, row-major, with [looks].
  final Uint8List? deepLooks;

  /// The kind of the tile at [column], [row].
  TileKind kindAt(int column, int row) =>
      TileKind.values[kinds[row * columns + column]];

  /// The look of the deep tile at [column], [row].
  int deepLookAt(int column, int row) =>
      deepLooks?[row * columns + column] ?? 0;

  // A deep tile reads one look only where one look's shapes alone weigh in:
  // a shape's weight in a smooth union is gone once its distance exceeds the
  // deepest member's by the blend, and a group's own fold lowers it by at
  // most its smoothing, so a shape weighs in only within 1.25 times its
  // group's blends. Other deep tiles turn ring and are evaluated; so does a
  // deep tile of a field no shape reaches. Returns each deep tile's look.
  static Uint8List _lookKinds(
    List<_ShapeBounds> bounds,
    _ShapeGroups groups,
    ShapeLooks looks,
    int columns,
    int rows,
    Uint8List kinds,
    Uint8List fine,
  ) {
    const none = -1;
    const mixed = -2;
    final owners = Int8List(columns * rows)..fillRange(0, columns * rows, none);
    for (var i = 0; i < bounds.length; i++) {
      final shape = bounds[i];
      final reach = groups.lookReach(i);
      final look = looks.lookOf[i];
      final (c0, r0, c1, r1) = shape.tileSpan(reach, columns, rows);
      for (var row = r0; row <= r1; row++) {
        for (var column = c0; column <= c1; column++) {
          final tile = row * columns + column;
          final owner = owners[tile];
          if (kinds[tile] != TileKind.deep.index ||
              owner == mixed ||
              owner == look) {
            continue;
          }
          if (shape.lowerOverTile(column, row) < reach) {
            owners[tile] = owner == none ? look : mixed;
          }
        }
      }
    }
    // Such a tile keeps one texel a pixel: looks of different groups meet at
    // a hard seam.
    final deepLooks = Uint8List(columns * rows);
    for (var tile = 0; tile < kinds.length; tile++) {
      if (kinds[tile] != TileKind.deep.index) continue;
      final owner = owners[tile];
      if (owner < 0) {
        kinds[tile] = TileKind.ring.index;
        fine[tile] = 1;
      } else {
        deepLooks[tile] = owner;
      }
    }
    return deepLooks;
  }

  // Each tile's kind, and whether it keeps one texel a pixel.
  //
  // A field's body is bilinear between its nodes, which a linear read of
  // coarse texels follows where the nodes lie at least a texel apart and
  // their gradients agree. Where the gradients over a tile turn against
  // one another, a ridge of the body or a corner the grid barely resolves,
  // the tile keeps one texel a pixel. NEAR, within what the grid resolves:
  // the body creases along the grid's lines, and a coarse texel across a
  // crease rounds it by up to the texel's side times the gradient's turn
  // there over four, the same order as the grid's own sag between nodes:
  // a sixth of a pixel on a corner six nodes in radius, half a pixel in
  // the tightest neck a grid holds.
  @pragma('vm:unsafe:no-bounds-checks')
  static (Uint8List, Uint8List) _fieldKinds(
    BufferField field,
    int columns,
    int rows,
    GlassReach reach,
  ) {
    final kinds = Uint8List(columns * rows);
    final fine = Uint8List(columns * rows);
    final (xx, xy, yx, yy, dx, dy) = field.bufferToGrid;
    final LiquidGlassField(:samples, :cols, rows: nodeRows, :step) =
        field.field;
    final scale = field.distanceScale;
    final coarse = reach.coarseTexel > 1 && step * scale >= reach.coarseTexel;
    // In the field's own units, so a node's distance is compared as read.
    final outward = reach.outward / scale;
    final inward = -reach.inward / scale;
    const agreement = _fieldAgreement * _fieldAgreement;
    // A tile's nodes are those over it and over its strip's apron.
    final apron = reach.coarseTexel / 2;
    final spanX = (xx.abs() + xy.abs()) * (size / 2 + apron);
    final spanY = (yx.abs() + yy.abs()) * (size / 2 + apron);
    final lastColumn = cols - 1;
    final lastRow = nodeRows - 1;
    final outside = TileKind.outside.index;
    final deep = TileKind.deep.index;
    final ring = TileKind.ring.index;
    var tile = 0;
    for (var row = 0; row < rows; row++) {
      final y = (row + 0.5) * size;
      for (var column = 0; column < columns; column++, tile++) {
        final x = (column + 0.5) * size;
        final gx = xx * x + xy * y + dx;
        final gy = yx * x + yy * y + dy;
        // Bilinear values stay within their nodes, and the field pass
        // clamps to the grid, so the nodes over the tile bound it.
        var i0 = (gx - spanX).floor();
        var i1 = (gx + spanX).ceil();
        var j0 = (gy - spanY).floor();
        var j1 = (gy + spanY).ceil();
        if (i0 < 0) i0 = 0;
        if (i0 > lastColumn) i0 = lastColumn;
        if (i1 < 0) i1 = 0;
        if (i1 > lastColumn) i1 = lastColumn;
        if (j0 < 0) j0 = 0;
        if (j0 > lastRow) j0 = lastRow;
        if (j1 < 0) j1 = 0;
        if (j1 > lastRow) j1 = lastRow;
        var lowest = double.infinity;
        var highest = double.negativeInfinity;
        for (var j = j0; j <= j1; j++) {
          final from = (j * cols + i0) * 4;
          final to = (j * cols + i1) * 4;
          for (var at = from; at <= to; at += 4) {
            final d = samples[at];
            if (d < lowest) lowest = d;
            if (d > highest) highest = d;
          }
        }
        if (lowest >= outward) {
          kinds[tile] = outside;
          continue;
        }
        if (highest <= inward) {
          kinds[tile] = deep;
          continue;
        }
        kinds[tile] = ring;
        if (!coarse) {
          fine[tile] = 1;
          continue;
        }
        // Only a ring tile has texels to keep fine or coarse, and most of a
        // body's tiles are deep or outside: their gradients are not read.
        var sumX = 0.0;
        var sumY = 0.0;
        var lengths = 0.0;
        for (var j = j0; j <= j1; j++) {
          final from = (j * cols + i0) * 4;
          final to = (j * cols + i1) * 4;
          for (var at = from; at <= to; at += 4) {
            final nx = samples[at + 1];
            final ny = samples[at + 2];
            sumX += nx;
            sumY += ny;
            lengths += sqrt(nx * nx + ny * ny);
          }
        }
        if (sumX * sumX + sumY * sumY < agreement * lengths * lengths) {
          fine[tile] = 1;
        }
      }
    }
    return (kinds, fine);
  }

  // How much of their summed length the gradients of a tile's nodes keep
  // when added as vectors, at least, for the tile to take coarse texels:
  // 0.8 is a corner turning through about 130 degrees over the tile.
  static const double _fieldAgreement = 0.8;

  static (List<List<int>>, Int32List, int) _shapeSets(
    List<_ShapeBounds> bounds,
    _ShapeGroups groups,
    int columns,
    int rows,
    GlassReach reach,
    Uint8List kinds, {
    required bool looks,
  }) {
    final count = bounds.length;
    final tileSets = Int32List(columns * rows);
    if (count <= geometryMaxShapesPerDraw) {
      return (
        [List<int>.generate(count, (i) => i, growable: false)],
        tileSets,
        0,
      );
    }
    // A group reaches a pixel only where its smoothed union can come within
    // the outward reach, or its look can weigh in, so a ring tile evaluates
    // every group that can; whole groups keep the chain's order exact.
    final reached = List<Set<int>>.generate(
      columns * rows,
      (_) => <int>{},
      growable: false,
    );
    for (var i = 0; i < count; i++) {
      final shape = bounds[i];
      final group = groups.groupOf[i];
      final reachOut = max(
        reach.outward + groups.smoothing(i) + groups.blendOf(group),
        looks ? groups.lookReach(i) : 0.0,
      );
      final (c0, r0, c1, r1) = shape.tileSpan(reachOut, columns, rows);
      for (var row = r0; row <= r1; row++) {
        for (var column = c0; column <= c1; column++) {
          final tile = row * columns + column;
          if (kinds[tile] != TileKind.ring.index) continue;
          if (shape.lowerOverTile(column, row) < reachOut) {
            reached[tile].add(group);
          }
        }
      }
    }
    final sets = <List<int>>[];
    final index = <String, int>{};
    var dropped = 0;
    for (var tile = 0; tile < tileSets.length; tile++) {
      if (kinds[tile] != TileKind.ring.index) continue;
      final members = [
        for (final group in reached[tile].toList()..sort())
          ...groups.members[group],
      ];
      if (members.length > geometryMaxShapesPerDraw) {
        dropped = max(dropped, members.length - geometryMaxShapesPerDraw);
        members.length = geometryMaxShapesPerDraw;
      }
      final key = members.join(',');
      tileSets[tile] = index.putIfAbsent(key, () {
        sets.add(List.unmodifiable(members));
        return sets.length - 1;
      });
    }
    return (sets, tileSets, dropped);
  }
}
