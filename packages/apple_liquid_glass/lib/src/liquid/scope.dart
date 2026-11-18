import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/liquid/adaptive.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';

/// The root of an app's glass: the theme of every control below, the
/// renderer that draws its glass, and the rate the app draws frames at.
///
/// Put one above the app's navigator, usually in `WidgetsApp.builder`, so
/// that alerts, sheets and pages pushed on that navigator sit under it
/// too. [data] sets the theme: brightness, colors and the controls'
/// styles. [renderer] picks how the glass draws, and an app that lets its
/// users choose passes their choice here; it switches at any time, and the
/// controls keep their state. Awaiting [precacheGlass] before `runApp`
/// lets the default renderer draw its pick for the device from the first
/// glass frame on.
///
/// ```dart
/// void main() {
///   runApp(
///     WidgetsApp(
///       color: const Color(0xFF007AFF),
///       pageRouteBuilder: <T>(settings, builder) =>
///           GlassPageRoute<T>(settings: settings, builder: builder),
///       builder: (context, child) => GlassScope(child: child!),
///       home: const Center(child: Text('Hello')),
///     ),
///   );
/// }
/// ```
///
/// By default the glass draws with [AdaptiveGlassRenderer]: liquid glass
/// where the device draws it well, fake glass (blurred and lit, without
/// bending) elsewhere and on the web. [FlatGlassRenderer] draws a fill per
/// role with no backdrop reads. Without a `GlassScope` or a
/// [GlassRendererScope] above, controls draw flat, as under
/// [FlatGlassRenderer], with the default [GlassThemeData].
///
/// When [data] changes, the theme moves to it on [themeSpring] as
/// [GlassThemeData.lerp] interpolates (Flutter: the `AnimatedTheme` of
/// `MaterialApp`); under Reduce Motion it switches at once. While it moves,
/// a widget that reads a part of the theme that differs between the two
/// rebuilds every frame; at rest the theme is [data] exactly.
///
/// The outermost scope starts `FrameCadence`, which on a fast display draws
/// about 60 frames a second while nothing fast moves, and reports it the
/// scrolls below the scope. A scroll outside any scope stays at the lower
/// rate.
///
/// A subtree takes another theme from a [GlassTheme], or another renderer
/// from a [GlassRendererScope].
///
/// Fidelity. Under Reduce Transparency the liquid and fake renderers draw
/// flat, a stand-in for iOS's frosted glass that is not measured.
class GlassScope extends StatefulWidget {
  /// Applies [data] and [renderer] to [child].
  const GlassScope({
    required this.child,
    this.data = const GlassThemeData(),
    this.renderer = const AdaptiveGlassRenderer(),
    this.themeSpring = Spring.smooth,
    super.key,
  });

  /// The theme of the controls below.
  final GlassThemeData data;

  /// The renderer that draws the glass below.
  final GlassRenderer renderer;

  /// The spring the theme moves on when [data] changes.
  final Spring themeSpring;

  /// The subtree the theme and renderer apply to.
  final Widget child;

  @override
  State<GlassScope> createState() => _GlassScopeState();
}

class _GlassScopeState extends State<GlassScope> {
  // The double converter's rest distance is a pixel's; this runs 0 to 1.
  final _progress = MotionValue<double>(1, restDistance: 0.002);
  late GlassThemeData _from = widget.data;

  GlassThemeData get _shown =>
      GlassThemeData.lerp(_from, widget.data, _progress.value.clamp(0, 1));

  bool get _outermost =>
      context.getInheritedWidgetOfExactType<_Scoped>() == null;

  @override
  void initState() {
    super.initState();
    if (_outermost) FrameCadence.instance.start();
  }

  @override
  void didUpdateWidget(GlassScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data == widget.data) return;
    _from = GlassThemeData.lerp(
      _from,
      oldWidget.data,
      _progress.value.clamp(0, 1),
    );
    final now = _progress.clock.now;
    if (GlassTraits.of(context).reduceMotion) {
      _progress.snap(now, 1);
      return;
    }
    _progress.snap(now, 0);
    withSpring(widget.themeSpring, () => _progress.target = 1);
  }

  @override
  Widget build(BuildContext context) {
    Widget child = _Scoped(child: widget.child);
    if (_outermost) {
      child = NotificationListener<ScrollUpdateNotification>(
        onNotification: (notification) {
          if (notification.scrollDelta case final delta?) {
            FrameCadence.instance.scrolled(
              delta,
              notification.metrics.devicePixelRatio,
            );
          }
          return false;
        },
        child: child,
      );
    }
    return GlassRendererScope(
      renderer: widget.renderer,
      child: ListenableBuilder(
        listenable: _progress,
        builder: (context, child) => GlassTheme(data: _shown, child: child!),
        child: child,
      ),
    );
  }
}

// Marks a scope's subtree, so that a nested scope leaves the scrolls to the
// outermost one and each reaches the frame cadence once.
class _Scoped extends InheritedWidget {
  const _Scoped({required super.child});

  @override
  bool updateShouldNotify(_Scoped oldWidget) => false;
}
