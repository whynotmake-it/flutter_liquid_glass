part of 'geometry_tiling.dart';

/// The blend groups of a [ShapeSet]: shapes in chain order, a negative blend
/// marker starting each group.
final class _ShapeGroups {
  _ShapeGroups._(this.groupOf, this.members, this._blends, this._smoothing);

  factory _ShapeGroups.of(ShapeSet shapes) {
    final groupOf = Int32List(shapes.count);
    final members = <List<int>>[];
    final blends = <double>[];
    final sums = <double>[];
    for (var i = 0; i < shapes.count; i++) {
      final marker = shapes.shapes[i * 12 + 11];
      if (marker < 0 || members.isEmpty) {
        members.add(<int>[]);
        blends.add(0);
        sums.add(0);
      } else {
        blends.last = max(blends.last, marker);
        sums.last += marker;
      }
      members.last.add(i);
      groupOf[i] = members.length - 1;
    }
    // A smooth fold lowers the union by at most a quarter of its radius.
    return _ShapeGroups._(
      groupOf,
      members,
      blends,
      [for (final sum in sums) sum * 0.25],
    );
  }

  final Int32List groupOf;
  final List<List<int>> members;
  final List<double> _blends;
  final List<double> _smoothing;

  /// How far below its nearest member [group]'s union can reach.
  double smoothingOf(int group) => _smoothing[group];

  /// The largest smooth-union radius in [group]: a member changes the union
  /// only where its distance comes within this of the rest's.
  double blendOf(int group) => _blends[group];

  /// How far below its nearest member a shape's group can reach.
  double smoothing(int shape) => _smoothing[groupOf[shape]];

  /// How far outside a shape its look can weigh in: 1.25 times its group's
  /// blends, and a pixel.
  double lookReach(int shape) => smoothing(shape) * 5 + 1;
}

/// Classifies the tiles of a buffer group by group.
///
/// A tile is outside or deep where the bounds of its groups' unions prove
/// every pixel is, and ring elsewhere. A ring tile keeps one texel a pixel
/// where two groups meet, where two members of a group with a narrow blend
/// meet, or where a shape's distance or normal folds. A wide blend folds
/// the union nowhere: the blend narrows as the members' normals agree, so
/// the turn of the normal across a seam stays within a texel's worth.
///
/// Each tile also gets its list of shapes ([TileRun.members]), for a
/// buffer whose shapes fit one draw: the members of each group that change
/// the group's union somewhere over the tile ([_chain]).
///
/// A group is bounded over blocks of [blockTiles] x [blockTiles] tiles
/// first: what holds over a block holds for each of its tiles, so a block
/// past every reach is skipped, a deep block is deep throughout, and the
/// tiles of any other bound only the members that change the block.
///
/// A block only one group reaches is not bounded tile by tile where it is
/// one thing as a whole: deep, past the ring, or crossed by the ring
/// without a fold. The last is one piece of coarse texels, which hold
/// what its outside and deep tiles would have held as constants. That is
/// most of a large smooth outline, for a few more coarse texels where the
/// ring only clips a block.
final class _Classifier {
  _Classifier({
    required this.columns,
    required this.rows,
    required GlassReach reach,
    required this.listable,
  }) : _kinds = Uint8List(columns * rows),
       _fine = Uint8List(columns * rows),
       _lists = Uint32List(columns * rows),
       _deep = Uint8List(columns * rows),
       _listed = Uint8List(columns * rows),
       _seamGroup = Int32List(columns * rows)..fillRange(0, columns * rows, -1),
       _claims = Int32List(
         _blocksOver(columns) * _blocksOver(rows),
       )..fillRange(0, _blocksOver(columns) * _blocksOver(rows), _free),
       _claimKinds = Uint8List(_blocksOver(columns) * _blocksOver(rows)),
       _claimLists = Uint32List(_blocksOver(columns) * _blocksOver(rows)),
       _coarse = reach.coarseTexel > 1,
       _outward = reach.outward,
       _inward = reach.inward,
       // A linear read blends texels up to a texel's diagonal away. Where
       // that footprint crosses a hard seam, both groups come within the
       // reach plus two diagonals of the pixel read.
       _seamReach =
           reach.outward +
           (reach.coarseTexel > 1 ? 3.0 * reach.coarseTexel : 0),
       // So the texels of every pixel a read shows are exact where a tile
       // lists every group that comes this near.
       _blended = reach.outward + 1.5 * reach.coarseTexel;

