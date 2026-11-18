import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// The menu's glass in [motion]'s frame.
///
/// A tinted source's color, [sourceTint], stays on the glass, fused body
/// included, until its look has faded.
@internal
GlassFrame menuFrame(
  MenuMotion motion, {
  Color? sourceTint,
  double opacity = 1,
}) {
  final tint = motion.drawsSource ? sourceTint : null;
  final tintAmount = tint == null ? 1.0 : motion.buttonLookOpacity;
  final (:shape, :outline) = motion.rootBody;
  final glow = motion.rootGlow?.shift(
    -(outline?.bounds.topLeft ?? shape.outerRect.topLeft),
  );
  if (outline != null) {
    return GlassFrame(
      outline: outline,
      tint: tint,
      tintAmount: tintAmount,
      glow: glow,
      opacity: opacity,
    );
  }
  return GlassFrame(
    shape: LiquidRoundedRectangle(radius: shape.tlRadiusX),
    rect: shape.outerRect,
    tint: tint,
    tintAmount: tintAmount,
    glow: glow,
    opacity: opacity,
  );
}

/// A menu's glass over its whole box, whose frame is [frameOf], read again
/// on every step [live] publishes and on every rebuild.
@internal
class MenuLiveGlass extends StatelessWidget {
  /// Creates glass framed by [frameOf] as [live] steps.
  const MenuLiveGlass({required this.live, required this.frameOf, super.key});

  /// The steps that frame the glass again.
  final MotionSelection<Object?> live;

  /// The glass's frame now.
  final GlassFrame Function() frameOf;

  @override
  Widget build(BuildContext context) => GlassSurface.live(
    role: GlassRole.panel,
    frame: MotionSelection(() {
      live.value;
      return frameOf();
    }),
    child: const SizedBox.expand(),
  );
}
