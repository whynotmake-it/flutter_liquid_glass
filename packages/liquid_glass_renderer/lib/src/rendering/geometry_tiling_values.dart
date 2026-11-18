part of 'geometry_tiling.dart';

/// How far from a silhouette the final shader needs exact geometry, in
/// buffer pixels: deeper than [inward] it reads only "deep", farther out
/// than [outward] only "outside". Between them a texel spans [coarseTexel]
/// pixels a side wherever the geometry is smooth.
@internal
@immutable
final class GlassReach {
  /// Creates the reach.
  const GlassReach({
    required this.inward,
    required this.outward,
    this.coarseTexel = 1,
    double? exactInward,
  }) : exactInward = exactInward ?? inward;

  /// Depth past which the shading no longer depends on the distance or the
  /// normal.
  final double inward;

  /// The least depth the shading reads, [inward] at most.
  final double exactInward;

  /// Distance outside past which nothing is drawn.
  final double outward;

  /// The side in buffer pixels of a texel of a ring tile no ridge, seam or
  /// tight corner comes near, a power of two up to [Tiling.size]. The final
  /// shader reads such a tile linearly, which is exact on straight edges and
  /// elsewhere within a quarter pixel of distance and a tenth of the normal
  /// in the outer four pixels, a fifth deeper in, where a corner's inner
  /// contours tighten (NEAR, the low-res atlas's density). Where the
  /// distance or the normal folds, the tile keeps one texel a pixel.
  final int coarseTexel;

  /// Whether geometry tiled for this reach serves [other]: a narrower reach
  /// finds every constant tile still constant, and finer texels serve
  /// coarser ones.
  bool covers(GlassReach other) =>
      inward >= other.inward &&
      outward >= other.outward &&
      coarseTexel <= other.coarseTexel;

  GlassReach get _shallower => GlassReach(
    inward: inward > exactInward
        ? exactInward
        : inward > 2
        ? inward / 2
        : 1,
    outward: outward,
    coarseTexel: coarseTexel,
  );

  @override
  bool operator ==(Object other) =>
      other is GlassReach &&
      other.inward == inward &&
      other.exactInward == exactInward &&
      other.outward == outward &&
      other.coarseTexel == coarseTexel;

  @override
  int get hashCode => Object.hash(inward, exactInward, outward, coarseTexel);
}

/// What one 16 x 16 tile of a geometry buffer holds.
@internal
enum TileKind {
  /// Farther outside every shape than [GlassReach.outward] at every pixel.
  outside,

  /// Deeper than [GlassReach.inward] at every pixel.
  deep,

  /// Within reach of a silhouette somewhere: its pixels are evaluated.
  ring,
}

/// Consecutive ring tiles of one table row that evaluate the same shapes at
/// the same density, or a block of such rows ([tall]).
@internal
@immutable
final class TileRun {
  /// Creates the run.
  const TileRun(
    this.row,
    this.column,
    this.length,
    this.shapes,
    this.texel, [
    this.members = TileMembers.whole,
    this.tall = 1,
  ]);

  /// The table row, the first of [tall].
  final int row;

  /// The first tile's column.
  final int column;

  /// How many tiles, at most [Tiling.maxRunTiles].
  final int length;

  /// Index into [Tiling.shapeSets].
  final int shapes;

  /// The side of a texel in buffer pixels: 1, or [GlassReach.coarseTexel].
  final int texel;

  /// The shapes of the set the run's texels evaluate.
  final TileMembers members;

  /// How many table rows the run spans: 1, or up to [Tiling.blockTiles]
  /// for a block of coarse tiles, whose strip is one piece.
  final int tall;
}

/// The shapes of a set a run's texels evaluate ([TileRun.members]), where
/// every other shape provably leaves them as they are: up to
/// [Tiling.maxListed] of them in chain order, a byte each from the lowest,
/// holding the shape's place in the set plus one, and a flag where it is the
/// first of its group among them.
@internal
extension type const TileMembers(int word) {
  /// The whole set.
  static const TileMembers whole = TileMembers(0);

  static const int _place = 0x7f;
  static const int _startsGroup = 0x80;

  /// Whether the texels evaluate the whole set.
  bool get isWhole => word == 0;

  /// These with the shape at [place] in the set as member [slot], the first
  /// of its group where [startsGroup].
  TileMembers withMember(int slot, int place, {required bool startsGroup}) =>
      TileMembers(
        word | ((place + 1) | (startsGroup ? _startsGroup : 0)) << (8 * slot),
      );

