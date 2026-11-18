// A sheet held under the finger keeps its glass from frame to frame. A
// pressed sheet is drawn scaled a hair, and a layer Impeller sized a row
// short there dropped the haze of the sheet's glass every other frame or so.
//
// flutter test --enable-impeller --enable-flutter-gpu \
//   test/sheet_haze_host_test.dart

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/app.dart';
import 'package:apple_liquid_glass_example/home.dart';
import 'package:apple_liquid_glass_example/settings_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/rendering.dart';

class _Capturing extends Fake implements ui.SceneBuilder {
  _Capturing(this._builder);

  final ui.SceneBuilder _builder;

  @override
  Object? noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #build) {
      final scene = _builder.build();
      if (_Binding.capture) {
        final size = _Binding.size;
        _Binding.shots.add(
          scene.toImage(size.width.toInt(), size.height.toInt()),
        );
      }
      return scene;
    }
    final method = switch (invocation.memberName) {
      #pushTransform => _builder.pushTransform,
      #pushOffset => _builder.pushOffset,
      #pushClipRect => _builder.pushClipRect,
      #pushClipRRect => _builder.pushClipRRect,
      #pushClipRSuperellipse => _builder.pushClipRSuperellipse,
      #pushClipPath => _builder.pushClipPath,
      #pushOpacity => _builder.pushOpacity,
      #pushColorFilter => _builder.pushColorFilter,
      #pushImageFilter => _builder.pushImageFilter,
      #pushBackdropFilter => _builder.pushBackdropFilter,
      #pushShaderMask => _builder.pushShaderMask,
      #pop => _builder.pop,
      #addRetained => _builder.addRetained,
      #addPicture => _builder.addPicture,
      #addTexture => _builder.addTexture,
      #addPerformanceOverlay => _builder.addPerformanceOverlay,
      #addPlatformView => _builder.addPlatformView,
      _ => throw UnsupportedError('${invocation.memberName}'),
    };
    return Function.apply(
      method,
      invocation.positionalArguments,
      invocation.namedArguments,
    );
  }
}

class _Binding extends AutomatedTestWidgetsFlutterBinding {
  static bool capture = false;
  static Size size = Size.zero;
  static final shots = <Future<ui.Image>>[];

  @override
  ui.SceneBuilder createSceneBuilder() =>
      _Capturing(super.createSceneBuilder());
}

// The mean of the sheet's lower part in [image], as display values.
Future<double> _meanOf(WidgetTester tester, ui.Image image) async {
  final data = (await tester.runAsync(image.toByteData))!;
  final bytes = Uint8List.sublistView(data);
  final width = image.width;
  var sum = 0;
  var n = 0;
  for (var y = 700; y < 1100; y += 2) {
    for (var x = 100; x < 1500; x += 2) {
      final at = (y * width + x) * 4;
      sum += bytes[at] + bytes[at + 1] + bytes[at + 2];
      n += 3;
    }
  }
  return sum / n;
}

void main() {
  _Binding();

  testWidgets('a pressed sheet keeps its haze from frame to frame', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    glassReadsCopies = true;
    addTearDown(() => glassReadsCopies = false);
    await tester.runAsync(precacheGlass);
    await tester.pumpWidget(const GalleryApp());
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    unawaited(showGallerySettings(tester.element(find.byType(GalleryHome))));
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Settings')),
    );
    for (var i = 0; i < 30; i++) {
      await gesture.moveBy(const Offset(0, -2));
      await tester.pump(const Duration(milliseconds: 8));
      await tester.pump(const Duration(milliseconds: 8));
    }
    _Binding.size = tester.view.physicalSize;
    _Binding.capture = true;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    _Binding.capture = false;
    await gesture.up();

    final means = <double>[];
    for (final pending in _Binding.shots) {
      final image = (await tester.runAsync(() => pending))!;
      means.add(await _meanOf(tester, image));
      image.dispose();
    }
    // The sheet settles under the finger: no frame steps away from both of
    // its neighbours.
    final flips = <int>[
      for (var i = 1; i < means.length - 1; i++)
        if ((means[i] - means[i - 1]) * (means[i + 1] - means[i]) < 0 &&
            (means[i] - means[i - 1]).abs() > 0.05 &&
            (means[i + 1] - means[i]).abs() > 0.05)
          i,
    ];
    expect(flips, isEmpty, reason: 'frame means $means');

    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }, skip: !ui.ImageFilter.isShaderFilterSupported);
}