  static const int blockTiles = Tiling.blockTiles;

  static int _blocksOver(int tiles) => (tiles + blockTiles - 1) ~/ blockTiles;

  // A block no group has reached, and one bounded tile by tile.
  static const int _free = -1;
  static const int _byTile = -2;

  final int columns;
  final int rows;
  final bool listable;

  // Each block's claim: the one group that reaches it, or [_free] or
  // [_byTile]; what a claimed block is as a whole ([_whole]); and the list
  // of a smooth one.
  final Int32List _claims;
  final Uint8List _claimKinds;
  final Uint32List _claimLists;

  static const int _none = 0;
  static const int _smooth = 1;
  static const int _margin = 2;
  static const int _deepBlock = 3;

  // What each group was added with, for a block it claimed that another
  // group reaches after all.
  final List<List<int>> _members = [];
  final List<List<_ShapeBounds>> _blockBounds = [];
  final List<bool> _sharp = [];
  List<_ShapeBounds> _tileBounds = const [];
  final Uint8List _kinds;
  final Uint8List _fine;
  final Uint32List _lists;
  final Uint8List _deep;
  final Uint8List _listed;
  final Int32List _seamGroup;
  final bool _coarse;
  final double _outward;
  final double _inward;
  final double _seamReach;
  final double _blended;

  // What [_chain] found last: the places of the members it kept, and the
  // union's bounds.
  Int32List _kept = Int32List(0);
  double _lower = 0;
  double _upper = 0;

  final List<_ShapeBounds> _near = [];
  final List<int> _nearIndices = [];

  /// Each tile's kind, its density (whether it keeps one texel a pixel, or
  /// is part of a block), and its list; and what each block is as a whole
  /// ([Tiling._outsideBlock] and the constants beside it). Only the blocks
  /// bounded tile by tile are visited tile by tile.
  (Uint8List, Uint8List, Uint32List, Uint8List) finish() {
    final wholes = Uint8List(_claims.length);
    final blockColumns = _blocksOver(columns);
    for (var block = 0; block < _claims.length; block++) {
      final claim = _claims[block];
      if (claim == _free || (claim >= 0 && _claimKinds[block] == _margin)) {
        wholes[block] = Tiling._outsideBlock;
        continue;
      }
      final left = block % blockColumns * blockTiles;
      final top = block ~/ blockColumns * blockTiles;
      final right = min(columns, left + blockTiles);
      final bottom = min(rows, top + blockTiles);
      if (claim == _byTile) {
        for (var y = top; y < bottom; y++) {
          for (var x = left; x < right; x++) {
            final tile = y * columns + x;
            if (_deep[tile] != 0) _kinds[tile] = TileKind.deep.index;
            if (!listable || _listed[tile] > Tiling.maxListed) {
              _lists[tile] = 0;
            }
          }
        }
        continue;
      }
      final deep = _claimKinds[block] == _deepBlock;
      wholes[block] = deep ? Tiling._deepBlock : Tiling._ringBlock;
      for (var y = top; y < bottom; y++) {
        for (var x = left; x < right; x++) {
          final tile = y * columns + x;
          if (deep) {
            _kinds[tile] = TileKind.deep.index;
          } else {
            _kinds[tile] = TileKind.ring.index;
            _fine[tile] = Tiling._inBlock;
            _lists[tile] = _claimLists[block];
          }
        }
      }
    }
    return (_kinds, _fine, _lists, wholes);
  }

