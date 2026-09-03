import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/pages/lens_page.dart';
import 'package:liquid_glass_renderer_example/pages/playground_page.dart';
import 'package:liquid_glass_renderer_example/pages/showcase_page.dart';
import 'package:liquid_glass_renderer_example/preset_store.dart';
import 'package:liquid_glass_renderer_example/state.dart';
import 'package:liquid_glass_renderer_example/widgets/backgrounds.dart';
import 'package:liquid_glass_renderer_example/widgets/bottom_bar.dart';

const _enablePerformanceProbe = bool.fromEnvironment(
  'LIQUID_GLASS_EXAMPLE_PERFORMANCE_PROBE',
);

/// The example workbench.
///
/// One [LiquidGlassLayer] wraps every page and the bottom bar, so all chrome
/// and showcase shapes share a single backdrop sample. Glass that sits on top
/// of other glass (slider thumbs, the selection lens, the loupe) creates small
/// nested layers that join the shared backdrop group instead of capturing
/// their own backdrop.
class GlassWorkbench extends HookWidget {
  const GlassWorkbench({super.key});

  @override
  Widget build(BuildContext context) {
    final tab = useState(0);
    final brightness = MediaQuery.platformBrightnessOf(context);

    useEffect(() {
      PresetStore().seed();
      return null;
    }, const []);

    useEffect(() {
      settingsNotifier.value = exampleDefaultGlassSettingsForBrightness(
        brightness,
      );
      appearanceNotifier.value = exampleDefaultAppearanceFor(brightness);
      return null;
    }, [brightness]);

    final page = switch (tab.value) {
      1 => const PlaygroundPage(),
      2 => const LensPage(),
      _ => const ShowcasePage(),
    };

    return Stack(
      children: [
        Positioned.fill(
          child: ValueListenableBuilder<String>(
            valueListenable: backgroundNotifier,
            builder: (context, background, _) => switch (background) {
              'black' => const SolidBackdrop(color: Color(0xff000000)),
              'white' => const SolidBackdrop(color: Color(0xffffffff)),
              'grid' => const Grid(),
              _ => const WallPaper(),
            },
          ),
        ),
        // Keep the scrolling page and the fixed chrome in separate retained
        // layers. A nested lens (and a moving page surface) must never be
        // able to invalidate or occlude the bottom bar's compositor layer.
        // Both layers still share BackdropGroup's capture, so this is not a
        // second full-screen backdrop read.
        ListenableBuilder(
          listenable: Listenable.merge([
            settingsNotifier,
            appearanceNotifier,
            fakeNotifier,
            backgroundRevisionNotifier,
          ]),
          builder: (context, _) {
            final bottomChromeExtent =
                104.0 + MediaQuery.paddingOf(context).bottom;
            return Stack(
              children: [
                Positioned.fill(
                  bottom: bottomChromeExtent,
                  child: LiquidGlassLayer(
                    key: ValueKey('glass-layer-0-${tab.value}'),
                    settings: settingsNotifier.value,
                    defaultAppearance: appearanceNotifier.value,
                    fake: fakeNotifier.value,
                    useBackdropGroup: true,
                    child: KeyedSubtree(
                      key: ValueKey('workbench-page-${tab.value}'),
                      child: page,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: SafeArea(
                    bottom: false,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: LiquidGlassLayer(
                        defaultAppearance: .ios27Toolbar(
                          brightness: brightness,
                        ),
                        fake: fakeNotifier.value,
                        // The chrome owns its filter boundary. Sharing the
                        // backdrop key with moving page glass lets a retained
                        // page texture contaminate the bar during scroll.
                        child: LiquidGlassBottomBar(
                          fake: fakeNotifier.value,
                          tabs: const [
                            LiquidGlassBottomBarTab(
                              label: 'Showcase',
                              icon: CupertinoIcons.square_grid_2x2,
                            ),
                            LiquidGlassBottomBarTab(
                              label: 'Playground',
                              icon: CupertinoIcons.slider_horizontal_3,
                            ),
                            LiquidGlassBottomBarTab(
                              label: 'Lens',
                              icon: CupertinoIcons.search,
                            ),
                          ],
                          selectedIndex: tab.value,
                          onTabSelected: (index) => tab.value = index,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        if (_enablePerformanceProbe) const WorkbenchPerformanceProbe(),
      ],
    );
  }
}

/// Frames-timing probe used by performance audits. Enabled with
/// `--dart-define=LIQUID_GLASS_EXAMPLE_PERFORMANCE_PROBE=true`.
class WorkbenchPerformanceProbe extends StatefulWidget {
  const WorkbenchPerformanceProbe({super.key});

  @override
  State<WorkbenchPerformanceProbe> createState() =>
      _WorkbenchPerformanceProbeState();
}

class _WorkbenchPerformanceProbeState extends State<WorkbenchPerformanceProbe> {
  final _timings = <FrameTiming>[];
  Timer? _timer;
  var _window = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_collect);
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _flush());
  }

  @override
  void dispose() {
    _timer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_collect);
    _flush();
    super.dispose();
  }

  void _collect(List<FrameTiming> timings) => _timings.addAll(timings);

  void _flush() {
    final timings = List<FrameTiming>.of(_timings);
    _timings.clear();
    if (timings.isEmpty) return;
    _window += 1;
    debugPrint(
      'LIQUID_GLASS_WORKBENCH_WINDOW:${jsonEncode(<String, Object?>{
        'window': _window,
        'frameCount': timings.length,
        'buildP95Micros': _framePercentile(
          timings,
          .95,
          (timing) => timing.buildDuration,
        ),
        'rasterP50Micros': _framePercentile(
          timings,
          .5,
          (timing) => timing.rasterDuration,
        ),
        'rasterP95Micros': _framePercentile(
          timings,
          .95,
          (timing) => timing.rasterDuration,
        ),
      })}',
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

int _framePercentile(
  List<FrameTiming> timings,
  double percentile,
  Duration Function(FrameTiming timing) select,
) {
  final values =
      timings
          .map((timing) => select(timing).inMicroseconds)
          .toList(growable: false)
        ..sort();
  return values[((values.length - 1) * percentile).round()];
}
