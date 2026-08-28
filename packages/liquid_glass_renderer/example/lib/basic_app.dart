import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/preset_store.dart';
import 'package:liquid_glass_renderer_example/shared.dart';
import 'package:liquid_glass_renderer_example/widgets/bottom_bar.dart';
import 'package:liquid_glass_renderer_example/widgets/settings_split_scaffold.dart';
import 'package:rivership/rivership.dart';

void main() {
  runApp(const CupertinoApp(home: BasicApp()));
}

const _useTestBackground = bool.fromEnvironment(
  'LIQUID_GLASS_EXAMPLE_TEST_BACKGROUND',
);
const _testBlur = int.fromEnvironment(
  'LIQUID_GLASS_EXAMPLE_TEST_BLUR',
);
const _enablePerformanceProbe = bool.fromEnvironment(
  'LIQUID_GLASS_EXAMPLE_PERFORMANCE_PROBE',
);
const _testBackgroundColors = [
  Color(0xffff595e),
  Color(0xff8ac926),
  Color(0xff1982c4),
  Color(0xffc77dff),
  Color(0xffffca3a),
  Color(0xff00c2d1),
];

/// Start from the fitted toolbar material. Frost-free glass is reserved for
/// the explicit clear-glass/loupe examples.
const exampleDefaultGlassSettings = LiquidGlassSettings.ios27ToolbarLight();

LiquidGlassSettings exampleDefaultGlassSettingsForBrightness(
  Brightness brightness,
) {
  final settings = LiquidGlassSettings.ios27Toolbar(brightness: brightness);
  return _useTestBackground
      ? settings.copyWith(frost: _testBlur.toDouble())
      : settings;
}

final settingsNotifier = ValueNotifier(
  exampleDefaultGlassSettingsForBrightness(Brightness.light),
);

final blendNotifier = ValueNotifier<double>(10);

class BasicApp extends HookWidget {
  const BasicApp({super.key, this.backgroundOverride});

  /// Optional deterministic background used by widget tests and screenshot
  /// harnesses without changing the normal image-first example.
  final String? backgroundOverride;

