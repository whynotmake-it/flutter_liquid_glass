import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/app.dart';
import 'package:liquid_glass_renderer_example/bottom_bar/loupe_tab_bar.dart';
import 'package:liquid_glass_renderer_example/playground/backdrops.dart';
import 'package:liquid_glass_renderer_example/playground/playground_state.dart';

/// Directory the captures are written to. The test only runs when it is set:
///
/// ```sh
/// flutter test --enable-impeller --enable-flutter-gpu \
///   --dart-define=BOTTOM_BAR_MATCH_OUT=/tmp/bottom-bar-match \
///   test/bottom_bar_match_test.dart
/// ```
const _out = String.fromEnvironment('BOTTOM_BAR_MATCH_OUT');

/// iPhone 17 Pro: 402 × 874 pt at 3x, 62 pt status bar inset and a 34 pt
/// home indicator inset.
const _screen = Size(402, 874);
const _scale = 3.0;
const _padding = FakeViewPadding(top: 62 * _scale, bottom: 34 * _scale);

/// Real glyphs instead of the test font's boxes: CupertinoIcons, and Roboto
/// from the Flutter SDK standing in for SF Pro.
Future<void> _loadFonts() async {
  final icons = FontLoader('packages/cupertino_icons/CupertinoIcons')
    ..addFont(
      rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
    );
  await icons.load();
  final fonts =
      '${Platform.environment['FLUTTER_ROOT']}'
      '/bin/cache/artifacts/material_fonts';
  for (final family in ['CupertinoSystemText', 'CupertinoSystemDisplay']) {
    final loader = FontLoader(family);
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      final bytes = File('$fonts/Roboto-$weight.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(() async {
    if (_out.isNotEmpty) await _loadFonts();
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'captures the controls scene at iPhone 17 Pro size (${brightness.name})',
      (tester) async {
        tester.view
          ..physicalSize = _screen * _scale
          ..devicePixelRatio = _scale
          ..padding = _padding
          ..viewPadding = _padding;
        addTearDown(tester.view.reset);

        final state = PlaygroundState(brightness: brightness);
        state.backdrop.value = Backdrop.grid;
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: CupertinoApp(
              debugShowCheckedModeBanner: false,
              theme: CupertinoThemeData(brightness: brightness),
              home: Playground(state: state),
            ),
          ),
        );
        for (var frame = 0; frame < 60; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (find.byType(FakeGlass).evaluate().isEmpty) break;
        }
        for (var frame = 0; frame < 30; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        Future<void> capture(String name) async {
          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: _scale);
          await tester.runAsync(() async {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('$_out/${brightness.name}-$name.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(png!.buffer.asUint8List());
          });
          image.dispose();
        }

        Offset tab(String label) => tester.getCenter(find.text(label).first);

        await capture('idle');

        final gesture = await tester.startGesture(tab('Home'));
        for (var frame = 0; frame < 30; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await capture('pressed');

        final home = tab('Home');
        final library = tab('Library');
        final between = Offset.lerp(tab('New'), tab('Radio'), .5)!;
        for (var i = 1; i <= 8; i++) {
          await gesture.moveTo(Offset.lerp(home, between, i / 8)!);
          await tester.pump(const Duration(milliseconds: 16));
        }
        await capture('dragging');
        for (var frame = 0; frame < 40; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await capture('held-between');

        final beyond = library + const Offset(160, 0);
        for (var i = 1; i <= 12; i++) {
          await gesture.moveTo(Offset.lerp(between, beyond, i / 12)!);
          await tester.pump(const Duration(milliseconds: 16));
        }
        for (var frame = 0; frame < 40; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await capture('overdrag');
        expect(find.byKey(LoupeTabBar.loupeKey), findsOneWidget);

        await gesture.up();
        for (var frame = 0; frame < 90; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await capture('released');

        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
      skip: _out.isEmpty,
    );
  }
}
