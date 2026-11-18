import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/surfaces/follow.dart';
import 'package:apple_liquid_glass/src/surfaces/renderer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// The numbers of UIKit's scroll edge effect on iOS 27: `PocketSettings`
/// and the layers of `UIKit.ScrollEdgeEffectView` (read from UIKit, notes
/// private; the hard band replayed against an iPhone 16 Pro capture that
/// is not among this package's fixtures). Radii are taken as Gaussian
/// sigmas.
@internal
abstract final class ScrollEdgeTuning {
  /// How far the soft band reaches past the bar.
  static const double softOverhang = 40;

  /// Where along the soft band, from the screen's edge, the fade starts to
  /// dissolve.
  static const double softFadeStart = 0.3407;

  /// The blur of the soft band.
  static const double softBlur = 1.5;

  /// The blur of the hard band, a navigation bar's.
  static const double hardBlur = 2;

  /// The saturation of the content under the hard band.
  static const double hardSaturation = 1.25;

  /// The brightness added under the hard band, as a share of full
  /// intensity.
  static const double hardBrightness = 0.03;

  /// How far the content fades toward the background: UIKit's replay
  /// alpha, 0.5 in light and 0.6 in dark.
  static double fade(Brightness brightness) =>
      brightness == Brightness.dark ? 0.6 : 0.5;

  /// The hairline of the hard band: black or white at 10 percent.
  static Color hairline(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0x1AFFFFFF)
      : const Color(0x1A000000);
}

/// The band of a scroll edge effect as [details] describe it, laid out at
/// its edge of the scroll view: the bar's extent, and for the soft effect
/// [ScrollEdgeTuning.softOverhang] past it. [paint] draws the band.
class ScrollEdgeBand extends StatelessWidget {
  /// Lays [paint] out where the band of [details] lies.
  const ScrollEdgeBand({required this.details, required this.paint, super.key});

  /// What to draw.
  final GlassScrollEdgeDetails details;

  /// The render object widget that draws the band.
  final Widget paint;

  @override
  Widget build(BuildContext context) {
    final top = details.edge == AxisDirection.up;
    return IgnorePointer(
      child: Align(
        alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
        child: SizedBox(
          height: details.hard
              ? details.extent
              : details.extent + ScrollEdgeTuning.softOverhang,
          width: double.infinity,
          child: paint,
        ),
      ),
    );
  }
}

/// The flat scroll edge effect: the content under the band dissolves
/// toward the background, and the hard effect draws its hairline, with no
/// blur. Every renderer draws it unless it draws its own.
@internal
class FlatScrollEdge extends StatelessWidget {
  /// Creates the effect [details] describe.
  const FlatScrollEdge({required this.details, super.key});

  /// What to draw.
  final GlassScrollEdgeDetails details;

  @override
  Widget build(BuildContext context) {
    final traits = GlassTraits.of(context);
    return ScrollEdgeBand(
      details: details,
      paint: _FlatEdgePaint(
        details: details,
        brightness: traits.brightness,
        devicePixelRatio: traits.viewPixelRatio,
      ),
    );
  }
}

class _FlatEdgePaint extends LeafRenderObjectWidget {
  const _FlatEdgePaint({
    required this.details,
    required this.brightness,
    required this.devicePixelRatio,
  });

  final GlassScrollEdgeDetails details;
  final Brightness brightness;
  final double devicePixelRatio;

  @override
  RenderScrollEdge createRenderObject(BuildContext context) => RenderScrollEdge(
    details: details,
    brightness: brightness,
    devicePixelRatio: devicePixelRatio,
  );

  @override
  void updateRenderObject(BuildContext context, RenderScrollEdge renderObject) {
    renderObject.details = details;
    renderObject.brightness = brightness;
    renderObject.devicePixelRatio = devicePixelRatio;
  }
}

/// The fade toward the background and the hairline of a scroll edge
/// effect, faded as one by its presence through an opacity layer. A
/// renderer that blurs the band extends it, drawing the fade inside its
/// blur ([paintBand]) and updating its own layers in place
/// ([updateBand]).
class RenderScrollEdge extends RenderBox with ListenableFollower {
  /// Creates the band.
  RenderScrollEdge({
    required this._details,
    required this._brightness,
    required this._devicePixelRatio,
  });