  /// Classifies the tiles [group] reaches: its [members] in chain order,
  /// bounded over tiles by [tiles] and over blocks by [blocks]. Their union
  /// lies at most [smoothing] below its nearest member, and folds where two
  /// of them meet if their blend is [sharp].
  void add(
    int group,
    List<int> members, {
    required List<_ShapeBounds> tiles,
    required List<_ShapeBounds> blocks,
    required double smoothing,
    required bool sharp,
  }) {
    final count = members.length;
    if (_kept.length < count) _kept = Int32List(count);
    final reach = max(_blended, _seamReach);
    final blockColumns = _blocksOver(columns);
    final blockRows = _blocksOver(rows);
    var c0 = blockColumns;
    var r0 = blockRows;
    var c1 = -1;
    var r1 = -1;
    final shapes = <_ShapeBounds>[];
    for (final i in members) {
      final (left, top, right, bottom) = blocks[i].tileSpan(
        reach + smoothing,
        blockColumns,
        blockRows,
      );
      c0 = min(c0, left);
      r0 = min(r0, top);
      c1 = max(c1, right);
      r1 = max(r1, bottom);
      shapes.add(blocks[i]);
    }
    while (_members.length <= group) {
      _members.add(const []);
      _blockBounds.add(const []);
      _sharp.add(false);
    }
    _members[group] = members;
    _blockBounds[group] = shapes;
    _sharp[group] = sharp;
    _tileBounds = tiles;
    for (var row = r0; row <= r1; row++) {
      for (var column = c0; column <= c1; column++) {
        var kept = _chain(shapes, count, column, row);
        if (_lower >= reach) continue;
        final block = row * blockColumns + column;
        final claim = _claims[block];
        if (claim == _free) {
          final whole = _whole(shapes, kept, column, row, sharp);
          if (whole != _none) {
            _claims[block] = group;
            _claimKinds[block] = whole;
            var list = 0;
            if (whole == _smooth && kept <= Tiling.maxListed) {
              for (var k = 0; k < kept; k++) {
                list |=
                    ((members[_kept[k]] + 1) | (k == 0 ? 0x80 : 0)) << (8 * k);
              }
            }
            _claimLists[block] = list;
            continue;
          }
        }
        _claims[block] = _byTile;
        if (claim >= 0) {
          // Two groups meet here after all: the first is bounded tile by
          // tile like this one.
          _boundTiles(
            claim,
            _chain(_blockBounds[claim], _members[claim].length, column, row),
            column,
            row,
          );
          kept = _chain(shapes, count, column, row);
        }
        _boundTiles(group, kept, column, row);
      }
    }
  }

  // What block [column], [row] is as a whole for the group whose [kept]
  // members [_chain] just found over it, while no other group reaches it:
  // deep throughout; past the ring, where the group only counts beside
  // another's; or [_smooth], one piece of coarse texels, where its ring
  // crosses the block and neither a member nor a narrow blend folds there.
  // Else [_none].
  int _whole(
    List<_ShapeBounds> shapes,
    int kept,
    int column,
    int row,
    bool sharp,
  ) {
    if (_upper <= -_inward) return _deepBlock;
    if (_lower >= _outward) return _margin;
    if (!_coarse || !listable) return _none;
    if (kept > 1 && sharp) return _none;
    for (var k = 0; k < kept; k++) {
      if (shapes[_kept[k]].foldsOverTile(column, row)) return _none;
    }
    return _smooth;
  }

  // Bounds the tiles of block [column], [row] for [group], whose [kept]
  // members [_chain] just found over the block.
  void _boundTiles(int group, int kept, int column, int row) {
    final members = _members[group];
    final left = column * blockTiles;
    final top = row * blockTiles;
    final right = min(columns, left + blockTiles) - 1;
    final bottom = min(rows, top + blockTiles) - 1;
    if (_upper <= -_inward) {
      for (var y = top; y <= bottom; y++) {
        for (var x = left; x <= right; x++) {
          final tile = y * columns + x;
          _meet(tile, group);
          for (var k = 0; k < kept; k++) {
            _list(tile, members[_kept[k]], starts: k == 0);
          }
          _deep[tile] = 1;
        }
      }
      return;
    }
    if (kept == 1) {
      final i = members[_kept[0]];
      _alone(group, _tileBounds[i], i, left, top, right, bottom);
      return;
    }
    _near.clear();
    _nearIndices.clear();
    for (var k = 0; k < kept; k++) {
      final i = members[_kept[k]];
      _near.add(_tileBounds[i]);
      _nearIndices.add(i);
    }
    _several(group, left, top, right, bottom, sharp: _sharp[group]);
  }

  void _meet(int tile, int group) {
    final other = _seamGroup[tile];
    if (other < 0) {
      _seamGroup[tile] = group;
    } else if (other != group) {
      _fine[tile] = 1;
    }
  }

  void _list(int tile, int shape, {required bool starts}) {
    final count = _listed[tile];
    if (count < Tiling.maxListed) {
      _lists[tile] |= ((shape + 1) | (starts ? 0x80 : 0)) << (8 * count);
    }
    if (count < 255) _listed[tile] = count + 1;
  }

