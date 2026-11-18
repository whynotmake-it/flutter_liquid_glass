// A frame at rest is the same however the app got there: resized and back,
// its metrics fired unchanged, its pixel ratio changed and restored, a tab
// switched away and back. The test holds one testWidgets on purpose: each
// test file is a fresh process, and a picture kept wrong from a process's
// first frames shows only in its first test. Glass reads its copies, as it
// does in an app and not by default under flutter test: the pictures that
// can be kept wrong are drawn from them.
//
// flutter test --enable-impeller --enable-flutter-gpu \
//   test/glass_history_host_test.dart

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apple_liquid_glass_example/app.dart';
import 'package:apple_liquid_glass_example/stand/stand_home.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/rendering.dart' show glassReadsCopies;

const _frame = Duration(milliseconds: 16);
const _dpr = 2.0;
const _screen = Size(402, 874);

// Builds every scene through the engine's builder and, when a capture is
// asked for, renders the frame's scene to an image: what the frame put on
// the screen, glass included, which a repaint boundary's image is not.
class _Capturing extends Fake implements ui.SceneBuilder {
  _Capturing(this._builder);

  final ui.SceneBuilder _builder;

  @override
  Object? noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #build) {
      final scene = _builder.build();
      final size = _Binding.wanted;
      if (size != null) {
        _Binding.wanted = null;
        _Binding.captured = scene.toImage(
          size.width.toInt(),
          size.height.toInt(),
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
  static Size? wanted;
  static Future<ui.Image>? captured;

  @override
  ui.SceneBuilder createSceneBuilder() =>
      _Capturing(super.createSceneBuilder());
}

Future<Uint8List> _capture(WidgetTester tester) async {
  _Binding.wanted = tester.view.physicalSize;
  _Binding.captured = null;
  // At rest nothing asks for a frame; this one changes nothing and draws
  // what is kept.
  tester.binding.scheduleFrame();
  await tester.pump(_frame);
  _Binding.wanted = null;
  final pending = _Binding.captured;
  if (pending == null) throw TestFailure('the frame built no scene');
  final image = (await tester.runAsync(() => pending))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return Uint8List.fromList(bytes.buffer.asUint8List());
}

// Frames under fake time; an image decodes only in real time, so the frames
// wait for every image on screen first.
Future<void> _rest(WidgetTester tester, [int frames = 60]) async {
  for (var i = 0; i < 50; i++) {
    final images = tester.widgetList<RawImage>(find.byType(RawImage));
    if (images.every((image) => image.image != null)) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(_frame);
  }
  for (var i = 0; i < frames; i++) {
    await tester.pump(_frame);
  }
}

// Pixels a level apart are rounding: glass over a held copy and glass over
// the scene the copy was taken from round a pixel here and there apart.
// More of them than glass has at its rims, or any pixel further apart, is
// another picture.
const _handful = 2000;

// Null when equal; else how many pixels differ, by how much at most, and
// where, in logical pixels.
String? _difference(Uint8List a, Uint8List b, Size physical) {
  final width = physical.width.toInt();
  var apart = 0;
  var nearly = 0;
  var most = 0;
  var left = width;
  var top = physical.height.toInt();
  var right = -1;
  var bottom = -1;
  for (var i = 0; i < a.length; i += 4) {
    var d = 0;
    for (var c = 0; c < 4; c++) {
      final x = (a[i + c] - b[i + c]).abs();
      if (x > d) d = x;
    }
    if (d == 0) continue;
    if (d > most) most = d;
    if (d == 1) {
      nearly++;
      continue;
    }
    apart++;
    final x = (i ~/ 4) % width;
    final y = (i ~/ 4) ~/ width;
    if (x < left) left = x;
    if (x > right) right = x;
    if (y < top) top = y;
    if (y > bottom) bottom = y;
  }
  if (apart == 0 && nearly <= _handful) return null;
  if (apart == 0) return '$nearly px a level apart';
  return '$apart px up to $most levels apart in '
      '(${left / _dpr}, ${top / _dpr})-(${right / _dpr}, ${bottom / _dpr})';
}

void main() {
  _Binding();

  testWidgets(
    'the gallery at rest draws the same frame however it got there',
    (tester) async {
      tester.view.physicalSize = _screen * _dpr;
      tester.view.devicePixelRatio = _dpr;
      tester.view.padding = const FakeViewPadding(
        top: 62 * _dpr,
        bottom: 34 * _dpr,
      );
      addTearDown(tester.view.reset);
      glassReadsCopies = true;
      addTearDown(() => glassReadsCopies = false);
      await tester.pumpWidget(const GalleryApp(home: StandHome()));
      await _rest(tester, 40);
      await tester.tap(find.text('Controls').last);
      await _rest(tester, 300);
      final rested = await _capture(tester);
      final base = tester.view.physicalSize;

      final ways = <String, Future<void> Function()>{
        'resized by 2 px for a frame and back': () async {
          tester.view.physicalSize = base + const Offset(2, 0);
          await tester.pump(_frame);
          tester.view.physicalSize = base;
        },
        'its metrics fired unchanged': () async {
          tester.view.physicalSize = base;
        },
        'its pixel ratio changed for a frame and restored': () async {
          tester.view.devicePixelRatio = _dpr + 1;
          await tester.pump(_frame);
          tester.view.devicePixelRatio = _dpr;
        },
        'a tab switched away and back': () async {
          await tester.tap(find.text('Photos').last);
          await _rest(tester);
          await tester.tap(find.text('Controls').last);
        },
      };
      final differences = <String>[];
      for (final MapEntry(key: way, value: go) in ways.entries) {
        await go();
        await _rest(tester, 300);
        final difference = _difference(
          rested,
          await _capture(tester),
          base,
        );
        if (difference != null) differences.add('$way: $difference');
      }
      expect(differences, isEmpty);

      await tester.pumpWidget(const SizedBox());
      await _rest(tester, 5);
    },
    skip: !ui.ImageFilter.isShaderFilterSupported,
  );
}
