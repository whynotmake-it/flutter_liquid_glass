import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/backdrop_seed.dart';

const expectFlutterGpuFallback = bool.fromEnvironment(
  'EXPECT_FLUTTER_GPU_FALLBACK',
);

bool get skipProperGlassTests =>
    expectFlutterGpuFallback || !ui.ImageFilter.isShaderFilterSupported;

/// Alchemist still calls `testWidgets` when a golden is tagged `golden`, and
/// Flutter 3.44 asserts that the variant is non-empty. Platform goldens are
/// macOS-only, so skip registration on other hosts instead of loading an
/// empty variant.
bool get skipGoldenTests => skipProperGlassTests || !Platform.isMacOS;

/// Compares [actual] with the pixel reference at [path], on macOS only.
///
/// References are rendered by `flutter test --update-goldens` on the macOS
/// image the CI golden job uses; flutter_tester rasterizes differently on
/// other hosts, so they skip the comparison and keep the test's other checks.
Future<void> expectMacOSGolden(Object? actual, String path) async {
  if (!Platform.isMacOS) return;
  await expectLater(actual, matchesGoldenFile(path));
}

final testScenarioConstraints = BoxConstraints.tight(const Size(500, 500));

const settingsWithoutLighting = LiquidGlassSettings(
  highlight: 0,
  contourStrength: 0,
  bevelShadowStrength: 0,
  frost: 0,
);

Widget buildWithGridPaper(Widget child) {
  return ColoredBox(
    color: Colors.white,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          const Positioned.fill(
            child: GridPaper(
              color: Colors.black,
            ),
          ),
          Center(
            child: child,
          ),
        ],
      ),
    ),
  );
}

/// Pins the optimization that changes what the plain backdrop path draws or
/// how many passes it costs (the native seeds) off for the current test, so it
/// measures that path whatever `--dart-define`s set the default to
/// (`melos run test:defaults` runs the suite with the production one). A test
/// that wants seeds turns them on itself, after this. Call it from `setUp`;
/// the flag is restored after the test.
///
/// Also used by the tests that compare captured pixels of real glass, in
/// flutter_tester: it renders a seeded pass of real glass wrongly there
/// (colour and alpha, differently from run to run: the foreground painted
/// after the pass is erased, or the whole frame comes out partly transparent),
/// while macOS Metal renders it exactly as the plain path does. The same
/// scenes run unpinned on a device by the `*_device_test.dart` wrappers in
/// `example/integration_test`.
void pinPlainBackdropPath() {
  final seed = liquidGlassNativeSeed;
  liquidGlassNativeSeed = LiquidGlassNativeSeed.none;
  addTearDown(() => liquidGlassNativeSeed = seed);
}

/// The passes of the current frame that are natively seeded.
///
/// A device run uses the production defaults, so a scene with a blurred glass
/// has some; a host run pins them off (see [pinPlainBackdropPath]).
List<SeededBackdropPassLayer> seededPasses(WidgetTester tester) => tester
    .binding
    .renderViews
    .single
    .debugLayer!
    .depthFirstIterateChildren()
    .whereType<SeededBackdropPassLayer>()
    .where((pass) => pass.nativeSeed != LiquidGlassNativeSeed.none)
    .toList();
