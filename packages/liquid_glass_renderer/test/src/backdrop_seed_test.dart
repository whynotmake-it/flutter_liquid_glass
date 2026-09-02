import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'submitted_scene_binding.dart';

void main() {
  runBackdropSeedTests(SubmittedSceneBinding());
}

void runBackdropSeedTests(SubmittedSceneCapture binding) {
  binding
    ..captureWidth = 240
    ..captureHeight = 160;
  if (const bool.fromEnvironment('PROBE_NATIVE_GROUP_COORDS')) {
    _nativeGroupCoordinates(binding);
    return;
  }
  if (const bool.fromEnvironment('PROBE_FILTER_OUTPUT_ALPHA')) {
    _filterOutputOpacityTests(binding);
    return;
  }
  const identity = ColorFilter.matrix([
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);

  for (var repetition = 0; repetition < 3; repetition++) {
    testWidgets(
      'identity backdrop preserves background repetition=$repetition',
      (tester) async {
        tester.view
          ..physicalSize = const Size(240, 160)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final opacity = ValueNotifier<double>(0);
        var enableShell = false;
        addTearDown(opacity.dispose);
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: CustomPaint(painter: _Background()),
                ),
                Center(
                  child: ValueListenableBuilder<double>(
                    valueListenable: opacity,
                    builder: (_, alpha, child) => Opacity(
                      opacity: alpha,
                      child: ClipRect(
                        child: BackdropFilter(
                          enabled: enableShell,
                          filter: identity,
                          child: const bool.fromEnvironment('PROBE_WIDE_SEED')
                              ? SizedBox(
                                  width: 240,
                                  height: 160,
                                  child: Center(child: child),
                                )
                              : child,
                        ),
                      ),
                    ),
                    child: const bool.fromEnvironment('PROBE_NESTED_SEED')
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: const SizedBox(
                                width: 160,
                                height: 100,
                                child: Center(
                                  child: SizedBox.square(
                                    dimension: 10,
                                    child: ColoredBox(color: Colors.red),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : const SizedBox(width: 160, height: 100),
                  ),
                ),
              ],
            ),
          ),
        );

        Future<Uint8List> capture(double alpha) async {
          opacity.value = alpha;
          binding
            ..captured = null
            ..captureNextScene = true
            ..scheduleFrame();
          await tester.pump();
          expect(binding.captureNextScene, isFalse);
          expect(binding.captured, isNotNull);
          final image = (await tester.runAsync(() => binding.captured!))!;
          expect(image.width, 240);
          expect(image.height, 160);
          final bytes = (await tester.runAsync(image.toByteData))!;
          final result = Uint8List.fromList(bytes.buffer.asUint8List());
          image.dispose();
          return result;
        }

        final background = await capture(0);
        final full = await capture(1);
        enableShell = true;
        await capture(0);
        for (final alpha in [1.0, 254 / 255, 0.5, 0.0, 1.0]) {
          final actual = await capture(alpha);
          var mismatches = 0;
          for (var i = 0; i < actual.length; i++) {
            final a = (alpha * 255).round();
            final expected = (full[i] * a + background[i] * (255 - a)) / 255;
            const tolerance = bool.fromEnvironment('PROBE_NESTED_SEED') ? 2 : 0;
            if ((actual[i] - expected).abs() > tolerance) mismatches++;
          }
          expect(mismatches, 0, reason: 'Identity seed at alpha=$alpha');
        }
      },
    );
  }
}

