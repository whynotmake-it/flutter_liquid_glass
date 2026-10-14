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

/// Directory the figures of `docs/liquid-glass-rewrite.md` are written to.
/// The test only runs when it is set:
///
/// ```sh
/// flutter test --enable-impeller --enable-flutter-gpu \
///   --dart-define=BLOG_FIGURES_OUT=/tmp/blog-figures \
///   test/blog_figures_test.dart
/// ```
///
/// Like `readme_screenshots_test.dart`, but each capture scrolls its backdrop
/// so the glass sits over one photograph instead of a seam between two.
/// `tool/compose_blog_figures.py` frames the captures for the post.
const _out = String.fromEnvironment('BLOG_FIGURES_OUT');

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

typedef _Figure = ({
  String name,
  StageScene scene,
  Brightness brightness,
  Backdrop backdrop,
  double scroll,
});

const List<_Figure> _figures = [
  (
    name: 'controls-light',
    scene: StageScene.controls,
    brightness: Brightness.light,
    backdrop: Backdrop.photos,
    scroll: 0,
  ),
  (
    name: 'controls-dark',
    scene: StageScene.controls,
    brightness: Brightness.dark,
    backdrop: Backdrop.night,
    scroll: 0,
  ),
  (
    name: 'blend-light',
    scene: StageScene.blend,
    brightness: Brightness.light,
    backdrop: Backdrop.photos,
    scroll: 230,
  ),
  (
    name: 'blend-dark',
    scene: StageScene.blend,
    brightness: Brightness.dark,
    backdrop: Backdrop.night,
    scroll: 880,
  ),
  (
    name: 'colors-light',
    scene: StageScene.colors,
    brightness: Brightness.light,
    backdrop: Backdrop.photos,
    scroll: 600,
  ),
  (
    name: 'loupe-light',
    scene: StageScene.loupe,
    brightness: Brightness.light,
    backdrop: Backdrop.article,
    scroll: 0,
  ),
];

void main() {
  setUpAll(() async {
    if (_out.isNotEmpty) await _loadFonts();
  });

  for (final figure in _figures) {
    testWidgets(
      'captures ${figure.name}',
      (tester) async {
        final shadowsWereDisabled = debugDisableShadows;
        debugDisableShadows = false;
        try {
          tester.view
            ..physicalSize = _screen * _scale
            ..devicePixelRatio = _scale
            ..padding = _padding
            ..viewPadding = _padding;
          addTearDown(tester.view.reset);

          final state = PlaygroundState(brightness: figure.brightness);
          state.scene.value = figure.scene;
          state.backdrop.value = figure.backdrop;
          if (figure.scene == StageScene.loupe) {
            state.material.value = GlassMaterial.preset(
              style: GlassStyle.loupe,
              brightness: figure.brightness,
            );
          }
          state.loupes[0].offset.value = const Offset(-40, -110);
          state.loupes[1].offset.value = const Offset(100, -205);
          final captureKey = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: captureKey,
              child: CupertinoApp(
                debugShowCheckedModeBanner: false,
                theme: CupertinoThemeData(brightness: figure.brightness),
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
          await tester.pump();
          if (figure.scroll != 0) {
            final page = tester
                .stateList<ScrollableState>(find.byType(Scrollable))
                .firstWhere(
                  (s) =>
                      s.position.axis == Axis.vertical &&
                      s.position.maxScrollExtent > 0 &&
                      s.context.findRenderObject()!.paintBounds.width > 0 &&
                      (s.context.findRenderObject()! as RenderBox)
                              .localToGlobal(Offset.zero)
                              .dx
                              .abs() <
                          1,
                );
            page.position.jumpTo(figure.scroll);
          }
          for (var frame = 0; frame < 60; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            if (find.byType(FakeGlass).evaluate().isEmpty) break;
          }
          for (var frame = 0; frame < 60; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: _scale);
          await tester.runAsync(() async {
            final png = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File('$_out/${figure.name}.png')
              ..parent.createSync(recursive: true)
              ..writeAsBytesSync(png!.buffer.asUint8List());
          });
          image.dispose();

          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        } finally {
          debugDisableShadows = shadowsWereDisabled;
        }
      },
      skip: _out.isEmpty,
      tags: 'golden',
    );
  }
}
