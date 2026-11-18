import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/liquid/lens_shadows.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/rendering.dart';

/// How a lifted lens shows what it selects, as iOS 27 does.
///
/// Read from UIKit's lifted tab bar and segmented control lenses on iOS
/// 27.2 (notes private). UIKit draws the selected look of the items over
/// the lens's glass and moves it away from the rim twice, each time along
/// a quarter circle that is strongest at the rim: first by the bend the
/// lens gives its content, 0.2 of its height over 0.16 of it
/// ([LensShadowLaw.contentBend]), then by the bend the lift adds,
/// [liftBend] over [liftBendHeight] on every lens. So the rim of a tab
/// bar's lens shows what lies 14 points inside it, 4.2 points deep shows
/// what lies 8.4 points deep, the nearest to the rim that ever shows, and
/// from 11.2 points deep everything shows in place. Both bends grow with
/// the lift.
///
/// What the bends show is parted with the glass under it: the lens parts
/// the colors of everything inside its rim by one law, [parting] at the rim
/// fading to nothing [partingDepth] deep, so a label that reaches the rim
/// spreads into its colors there the way the page behind the glass does.
@internal
abstract final class LensContentLaw {
  /// How far the lift moves the content away from the rim, at the rim.
  static const double liftBend = 17.5;

  /// How deep from the rim [liftBend] reaches.
  static const double liftBendHeight = 11.2;

  /// The bends of a lens of [height] across its short side lifted by
  /// [lift], from the one nearest the eye.
  static List<LiquidGlassContentBend> bends(double height, {double lift = 1}) {
    return [
      LensShadowLaw.contentBend(height, small: false, lift: lift),
      LiquidGlassContentBend(amount: liftBend * lift, height: liftBendHeight),
    ];
  }

  /// How far a lens of [height] across its short side, lifted by [lift],
  /// parts colors at its rim, in points: 1 / 19 of the height.
  static double parting(double height, {double lift = 1}) => height / 19 * lift;

  /// How deep from the rim of a lens of [height] across its short side its
  /// parting fades to nothing: 0.2 of the height.
  static double partingDepth(double height) => 0.2 * height;

  /// How deep from the rim lies what a lens of [height] across its short
  /// side, lifted by [lift], shows [depth] from its rim.
  static double shownDepth(
    double depth, {
    required double height,
    double lift = 1,
  }) {
    var shown = depth;
    for (final bend in bends(height, lift: lift)) {
      shown = bend.shownDepth(shown);
    }
    return shown;
  }
}

/// Shows the content a control draws over a lifted lens by
/// [LensContentLaw], through the renderer's [LiquidGlassBentContent]: one
/// offscreen pass the size of the lens while it is lifted, none at rest,
/// where the content is painted as it is.
///
/// Fidelity. The bend and the parting are UIKit's laws, NEAR: both follow
/// an outline with circular corners, and the content is parted in a
/// picture of its own, every color covering the glass by what its own
/// reads hold, where UIKit parts the content and the glass as one picture.
/// The two agree wherever the lens draws onto an opaque page; inside a
/// layer that holds nothing under the lens the content covers by its
/// widest color. NEAR: UIKit lays the rim's light and the inner shadow
/// over the content; here the content lies over them, which shows only
/// where content reaches the rim.
@internal
final class LensContentBend implements GlassLensContent {
  /// The device pixels per logical pixel the content is drawn at.
  double devicePixelRatio = 1;

  final _bent = LiquidGlassBentContent();

  /// Releases the last picture.
  void dispose() => _bent.dispose();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required GlassFrame frame,
    required Size size,
    required PaintingContextCallback content,
  }) {
    final placed = frame.bodyIn(size);
    final body = placed.drawnRect;
    if (frame.lift <= GlassFrame.restingLift ||
        frame.outline != null ||
        body.isEmpty) {
      // A resting lens keeps no picture.
      _bent.dispose();
      return content(context, offset);
    }
    final lift = frame.lift.clamp(0.0, 1.0);
    final drawn = body.shift(offset);
    _bent.paint(
      context,
      offset,
      rect: drawn,
      radius: placed.drawnRadius,
      clip: placed.edgeInBox.shift(offset),
      bends: LensContentLaw.bends(body.shortestSide, lift: lift),
      aberration: LensContentLaw.parting(body.shortestSide, lift: lift),
      aberrationDepth: LensContentLaw.partingDepth(body.shortestSide),
      devicePixelRatio: devicePixelRatio,
      content: content,
    );
  }
}
