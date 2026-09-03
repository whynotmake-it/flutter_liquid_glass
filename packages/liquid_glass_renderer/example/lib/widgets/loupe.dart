import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:motor/motor.dart';

/// Apple's loupe is a clear lens: its backdrop is enlarged, but it does not
/// inherit the toolbar's milky tint or frost. Keep the edge optics and contour
/// from the matched toolbar while neutralizing transmission.
const loupeGlassSettings = LiquidGlassSettings(
  thickness: 12,
  edgeRefraction: 27.42,
  frost: 0,
  chromaticAberration: 0.005,
  // Keep only a hairline dielectric rim. The lens body must remain the
  // magnified backdrop, not a translucent white fill.
  highlight: 0.25,
  contourStrength: 0.08,
  contourWidth: 0.75,
);

const loupeGlassAppearance = LiquidGlassAppearance();

/// Example-only loupe composition.
///
/// Flutter's [RawMagnifier] paints a higher-resolution view of the already
/// painted backdrop first. The liquid-glass layer is then composited above
/// that result, so its ordinary edge refraction and lighting operate on the
/// magnified pixels without introducing a shader-level zoom or another public
/// renderer setting.
class ExampleLoupe extends StatelessWidget {
  const ExampleLoupe({
    required this.settings,
    super.key,
    this.size = const Size(116, 86),
    this.magnificationScale = 1.55,
    this.alignment = Alignment.center,
    this.focalPointOffset = Offset.zero,
  });

  final LiquidGlassSettings settings;
  final Size size;
  final double magnificationScale;
  final Alignment alignment;
  final Offset focalPointOffset;

  @override
  Widget build(BuildContext context) {
    assert(
      magnificationScale >= 1.0,
      'Magnification cannot shrink its source.',
    );
    final radius = BorderRadius.circular(size.height / 2);
    return Align(
      alignment: alignment,
      child: SizedBox.fromSize(
        size: size,
        child: Stack(
          children: [
            RawMagnifier(
              size: size,
              magnificationScale: magnificationScale,
              focalPointOffset: focalPointOffset,
              decoration: MagnifierDecoration(
                shape: RoundedRectangleBorder(borderRadius: radius),
              ),
              clipBehavior: Clip.hardEdge,
            ),
            LiquidGlass.withOwnLayer(
              settings: settings,
              appearance: loupeGlassAppearance,
              shape: LiquidRoundedRectangle(borderRadius: size.height / 2),
              // There is intentionally no child fill or glow here: Apple's
              // loupe is a clear magnified lens with only its edge optics.
              child: const SizedBox.expand(),
            ),
          ],
        ),
      ),
    );
  }
}

/// A loupe that trails the pointer through a spring, so the lens feels like it
/// has inertia while the magnified content stays locked to the finger.
class DraggableLoupe extends StatefulWidget {
  const DraggableLoupe({
    required this.settings,
    super.key,
    this.size = const Size(120, 88),
    this.magnificationScale = 1.6,
  });

  final LiquidGlassSettings settings;
  final Size size;
  final double magnificationScale;

  @override
  State<DraggableLoupe> createState() => _DraggableLoupeState();
}

class _DraggableLoupeState extends State<DraggableLoupe> {
  Offset _position = Offset.zero;
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounds = Offset(
          (constraints.maxWidth - widget.size.width)
              .clamp(0, double.infinity),
          (constraints.maxHeight - widget.size.height)
              .clamp(0, double.infinity),
        );
        _clampPosition(bounds);
        return MouseRegion(
          cursor: SystemMouseCursors.precise,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => setState(() => _active = true),
            onPanUpdate: (details) => setState(
              () => _position = Offset(
                (_position + details.delta).dx.clamp(0, bounds.dx),
                (_position + details.delta).dy.clamp(0, bounds.dy),
              ),
            ),
            onPanEnd: (_) => setState(() => _active = false),
            child: MotionBuilder<Offset>(
              motion: _active
                  ? const Motion.interactiveSpring(snapToEnd: true)
                  : const Motion.bouncySpring(snapToEnd: true),
              value: _position,
              converter: const OffsetMotionConverter(),
              builder: (context, position, child) => Stack(
                children: [
                  Positioned(
                    left: position.dx,
                    top: position.dy,
                    child: child!,
                  ),
                ],
              ),
              child: ExampleLoupe(
                settings: widget.settings,
                size: widget.size,
                magnificationScale: widget.magnificationScale,
                alignment: Alignment.topLeft,
                focalPointOffset: Offset(
                  widget.size.width / 2,
                  widget.size.height / 2,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _clampPosition(Offset bounds) {
    _position = Offset(
      _position.dx.clamp(0, bounds.dx),
      _position.dy.clamp(0, bounds.dy),
    );
  }
}
