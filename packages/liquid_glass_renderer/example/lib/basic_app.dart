import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/shared.dart';
import 'package:liquid_glass_renderer_example/widgets/bottom_bar.dart';

void main() {
  runApp(CupertinoApp(home: BasicApp()));
}

final settingsNotifier = ValueNotifier(
  LiquidGlassSettings(
    thickness: 20,
    blur: 10,
    refractiveIndex: 1.2,
    glassColor: Colors.white.withValues(alpha: 0.2),
  ),
);

class BasicApp extends HookWidget {
  const BasicApp({super.key});

  @override
  Widget build(BuildContext context) {
    useStream(Stream.periodic(const Duration(seconds: 1)));
    final lightAngleController = useRotatingAnimationController();

    final tab = useState(0);

    return GestureDetector(
      onTap: () {
        SettingsSheet(
          settingsNotifier: settingsNotifier,
          lightAngleAnimation: lightAngleController,
        ).show(context);
      },
      child: CupertinoPageScaffold(
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => Image.network(
                      'https://picsum.photos/500/500?random=$index',
                    ),
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                  ),
                ),
              ],
            ),
            Center(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  settingsNotifier,
                  lightAngleController,
                ]),
                builder: (context, child) {
                  final settings = settingsNotifier.value.copyWith(
                    lightAngle: lightAngleController.value,
                    glassColor: CupertinoTheme.of(
                      context,
                    ).barBackgroundColor.withValues(alpha: 0.4),
                  );
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 16,
                    children: [
                      LiquidGlass(
                        settings: settings,
                        shape: LiquidRoundedSuperellipse(
                          borderRadius: Radius.circular(20),
                        ),
                        glassContainsChild: false,
                        child: SizedBox.square(
                          dimension: 100,
                          child: Center(child: Text('REAL')),
                        ),
                      ),
                      FakeGlass(
                        settings: settings,
                        shape: LiquidRoundedSuperellipse(
                          borderRadius: Radius.circular(20),
                        ),
                        child: SizedBox.square(
                          dimension: 100,
                          child: Center(child: Text('FAKE')),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: LiquidGlassBottomBar(
                  extraButton: LiquidGlassBottomBarExtraButton(
                    icon: CupertinoIcons.add_circled,
                    onTap: () {
                      Navigator.of(context).push(
                        CupertinoPageRoute(
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
