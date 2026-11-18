import 'package:kinesis/widgets.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:meta/meta.dart';

bool _taught = false;

/// Teaches the renderer's copies how kinesis layers draw: pages and
/// controls move on them, and what lies under a copy's glass or scroll edge
/// is drawn again only from layers the renderer knows.
@internal
void teachLiquidUnderlay() {
  if (_taught) return;
  _taught = true;
  LiquidGlassUnderlay.registerLayer<MotionTransitionLayer>(
    (layer) => LiquidGlassLayerEffects(
      transform: layer.total,
      clip: layer.clip,
      alpha: layer.alpha,
      blurSigma: layer.blur,
    ),
  );
}
