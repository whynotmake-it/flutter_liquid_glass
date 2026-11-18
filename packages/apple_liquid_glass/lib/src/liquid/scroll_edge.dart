import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/liquid/underlay_layers.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:meta/meta.dart';

/// A scroll edge effect as [details] describe it, whose band blurs the
/// content under it before the content dissolves toward the background.
@internal
class ScrollEdge extends StatelessWidget {
  /// Creates the effect.
  const ScrollEdge({required this.details, super.key});

  /// What to draw.
  final GlassScrollEdgeDetails details;

  @override
  Widget build(BuildContext context) {
    final traits = GlassTraits.of(context);
    return ScrollEdgeBand(
      details: details,
      paint: _EdgePaint(
        details: details,
        brightness: traits.brightness,
        devicePixelRatio: traits.viewPixelRatio,
      ),
    );
  }
}

class _EdgePaint extends LeafRenderObjectWidget {
  const _EdgePaint({
    required this.details,
    required this.brightness,
    required this.devicePixelRatio,
  });

  final GlassScrollEdgeDetails details;
  final Brightness brightness;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) {
    teachLiquidUnderlay();
    return _RenderEdge(
      details: details,
      brightness: brightness,
      devicePixelRatio: devicePixelRatio,
    );
  }

  @override
  void updateRenderObject(BuildContext context, _RenderEdge renderObject) {
    renderObject.details = details;
    renderObject.brightness = brightness;
    renderObject.devicePixelRatio = devicePixelRatio;
  }
}

/// The blur of the band under the flat effect's fade and hairline: the
/// presence fades the blurred backdrop through its alpha, as an opacity
/// layer above a blur would read an empty backdrop. The blur reads a copy
/// of the backdrop only as far around the band as its kernel reaches.
class _RenderEdge extends RenderScrollEdge with LiquidGlassBackdropFilterHost {
  _RenderEdge({
    required super.details,
    required super.brightness,
    required super.devicePixelRatio,
  });

  final _blur = LayerHandle<LiquidGlassBackdropFilterLayer>();

  @override
  LiquidGlassBackdropFilterLayer? get backdropFilterLayer => _blur.layer;

  @override
  bool updateBand(double presence) {
    final blur = _blur.layer;
    if (blur == null) return false;
    blur.filter = bandAt(presence);
    return true;
  }

  @override
  void dropBand() => _blur.layer = null;

  @override
  void paintBand(
    PaintingContext context,
    Offset offset,
    double presence,
    PaintingContextCallback fade,
  ) {
    final box = offset & size;
    final band = bandAt(presence);
    final blur =
        (_blur.layer ??= LiquidGlassBackdropFilterLayer(
            filter: band,
            clip: box,
          ))
          ..filter = band
          ..clip = box;
    context.pushLayer(blur, fade, offset);
  }
}
