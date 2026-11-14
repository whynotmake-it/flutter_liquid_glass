part of 'geometry_tiling.dart';

/// Where a drawn atlas lies in the texture it shares with the other
/// atlases of its frame: the texel of its table's first entry and the
/// texture's size, as the final shader's uGeometryAtlas takes them.
typedef AtlasPlace = ({int tableX, int tableY, int width, int height});

/// Where one buffer's table, constant tiles and ring strips sit in its atlas
/// texture.
///
/// The 18 x 18 block at texel (0, 0) holds the outside value and the next
/// blocks the deep value, one block a look ([Tiling.looks]). The atlas is
/// cleared to the outside tile's table entry, so only deep and ring tiles
/// write theirs. The table lies below them, one texel per tile, and the
/// strips beside and below both: a run of n tiles of texels t pixels a
/// side ([TileRun.texel]), m rows tall ([TileRun.tall]), is `16 n / t + 2`
/// x `16 m / t + 2` texels, with a one-texel apron evaluated like the
/// rest, so a linear read between texels stays on exact values.
@internal
@immutable
final class AtlasLayout {
  const AtlasLayout._({
    required this.width,
    required this.height,
    required this.strips,
    required this._runs,
  });

  // Shelves of strips, the tallest strips first (the full-density strips
  // and the blocks, then the coarse runs), each height on shelves of its
  // own, the shelves beside the constants and the table starting past
  // them. A layout taller than [maxSize] does not fit; Tiling tiles such a
  // ring again.
  factory AtlasLayout._of(Tiling tiling, {int? width}) {
    final runs = tiling.runs;
    final headWidth = _headWidth(tiling);
    final headHeight = tableOrigin.$2 + tiling.rows;
    var atlasWidth = width ?? 0;
    final heights = <int>[];
    var area = headWidth * headHeight;
    for (final run in runs) {
      final height = _stripHeight(run);
      area += _stripWidth(run) * height;
      if (!heights.contains(height)) heights.add(height);
    }
    heights.sort((a, b) => b - a);
    if (width == null) {
      // An eighth over the area for what the shelves leave empty.
      atlasWidth = max(_leastWidth(tiling), sqrt(area * 1.125).ceil());
      atlasWidth = min(
        maxSize,
        (atlasWidth + _alignWidth - 1) ~/ _alignWidth * _alignWidth,
      );
    }
    final strips = Int32List(runs.length * 2);
    var x = headWidth;
    var y = 0;
    var shelf = 0;
    for (final height in heights) {
      for (var i = 0; i < runs.length; i++) {
        final run = runs[i];
        if (_stripHeight(run) != height) continue;
        final stripWidth = _stripWidth(run);
        if (x + stripWidth > atlasWidth || height != shelf) {
          y += shelf;
          shelf = height;
          x = y < headHeight ? headWidth : 0;
          if (x + stripWidth > atlasWidth) {
            y = headHeight;
            x = 0;
          }
        }
        strips[i * 2] = x;
        strips[i * 2 + 1] = y;
        x += stripWidth;
      }
    }
    final used = max(headHeight, y + shelf);
    return AtlasLayout._(
      width: atlasWidth,
      height: (used + _alignHeight - 1) ~/ _alignHeight * _alignHeight,
      strips: strips,
      runs: runs,
    );
  }

  // The width of the constant tiles above the table, and of the table.
  static int _headWidth(Tiling tiling) => max(
    (1 + max<int>(1, tiling.looks?.count ?? 0)) * _strip,
    tiling.columns,
  );

  // The narrowest atlas that holds the constants, the table and every
  // strip of [tiling].
  static int _leastWidth(Tiling tiling) {
    var widest = _headWidth(tiling);
    for (final run in tiling.runs) {
      widest = max(widest, _stripWidth(run));
    }
    return widest;
  }

  static int _stripWidth(TileRun run) =>
      run.length * Tiling.size ~/ run.texel + 2;

  static int _stripHeight(TileRun run) =>
      run.tall * Tiling.size ~/ run.texel + 2;

  static const int _strip = Tiling.size + 2;

  // A tiled GPU stores a target in tiles of 16 texels. Widths step by two,
  // so an atlas that grows a little keeps its width and its texture.
  static const int _alignWidth = 32;
  static const int _alignHeight = 16;

  /// The largest atlas side: table entries are atlas texel coordinates in a
  /// 16-bit float, exact up to 2048.
  static const int maxSize = 2048;

  /// The atlas size in texels.
  final int width;

  /// The atlas size in texels.
  final int height;

  /// Texel of table entry (0, 0), below the constant tiles.
  static const (int, int) tableOrigin = (0, _strip);

  /// The place of an atlas that is not drawn.
  static const AtlasPlace unplaced = (
    tableX: 0,
    tableY: _strip,
    width: 0,
    height: 0,
  );

  /// Each run's strip corner (its apron's top-left texel), x then y.
  final Int32List strips;

  final List<TileRun> _runs;

  /// The table entry of the outside tile: the texel of its pixel (0, 0).
  static const (int, int) outsideEntry = (1, 1);

  /// The table entry of the deep tiles of [look].
  static (int, int) deepEntryOf(int look) => ((look + 1) * _strip + 1, 1);

  /// The table entry of tile [index] of [run], [down] rows below its
  /// first: the corner of the texel of that tile's pixel (0, 0) in the
  /// run's strip.
  (int, int) entryOf(int run, int index, [int down = 0]) => (
    strips[run * 2] + 1 + index * Tiling.size ~/ _runs[run].texel,
    strips[run * 2 + 1] + 1 + down * Tiling.size ~/ _runs[run].texel,
  );
}
