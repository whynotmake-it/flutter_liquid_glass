import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/loupe/liquid_glass_loupe.dart';
import 'package:liquid_glass_renderer_example/performance_probe.dart';
import 'package:liquid_glass_renderer_example/playground/backdrops.dart';
import 'package:liquid_glass_renderer_example/playground/playground_state.dart';
import 'package:liquid_glass_renderer_example/playground/settings_sheet.dart';
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
        home: home,
      ),
      child: Playground(state: _state),
    );
  }
}

/// The stage over a backdrop, filling the screen. The settings button in the
/// stage's top controls toggles the settings sheet.
class Playground extends StatefulWidget {
  const Playground({required this.state, super.key});

  final PlaygroundState state;

  @override
  State<Playground> createState() => _PlaygroundState();
}

class _PlaygroundState extends State<Playground> {
  var _precached = false;
  SettingsSheetRoute? _settings;

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
    final route = _settings = SettingsSheetRoute(
      state: widget.state,
      wide: MediaQuery.sizeOf(context).width >= wideBreakpoint,
    );
    navigator.push(route).whenComplete(() {
      if (_settings == route) _settings = null;
    });
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
              child: LiquidGlassBrightnessBackdrop(
                source: state.brightnessSource,
                child: BackdropPager(backdrop: state.backdrop),
              ),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: RepaintBoundary(
                child: Stage(state: state, onSettings: _toggleSettings),
              ),
            ),
          ),
          if (_enablePerformanceProbe) const PerformanceProbe(),
        ],
      ),
    );
  }
}
