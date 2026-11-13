import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart';
import 'package:liquid_glass_renderer/src/composer/plan_result.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_form.dart';
import 'package:liquid_glass_renderer/src/rendering/transform_tracking_render_object_mixin.dart';
import 'package:material_ui/material_ui.dart';

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

/// Draws every copy of the current test into an image, as copies asked for
/// with a filter always are, for tests of how images are shared and held.
void copyIntoImages() {
  debugGlassPolicy = const PlanPolicy(maxTargets: 0);
  addTearDown(() => debugGlassPolicy = const PlanPolicy());
}

/// What the plans of the current test decided.
final class PlanWatch {
  /// Watches every plan from here to the end of the test.
  PlanWatch() {
    GlassComposer.debugOnPlan = _note;
    addTearDown(() => GlassComposer.debugOnPlan = null);
  }

  final _changes = Map<Object, int>.identity();

  /// The last plan.
  GlassPlan? last;

  void _note(GlassForm form, GlassPlan plan) {
    last = plan;
    for (var i = 0; i < plan.fates.length; i++) {
      final read = switch (plan.fates[i]) {
        LeadFate(:final read) || FollowFate(:final read) => read,
        HiddenFate() => null,
      };
      if (read == null || !read.changed) continue;
      final id = form.sites[i].id;
      final site = id is GeometryTransformTrackingLayer ? id.trackedSite! : id;
      _changes[site] = (_changes[site] ?? 0) + 1;
    }
  }

  /// In how many plans the read of [site], a render object or a filter layer,
  /// held something new.
  int changes(Object site) => _changes[site] ?? 0;
}
