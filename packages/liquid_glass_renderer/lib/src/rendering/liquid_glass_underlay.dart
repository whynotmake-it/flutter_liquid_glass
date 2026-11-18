import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// What a layer adds to the scene around its children, outermost first: a
/// [transform], a rounded [clip], an opacity of [alpha] and a Gaussian blur
/// of [blurSigma].
@immutable
final class LiquidGlassLayerEffects {
  /// Describes a layer that moves its children by [transform] (its offset
  /// included), clips them to [clip] in the transformed coordinates, fades
  /// them to [alpha] and blurs them by [blurSigma] logical pixels; what is
  /// left out adds nothing.
  const LiquidGlassLayerEffects({
    required this.transform,
    this.clip,
    this.alpha,
    this.blurSigma = 0,
  }) : assert(alpha == null || (alpha >= 0 && alpha <= 255), '0 to 255.'),
       assert(blurSigma >= 0, 'A blur has no negative sigma.');

  /// How the layer moves its children, its offset included.
  final Matrix4 transform;

  /// The rounded clip of the children, in the transformed coordinates, or
  /// null for none.
  final RRect? clip;

  /// The opacity of the children, 0 to 255 as [OpacityLayer.alpha] takes
  /// it, or null for a layer that adds none.
  final int? alpha;

  /// The sigma of the Gaussian blur of the children, in logical pixels;
  /// zero for none.
  final double blurSigma;

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassLayerEffects &&
      other.transform == transform &&
      other.clip == clip &&
      other.alpha == alpha &&
      other.blurSigma == blurSigma;

  @override
  int get hashCode => Object.hash(transform, clip, alpha, blurSigma);

  @override
  String toString() =>
      'LiquidGlassLayerEffects(transform: $transform, clip: $clip, '
      'alpha: $alpha, blurSigma: $blurSigma)';
}

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

  /// Registers how layers of type [T] draw: what [effects] returns for a
  /// layer, around its children. [effects] runs while a frame composites,
  /// so it must be cheap. Registering [T] again replaces what it had.
  ///
  /// It holds for [T] exactly: a subtype can add to the scene what [effects]
  /// does not say, as only its own registration can vouch it does not.
  static void registerLayer<T extends ContainerLayer>(
    LiquidGlassLayerEffects Function(T layer) effects,
  ) {
    _effects[T] = (layer) => effects(layer as T);
  }

  /// Forgets how layers of type [T] draw: glass over one reads its backdrop
  /// again.
  static void unregisterLayer<T extends ContainerLayer>() {
    _effects.remove(T);
  }
}

/// What [layer] adds around its children, as its type registered with
/// [LiquidGlassUnderlay.registerLayer], or null for a type nobody registered.
LiquidGlassLayerEffects? underlayEffectsOf(Layer layer) =>
    LiquidGlassUnderlay._effects[layer.runtimeType]?.call(layer);
