import 'package:flutter/widgets.dart';

const _deprecation =
    'No longer needed: glass now crops its backdrop read and shares it '
    'automatically. Remove the LiquidGlassCapture.';

/// Does nothing: it returns [child] unchanged.
///
/// It used to limit the backdrop read of the glass inside it. Glass now does
/// that itself: with native seeds (see `liquidGlassNativeSeed`, on by default
/// wherever Impeller renders) each glass reads only a small copy of the
/// backdrop around itself, and glass whose copies can come from one read of
/// the backdrop shares that read automatically. Glass on glass looks the same
/// without a capture, so remove it.
///
/// See also the "Glass on glass" section of the package README.
@Deprecated(_deprecation)
class LiquidGlassCapture extends StatelessWidget {
  /// Creates a widget that returns [child].
  @Deprecated(_deprecation)
  const LiquidGlassCapture({
    required this.child,
    @Deprecated(_deprecation) this.bleed,
    super.key,
  });

  /// The widget below this one.
  final Widget child;

  /// Has no effect.
  @Deprecated(_deprecation)
  final EdgeInsets? bleed;

  @override
  Widget build(BuildContext context) => child;
}