  /// The place in the set of member [slot], or -1 past the last.
  int placeAt(int slot) => ((word >> (8 * slot)) & _place) - 1;

  /// Whether member [slot] is the first of its group.
  bool startsGroupAt(int slot) => (word >> (8 * slot)) & _startsGroup != 0;

  /// The members: their places in the set and whether each starts its
  /// group.
  List<(int, bool)> get listed => [
    for (var slot = 0; slot < Tiling.maxListed && placeAt(slot) >= 0; slot++)
      (placeAt(slot), startsGroupAt(slot)),
  ];
}

/// What the shapes of a buffer whose glass differs in tint or material look
/// like. The atlas pass writes each texel's look beside its geometry, blended
/// where shapes fuse by the smooth union's weight over its full radius
/// (looks.glsl), so the final shader reads it at the geometry's texel.
@internal
@immutable
final class ShapeLooks {
  /// The looks of shapes given by [entries], [lookFloats] a shape, by
  /// [LookLane]. With [tintOnly] the atlas carries the tint alone. Shapes
  /// that look the same share a look; past [maxLooks] looks the rest take
  /// the last.
  factory ShapeLooks(List<double> entries, {required bool tintOnly}) {
    final compared = tintOnly ? LookLane.tint.width : lookFloats;
    final count = entries.length ~/ lookFloats;
    final lookOf = Uint8List(count);
    final looks = <double>[];
    for (var shape = 0; shape < count; shape++) {
      final at = shape * lookFloats;
      var look = 0;
      final known = looks.length ~/ lookFloats;
      while (look < known) {
        var same = true;
        for (var i = 0; i < compared && same; i++) {
          same = looks[look * lookFloats + i] == entries[at + i];
        }
        if (same) break;
        look++;
      }
      if (look == known) {
        if (known < maxLooks) {
          looks.addAll(entries.getRange(at, at + lookFloats));
        } else {
          look = maxLooks - 1;
        }
      }
      lookOf[shape] = look;
    }
    return ShapeLooks._(
      tintOnly: tintOnly,
      lookOf: lookOf,
      looks: List.unmodifiable(looks),
    );
  }

  const ShapeLooks._({
    required this.tintOnly,
    required this.lookOf,
    required this.looks,
  });

  /// The floats of one look.
  static final int lookFloats = laneBlockFloats(LookLane.values);

  /// The most looks one atlas holds: an atlas pass reads them from one
  /// uniform array.
  static const int maxLooks = geometryMaxShapesPerDraw;

  /// Whether the atlas carries the tint alone.
  final bool tintOnly;

  /// Each shape's look.
  final Uint8List lookOf;

  /// [lookFloats] floats a look, as the entries came.
  final List<double> looks;

  /// How many looks there are.
  int get count => looks.length ~/ lookFloats;
}

/// A fused body (`LiquidGlassLayer.field`) placed in a geometry buffer.
@internal
@immutable
final class BufferField {
  /// Places [field], whose frame is in its layer's logical pixels, by
  /// [layerToBuffer]: `(xx, xy, yx, yy, tx, ty)` with
  /// `buffer.x = xx * x + xy * y + tx`.
  factory BufferField(
    LiquidGlassField field, {
    required (double, double, double, double, double, double) layerToBuffer,
  }) {
    final (xx, xy, yx, yy, tx, ty) = layerToBuffer;
    final determinant = xx * yy - xy * yx;
    final step = field.step;
    final ix = yy / determinant / step;
    final ixy = -xy / determinant / step;
    final iyx = -yx / determinant / step;
    final iy = xx / determinant / step;
    final ox = field.origin.dx / step;
    final oy = field.origin.dy / step;
    return BufferField._(
      field,
      bufferToGrid: (
        ix,
        ixy,
        iyx,
        iy,
        -(ix * tx + ixy * ty) - ox,
        -(iyx * tx + iy * ty) - oy,
      ),
      distanceScale: leastSingularValue(xx, xy, yx, yy),
    );
  }

  const BufferField._(
    this.field, {
    required this.bufferToGrid,
    required this.distanceScale,
  });

  /// The field.
  final LiquidGlassField field;

  /// Buffer pixels to grid coordinates (node (i, j) at (i, j)):
  /// `(xx, xy, yx, yy, dx, dy)` with `grid.x = xx * x + xy * y + dx`.
  final (double, double, double, double, double, double) bufferToGrid;

  /// Buffer pixels per logical pixel of the field's distances: the
  /// placement's least stretch, as a shape's distance scale.
  final double distanceScale;
}