  final _fade = LayerHandle<OpacityLayer>();
  double? _painted;

  /// What to draw.
  GlassScrollEdgeDetails get details => _details;
  GlassScrollEdgeDetails _details;
  set details(GlassScrollEdgeDetails value) {
    if (value == _details) return;
    refollow(() => _details = value);
    markNeedsPaint();
  }

  /// The brightness the fade and hairline follow.
  Brightness get brightness => _brightness;
  Brightness _brightness;
  set brightness(Brightness value) {
    if (value == _brightness) return;
    _brightness = value;
    markNeedsPaint();
  }

  /// The device pixels per logical pixel of the view, which the hairline
  /// is one of.
  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  /// How present the effect is now, 0 to 1.
  double get presence => _details.presence.value.clamp(0.0, 1.0);

  /// The band at [presence] as the glass renderer's values describe it:
  /// the blur of the content under it (UIKit's hard or soft radius, as a
  /// Gaussian sigma), the saturation and added brightness under the hard
  /// band, the color the content fades toward (the background at UIKit's
  /// fade for the brightness), the hard band's hairline and where along the
  /// soft band the fade starts to dissolve. The flat effect paints its fade
  /// and hairline; a renderer that blurs the band draws all of it.
  @protected
  LiquidGlassFrostBand bandAt(double presence) => _details.hard
      ? LiquidGlassFrostBand.hard(
          sigma: ScrollEdgeTuning.hardBlur,
          edge: _details.edge,
          fade: _fadeColor,
          line: ScrollEdgeTuning.hairline(_brightness),
          saturation: ScrollEdgeTuning.hardSaturation,
          brightness: ScrollEdgeTuning.hardBrightness,
          presence: presence,
        )
      : LiquidGlassFrostBand.soft(
          sigma: ScrollEdgeTuning.softBlur,
          edge: _details.edge,
          fade: _fadeColor,
          fadeStart: ScrollEdgeTuning.softFadeStart,
          presence: presence,
        );

  Color get _fadeColor {
    final background = _details.background;
    return background.withValues(
      alpha: background.a * ScrollEdgeTuning.fade(_brightness),
    );
  }

  // A presence change between two visible values updates the layers it
  // already has, without painting; appearing or vanishing paints.
  void _presenceChanged() {
    final presence = this.presence;
    final painted = _painted;
    if (presence == painted) return;
    final fade = _fade.layer;
    if (painted == null ||
        painted <= 0.001 ||
        presence <= 0.001 ||
        fade == null ||
        !updateBand(presence)) {
      markNeedsPaint();
      return;
    }
    _painted = presence;
    fade.alpha = Color.getAlphaFromOpacity(presence);
    markNeedsCompositedLayerUpdate();
  }

  /// Updates the layers a subclass drew around the fade to [presence], and
  /// says whether it could without painting.
  @protected
  bool updateBand(double presence) => true;

  /// Drops the layers a subclass drew around the fade.
  @protected
  void dropBand() {}

  @override
  List<(Listenable, VoidCallback)> get followed => [
    (_details.presence, _presenceChanged),
  ];

  @override
  void dispose() {
    _drop();
    super.dispose();
  }

  void _drop() {
    dropBand();
    _fade.layer = null;
  }

  @override
  bool get sizedByParent => true;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  bool get isRepaintBoundary => true;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  void paint(PaintingContext context, Offset offset) {
    final presence = this.presence;
    _painted = presence;
    if (presence <= 0.001) {
      _drop();
      return;
    }
    paintBand(context, offset, presence, paintFade);
  }

  /// Paints the band at [presence]: by default only [fade], the fade and
  /// hairline.
  @protected
  void paintBand(
    PaintingContext context,
    Offset offset,
    double presence,
    PaintingContextCallback fade,
  ) {
    dropBand();
    fade(context, offset);
  }

  /// Paints the fade and the hairline in an opacity layer of the effect's
  /// presence.
  @protected
  void paintFade(PaintingContext context, Offset offset) {
    final box = offset & size;
    _fade.layer = context.pushOpacity(
      offset,
      Color.getAlphaFromOpacity(presence),
      (context, _) => bandAt(presence).paintOver(
        context.canvas,
        box,
        devicePixelRatio: _devicePixelRatio,
      ),
      oldLayer: _fade.layer,
    );
  }
}
