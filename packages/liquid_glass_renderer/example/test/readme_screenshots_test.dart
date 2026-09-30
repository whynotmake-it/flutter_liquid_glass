import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/app.dart';
import 'package:liquid_glass_renderer_example/playground/backdrops.dart';
import 'package:liquid_glass_renderer_example/playground/playground_state.dart';
import 'package:liquid_glass_renderer_example/playground/presets.dart';

/// Directory the README screenshots are written to. The test only runs when
/// it is set:
///
/// ```sh
/// flutter test --enable-impeller --enable-flutter-gpu \
///   --dart-define=README_SHOTS_OUT=/tmp/readme-shots \
///   test/readme_screenshots_test.dart
/// ```
///
/// Each capture is a full iPhone 17 Pro screen at 3x; crop them with
/// `tool/crop_readme_screenshots.py`.
const _out = String.fromEnvironment('README_SHOTS_OUT');

const _screen = Size(402, 874);
const _scale = 3.0;
const _padding = FakeViewPadding(top: 62 * _scale, bottom: 34 * _scale);

Future<void> _loadFonts() async {
  final icons = FontLoader('packages/cupertino_icons/CupertinoIcons')
    ..addFont(
      rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
    );
  await icons.load();
  final fonts =
      '${Platform.environment['FLUTTER_ROOT']}'
      '/bin/cache/artifacts/material_fonts';
  // `FlutterTest` is the fallback for text styles without a family.
  for (final family in [
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
    'FlutterTest',
  ]) {
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

  final captures = [
    for (final brightness in Brightness.values)
      for (final scene in StageScene.values) (scene, brightness, false),
    (StageScene.controls, Brightness.light, true),
    (StageScene.controls, Brightness.dark, true),
  ];
  for (final (scene, brightness, fake) in captures) {
    final name = '${scene.name}${fake ? '-fake' : ''}-${brightness.name}';
    {
      testWidgets(
        'captures $name',
        (tester) async {
          tester.view
            ..physicalSize = _screen * _scale
            ..devicePixelRatio = _scale
            ..padding = _padding
            ..viewPadding = _padding;
          addTearDown(tester.view.reset);

          final state = PlaygroundState(brightness: brightness);
          state.scene.value = scene;
          state.fake.value = fake;
          state.backdrop.value = switch ((scene, brightness)) {
            (StageScene.loupe, _) => Backdrop.article,
            (_, Brightness.dark) => Backdrop.night,
            (_, Brightness.light) => Backdrop.photos,
          };
          if (scene == StageScene.loupe) {
            state.material.value = GlassMaterial.preset(
              style: GlassStyle.loupe,
              brightness: brightness,
            );
          }
          // The text loupe over the specimen line and the round magnifier
          // over the body text.
          state.loupes[0].offset.value = const Offset(-40, -110);
          state.loupes[1].offset.value = const Offset(100, -205);
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
          await tester.runAsync(() async {
            final context = tester.element(find.byType(Playground));
            for (final asset in backdropPhotos) {
              await precacheImage(AssetImage(asset), context);
            }
          });
          for (var frame = 0; frame < 60; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            if (fake || find.byType(FakeGlass).evaluate().isEmpty) break;
          }
          for (var frame = 0; frame < 60; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
          }

          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: _scale);
          await tester.runAsync(() async {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('$_out/$name.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(png!.buffer.asUint8List());
          });
          image.dispose();

          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        },
        skip: _out.isEmpty,
      );
    }
  }
}
