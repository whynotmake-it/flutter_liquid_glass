import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/performance_probe.dart';
import 'package:liquid_glass_renderer_example/playground/backdrops.dart';
import 'package:liquid_glass_renderer_example/playground/inspector/grouped_list.dart';
import 'package:liquid_glass_renderer_example/playground/inspector/inspector.dart';
import 'package:liquid_glass_renderer_example/playground/playground_state.dart';
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

/// The stage over a backdrop, with the inspector beside it on wide screens
/// and below it on phones.
class Playground extends StatefulWidget {
  const Playground({required this.state, super.key});

  final PlaygroundState state;

  static const wideBreakpoint = 760.0;
  static const _inspectorWidth = 380.0;
  static const _panelRadius = Radius.circular(panelRadius);

  @override
  State<Playground> createState() => _PlaygroundState();
}

class _PlaygroundState extends State<Playground> {
  var _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    for (final asset in backdropPhotos) {
      precacheImage(AssetImage(asset), context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final padding = MediaQuery.paddingOf(context);
    return CupertinoPageScaffold(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= Playground.wideBreakpoint;
          final stageHeight = (constraints.maxHeight * 0.5).clamp(
            380.0,
            560.0,
          );
          return Stack(
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
              if (wide) ...[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  right: Playground._inspectorWidth + 16,
                  child: SafeArea(
                    child: RepaintBoundary(child: Stage(state: state)),
                  ),
                ),
                Positioned(
                  top: padding.top + 16,
                  bottom: padding.bottom + 16,
                  right: padding.right + 16,
                  width: Playground._inspectorWidth,
                  child: _Panel(
                    borderRadius: const BorderRadius.all(
                      Playground._panelRadius,
                    ),
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      removeBottom: true,
                      child: Inspector(state: state),
                    ),
                  ),
                ),
              ] else ...[
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: stageHeight,
                  child: MediaQuery.removePadding(
                    context: context,
                    removeBottom: true,
                    child: SafeArea(
                      bottom: false,
                      child: RepaintBoundary(child: Stage(state: state)),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: stageHeight,
                  bottom: 0,
                  child: _Panel(
                    borderRadius: const BorderRadius.vertical(
                      top: Playground._panelRadius,
                    ),
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: Inspector(
                        state: state,
                        padding: EdgeInsets.only(bottom: padding.bottom),
                      ),
                    ),
                  ),
                ),
              ],
              if (_enablePerformanceProbe) const PerformanceProbe(),
            ],
          );
        },
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.borderRadius, required this.child});

  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(borderRadius: borderRadius),
          shadows: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 32,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRSuperellipse(
          borderRadius: borderRadius,
          child: ColoredBox(
            color: CupertinoColors.systemGroupedBackground.resolveFrom(context),
            child: child,
          ),
        ),
      ),
    );
  }
}
