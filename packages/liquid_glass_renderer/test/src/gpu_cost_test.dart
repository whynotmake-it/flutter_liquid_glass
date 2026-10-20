// Locks down the per-frame pass and memory-traffic budgets of the glass
// composition patterns that matter most.
//
// Impeeler replays the last frame through a model of Impeller's pass logic.
// A plain frame is 1 pass and 1.0x traffic; every extra pass stores an
// offscreen texture and reads it back. The budgets below are per device
// because Metal (framebuffer fetch) and Pixel 10 (no fetch) split passes
// differently.
//
// Flutter GPU draws the geometry mattes in their own command buffers, which
// are outside the scene Impeeler replays. These budgets cover the layer-tree
// passes (backdrop capture, blur, shader filter, snapshot) that the scene
// contributes. A change that adds another backdrop capture, blur pass or
// saveLayer still fails these tests.
//
// Impeeler's model is pinned to Flutter 3.47.1. When the SDK moves, re-measure
// these budgets instead of widening them blindly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impeeler/impeeler.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

const _settings = LiquidGlassSettings(
  frost: 8,
  refractionAmount: 30,
  highlight: 0.5,
);

const _shape = LiquidRoundedSuperellipse(borderRadius: 28);
const _backdropLayer = 'GeometryTransformTrackingLayer';

typedef _Budget = ({int passes, double traffic});

// Counts are exact `renderPasses`; traffic is `relativeToPlainFrame` to three
// decimals. When a change improves either number, lower the budget here so
// the improvement is locked in and cannot regress later.
const _singleGlassBudget = <String, _Budget>{
  'iPhone 16': (passes: 7, traffic: 3.535),
  'Pixel 9': (passes: 7, traffic: 3.504),
  'Pixel 10': (passes: 8, traffic: 5.504),
};

const _blendGroupBudget = <String, _Budget>{
  'iPhone 16': (passes: 7, traffic: 3.578),
  'Pixel 9': (passes: 7, traffic: 3.548),
  'Pixel 10': (passes: 8, traffic: 5.548),
};

const _twoLayersBudget = <String, _Budget>{
  'iPhone 16': (passes: 13, traffic: 6.689),
  'Pixel 9': (passes: 13, traffic: 5.740),
  'Pixel 10': (passes: 14, traffic: 7.740),
};

const _nestedLayersBudget = <String, _Budget>{
  'iPhone 16': (passes: 13, traffic: 6.121),
  'Pixel 9': (passes: 13, traffic: 6.016),
  'Pixel 10': (passes: 14, traffic: 8.016),
};

const _fakeGlassBudget = <String, _Budget>{
  'iPhone 16': (passes: 6, traffic: 3.213),
  'Pixel 9': (passes: 6, traffic: 3.209),
  'Pixel 10': (passes: 7, traffic: 5.209),
};

Widget _background(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Stack(
    fit: StackFit.expand,
    children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E3A8A), Color(0xFFF59E0B)],
          ),
        ),
      ),
      Center(child: child),
    ],
  ),
);

Widget _glass({bool fake = false}) => _background(
  LiquidGlassLayer(
    fake: fake,
    settings: _settings,
    child: const LiquidGlass(
      shape: _shape,
      child: SizedBox(width: 220, height: 90),
    ),
  ),
);

Widget _blendGroup() => _background(
  LiquidGlassLayer(
    settings: _settings,
    child: LiquidGlassBlendGroup(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            const LiquidGlass.grouped(
              shape: LiquidOval(),
              child: SizedBox.square(dimension: 80),
            ),
        ],
      ),
    ),
  ),
);

Widget _twoLayers() => _background(
  const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      LiquidGlass.withOwnLayer(
        settings: _settings,
        shape: _shape,
        child: SizedBox(width: 160, height: 80),
      ),
      SizedBox(width: 16),
      LiquidGlass.withOwnLayer(
        settings: _settings,
        shape: _shape,
        child: SizedBox(width: 160, height: 80),
      ),
    ],
  ),
);

Widget _nestedLayers() => _background(
  const LiquidGlassLayer(
    settings: _settings,
    child: LiquidGlass(
      shape: _shape,
      child: SizedBox(
        width: 240,
        height: 160,
        child: Center(
          child: LiquidGlass.withOwnLayer(
            settings: _settings,
            shape: LiquidRoundedSuperellipse(borderRadius: 20),
            child: SizedBox(width: 120, height: 70),
          ),
        ),
      ),
    ),
  ),
);