  // The tiles [left], [top] to [right], [bottom] where [shape], shape
  // [index] of the buffer, is the one member of [group] that changes its
  // union.
  void _alone(
    int group,
    _ShapeBounds shape,
    int index,
    int left,
    int top,
    int right,
    int bottom,
  ) {
    for (var row = top; row <= bottom; row++) {
      for (var column = left; column <= right; column++) {
        final lower = shape.lowerOverTile(column, row);
        if (lower >= _blended && lower >= _seamReach) continue;
        final tile = row * columns + column;
        if (lower < _seamReach) _meet(tile, group);
        if (lower >= _blended) continue;
        _list(tile, index, starts: true);
        if (lower >= _outward) continue;
        if (lower <= -_inward && shape.upperOverTile(column, row) <= -_inward) {
          _deep[tile] = 1;
          continue;
        }
        _kinds[tile] = TileKind.ring.index;
        if (_coarse && _fine[tile] == 0 && shape.foldsOverTile(column, row)) {
          _fine[tile] = 1;
        }
      }
    }
  }

  // The tiles [left], [top] to [right], [bottom] of [group] whose union
  // only the members in [_near] change.
  void _several(
    int group,
    int left,
    int top,
    int right,
    int bottom, {
    required bool sharp,
  }) {
    final shapes = _near;
    final indices = _nearIndices;
    final count = shapes.length;
    for (var row = top; row <= bottom; row++) {
      for (var column = left; column <= right; column++) {
        final kept = _chain(shapes, count, column, row);
        final lower = _lower;
        if (lower >= _blended && lower >= _seamReach) continue;
        final tile = row * columns + column;
        if (lower < _seamReach) _meet(tile, group);
        if (lower >= _blended) continue;
        for (var k = 0; k < kept; k++) {
          _list(tile, indices[_kept[k]], starts: k == 0);
        }
        if (lower >= _outward) continue;
        if (_upper <= -_inward) {
          _deep[tile] = 1;
          continue;
        }
        _kinds[tile] = TileKind.ring.index;
        if (!_coarse || _fine[tile] != 0) continue;
        if (kept > 1 && sharp) {
          _fine[tile] = 1;
          continue;
        }
        for (var k = 0; k < kept; k++) {
          if (shapes[_kept[k]].foldsOverTile(column, row)) {
            _fine[tile] = 1;
            break;
          }
        }
      }
    }
  }

  // Folds the first [count] of [shapes], one group in chain order, over
  // cell [column], [row] as the geometry pass folds them at a pixel, on
  // bounds: [_lower] and [_upper] bound the union over the cell, and
  // [_kept] holds the places of the members that change it there; returns
  // how many.
  //
  // A smooth union of radius k is the nearer operand wherever the other
  // lies k or more past it, its distance, its normal and its look alike.
  // So a member that far past the union so far over the whole cell changes
  // nothing, and one that far inside it replaces everything before it.
  // Elsewhere the union is at most the nearer of the two, and below it by
  // at most what a blend takes at the narrowest gap between them.
  int _chain(List<_ShapeBounds> shapes, int count, int column, int row) {
    final first = shapes[0];
    var lower = first.lowerOverTile(column, row);
    var upper = first.upperOverTile(column, row);
    var kept = 1;
    _kept[0] = 0;
    for (var k = 1; k < count; k++) {
      final shape = shapes[k];
      final blend = shape.blend;
      final shapeLower = shape.lowerOverTile(column, row);
      if (shapeLower >= upper + blend) continue;
      final shapeUpper = shape.upperOverTile(column, row);
      if (lower >= shapeUpper + blend) {
        _kept[0] = k;
        kept = 1;
        lower = shapeLower;
        upper = shapeUpper;
        continue;
      }
      _kept[kept++] = k;
      if (blend > 0) {
        final gap = max(0, max(shapeLower - upper, lower - shapeUpper));
        final bite = blend - gap;
        lower = min(lower, shapeLower) - bite * bite * 0.25 / blend;
      } else {
        lower = min(lower, shapeLower);
      }
      upper = min(upper, shapeUpper);
    }
    _lower = lower;
    _upper = upper;
    return kept;
  }
}
