import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/shape_set.dart';
import 'package:liquid_glass_renderer/src/rendering/snap_rect_to_pixels.dart';

/// The tiling of a glass layer's latest atlas, kept while its shapes only
/// drift: shapes that move a little from encode to encode keep the tiling
/// of an earlier one, in that one's buffer, and only the pass runs again.
@internal
final class TilingDrift {
  Tiling? _tiling;
  Rect _bounds = Rect.zero;
  double _ratio = 0;
  int _width = 0;
  int _height = 0;

  // How many encodes running found the shapes of the one before only moved.
  int _driftingEncodes = 0;

  // How far, in device pixels, a drifting shape may move at most before
  // its layer is tiled again.
  static const double _tilingSlack = 3;

  /// The tiling of the latest atlas, or null since [reset].
  Tiling? get tiling => _tiling;

  /// The layer-local bounds of the latest atlas's buffer.
  Rect get bounds => _bounds;

  /// The width, in device pixels, of the latest atlas's buffer.
  int get width => _width;

  /// The height, in device pixels, of the latest atlas's buffer.
  int get height => _height;

  /// Forgets the tiling: the layer's geometry is no atlas now.
  void reset() {
    _tiling = null;
    _driftingEncodes = 0;
  }

  /// The tiling of an atlas of [shapes], whose layer-local [bounds] grown by
  /// [padding] and snapped to pixels are [padded], at [devicePixelRatio]:
  /// the latest one where it still holds them, else a new one, with slack
  /// around shapes seen to drift. [bounds], [width] and [height] then
  /// describe its buffer.
  Tiling advance(
    ShapeSet shapes, {
    required Rect bounds,
    required Rect padded,
    required double padding,
    required double devicePixelRatio,
    required LiquidGlassField? field,
    required GlassReach reach,
    required ShapeLooks? looks,
  }) {
    final dpr = devicePixelRatio;
    var boundsInMatteSpace = padded;
    Tiling? tiling;
    ShapeSet? inLast;
    var slack = 0.0;
    final last = _tiling;
    if (last != null && field == null && _ratio == dpr) {
      inLast = ShapeSet.join([(shapes, -_bounds.topLeft * dpr)]);
      final motion = last.motionTo(inLast);
      if (motion == null) {
        _driftingEncodes = 0;
      } else {
        if (_bounds.left <= boundsInMatteSpace.left &&
            _bounds.top <= boundsInMatteSpace.top &&
            _bounds.right >= boundsInMatteSpace.right &&
            _bounds.bottom >= boundsInMatteSpace.bottom) {
          tiling = last.held(inLast, reach: reach, looks: looks);
        }
        // Slack rings a few more tiles, so only shapes seen to move slowly
        // twice running are tiled with it, and with no more than serves
        // them for about six frames. Shapes encoded again where they were,
        // for a new look, say nothing of how they move.
        if (motion > 0) {
          if (motion <= _tilingSlack / 2 && _driftingEncodes > 0) {
            slack = (6 * motion).clamp(1, _tilingSlack);
          }
          _driftingEncodes++;
        }
      }
    } else {
      _driftingEncodes = 0;
    }
    if (tiling != null) {
      boundsInMatteSpace = _bounds;
    } else if (slack > 0) {
      boundsInMatteSpace = bounds
          .inflate(padding + slack / dpr)
          .snapToPixels(dpr);
    }
    final physicalSize = boundsInMatteSpace.size * dpr;
    final width = physicalSize.width.ceil();
    final height = physicalSize.height.ceil();
    final origin = boundsInMatteSpace.topLeft * dpr;
    if (tiling == null) {
      final inBuffer = inLast != null && boundsInMatteSpace == _bounds
          ? inLast
          : ShapeSet.join([(shapes, -origin)]);
      tiling = switch (field) {
        final field? => Tiling.field(
          BufferField(
            field,
            layerToBuffer: (dpr, 0, 0, dpr, -origin.dx, -origin.dy),
          ),
          width: width,
          height: height,
          reach: reach,
          shapes: inBuffer,
          looks: looks,
        ),
        null => Tiling.shapes(
          inBuffer,
          width: width,
          height: height,
          reach: reach,
          looks: looks,
          slack: slack,
        ),
      };
    }
    _tiling = tiling;
    _bounds = boundsInMatteSpace;
    _ratio = dpr;
    _width = width;
    _height = height;
    return tiling;
  }
}