/// Waits until every glass layer found a Flutter GPU renderer, so the
/// estimate measures the real effect instead of the fake fallback.
Future<void> _pumpUntilGlassReady(WidgetTester tester) async {
  for (var frame = 0; frame < 60; frame++) {
    final scopes = tester.widgetList<LiquidGlassRenderScope>(
      find.byType(LiquidGlassRenderScope),
    );
    final realLayers = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .where((layer) => layer.attached && layer.gpuGeometryRenderer != null);
    if (scopes.isNotEmpty &&
        scopes.every((scope) => !scope.useFake) &&
        realLayers.isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  fail('Glass never became GPU-backed; run with --enable-flutter-gpu.');
}

Future<GpuReport> _estimate(
  WidgetTester tester,
  Widget scene, {
  bool real = true,
}) async {
  await tester.pumpWidget(scene);
  if (real) await _pumpUntilGlassReady(tester);
  return estimateGpu(
    tester,
    devices: GpuDevice.phones,
    frameDemandWindow: null,
    writeFiles: false,
  );
}

void _expectBudget(GpuReport report, Map<String, _Budget> budgets) {
  for (final frame in report.frames) {
    final budget =
        budgets[frame.device.name] ??
        fail('No Impeeler budget for ${frame.device.name}.');
    final where =
        '${frame.device.name}: ${frame.renderPasses} passes '
        '(${frame.renderPassesByLabel}), '
        '${frame.traffic.relativeToPlainFrame.toStringAsFixed(2)}x traffic';

    // A silently unmodeled custom layer would make the estimate too low.
    expect(
      frame.sceneLayers,
      contains(_backdropLayer),
      reason: '$where; the glass backdrop layer was not read by Impeeler.',
    );
    expect(frame.unmodeledLayers, isEmpty, reason: where);
    expect(frame.missingPictures, 0, reason: where);
    expect(
      frame.renderPasses,
      budget.passes,
      reason: '$where expected exactly ${budget.passes} passes.',
    );
    expect(
      frame.traffic.relativeToPlainFrame,
      moreOrLessEquals(budget.traffic, epsilon: 0.001),
      reason: '$where expected exactly ${budget.traffic}x traffic.',
    );
  }
}

void main() {
  // This test file needs Impeeler's recording binding. It is installed here
  // rather than in flutter_test_config.dart because some test files install
  // their own specialized binding.
  ImpeelerBinding.ensureInitialized();

  testWidgets('a plain frame is the 1-pass baseline', (tester) async {
    await tester.pumpWidget(_background(const SizedBox()));
    final report = await estimateGpu(
      tester,
      devices: GpuDevice.phones,
      frameDemandWindow: null,
      writeFiles: false,
    );

    for (final frame in report.frames) {
      expect(frame.renderPasses, 1, reason: frame.device.name);
      expect(
        frame.traffic.relativeToPlainFrame,
        1.0,
        reason: frame.device.name,
      );
      expect(frame.unmodeledLayers, isEmpty, reason: frame.device.name);
      expect(frame.missingPictures, 0, reason: frame.device.name);
    }
  });

  testWidgets('one glass layer stays at the single-backdrop budget', (
    tester,
  ) async {
    final report = await _estimate(tester, _glass());
    _expectBudget(report, _singleGlassBudget);
  }, skip: skipProperGlassTests);

  testWidgets('blending three shapes adds no render passes', (tester) async {
    final report = await _estimate(tester, _blendGroup());
    _expectBudget(report, _blendGroupBudget);
  }, skip: skipProperGlassTests);

  testWidgets('two independent glass layers stay at two backdrops', (
    tester,
  ) async {
    final report = await _estimate(tester, _twoLayers());
    _expectBudget(report, _twoLayersBudget);
  }, skip: skipProperGlassTests);

  testWidgets('nested glass layers stay at two backdrops', (tester) async {
    final report = await _estimate(tester, _nestedLayers());
    _expectBudget(report, _nestedLayersBudget);
  }, skip: skipProperGlassTests);

  testWidgets('fake glass matches the fallback budget', (tester) async {
    final report = await _estimate(tester, _glass(fake: true), real: false);
    _expectBudget(report, _fakeGlassBudget);
  });

  testWidgets('a static glass screen requests no idle frames', (tester) async {
    await tester.pumpWidget(_glass());
    await _pumpUntilGlassReady(tester);

    final report = await estimateGpu(
      tester,
      devices: [GpuDevice.iPhone16],
      writeFiles: false,
    );

    expect(report.frameDemand, isNotNull);
    expect(report.frameDemand!.verdict, FrameDemandVerdict.idle);
    expect(report.frameDemand!.frames, isEmpty);
  }, skip: skipProperGlassTests);
}
