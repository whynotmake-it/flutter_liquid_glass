import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/paint_fake_glass_surface.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

void main() {
  // FakeGlass may stay SDR (Skia needs premultiplied color within alpha);
  // RealGlass keeps the glint's headroom above white.
  Future<List<double>> fakeGlassRed(Color backdrop) async {
    final program = await ui.FragmentProgram.fromAsset(
      ShaderKeys.fakeGlassSurface,
    );
    const size = Size(120, 60);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(Offset.zero & size, Paint()..color = backdrop);
    paintFakeGlassSurface(
      canvas,
      shader: program.fragmentShader(),
      size: size,
      shape: const LiquidRoundedSuperellipse(borderRadius: 30),
      settings: LiquidGlassSettings.ios27ToolbarLight(frost: 0),
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
    return [
      for (var i = 0; i < data.lengthInBytes; i += 16)
        data.getFloat32(i, Endian.host),
    ];
  }

  test('FakeGlass glint reaches but never exceeds SDR white', () async {
    const width = 120;
    final overWhite = await fakeGlassRed(Colors.white);
    // The first covered row along the top wall carries the glint peak.
    expect(overWhite[60], closeTo(1, 0.01));
    expect(overWhite.reduce(math.max), lessThanOrEqualTo(1.0 + 1e-3));

    final overBlack = await fakeGlassRed(Colors.black);
    expect(overBlack[60], greaterThan(overBlack[30 * width + 60] + 0.1));
    expect(overBlack.reduce(math.max), lessThanOrEqualTo(1.0 + 1e-3));
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
