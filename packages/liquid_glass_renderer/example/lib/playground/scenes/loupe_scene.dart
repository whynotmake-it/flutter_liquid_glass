import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer_example/loupe/liquid_glass_loupe.dart';
import 'package:liquid_glass_renderer_example/playground/playground_state.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/draggable_glass.dart';

/// Draggable [LiquidGlassLoupe]s over the backdrop, which is their
/// [LiquidGlassLoupeSource].
///
/// Each loupe re-renders the backdrop under it at the magnified resolution
/// and refracts it through its own glass, so it takes the playground's
/// material directly instead of joining the stage layer.
class LoupeScene extends StatelessWidget {
  const LoupeScene({
    required this.link,
    required this.loupes,
    required this.material,
    required this.magnification,
    super.key,
  });

  final LiquidGlassLoupeLink link;
  final List<LoupeSpec> loupes;
  final ValueListenable<GlassMaterial> material;
  final ValueListenable<double> magnification;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final center = constraints.biggest.center(Offset.zero);
        return ListenableBuilder(
          listenable: Listenable.merge([material, magnification]),
          builder: (context, _) => Stack(
            children: [
              for (final loupe in loupes)
                _DraggableLoupe(
                  center: center,
                  loupe: loupe,
                  child: LiquidGlassLoupe(
                    link: link,
                    size: loupe.size,
                    shape: loupe.shape,
                    magnification: magnification.value,
                    focalPointOffset: loupe.focalPointOffset,
                    settings: material.value.settings,
                    appearance: material.value.appearance,
                    shadows: glassShadows,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Positions a loupe by its focal point, which is where it is dragged, and
/// marks that point with a caret like iOS text selection.
class _DraggableLoupe extends StatelessWidget {
  const _DraggableLoupe({
    required this.center,
    required this.loupe,
    required this.child,
  });

  final Offset center;
  final LoupeSpec loupe;
  final Widget child;

  static const _caret = Size(2, 24);

  void _drag(DragUpdateDetails details) {
    final limit = center - loupe.size.center(Offset.zero);
    final next = loupe.offset.value + details.delta;
    loupe.offset.value = Offset(
      next.dx.clamp(-limit.dx, limit.dx),
      next.dy.clamp(-limit.dy, limit.dy),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lens = ImmediateDrag(onUpdate: _drag, child: child);
    final showCaret = loupe.focalPointOffset != Offset.zero;
    final caret = ColoredBox(color: CupertinoTheme.of(context).primaryColor);
    return ValueListenableBuilder(
      valueListenable: loupe.offset,
      builder: (context, offset, lens) {
        final lensCenter = center + offset;
        final lensTopLeft = lensCenter - loupe.size.center(Offset.zero);
        final focus = lensCenter + loupe.focalPointOffset;
        return Stack(
          children: [
            if (showCaret)
              Positioned(
                left: focus.dx - _caret.width / 2,
                top: focus.dy - _caret.height / 2,
                width: _caret.width,
                height: _caret.height,
                child: caret,
              ),
            Positioned(
              left: lensTopLeft.dx,
              top: lensTopLeft.dy,
              child: lens!,
            ),
          ],
        );
      },
      child: lens,
    );
  }
}
