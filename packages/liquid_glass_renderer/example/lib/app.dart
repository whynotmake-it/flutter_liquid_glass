import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer_example/loupe/liquid_glass_loupe.dart';
import 'package:liquid_glass_renderer_example/performance_probe.dart';
import 'package:liquid_glass_renderer_example/playground/backdrops.dart';
import 'package:liquid_glass_renderer_example/playground/playground_state.dart';
import 'package:liquid_glass_renderer_example/playground/settings_sheet.dart';
import 'package:liquid_glass_renderer_example/playground/sheet_avoidance.dart';
import 'package:liquid_glass_renderer_example/playground/stage.dart';

const _enablePerformanceProbe = bool.fromEnvironment(
  'LIQUID_GLASS_EXAMPLE_PERFORMANCE_PROBE',
);

/// The Liquid Glass playground.
///
/// The app follows the brightness chosen in the inspector, which starts at
/// the platform brightness.
class PlaygroundApp extends StatefulWidget {
  const PlaygroundApp({super.key});

  @override
  State<PlaygroundApp> createState() => _PlaygroundAppState();
}

class _PlaygroundAppState extends State<PlaygroundApp> {
  late final PlaygroundState _state = PlaygroundState(
    brightness: WidgetsBinding.instance.platformDispatcher.platformBrightness,
  );
  late final _brightness = _state.material.select(
    (material) => material.brightness,
  );

  @override
  void dispose() {
    _brightness.dispose();
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _brightness,
      builder: (context, brightness, home) => CupertinoApp(
        debugShowCheckedModeBanner: false,
        title: 'Liquid Glass',
        theme: CupertinoThemeData(brightness: brightness),
        // Shown in every build mode, unlike the checked-mode banner, so a
        // device build is never mistaken for a release of the example.
        builder: (context, child) => Banner(
          message: 'DEBUG',
          location: BannerLocation.topEnd,
          child: child,
        ),
        home: home,
      ),
      child: Playground(state: _state),
    );
  }
}

/// The stage over a backdrop, filling the screen. The settings button in the
/// stage's top controls toggles the settings sheet, which the stage content
/// makes room for while the backdrop stays in place behind it.
class Playground extends StatefulWidget {
  const Playground({required this.state, super.key});

  final PlaygroundState state;

  @override
  State<Playground> createState() => _PlaygroundState();
}

class _PlaygroundState extends State<Playground> {
  var _precached = false;
  SettingsSheetRoute? _settings;

  /// Follows the open settings sheet's position until its route has
  /// finished closing.
  final _sheetPosition = ProxyAnimation(kAlwaysDismissedAnimation);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    for (final asset in backdropPhotos) {
      precacheImage(AssetImage(asset), context);
    }
  }

  void _toggleSettings() {
    final navigator = Navigator.of(context);
    if (_settings case final open?) {
      if (open.isCurrent) navigator.pop();
      return;
    }
    final route = _settings = SettingsSheetRoute(state: widget.state);
    navigator.push(route).whenComplete(() {
      if (_settings == route) _settings = null;
    });
    final position = route.animation!;
    _sheetPosition.parent = position;
    void release(AnimationStatus status) {
      if (!status.isDismissed) return;
      position.removeStatusListener(release);
      if (_sheetPosition.parent == position) {
        _sheetPosition.parent = kAlwaysDismissedAnimation;
      }
    }

    position.addStatusListener(release);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return CupertinoPageScaffold(
      child: Stack(
        children: [
          Positioned.fill(
            child: LiquidGlassLoupeSource(
              link: state.loupeLink,
              child: BackdropPager(backdrop: state.backdrop),
            ),
          ),
          Positioned.fill(
            // The bottom bar sits inside the home indicator's inset, as on
            // iOS; see ControlsScene.
            child: SafeArea(
              bottom: false,
              child: SheetAvoidance(
                position: _sheetPosition,
                coverage: SettingsSheetRoute.coverage(
                  MediaQuery.sizeOf(context),
                  MediaQuery.paddingOf(context).copyWith(bottom: 0),
                ),
                child: RepaintBoundary(
                  child: Stage(state: state, onSettings: _toggleSettings),
                ),
              ),
            ),
          ),
          if (_enablePerformanceProbe) const PerformanceProbe(),
        ],
      ),
    );
  }
}
