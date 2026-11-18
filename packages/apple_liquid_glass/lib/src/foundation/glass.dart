import 'package:apple_liquid_glass/src/foundation/frame.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The glass a surface is made of: regular or clear, and an optional tint.
///
/// UIKit: `UIGlassEffect`. SwiftUI: `Glass`. A prominent button is glass
/// with a [tint].
@immutable
final class Glass {
  /// The regular glass, the one bars, buttons and menus use, filled with
  /// [tint] when given.
  const Glass.regular({this.tint}) : isClear = false;

  /// The clear glass, for surfaces over rich media: it passes the backdrop
  /// through almost untouched, so its content needs contrast of its own.
  /// Filled with [tint] when given.
  const Glass.clear({this.tint}) : isClear = true;

  /// The color the glass is filled with, or null for untinted glass.
  final Color? tint;

  /// Whether this is the clear glass.
  final bool isClear;

  @override
  bool operator ==(Object other) =>
      other is Glass && other.isClear == isClear && other.tint == tint;

  @override
  int get hashCode => Object.hash(isClear, tint);
}

/// The UIKit glass family a surface belongs to.
///
/// Renderers read it to give each family its look (fill, shadow).
enum GlassRole {
  /// A tab bar, toolbar or navigation bar platter.
  bar,

  /// A button or another free-standing control.
  control,

  /// A card that floats over the page: a menu, popover, alert or sheet.
  panel,

  /// A selection that slides over its control, or a knob or thumb that
  /// lifts into a clear lens under the finger.
  lens,

  /// A plain fill that draws no glass: a switch's or segmented control's
  /// track, a slider's track and fill, a disabled search field.
  track,
}

/// What a lens body ([GlassRole.lens]) asks of the glass it lifts into,
/// beyond its frames: how its glass shows what lies under it, as the
/// control that owns the lens measured it.
///
/// A lifted lens pulls in what lies just outside it, so the edges of the
/// track or bar under it show inside it with the page between them and the
/// rim, while its middle shows what lies under it in place. A renderer that
/// draws no such glass ignores it.
@immutable
final class GlassLens {
  /// Describes a lens; the defaults pull nothing and lift a large lens.
  const GlassLens({
    this.pull = 0,
    this.pullHeight = 0,
    this.small = false,
    this.restingShadow,
  });

  /// UIKit's lifted lens (read from UIKit on iOS 27.2, notes private): it
  /// reads what lies under it 9 pt outside itself at its edge, falling
  /// along a quarter circle over 36 pt.
  const GlassLens.lifted({this.small = false, this.restingShadow})
    : pull = 9,
      pullHeight = 36;

  /// How far outside itself the glass of a fully lifted lens reads what
  /// lies under it at its edge, in logical pixels; the pull falls along a
  /// quarter circle to nothing [pullHeight] from the edge. 0 pulls nothing.
  final double pull;

  /// How deep from the edge [pull] reaches, in logical pixels.
  final double pullHeight;

  /// Whether the lens is a small one, a knob or a thumb, whose glass bends
  /// and frosts what lies under it strongly at rest and lifts clear; a
  /// large lens, a selection, rests clear.
  final bool small;

  /// The shadow the lens casts at rest, as its control measured it, or
  /// null for none.
  ///
  /// A renderer whose resting lens is a platter draws it outside the
  /// platter, and lets it darken and spread as the lens lifts until glass
  /// covers it. Its blur is [BoxShadow.blurSigma].
  final BoxShadow? restingShadow;

  @override
  bool operator ==(Object other) =>
      other is GlassLens &&
      other.pull == pull &&
      other.pullHeight == pullHeight &&
      other.small == small &&
      other.restingShadow == restingShadow;

  @override
  int get hashCode => Object.hash(pull, pullHeight, small, restingShadow);
}

/// How the renderer of a lens body ([GlassRole.lens]) shows what its
/// control draws over the lens: the selected look of the items under it.
///
/// UIKit draws what a lifted lens selects over the lens's glass and bends
/// it at the rim by a law of its own, apart from the bend of the glass. A
/// renderer whose lens does the same gives the control one of these
/// (`GlassSurfaceDetails.lensContent`), and the control paints its
/// selected content through it; without one the control paints the
/// content as it is.
abstract interface class GlassLensContent {
  /// Paints what [content] paints as the lens of [frame], drawn in a box
  /// of [size] at [offset], shows it; a resting lens shows it as it is.
  ///
  /// The control calls this every time it paints its selected content,
  /// lifted or not. [content] paints in the coordinates of [offset],
  /// already clipped to the lens, and may run into another context than
  /// [context].
  void paint(
    PaintingContext context,
    Offset offset, {
    required GlassFrame frame,
    required Size size,
    required PaintingContextCallback content,
  });
}
