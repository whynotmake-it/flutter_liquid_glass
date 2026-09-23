// Reproduction tests for glass-rendering bugs seen in the ClickUp bottom
// bar's collapsing "brain pill". These are expected to FAIL today; each group
// isolates one hypothesis:
//
//  A. `_maybeFade` (liquid_glass.dart / fake_glass.dart) swaps `child` for
//     `Opacity(child)` when visibility crosses 1, remounting the glass child
//     subtree on every crossing of a bouncy animation.
//  B. A real `LiquidGlassLayer` starts as a fake layer until async Flutter GPU
//     init finishes, then `_buildLayer` returns a different subtree and the
//     whole child remounts once after mount.
//  C. `RenderLiquidGlassCapture` recomputes its clip region only in paint();
//     paint-only changes inside the layer's RepaintBoundary (visibility,
//     translation) leave a stale `captureRect` that clips shadows.
//  D. The combined ClickUp-like collapse scene: probe-state survival and
//     per-frame capture coverage while the pill overshoots visibility 1.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/fake_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_capture.dart';

import 'capture_scenes.dart';
import 'shared.dart';
import 'submitted_scene_binding.dart';

void main() {
  final binding = SubmittedSceneBinding();

  setUp(_Probe.created.clear);

  const shape = LiquidRoundedSuperellipse(borderRadius: 20);
  const probeChild = SizedBox(width: 120, height: 44, child: _Probe());
  const visibilitySteps = [0.5, 1.0, 1.1, 0.95, 1.0, 0.0, 1.0];

  Widget framed(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  );

  /// Builds one A-config glass shape with visibility driven either through a
  /// [LiquidGlassVisibility] above it or an unclamped per-shape appearance.
  Widget aScene(
    _AConfig config,
    double v, {
    bool viaAppearance = false,
  }) {
    final appearance = viaAppearance
        ? const LiquidGlassAppearance().copyWith(visibility: v)
        : null;
    Widget glass = switch (config.kind) {
      _AKind.grouped => LiquidGlass.grouped(
        shape: shape,
        appearance: appearance,
        child: probeChild,
      ),
      _AKind.plain => LiquidGlass(
        shape: shape,
        appearance: appearance,
        child: probeChild,
      ),
      _AKind.standaloneFake => FakeGlass(
        shape: shape,
        settings: const LiquidGlassSettings(),
        appearance: appearance,
        child: probeChild,
      ),
    };
    if (!viaAppearance) {
      glass = LiquidGlassVisibility(visibility: v, child: glass);
    }
    if (config.grouped) {
      glass = LiquidGlassBlendGroup(child: glass);
    }
    return framed(
      switch (config.layer) {
        _ALayer.real => LiquidGlassLayer(child: glass),
        _ALayer.fake => LiquidGlassLayer(fake: true, child: glass),
        _ALayer.none => glass,
      },
    );
  }

  /// Mounts [scene] at visibility 1, waits for real layers if needed, then
  /// steps through [visibilitySteps] and requires that no new probe State is
  /// created after the baseline.
  Future<void> driveVisibilitySequence(
    WidgetTester tester,
    Widget Function(double v) scene, {
    required bool real,
  }) async {
    await tester.pumpWidget(scene(1.0));
    if (real) {
      await pumpUntilGlassReady(tester);
    }
    // Let MultiShaderBuilder's async swap resolve so a shader-load remount
    // lands in the baseline instead of being attributed to a sequence step.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final baseline = _Probe.created.length;
    var firstBad = -1;
    for (var i = 0; i < visibilitySteps.length; i++) {
      await tester.pumpWidget(scene(visibilitySteps[i]));
      if (firstBad < 0 && _Probe.created.length > baseline) {
        firstBad = i;
      }
    }
    expect(
      _Probe.created,
      hasLength(baseline),
      reason:
          'probe State must survive the visibility sequence; first extra '
          'State appeared at step $firstBad '
          '(visibility=${firstBad < 0 ? "-" : visibilitySteps[firstBad]}); '
          'total States ${_Probe.created.length}, baseline $baseline',
    );
  }

  group('A. state survives visibility changes', () {
    testWidgets('A1 real layer + blend group + grouped', (tester) async {
      await driveVisibilitySequence(
        tester,
        (v) => aScene(_AConfig.a1, v),
        real: true,
      );
    }, skip: skipProperGlassTests);

    testWidgets('A1 appearance-driven (unclamped)', (tester) async {
      await driveVisibilitySequence(
        tester,
        (v) => aScene(_AConfig.a1, v, viaAppearance: true),
        real: true,
      );
    }, skip: skipProperGlassTests);

    testWidgets('A2 real layer + ungrouped glass', (tester) async {
      await driveVisibilitySequence(
        tester,
        (v) => aScene(_AConfig.a2, v),
        real: true,
      );
    }, skip: skipProperGlassTests);

    testWidgets('A3 fake layer + blend group + grouped', (tester) async {
      await driveVisibilitySequence(
        tester,
        (v) => aScene(_AConfig.a3, v),
        real: false,
      );
    });

    testWidgets('A3 appearance-driven (unclamped)', (tester) async {
      await driveVisibilitySequence(
        tester,
        (v) => aScene(_AConfig.a3, v, viaAppearance: true),
        real: false,
      );
    });

    testWidgets('A4 fake layer + ungrouped glass', (tester) async {
      await driveVisibilitySequence(
        tester,
        (v) => aScene(_AConfig.a4, v),
        real: false,
      );
    });

    testWidgets('A5 standalone FakeGlass (no layer)', (tester) async {
      await driveVisibilitySequence(
        tester,
        (v) => aScene(_AConfig.a5, v),
        real: false,
      );
    });
  });

  group('B. layer GPU-init remount', () {
    testWidgets(
      'real layer remounts glass child once GPU is ready',
      (
        tester,
      ) async {
        await tester.pumpWidget(
          framed(
            const LiquidGlassLayer(
              child: LiquidGlass(
                shape: LiquidRoundedSuperellipse(borderRadius: 20),
                child: SizedBox(width: 120, height: 44, child: _Probe()),
              ),
            ),
          ),
        );
        await pumpUntilGlassReady(tester);
        await _pumpUntilRealLayer(tester);
        expect(
          _Probe.created,
          hasLength(1),
          reason:
              'fake->real layer swap must not remount the subtree; '
              '${_Probe.created.length} probe States created',
        );
      },
      skip: skipProperGlassTests,
    );

    testWidgets(
      'real layer remounts a plain child once GPU is ready',
      (
        tester,
      ) async {
        await tester.pumpWidget(
          framed(const LiquidGlassLayer(child: _Probe())),
        );
        await pumpUntilGlassReady(tester);
        await _pumpUntilRealLayer(tester);
        expect(
          _Probe.created,
          hasLength(1),
          reason:
              'fake->real layer swap must not remount the subtree; '
              '${_Probe.created.length} probe States created',
        );
      },
      skip: skipProperGlassTests,
    );
  });

  group('C. capture staleness', () {
    const pillShadows = [
      BoxShadow(color: Color(0x1A000000), blurRadius: 30),
    ];

    Widget cScene({required bool fake, required _CVars vars}) => framed(
      LiquidGlassCapture(
        child: SizedBox(
          width: 300,
          height: 200,
          child: LiquidGlassLayer(
            fake: fake,
            child: Align(
              alignment: Alignment.topCenter,
              child: Transform.translate(
                offset: vars.offset,
                child: LiquidGlass(
                  shape: const LiquidRoundedSuperellipse(borderRadius: 22),
                  shadows: pillShadows,
                  appearance: const LiquidGlassAppearance().copyWith(
                    visibility: vars.visibility,
                  ),
                  child: const SizedBox(width: 120, height: 44),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Future<RenderLiquidGlassCapture> pumpCScene(
      WidgetTester tester, {
      required bool fake,
      required _CVars vars,
      required ValueSetter<StateSetter> stater,
    }) async {
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            stater(setState);
            return cScene(fake: fake, vars: vars);
          },
        ),
      );
      if (!fake) await pumpUntilGlassReady(tester);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      return tester.renderObject<RenderLiquidGlassCapture>(
        find.byType(LiquidGlassCapture),
      );
    }

    for (final fake in [false, true]) {
      final label = fake ? 'fake' : 'real';
      testWidgets(
        'C1 $label: visibility-only change refreshes captureRect',
        (
          tester,
        ) async {
          final vars = _CVars()..visibility = 0.05;
          late StateSetter setState;
          await pumpCScene(
            tester,
            fake: fake,
            vars: vars,
            stater: (s) => setState = s,
          );
          setState(() => vars.visibility = 1.0);
          await tester.pump();
          final capture = tester.renderObject<RenderLiquidGlassCapture>(
            find.byType(LiquidGlassCapture),
          );
          final fresh = _freshRegion(capture);
          expect(
            _containsWithTolerance(capture.captureRect, fresh),
            isTrue,
            reason:
                'captureRect ${capture.captureRect} does not contain fresh '
                '$fresh after visibility ${vars.visibility}',
          );
        },
        skip: !fake && skipProperGlassTests,
      );

      testWidgets(
        'C2 $label: translation-only change refreshes captureRect',
        (
          tester,
        ) async {
          final vars = _CVars()..offset = const Offset(0, 40);
          late StateSetter setState;
          await pumpCScene(
            tester,
            fake: fake,
            vars: vars,
            stater: (s) => setState = s,
          );
          setState(() => vars.offset = Offset.zero);
          await tester.pump();
          final capture = tester.renderObject<RenderLiquidGlassCapture>(
            find.byType(LiquidGlassCapture),
          );
          final fresh = _freshRegion(capture);
          expect(
            _containsWithTolerance(capture.captureRect, fresh),
            isTrue,
            reason:
                'captureRect ${capture.captureRect} does not contain fresh '
                '$fresh after translate to ${vars.offset}',
          );
        },
        skip: !fake && skipProperGlassTests,
      );
    }
  });

  group('D. clickup-like collapse scene', () {
    const pngFrames = {5, 10, 15, 20, 30};

    for (final fake in [false, true]) {
      final label = fake ? 'fake' : 'real';
      testWidgets(
        'D $label: pill collapse keeps state and coverage',
        (
          tester,
        ) async {
          await tester.pumpWidget(_CollapseScene(fake: fake, open: false));
          if (!fake) await pumpUntilGlassReady(tester);
          await tester.pumpAndSettle();
          await tester.pumpWidget(_CollapseScene(fake: fake, open: true));
          await tester.pumpAndSettle();
          _Probe.created.clear();
          await tester.pumpWidget(_CollapseScene(fake: fake, open: false));

          final rows = <String>[
            'frame | vis | states | pillRect | captureRect | fresh | flags',
          ];
          final failures = <String>[];
          for (var frame = 0; frame < 50; frame++) {
            final wantPng = pngFrames.contains(frame);
            if (wantPng) {
              binding
                ..captureWidth = tester.view.physicalSize.width.round()
                ..captureHeight = tester.view.physicalSize.height.round()
                ..captureNextScene = true
                ..scheduleFrame();
            }
            await tester.pump(const Duration(milliseconds: 16));

            final scene = tester.state<_CollapseSceneState>(
              find.byType(_CollapseScene),
            );
            final capture = tester.renderObject<RenderLiquidGlassCapture>(
              find.byType(LiquidGlassCapture),
            );
            final capGlobal = MatrixUtils.transformRect(
              capture.getTransformTo(null),
              capture.captureRect,
            );
            final fresh = _freshRegion(capture);
            final freshGlobal = MatrixUtils.transformRect(
              capture.getTransformTo(null),
              fresh,
            );
            final pill = _pillBox(tester);
            Rect? pillGlobal;
            if (pill != null) {
              pillGlobal = pill.localToGlobal(Offset.zero) & pill.size;
            }

            final flags = <String>[];
            if (!_containsWithTolerance(capture.captureRect, fresh)) {
              flags.add('STALE-CAPTURE');
              failures.add(
                'frame $frame: captureRect ${capture.captureRect} does not '
                'contain fresh $fresh (local)',
              );
            }
            if (scene.currentVisibility > 0.3 &&
                pillGlobal != null &&
                capGlobal.top > pillGlobal.top - 10) {
              flags.add('NO-HEADROOM');
            }
            rows.add(
              '${frame.toString().padLeft(5)} | '
              '${scene.currentVisibility.toStringAsFixed(3).padLeft(6)} | '
              '${_Probe.created.length.toString().padLeft(6)} | '
              '${'${pillGlobal ?? '-'}'.padRight(24)} | '
              '${'$capGlobal'.padRight(24)} | '
              '${'$freshGlobal'.padRight(24)} | '
              '${flags.join(',')}',
            );

            if (wantPng) {
              try {
                final image = await tester.runAsync(() => binding.captured!);
                if (image != null) {
                  final png = await tester.runAsync(
                    () => image.toByteData(format: ui.ImageByteFormat.png),
                  );
                  final name =
                      'd_${label}_frame${frame.toString().padLeft(2, '0')}';
                  await tester.runAsync(() async {
                    final file = File('/tmp/lg_repro/$name.png');
                    await file.create(recursive: true);
                    await file.writeAsBytes(png!.buffer.asUint8List());
                  });
                  image.dispose();
                }
              } catch (error) {
                debugPrint('png capture frame $frame failed: $error');
              }
            }
          }
          for (final row in rows) {
            debugPrint(row);
          }
          if (_Probe.created.length != 1) {
            failures.add(
              'expected exactly one probe State across the collapse; '
              'got ${_Probe.created.length}',
            );
          }
          expect(failures, isEmpty, reason: failures.join('\n'));
        },
        skip: !fake && skipProperGlassTests,
      );
    }
  });
}

/// Records every [State] created so tests can detect subtree remounts.
class _Probe extends StatefulWidget {
  const _Probe();

  static final List<State<StatefulWidget>> created = [];

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _Probe.created.add(this);
  }

  @override
  Widget build(BuildContext context) => const Text('probe');
}

/// Mutable inputs for the C scenes so `setState` can drive visibility and
/// translation changes without rebuilding the whole harness.
class _CVars {
  double visibility = 1;
  Offset offset = Offset.zero;
}

enum _AKind { grouped, plain, standaloneFake }

enum _ALayer { real, fake, none }

class _AConfig {
  const _AConfig._(this.kind, this.layer, this.grouped);

  static const a1 = _AConfig._(_AKind.grouped, _ALayer.real, true);
  static const a2 = _AConfig._(_AKind.plain, _ALayer.real, false);
  static const a3 = _AConfig._(_AKind.grouped, _ALayer.fake, true);
  static const a4 = _AConfig._(_AKind.plain, _ALayer.fake, false);
  static const a5 = _AConfig._(_AKind.standaloneFake, _ALayer.none, false);

  final _AKind kind;
  final _ALayer layer;
  final bool grouped;
}

/// The capture region `RenderLiquidGlassCapture._computeRegion` would compute
/// right now: layout box plus every descendant glass layer's effect bounds.
Rect _freshRegion(RenderLiquidGlassCapture capture) {
  var region = Offset.zero & capture.size;
  for (final layer in glassLayersBelow(capture)) {
    final bounds = layer.effectBounds;
    if (bounds == null) continue;
    region = region.expandToInclude(
      MatrixUtils.transformRect(
        (layer as RenderObject).getTransformTo(capture),
        bounds,
      ),
    );
  }
  return region;
}

bool _containsWithTolerance(
  Rect outer,
  Rect inner, {
  double tolerance = 1,
}) =>
    inner.left >= outer.left - tolerance &&
    inner.top >= outer.top - tolerance &&
    inner.right <= outer.right + tolerance &&
    inner.bottom <= outer.bottom + tolerance;

/// The render box of the pill's glass shape, or null while the pill is
/// absent from the tree.
RenderBox? _pillBox(WidgetTester tester) {
  final elements = find.byKey(const ValueKey('pill')).evaluate();
  if (elements.isEmpty) return null;
  RenderObject? node = elements.first.findRenderObject();
  while (node != null &&
      node is! RenderLiquidGlass &&
      node is! RenderFakeGlass) {
    node = node.parent as RenderObject?;
  }
  return node is RenderBox ? node : null;
}

const _toolbarAppearance = LiquidGlassAppearance.ios27ToolbarLight();

const _pillShadows = [
  BoxShadow(color: Color(0x1A000000), blurRadius: 30),
];

/// Approximation of the ClickUp bottom bar: an expanding grouped container
/// and a "brain pill" that slides in/out through an [AnimatedSwitcher] while
/// its glass visibility follows the (overshooting) switch animation.
class _CollapseScene extends StatefulWidget {
  const _CollapseScene({required this.fake, required this.open});

  final bool fake;
  final bool open;

  @override
  State<_CollapseScene> createState() => _CollapseSceneState();
}

class _CollapseSceneState extends State<_CollapseScene> {
  double currentVisibility = 0;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 360,
          child: LiquidGlassCapture(
            child: LiquidGlassLayer(
              fake: widget.fake,
              defaultAppearance: _toolbarAppearance,
              child: LiquidGlassBlendGroup(
                blend: 7,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 64),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 500),
                        switchInCurve: Curves.easeOutBack,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) =>
                            SlideTransition(
                              position:
                                  Tween(
                                    begin: const Offset(0, 1),
                                    end: Offset.zero,
                                  ).animate(
                                    animation,
                                  ),
                              child: AnimatedBuilder(
                                animation: animation,
                                builder: (_, c) {
                                  currentVisibility = animation.value;
                                  return LiquidGlass.grouped(
                                    shape: const LiquidRoundedSuperellipse(
                                      borderRadius: 22,
                                    ),
                                    shadows: _pillShadows,
                                    appearance: _toolbarAppearance.copyWith(
                                      visibility: animation.value,
                                    ),
                                    child: c!,
                                  );
                                },
                                child: child,
                              ),
                            ),
                        child: widget.open
                            ? const SizedBox.shrink(key: ValueKey('empty'))
                            : const KeyedSubtree(
                                key: ValueKey('pill'),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 11,
                                  ),
                                  child: _Probe(),
                                ),
                              ),
                      ),
                    ),
                    LiquidGlass.grouped(
                      shape: const LiquidRoundedSuperellipse(
                        borderRadius: 28,
                      ),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 550),
                        curve: Curves.easeOut,
                        child: SizedBox(
                          width: 300,
                          height: widget.open ? 256 : 56,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `pumpUntilGlassReady` returns on the first frame because the fake layer's
/// scope also reports `useFake == false`; wait for the real render object.
Future<void> _pumpUntilRealLayer(WidgetTester tester) async {
  bool isReal() => tester.allRenderObjects.any(
    (r) => r.runtimeType.toString() == 'RenderLiquidGlassLayer',
  );
  for (var frame = 0; frame < 60 && !isReal(); frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(isReal(), isTrue, reason: 'real LiquidGlassLayer never appeared');
}
