import 'package:flutter/rendering.dart';

/// What a layer adds to the scene around its children, outermost first: a
/// `transform` (its offset included), a rounded `clip` in the transformed
/// coordinates, an opacity of `alpha` and a Gaussian `blur` of that sigma;
/// a null `clip` or `alpha` and a zero `blur` add nothing.
typedef LiquidGlassLayerEffects = ({
  Matrix4 transform,
  RRect? clip,
  int? alpha,
  double blur,
});

/// Teaches glass about layer types of other packages.
///
/// Glass that holds still over content that holds still paints over a copy
/// of that content instead of reading its backdrop every frame, which spares
/// the frame Impeller's backdrop passes. The copy is drawn from the layer
/// tree, so a layer type the renderer does not know, painted before the
/// glass near it, keeps the glass reading. Registering how such a type draws
/// lets the glass copy past it.
abstract final class LiquidGlassUnderlay {
  static final _effects = <Type, LiquidGlassLayerEffects Function(Layer)>{};

  /// Registers how layers of type [T] (exactly, not its subtypes) draw: what
  /// [effects] returns for a layer, around its children. [effects] runs
  /// while a frame composites, so it must be cheap.
  static void registerLayer<T extends ContainerLayer>(
    LiquidGlassLayerEffects Function(T layer) effects,
  ) {
    _effects[T] = (layer) => effects(layer as T);
  }
}

/// What [layer] adds around its children, as its type registered with
/// [LiquidGlassUnderlay.registerLayer], or null for a type nobody registered.
LiquidGlassLayerEffects? underlayEffectsOf(Layer layer) =>
    LiquidGlassUnderlay._effects[layer.runtimeType]?.call(layer);