// A fixed-color analytic circle isolates runtime coordinates from glass,
// geometry samplers, refraction and backdrop changes. Interior witnesses
// avoid conflating the known Vulkan AA compression residuals with displacement.
void _nativeGroupCoordinates(SubmittedSceneCapture binding) {
  const pointwise = bool.fromEnvironment('PROBE_NATIVE_POINTWISE_COLOR');
  const builtinColor = bool.fromEnvironment('PROBE_NATIVE_POINTWISE_BUILTIN');
  for (final input in [
    if (pointwise) ...[
      'pointwise',
      'pointwise-blur',
    ] else ...[
      'direct',
      'blur',
      'scale',
      'image-filtered',
      'mask-child',
    ],
  ]) {
    for (final clipped in [false, true]) {
      testWidgets('native grouped shader input=$input clipped=$clipped', (
        tester,
      ) async {
        tester.view
          ..physicalSize = const Size(240, 160)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final alpha = ValueNotifier<double>(1);
        addTearDown(alpha.dispose);
        final backdropPhase = ValueNotifier<int>(0);
        addTearDown(backdropPhase.dispose);
        final sharedInput =
            const bool.fromEnvironment(
              'PROBE_NATIVE_GROUP_BACKDROP_KEY',
            )
            ? BackdropKey()
            : null;
        final program = (await tester.runAsync(
          () => ui.FragmentProgram.fromAsset(
            'integration_test/filter_output_opacity.frag',
          ),
        ))!;
        final shader = program.fragmentShader()
          ..setFloat(2, pointwise ? .58 : 1)
          ..setFloat(3, pointwise ? 3 : 1);
        addTearDown(shader.dispose);
        if (input == 'mask-child') {
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawCircle(
            const Offset(90, 104),
            25,
            Paint()..color = Colors.white,
          );
          final picture = recorder.endRecording();
          final cachedMask = picture.toImageSync(240, 160);
          picture.dispose();
          addTearDown(cachedMask.dispose);
          shader
            ..setFloat(0, 240)
            ..setFloat(1, 160)
            ..setFloat(3, 2)
            ..setImageSampler(0, cachedMask);
        }
        final runtime = pointwise && builtinColor
            ? const ColorFilter.linearToSrgbGamma()
            : ui.ImageFilter.shader(shader);
        final filter = switch (input) {
          'blur' || 'pointwise-blur' => ui.ImageFilter.compose(
            inner: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            outer: runtime,
          ),
          // Deliberately exercise the engine's scaled-snapshot rasterization
          // branch. This is a diagnostic, not an invisible production fix.
          'scale' => ui.ImageFilter.compose(
            inner: ui.ImageFilter.matrix(
              Matrix4.diagonal3Values(1.001, 1.001, 1).storage,
            ),
            outer: runtime,
          ),
          _ => runtime,
        };
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: backdropPhase,
                  builder: (_, phase, _) => CustomPaint(
                    painter: _Background(phase: phase),
                  ),
                ),
                if (sharedInput != null)
                  BackdropFilter(
                    backdropGroupKey: sharedInput,
                    filter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.modulate,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ClipRect(
                  clipper: clipped ? const _GroupCoordinateClip() : null,
                  child: ValueListenableBuilder<double>(
                    valueListenable: alpha,
                    builder: (_, value, child) => Opacity(
                      opacity: value,
                      child: BackdropFilter(
                        enabled: value > 0 && value < 1,
                        filter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.modulate,
                        ),
                        child: child,
                      ),
                    ),
                    child: input == 'mask-child'
                        ? BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: CustomPaint(
                              painter: _NativeBackdropMask(shader),
                              child: const SizedBox.expand(),
                            ),
                          )
                        : input == 'image-filtered'
                        ? ImageFiltered(
                            imageFilter: filter,
                            child: const BackdropFilter(
                              filter: ColorFilter.mode(
                                Colors.white,
                                BlendMode.modulate,
                              ),
                              child: SizedBox.expand(),
                            ),
                          )
                        : BackdropFilter(
                            backdropGroupKey: sharedInput,
                            filter: filter,
                            child: const SizedBox.expand(),
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
        Future<Uint8List> capture(double value) async {
          late final ui.Image image;
          if (pointwise &&
              const bool.fromEnvironment('PROBE_NATIVE_FRESH_SCENE')) {
            // Diagnostic only: no retained widget/native layers and no display
            // submission of this tree. Normal tests still capture the actual
            // submitted Flutter scene below.
            final recorder = ui.PictureRecorder();
            _Background(phase: backdropPhase.value).paint(
              Canvas(recorder),
              const Size(240, 160),
            );
            final picture = recorder.endRecording();
            final builder = ui.SceneBuilder()..addPicture(Offset.zero, picture);
            final handles = <ui.EngineLayer>[];
            if (value > 0) {
              handles.add(
                builder.pushClipRect(
                  clipped
                      ? const Rect.fromLTWH(16, 64, 208, 80)
                      : const Rect.fromLTWH(0, 0, 240, 160),
                ),
              );
              if (value < 1) {
                handles
                  ..add(builder.pushOpacity(Color.getAlphaFromOpacity(value)))
                  ..add(
                    builder.pushBackdropFilter(
                      const ColorFilter.mode(Colors.white, BlendMode.modulate),
                    ),
                  );
              }
              handles.add(builder.pushBackdropFilter(filter));
              builder.pop();
              if (value < 1) {
                builder
                  ..pop()
                  ..pop();
              }
              builder.pop();
            }
            final scene = builder.build();
            try {
              image = (await tester.runAsync(() => scene.toImage(240, 160)))!;
            } finally {
              scene.dispose();
              picture.dispose();
              for (final handle in handles) {
                handle.dispose();
              }
            }
          } else {
            alpha.value = value;
            binding
              ..captured = null
              ..captureNextScene = true
              ..scheduleFrame();
            await tester.pump();
            expect(binding.captureNextScene, isFalse);
            image = (await tester.runAsync(() => binding.captured!))!;
          }
          try {
            final data = (await tester.runAsync(image.toByteData))!;
            return Uint8List.fromList(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            );
          } finally {
            image.dispose();
            binding.captured = null;
          }
        }

        final background = await capture(0);
        final full = await capture(1);
        final failures = <String>[];
        var visibleChannels = 0;
        // A 7x7 solid interior must stay at the same location, not just produce
        // the same two equally blank fractional captures.
        for (var y = 101; y <= 107; y++) {
          for (var x = 87; x <= 93; x++) {
            final i = (y * 240 + x) * 4;
            for (var c = 0; c < 4; c++) {
              if ((full[i + c] - background[i + c]).abs() > 2) {
                visibleChannels++;
              }
              if (input == 'pointwise') {
                final source = background[i + c] / 255;
                final expected = c == 3
                    ? 255
                    : 255 *
                          (builtinColor
                              ? source <= .0031308
                                    ? 12.92 * source
                                    : 1.055 * math.pow(source, 1 / 2.4) - .055
                              : math.pow(source, .58));
                expect(
                  (full[i + c] - expected).abs(),
                  lessThanOrEqualTo(2),
                  reason:
                      'Pointwise color must sample the corresponding '
                      'backdrop pixel.',
                );
              } else if (!pointwise && input != 'mask-child') {
                expect(
                  (full[i + c] - [51, 153, 204, 255][c]).abs(),
                  lessThanOrEqualTo(2),
                );
              }
            }
          }
        }
        expect(visibleChannels, greaterThan(0));
        if (input == 'mask-child') {
          for (var y = 88; y < 120; y++) {
            for (var x = 24; x < 48; x++) {
              for (var c = 0; c < 4; c++) {
                final i = (y * 240 + x) * 4 + c;
                expect(
                  (full[i] - background[i]).abs(),
                  lessThanOrEqualTo(2),
                  reason: 'Mask must remove blur outside the circle ($x,$y).',
                );
              }
            }
          }
        }
        for (final value in [254, 128, 32, 0, 255, 128]) {
          final actual = await capture(value / 255);
          var bad = 0;
          var maximum = 0.0;
          for (var y = 101; y <= 107; y++) {
            for (var x = 87; x <= 93; x++) {
              for (var c = 0; c < 4; c++) {
                final i = (y * 240 + x) * 4 + c;
                final expected =
                    (full[i] * value + background[i] * (255 - value)) / 255;
                final error = (actual[i] - expected).abs();
                if (error > 2) bad++;
                if (error > maximum) maximum = error;
              }
            }
          }
          if (bad > 0) {
            failures.add('alpha=$value: $bad channels, max=$maximum');
          }
        }
        if (input == 'mask-child' || pointwise) {
          backdropPhase.value = 1;
          final nextBackground = await capture(0);
          final nextFull = await capture(1);
          final nextHalf = await capture(128 / 255);
          expect(nextBackground, isNot(orderedEquals(background)));
          expect(nextFull, isNot(orderedEquals(full)));
          for (var y = 101; y <= 107; y++) {
            for (var x = 87; x <= 93; x++) {
              for (var c = 0; c < 4; c++) {
                final i = (y * 240 + x) * 4 + c;
                final expected =
                    (nextFull[i] * 128 + nextBackground[i] * 127) / 255;
                expect(
                  (nextHalf[i] - expected).abs(),
                  lessThanOrEqualTo(2),
                  reason: 'Backdrop-only change must use the same cached mask.',
                );
              }
            }
          }
        }
        expect(failures, isEmpty);
      });
    }
  }
}

class _GroupCoordinateClip extends CustomClipper<Rect> {
  const _GroupCoordinateClip();

  @override
  Rect getClip(Size size) => const Rect.fromLTWH(16, 64, 208, 80);

  @override
  bool shouldReclip(_GroupCoordinateClip oldClipper) => false;
}

class _NativeBackdropMask extends CustomPainter {
  const _NativeBackdropMask(this.shader);

  final ui.FragmentShader shader;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = shader
        ..blendMode = BlendMode.dstIn,
    );
  }

  @override
  bool shouldRepaint(_NativeBackdropMask oldDelegate) =>
      oldDelegate.shader != shader;
}

