import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/paint_fake_glass_surface.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

import 'shared.dart';

const _size = Size(120, 60);
const _fromLeft = Offset(1, 0);

/// Luma just inside the glass's top and left walls, at their midpoints.
({double top, double left}) _walls(ByteData rgba, int width) {
  double luma(int x, int y) {
    final o = (y * width + x) * 4;
    return 0.2126 * rgba.getUint8(o) +
        0.7152 * rgba.getUint8(o + 1) +
        0.0722 * rgba.getUint8(o + 2);
  }

  return (top: luma(width ~/ 2, 0), left: luma(0, _size.height ~/ 2));
}

Future<({double top, double left})> _fakeGlassWalls(
  LiquidGlassSettings settings,
) async {
  final program = await ui.FragmentProgram.fromAsset(
    ShaderKeys.fakeGlassSurface,
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(Offset.zero & _size, Paint()..color = Colors.black);
  paintFakeGlassSurface(
    canvas,
    shader: program.fragmentShader(),
    size: _size,
    shape: const LiquidRoundedSuperellipse(borderRadius: 30),
    settings: settings,
    appearance: const LiquidGlassAppearance(),
    devicePixelRatio: 1,
    // The glint is its own additive pass since 1.0.0-dev.1.
    highlightOnly: true,
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(_size.width.toInt(), _size.height.toInt());
  final rgba = (await image.toByteData())!;
  image.dispose();
  picture.dispose();
  return _walls(rgba, _size.width.toInt());
}

Future<({double top, double left})> _realGlassWalls(
  WidgetTester tester,
  LiquidGlassSettings settings,
) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = _size;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: ColoredBox(
        color: Colors.black,
        child: LiquidGlassLayer(
          settings: settings,
          child: const LiquidGlass(
            shape: LiquidRoundedSuperellipse(borderRadius: 30),
            child: SizedBox.expand(),
          ),
        ),
      ),
    ),
  );
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  final rgba = (await tester.runAsync(image.toByteData))!;
  final width = image.width;
  image.dispose();
  return _walls(rgba, width);
}

void main() {
  test('lightDirection defaults to the top light and is normalized', () {
    const settings = LiquidGlassSettings();
    expect(settings.lightDirection, const Offset(0, 1));
    expect(settings.effectiveLightDirection, const Offset(0, 1));
    expect(
      const LiquidGlassSettings(
        lightDirection: Offset(3, 4),
      ).effectiveLightDirection,
      const Offset(.6, .8),
    );
    expect(
      const LiquidGlassSettings(
        lightDirection: Offset.zero,
      ).effectiveLightDirection,
      const Offset(0, 1),
    );
    expect(
      settings.copyWith(lightDirection: _fromLeft),
      isNot(settings),
    );
  });

  test('lightDirection survives a JSON round trip', () {
    const original = LiquidGlassSettings(lightDirection: Offset(.6, .8));
    expect(
      LiquidGlassSettings.fromJson(original.toJson()).lightDirection,
      original.lightDirection,
    );
  });

  test('FakeGlass moves the glint with lightDirection', () async {
    final top = await _fakeGlassWalls(
      LiquidGlassSettings.ios27RegularLight(frost: 0),
    );
    final left = await _fakeGlassWalls(
      LiquidGlassSettings.ios27RegularLight(
        frost: 0,
      ).copyWith(lightDirection: _fromLeft),
    );
    // The soft glint plateau of 1.0.0-dev.1 peaks at about 36 here.
    expect(top.top, greaterThan(top.left + 20));
    expect(left.left, greaterThan(left.top + 20));
  });

  testWidgets(
    'RealGlass moves the glint with lightDirection',
    skip: skipProperGlassTests,
    (tester) async {
      final top = await _realGlassWalls(
        tester,
        LiquidGlassSettings.ios27RegularLight(frost: 0),
      );
      final left = await _realGlassWalls(
        tester,
        LiquidGlassSettings.ios27RegularLight(
          frost: 0,
        ).copyWith(lightDirection: _fromLeft),
      );
      // The walls differ by about 34 since 1.0.0-dev.1.
      expect(top.top, greaterThan(top.left + 20));
      expect(left.left, greaterThan(left.top + 20));
    },
  );
}
