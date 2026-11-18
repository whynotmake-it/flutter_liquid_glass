import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/full_glass.dart';

/// Loads and compiles every shader the renderer can use on this platform.
///
/// Shaders otherwise load on first use, so the first glass on screen paints
/// its fallback for a frame or two: fake glass without its surface shader,
/// real glass as fake glass. Glass layers mounted after the returned future
/// completes render real glass from their first frame.
///
/// This can be awaited before `runApp`, including on Android: loading GPU
/// resources does not depend on rendering a frame. Acquiring the engine's
/// GPU context may add startup time.
///
/// The first glass frame still creates its GPU pipelines, which stalls it
/// on a mid-range Android phone when none are cached. With [warmUp] the
/// precache draws the shaders, backdrop filters and shadows of glass
/// layers and fake glass once, offscreen, so that frame finds their
/// pipelines created. Pipelines are cached on disk, so this
/// spares only the first launch after an install or a cleared cache, while
/// the offscreen draws cost every launch: it is off by default.
///
/// Failures are reported through [FlutterError] and never thrown, and
/// leave glass layers drawing fake glass.
///
/// The returned [LiquidGlassSupport] is the one [liquidGlassSupport] settles
/// on. A later call loads nothing new, and draws the warm-up only if no
/// earlier call did.
Future<LiquidGlassSupport> precacheLiquidGlass({bool warmUp = false}) =>
    FullGlass.precache(warmUp: warmUp);

/// Whether full glass draws on this device and on what GPU, for code that
/// chooses a cheaper look itself: [LiquidGlassSupport.pending] until
/// [precacheLiquidGlass] or the first glass layer has loaded full glass,
/// then what loading found, for the life of the process.
///
/// Where the engine draws no shader filters, as on Skia and the web, it
/// says so from the start.
final ValueListenable<LiquidGlassSupport> liquidGlassSupport = _Support();

/// Makes [liquidGlassSupport], and every glass layer, act as if loading full
/// glass had found [support], for a test: [LiquidGlassSupport.pending]
/// forgets what was found until full glass loads again, a
/// [LiquidGlassSupport.unavailable] holds until the next call, and null gives
/// back what loading found. A load under way when it is called leaves what
/// it says.
///
/// Only a load makes full glass draw: a [LiquidGlassSupport.available]
/// throws an [ArgumentError].
@visibleForTesting
void debugOverrideLiquidGlassSupport(LiquidGlassSupport? support) =>
    FullGlass.debugOverride(support);

final class _Support implements ValueListenable<LiquidGlassSupport> {
  @override
  LiquidGlassSupport get value => FullGlass.state.value.support;

  @override
  void addListener(VoidCallback listener) =>
      FullGlass.state.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      FullGlass.state.removeListener(listener);
}