void _filterOutputOpacityTests(SubmittedSceneCapture binding) {
  for (final mode in [
    'blur',
    'tint',
    if (const bool.fromEnvironment('PROBE_NATIVE_SHADER_ALPHA')) ...[
      'shader',
      'shader-native-clip',
    ],
  ]) {
    testWidgets('completed backdrop output fades $mode', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(240, 160)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final alpha = ValueNotifier<int>(255);
      addTearDown(alpha.dispose);
      var material = ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8);
      if (mode == 'tint') {
        material = ui.ImageFilter.compose(
          inner: material,
          outer: const ColorFilter.mode(Color(0x602080D0), BlendMode.srcOver),
        );
      }
      ui.FragmentShader? shader;
      if (mode.startsWith('shader')) {
        final program = (await tester.runAsync(
          () => ui.FragmentProgram.fromAsset(
            'integration_test/filter_output_opacity.frag',
          ),
        ))!;
        shader = program.fragmentShader()
          ..setFloat(3, mode == 'shader' ? 1 : 0);
        addTearDown(shader.dispose);
      }
      ui.ImageFilter filter(int value) {
        if (shader case final shader?) {
          shader.setFloat(2, value / 255);
          return ui.ImageFilter.shader(shader);
        }
        return ui.ImageFilter.compose(
          inner: material,
          outer: ColorFilter.mode(
            Color.fromARGB(value, 255, 255, 255),
            BlendMode.modulate,
          ),
        );
      }

      final filterWidget = ValueListenableBuilder<int>(
        valueListenable: alpha,
        builder: (_, value, _) => BackdropFilter(
          filter: filter(value),
          child: const SizedBox.expand(),
        ),
      );
      final nativeClip = mode == 'shader-native-clip';
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const CustomPaint(painter: _Background()),
              Positioned(
                left: nativeClip ? 65 : 16,
                top: nativeClip ? 79 : 64,
                width: nativeClip ? 50 : 208,
                height: nativeClip ? 50 : 80,
                child: nativeClip
                    ? ClipOval(child: filterWidget)
                    : ClipRect(child: filterWidget),
              ),
            ],
          ),
        ),
      );
      Future<Uint8List> capture(int value) async {
        alpha.value = value;
        binding
          ..captured = null
          ..captureNextScene = true
          ..scheduleFrame();
        await tester.pump();
        expect(binding.captureNextScene, isFalse);
        final image = (await tester.runAsync(() => binding.captured!))!;
        try {
          final data = (await tester.runAsync(image.toByteData))!;
          return Uint8List.fromList(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
        } finally {
          image.dispose();
          binding.captured = null;
        }
      }

      final background = await capture(0);
      final full = await capture(255);
      expect(full, isNot(orderedEquals(background)));
      for (final value in [254, 128, 32, 0, 255, 128]) {
        final actual = await capture(value);
        var mismatches = 0;
        var maximum = 0.0;
        for (var i = 0; i < actual.length; i++) {
          final expected =
              (full[i] * value + background[i] * (255 - value)) / 255;
          final error = (actual[i] - expected).abs();
          if (error > 2) mismatches++;
          if (error > maximum) maximum = error;
        }
        expect(
          mismatches,
          0,
          reason: 'completed filter alpha=$value max error=$maximum',
        );
      }
    });
  }
}

class _Background extends CustomPainter {
  const _Background({this.phase = 0});

  final int phase;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = false;
    for (var y = 0; y < size.height; y += 16) {
      for (var x = 0; x < size.width; x += 16) {
        paint.color = (x ~/ 16 + y ~/ 16 + phase).isEven
            ? const Color(0xFF2468AC)
            : const Color(0xFFEDCBA9);
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 16, 16),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Background oldDelegate) => oldDelegate.phase != phase;
}
