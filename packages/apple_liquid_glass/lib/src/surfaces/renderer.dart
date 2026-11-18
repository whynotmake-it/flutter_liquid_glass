import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/surfaces/group.dart';
import 'package:apple_liquid_glass/src/surfaces/highlight.dart';
import 'package:apple_liquid_glass/src/surfaces/scroll_edge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';

/// How every glass surface is drawn: real glass, fake glass, one flat look
/// or an app's own, chosen by the app or its user in a `GlassRendererScope`
/// and switchable at any time.
///
/// The package draws with `FlatGlassRenderer` (this library) and with
/// `LiquidGlassRenderer`, `FakeGlassRenderer` and `AdaptiveGlassRenderer`
/// (the `liquid` library). An app's own renderer extends this class with
/// public API only: [GlassSurfaceDetails] says what to draw; a frame's
/// [GlassFrame.bodyIn] gives its [GlassBody], where the body and its
/// content go and its edge, drawn in the body's own coordinates under
/// [GlassBody.paintIn]; [GlassFrame.glassnessAt] says how far a lens has
/// turned into glass.
///
/// A renderer builds a surface when the surface's widget rebuilds; frames
/// reach what it built through [GlassSurfaceDetails.frame], followed below
/// build, so a moving control rebuilds nothing per frame. Controls above
/// the surfaces keep their state across a switch, even mid-press.
@immutable
abstract class GlassRenderer {
  /// Creates a renderer.
  const GlassRenderer();

  /// Builds the surface [details] describes.
  Widget buildSurface(BuildContext context, GlassSurfaceDetails details);

  /// Draws the focus ring and hover response of the surface [details]
  /// describes over its [body], the widget [buildSurface] built for it.
  ///
  /// By default a body whose [GlassSurfaceDetails.states] hold
  /// [WidgetState.focused] gets Flutter's Cupertino focus ring outside its
  /// shape, following its frame as it moves, lifts and stretches, and one
  /// that holds [WidgetState.hovered] a pressed glass's wash at half
  /// strength, eased in and out on a spring and switched without motion
  /// under Reduce Motion. Both are plain painting over the body, so they
  /// cost the glass no pass, and both are approximations of the platform
  /// pending a measurement. The package's renderers call it from
  /// [buildSurface]; a renderer of its own calls it too, or draws its own.
  Widget buildHighlights(
    BuildContext context,
    GlassSurfaceDetails details,
    Widget body,
  ) => GlassHighlightBox.around(context, details, body);

  /// Builds a group of surfaces that belong together; by default the
  /// surfaces are drawn on their own.
  Widget buildGroup(BuildContext context, GlassGroupDetails details) =>
      details.child;

  /// Builds the scroll edge effect [details] describes, laid out over the
  /// whole scroll view; by default the flat renderer's, where the content
  /// under it dissolves toward the background without a blur.
  Widget buildScrollEdge(
    BuildContext context,
    GlassScrollEdgeDetails details,
  ) => FlatScrollEdge(details: details);
}

/// What a renderer needs to build one surface.
@immutable
final class GlassSurfaceDetails {
  /// Describes a surface whose body follows [frame].
  GlassSurfaceDetails({
    required this.role,
    required this.glass,
    required ValueListenable<GlassFrame> frame,
    required this.child,
    this.lens = const GlassLens(),
    this.states,
    this.focusColor,
    this.hoverColor,
    this.lensContent,
  }) : frame = frame is _SameFrame ? frame : _SameFrame(frame);

  /// The glass family of the surface.
  final GlassRole role;

  /// What a [GlassRole.lens] body asks of its glass; other roles ignore
  /// it.
  final GlassLens lens;

  /// The glass it is made of.
  final Glass glass;

  /// Its frames; a renderer follows them below build rather than rebuilding
  /// per frame.
  ///
  /// A listener added here hears every frame in the frame that publishes
  /// it, before that frame paints: also one the frame's resolve phase
  /// publishes after layout. So a render object that listens and marks
  /// paint, composited layers or layout draws each frame in the same frame,
  /// never one late; what it marks for layout from the resolve phase is
  /// laid out again in that frame. A listener only marks; it does not
  /// rebuild. Two details over the same frames hold equal listenables.
  final ValueListenable<GlassFrame> frame;

