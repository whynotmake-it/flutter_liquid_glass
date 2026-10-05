import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/bottom_bar/ios_bottom_bar.dart';
import 'package:liquid_glass_renderer_example/bottom_bar/loupe_tab_bar.dart';

/// Where the loupe's per-frame size in the fast drag test is written as CSV,
/// if set.
const _dynamicsOut = String.fromEnvironment('LOUPE_DYNAMICS_OUT');

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

  testWidgets('the loupe keeps up with a finger that moves every frame', (
    tester,
  ) async {
    await pumpBar(tester);
    final home = tabCenter(tester, 'Home');
    final library = tabCenter(tester, 'Library');

    final gesture = await tester.startGesture(home);
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 1; i <= 30; i++) {
      await gesture.moveTo(Offset.lerp(home, library, i / 30)!);
      await tester.pump(const Duration(milliseconds: 8));
    }

    final slot = tabCenter(tester, 'New').dx - home.dx;
    final loupe = tester.getCenter(find.byKey(LoupeTabBar.loupeKey));
    expect((library.dx - loupe.dx).abs(), lessThan(slot));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a fast drag flattens the loupe, which springs back taller and '
      'jiggles out', (tester) async {
    await pumpBar(tester);
    final home = tabCenter(tester, 'Home');
    final library = tabCenter(tester, 'Library');

    final gesture = await tester.startGesture(home);
    // Past the loupe's pop on touch down.
    for (var frame = 0; frame < 90; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final rest = tester.getRect(find.byKey(LoupeTabBar.loupeKey)).size;

    // About 1100 pt/s, the fastest of the iOS 27 reference pans.
    final samples = <(int, Size)>[];
    const frames = 12;
    for (var frame = 1; frame <= frames; frame++) {
      await gesture.moveTo(Offset.lerp(home, library, frame / frames)!);
      await tester.pump(const Duration(milliseconds: 16));
      samples.add((
        frame * 16,
        tester.getRect(find.byKey(LoupeTabBar.loupeKey)).size,
      ));
    }
    for (var frame = 1; frame <= 90; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      samples.add((
        (frames + frame) * 16,
        tester.getRect(find.byKey(LoupeTabBar.loupeKey)).size,
      ));
    }

    if (_dynamicsOut.isNotEmpty) {
      File(_dynamicsOut)
        ..createSync(recursive: true)
        ..writeAsStringSync(
          [
            'ms,width,height,rest_width,rest_height',
            for (final (ms, size) in samples)
              '$ms,${size.width},${size.height},${rest.width},${rest.height}',
          ].join('\n'),
        );
    }

    final heights = [
      for (final (_, size) in samples) size.height / rest.height,
    ];
    final flattest = heights.reduce(math.min);
    final flattestAt = heights.indexOf(flattest);
    final tallest = heights.skip(flattestAt).reduce(math.max);
    expect(flattest, lessThan(.8), reason: 'flattened while moving fast');
    expect(tallest, greaterThan(1.02), reason: 'springs back past rest');
    expect(heights.last, closeTo(1, .01), reason: 'settles at rest');

    await gesture.up();
    await tester.pumpAndSettle();
  });

  for (final label in ['New', 'Home']) {
    testWidgets(
      'pressing the selected $label grows the loupe without a wobble',
      (
        tester,
      ) async {
        await pumpBar(tester);
        // Apple's reference presses are on the selected tab.
        await tester.tapAt(tabCenter(tester, label));
        await tester.pumpAndSettle();
        final gesture = await tester.startGesture(tabCenter(tester, label));
        final heights = <(int, double)>[];
        for (var frame = 1; frame <= 60; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          heights.add((
            frame * 16,
            tester.getRect(find.byKey(LoupeTabBar.loupeKey)).height,
          ));
        }
        final rest = heights.last.$2;
        if (_dynamicsOut.isNotEmpty) {
          File(_dynamicsOut.replaceFirst('.csv', '-press-$label.csv'))
            ..createSync(recursive: true)
            ..writeAsStringSync(
              [
                'ms,height,rest_height',
                for (final (ms, height) in heights) '$ms,$height,$rest',
              ].join('\n'),
            );
        }
        final peak = heights.map((h) => h.$2).reduce(math.max);
        expect(peak / rest, lessThan(1.01), reason: 'does not pop taller');
        await gesture.up();
        await tester.pumpAndSettle();
      },
    );
  }

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
}
