import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/paint_fake_glass_surface.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

void main() {
  test('FakeGlass glint keeps its headroom above SDR white', () async {
    final program = await ui.FragmentProgram.fromAsset(
      ShaderKeys.fakeGlassSurface,
    );
    const size = Size(120, 60);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(Offset.zero & size, Paint()..color = Colors.white);
    paintFakeGlassSurface(
      canvas,
      shader: program.fragmentShader(),
      size: size,
      shape: const LiquidRoundedSuperellipse(borderRadius: 30),
      settings: const LiquidGlassSettings.ios27ToolbarLight(frost: 0),
      appearance: const LiquidGlassAppearance(),
      devicePixelRatio: 1,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      size.width.toInt(),
      size.height.toInt(),
      targetFormat: ui.TargetPixelFormat.rgbaFloat32,
    );
    final data = (await image.toByteData(
      format: ui.ImageByteFormat.rawExtendedRgba128,
    ))!;
    image.dispose();
    picture.dispose();

    double red(int x, int y) =>
        data.getFloat32((y * size.width.toInt() + x) * 16, Endian.host);

    // The first covered row along the top wall carries the glint peak; the
    // centre of the face carries none.
    expect(red(60, 0), greaterThan(1.02));
    expect(red(60, 30), closeTo(1, 0.01));
  });

  test('RealGlass never caps the lit glint at SDR white', () {
    final source = File(
      'lib/assets/shaders/liquid_glass_final_render_core.glsl',
    ).readAsStringSync();
    expect(source, contains('kGlintLuminance = 1.6'));
    expect(
      source,
      contains('result = max(mix(result, glintTarget, glint), vec3(0.0));'),
    );
    final afterGlint = source.substring(
      source.indexOf('result = max(mix(result, glintTarget, glint)'),
    );
    expect(
      afterGlint,
      isNot(contains('clamp(finalColor')),
      reason: 'the composited color must reach the target unclamped',
    );
    expect(afterGlint, isNot(contains('clamp(premultipliedColor')));
    expect(afterGlint, isNot(contains('clamp(litColor')));
  });
}