  /// The content drawn over the body, clipped to it.
  final Widget child;

  /// The states of the control the body belongs to, or null for a body
  /// that shows neither focus nor hover; a renderer follows them below
  /// build.
  ///
  /// [WidgetState.focused] is in them only while the keyboard focus should
  /// show, so a tap that focuses the control lights nothing, and
  /// [WidgetState.hovered] only while a mouse is over it. A renderer draws
  /// a focus ring outside the body's shape, where the frame draws it, and
  /// a hover response over the body; the package's renderers draw
  /// Flutter's Cupertino ring and a pressed body's wash at half strength.
  final ValueListenable<Set<WidgetState>>? states;

  /// The color of the focus ring, resolved, or null for the renderer's:
  /// the package's derive it from the glass's tint, as Cupertino does. A
  /// transparent color draws no ring.
  final Color? focusColor;

  /// The color the hover response adds to the body, resolved, or null for
  /// the renderer's. A transparent color shows no hover response.
  final Color? hoverColor;

  /// Where a renderer that draws a [GlassRole.lens] body writes how its
  /// lens shows the content the control draws over it, or null when the
  /// control draws none.
  ///
  /// A renderer whose lifted lens bends what it selects writes its
  /// [GlassLensContent] while it draws the body and null when it stops;
  /// one that shows the content as it is leaves the notifier alone.
  final ValueNotifier<GlassLensContent?>? lensContent;
}

/// What a renderer needs to build a group of surfaces.
@immutable
final class GlassGroupDetails {
  /// Describes a group.
  const GlassGroupDetails({required this.merge, required this.child});

  /// How the members fuse.
  final GlassMerge merge;

  /// The subtree holding the members.
  final Widget child;
}

/// What a renderer needs to draw one scroll edge effect: the band where a
/// scroll view's content passes under a bar.
///
/// UIKit: `UIScrollEdgeEffect`. SwiftUI: `scrollEdgeEffectStyle`.
@immutable
final class GlassScrollEdgeDetails {
  /// Describes an edge effect.
  const GlassScrollEdgeDetails({
    required this.edge,
    required this.hard,
    required this.extent,
    required this.presence,
    required this.background,
  }) : assert(
         edge == AxisDirection.up || edge == AxisDirection.down,
         'Only the top and bottom edges have an effect.',
       );

  /// The edge: [AxisDirection.up] under a navigation bar,
  /// [AxisDirection.down] over a toolbar.
  final AxisDirection edge;

  /// Whether the effect is UIKit's hard one, the thin film of a navigation
  /// bar: a blur with raised saturation and brightness over the bar's own
  /// band, a uniform fade toward [background] and a hairline at the bar's
  /// edge. Otherwise it is the soft one: a light blur over a band that
  /// reaches 40 points past the bar, with a fade that dissolves along it.
  final bool hard;

  /// The distance from the scroll view's edge to the bar's far edge.
  final double extent;

  /// How present the effect is, 0 to 1; a renderer follows it below build.
  final ValueListenable<double> presence;

  /// What lies behind the content, resolved: the color the content fades
  /// toward under the bar.
  final Color background;

  @override
  bool operator ==(Object other) =>
      other is GlassScrollEdgeDetails &&
      other.edge == edge &&
      other.hard == hard &&
      other.extent == extent &&
      other.presence == presence &&
      other.background == background;

  @override
  int get hashCode => Object.hash(edge, hard, extent, presence, background);
}

// Wraps a surface's frames once, so every renderer listens to them in the
// frame's resolve phase too.
@immutable
final class _SameFrame implements ValueListenable<GlassFrame> {
  const _SameFrame(this.source);

  final ValueListenable<GlassFrame> source;

  @override
  GlassFrame get value => source.value;

  @override
  void addListener(VoidCallback listener) => source.addRenderListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      source.removeRenderListener(listener);

  @override
  bool operator ==(Object other) =>
      other is _SameFrame && other.source == source;

  @override
  int get hashCode => source.hashCode;
}
