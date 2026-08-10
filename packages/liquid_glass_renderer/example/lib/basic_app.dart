import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/shared.dart';
import 'package:liquid_glass_renderer_example/widgets/bottom_bar.dart';
import 'package:rivership/rivership.dart';

void main() {
  runApp(CupertinoApp(home: BasicApp()));
}

const _useTestBackground = bool.fromEnvironment(
  'LIQUID_GLASS_EXAMPLE_TEST_BACKGROUND',
);
const _testBlur = int.fromEnvironment(
  'LIQUID_GLASS_EXAMPLE_TEST_BLUR',
  defaultValue: 0,
);
const _testBackgroundColors = [
  Color(0xffff595e),
  Color(0xff8ac926),
  Color(0xff1982c4),
  Color(0xffc77dff),
  Color(0xffffca3a),
  Color(0xff00c2d1),
];

final settingsNotifier = ValueNotifier(
  _useTestBackground
      ? LiquidGlassSettings(
          blur: _testBlur.toDouble(),
          thickness: 40,
          saturation: 1,
        )
      : LiquidGlassSettings(
          thickness: 30,
          blur: 1,
          saturation: 1.2,
          glassColor: Colors.white.withValues(alpha: 0.2),
        ),
);

final blendNotifier = ValueNotifier(10.0);

class BasicApp extends HookWidget {
  const BasicApp({super.key});

  @override
  Widget build(BuildContext context) {
    final tab = useState(0);
    final fake = useState(false);

    final visibility = useState(true);
    final visibilityValue = useSingleMotion(
      value: visibility.value ? 1.0 : 0.0,
      motion: Motion.smoothSpring(),
    );

    const shadows = [
      BoxShadow(
        blurStyle: BlurStyle.outer,
        color: Color.from(alpha: 0.05, red: 0, green: 0, blue: 0),
        offset: Offset(0, 1),
        blurRadius: 2,
      ),
      BoxShadow(
        blurStyle: BlurStyle.outer,
        color: Color.from(alpha: 0.1, red: 0, green: 0, blue: 0),
        offset: Offset(0, 8),
        blurRadius: 30,
      ),
    ];

    return GestureDetector(
      onTap: () {
        SettingsSheet(
          fake: fake.value,
          blendNotifier: blendNotifier,
          settingsNotifier: settingsNotifier,
        ).show(context);
      },
      child: CupertinoPageScaffold(
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => Stack(
                      children: [
                        Positioned.fill(
                          child: _useTestBackground
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
                                    divisions: 2,
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
                ]),
                builder: (context, child) {
                  final settings = settingsNotifier.value.copyWith(
                    glassColor: CupertinoTheme.of(
                      context,
                    ).barBackgroundColor.withValues(alpha: 0.1),
                    edgeColor: Color.from(
                      alpha: .3,
                      red: .1,
                      green: .1,
                      blue: .1,
                    ),
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
                                onTap: () =>
                                    visibility.value = !visibility.value,
                                child: LiquidStretch(
                                  child: LiquidGlass.auto(
                                    shadows: shadows,
                                    shape: LiquidRoundedSuperellipse(
                                      borderRadius: 20,
                                    ),
                                    child: GlassGlow(
                                      child: SizedBox.square(
                                        dimension: 100,
                                        child: Center(
                                          child: fake.value
                                              ? Text('FAKE')
                                              : Text('REAL'),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              LiquidStretch(
                                child: LiquidGlass.auto(
                                  shadows: shadows,
                                  shape: LiquidRoundedSuperellipse(
                                    borderRadius: 20,
                                  ),
                                  child: GlassGlow(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      child: SizedBox.square(
                                        dimension: 100,
                                        child: Center(
                                          child: fake.value
                                              ? Text('FAKE')
                                              : Text('REAL'),
                                        ),
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
                              shape: LiquidRoundedSuperellipse(
                                borderRadius: 9000,
                              ),
                              child: GlassGlow(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  child: SizedBox(
                                    width: 400,
                                    height: 64,
                                    child: Center(
                                      child: fake.value
                                          ? Text('FAKE')
                                          : Text('REAL'),
                                    ),
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
                child: LiquidGlassBottomBar(
                  fake: fake.value,
                  extraButton: LiquidGlassBottomBarExtraButton(
                    icon: CupertinoIcons.add_circled,
                    onTap: () {
                      Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (context) => CupertinoPageScaffold(
                            child: SizedBox(),
                            navigationBar: CupertinoNavigationBar.large(),
                          ),
                        ),
                      );
                    },
                    label: '',
                  ),
                  tabs: [
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
          ],
        ),
      ),
    );
  }
}

class Blink extends StatelessWidget {
  const Blink({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SequenceMotionBuilder(
      converter: SingleMotionConverter(),
      sequence: StepSequence.withMotions([
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
