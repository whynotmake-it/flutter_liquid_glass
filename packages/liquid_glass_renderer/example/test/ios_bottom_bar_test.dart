import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/bottom_bar/ios_bottom_bar.dart';
import 'package:liquid_glass_renderer_example/bottom_bar/loupe_tab_bar.dart';

const _tabs = [
  BottomBarTab(icon: CupertinoIcons.house_fill, label: 'Home'),
  BottomBarTab(icon: CupertinoIcons.square_grid_2x2_fill, label: 'New'),
  BottomBarTab(icon: CupertinoIcons.dot_radiowaves_left_right, label: 'Radio'),
  BottomBarTab(icon: CupertinoIcons.music_albums_fill, label: 'Library'),
];

void main() {
  late List<int> selections;

  Future<void> pumpBar(WidgetTester tester) async {
    selections = [];
    tester.view
      ..physicalSize = const Size(400, 240)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      CupertinoApp(
        home: LiquidGlassLayer(
          fake: true,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: IosBottomBar(
                tabs: _tabs,
                onSelected: selections.add,
                accessory: const NowPlayingAccessory(),
                fake: true,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Offset tabCenter(WidgetTester tester, String label) =>
      tester.getCenter(find.text(label).first);

  testWidgets('tapping a tab selects it', (tester) async {
    await pumpBar(tester);

    await tester.tapAt(tabCenter(tester, 'Radio'));
    await tester.pumpAndSettle();

    expect(selections, [2]);
    expect(find.byKey(LoupeTabBar.loupeKey), findsNothing);
  });

  testWidgets('the loupe follows a drag and snaps to the tab under release', (
    tester,
  ) async {
    await pumpBar(tester);
    expect(find.byKey(LoupeTabBar.loupeKey), findsNothing);

    final gesture = await tester.startGesture(tabCenter(tester, 'Home'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(LoupeTabBar.loupeKey), findsOneWidget);

    final library = tabCenter(tester, 'Library');
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(
        Offset.lerp(tabCenter(tester, 'Home'), library, i / 10)!,
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(selections, isEmpty);

    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selections, [3]);
    expect(find.byKey(LoupeTabBar.loupeKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('moving the finger rebuilds nothing', (tester) async {
    await pumpBar(tester);

    final gesture = await tester.startGesture(tabCenter(tester, 'Home'));
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(LoupeTabBar.loupeKey), findsOneWidget);

    var rebuilds = 0;
    debugOnRebuildDirtyWidget = (element, builtOnce) => rebuilds++;
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(12, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    debugOnRebuildDirtyWidget = null;
    expect(rebuilds, 0);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the whole bar shares one adaptive brightness estimate', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(400, 240)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = LiquidGlassBrightnessSource();
    await tester.pumpWidget(
      CupertinoApp(
        home: LiquidGlassLayer(
          fake: true,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: IosBottomBar(
              tabs: _tabs,
              accessory: const NowPlayingAccessory(),
              brightnessSource: source,
              appearanceFor: (brightness) =>
                  LiquidGlassAppearance.ios27Toolbar(brightness: brightness),
              fake: true,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(LiquidGlassAdaptiveBrightness), findsOneWidget);
    expect(find.byType(LiquidGlassBlendGroup), findsOneWidget);
  });
}