  @override
  Widget build(BuildContext context) {
    final tab = useState(0);
    final fake = useState(false);
    final showSettings = useState(false);
    final outerShadowAlpha = useState(.03);
    final background = useState(
      backgroundOverride ?? (_useTestBackground ? 'grid' : 'image'),
    );
    useEffect(() {
      PresetStore().seed();
      return null;
    }, const []);
    final brightness = MediaQuery.platformBrightnessOf(context);
    useEffect(() {
      settingsNotifier.value = exampleDefaultGlassSettingsForBrightness(
        brightness,
      );
      return null;
    }, [brightness]);

    final visibility = useState(true);
    final visibilityValue = useSingleMotion(
      value: visibility.value ? 1.0 : 0.0,
      motion: const Motion.smoothSpring(),
    );

    final shadows = outerShadowAlpha.value <= 0
        ? const <BoxShadow>[]
        : <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: outerShadowAlpha.value),
              offset: const Offset(0, 6),
              blurRadius: 12,
              spreadRadius: -1,
            ),
          ];

    final content = Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => Stack(
                  children: [
                    Positioned.fill(
                      child: background.value == 'black'
                          ? const ColoredBox(color: Colors.black)
                          : background.value == 'white'
                          ? const ColoredBox(color: Colors.white)
                          : background.value == 'grid' || _useTestBackground
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    _testBackgroundColors[index %
                                        _testBackgroundColors.length],
                                    _testBackgroundColors[(index + 3) %
                                        _testBackgroundColors.length],
                                  ],
                                ),
                              ),
                              child: GridPaper(
                                color: index.isEven
                                    ? Colors.black87
                                    : Colors.white70,
                                interval: 32,
                                subdivisions: 1,
                              ),
                            )
                          : Image.network(
                              fit: BoxFit.cover,
                              'https://picsum.photos/500/500?random=$index',
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: CupertinoSwitch(
              value: fake.value,
              onChanged: (v) => fake.value = v,
            ),
          ),
        ),
        Center(
          child: ListenableBuilder(
            listenable: Listenable.merge([
              settingsNotifier,
              blendNotifier,
              outerShadowAlpha,
            ]),
            builder: (context, child) {
              final settings = settingsNotifier.value.copyWith(
                visibility: visibilityValue,
              );
              return LiquidGlassLayer(
                fake: fake.value,
                useBackdropGroup: true,
                settings: settings,
                child: LiquidGlassBlendGroup(
                  blend: blendNotifier.value,
                  child: Column(
                    spacing: 16,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 16,
                        children: [
                          GestureDetector(
                            onTap: () => visibility.value = !visibility.value,
                            child: LiquidStretch(
                              child: LiquidGlass.auto(
                                shadows: shadows,
                                shape: const LiquidRoundedSuperellipse(
                                  borderRadius: 20,
                                ),
                                child: const GlassGlow(
                                  child: SizedBox.square(
                                    dimension: 100,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          LiquidStretch(
                            child: LiquidGlass.auto(
                              shadows: shadows,
                              shape: const LiquidRoundedSuperellipse(
                                borderRadius: 20,
                              ),
                              child: GlassGlow(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  child: const SizedBox.square(
                                    dimension: 100,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      LiquidStretch(
                        child: LiquidGlass.auto(
                          shadows: shadows,
                          shape: const LiquidRoundedSuperellipse(
                            borderRadius: 9000,
                          ),
                          child: GlassGlow(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              child: const SizedBox(
                                width: 400,
                                height: 64,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ListenableBuilder(
              listenable: Listenable.merge([settingsNotifier, fake]),
              builder: (context, child) => LiquidGlassBottomBar(
                fake: fake.value,
                extraButton: LiquidGlassBottomBarExtraButton(
                  icon: CupertinoIcons.add_circled,
                  onTap: () {
                    Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (context) => const LoupeExamplePage(),
                      ),
                    );
                  },
                  label: '',
                  loupeMagnification: 1.1,
                ),
                tabs: const [
                  LiquidGlassBottomBarTab(
                    label: 'Home',
                    icon: CupertinoIcons.home,
                  ),
                  LiquidGlassBottomBarTab(
                    label: 'Profile',
                    icon: CupertinoIcons.person,
                  ),
                  LiquidGlassBottomBarTab(
                    label: 'Settings',
                    icon: CupertinoIcons.settings,
                  ),
                ],
                selectedIndex: tab.value,
                onTabSelected: (index) {
                  tab.value = index;
                },
              ),
            ),
          ),
        ),
        if (!showSettings.value)
          SafeArea(
            minimum: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.topRight,
              child: CupertinoButton.filled(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                onPressed: () => showSettings.value = true,
                child: const Text('Settings'),
              ),
            ),
          ),
        if (_enablePerformanceProbe)
          _BasicAppPerformanceProbe(fake: fake.value),
      ],
    );

    return CupertinoPageScaffold(
      child: SettingsSplitScaffold(
        open: showSettings.value,
        onOpenChanged: (value) => showSettings.value = value,
        panel: SettingsSheet(
          onClose: () => showSettings.value = false,
          blendNotifier: blendNotifier,
          settingsNotifier: settingsNotifier,
          outerShadowAlphaNotifier: outerShadowAlpha,
          fakeNotifier: fake,
          backgroundNotifier: background,
        ),
        child: content,
      ),
    );
  }
}

class _BasicAppPerformanceProbe extends StatefulWidget {
  const _BasicAppPerformanceProbe({required this.fake});

  final bool fake;

  @override
  State<_BasicAppPerformanceProbe> createState() =>
      _BasicAppPerformanceProbeState();
}

class _BasicAppPerformanceProbeState extends State<_BasicAppPerformanceProbe> {
  final _timings = <FrameTiming>[];
  Timer? _timer;
  var _window = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_collect);
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _flush());
    _logMode();
  }

  @override
  void didUpdateWidget(_BasicAppPerformanceProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fake == widget.fake) return;
    _flush();
    _window = 0;
    _logMode();
  }

  @override
  void dispose() {
    _timer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_collect);
    _flush();
    super.dispose();
  }

  void _collect(List<FrameTiming> timings) => _timings.addAll(timings);

  void _logMode() {
    debugPrint(
      'LIQUID_GLASS_BASIC_APP_MODE:${widget.fake ? 'fake' : 'real'}',
    );
  }

  void _flush() {
    final timings = List<FrameTiming>.of(_timings);
    _timings.clear();
    if (timings.isEmpty) return;
    _window += 1;
    debugPrint(
      'LIQUID_GLASS_BASIC_APP_WINDOW:${jsonEncode(<String, Object?>{
        'implementation': widget.fake ? 'fake' : 'real',
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
        'rasterP99Micros': _framePercentile(
          timings,
          .99,
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

class Blink extends StatelessWidget {
  const Blink({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SequenceMotionBuilder(
      converter: const SingleMotionConverter(),
      sequence: const StepSequence.withMotions([
        (0.0, Motion.linear(Duration(seconds: 1))),
        (1.0, Motion.linear(Duration(seconds: 1))),
        (1.0, Motion.linear(Duration(seconds: 1))),
      ], loop: LoopMode.loop),
      builder: (context, value, phase, child) =>
          Opacity(opacity: value, child: child),
      child: child,
    );
  }
}
