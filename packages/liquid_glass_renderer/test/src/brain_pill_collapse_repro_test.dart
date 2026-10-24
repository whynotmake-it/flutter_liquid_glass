// Regression tests modeled on a collapsing bottom-bar pill (from ClickUp).
// Each group guards one behavior:
//
//  A. A glass child keeps its state while visibility crosses 1 during a
//     bouncy animation.
//  B. A real `LiquidGlassLayer` keeps its child mounted when async Flutter
//     GPU initialization finishes.
//  C. The combined collapse scene: child state survives while the pill
//     overshoots visibility 1.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/fake_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';

import 'shared.dart';

void main() {
  setUp(_Probe.created.clear);

  const shape = LiquidRoundedSuperellipse(borderRadius: 20);
  const probeChild = SizedBox(width: 120, height: 44, child: _Probe());
  const visibilitySteps = <double>[0.5, 1, 1.1, 0.95, 1, 0, 1];

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
    var glass = switch (config.kind) {
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
    Widget Function(double v) scene,
  ) async {
    await tester.pumpWidget(scene(1));
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
      await driveVisibilitySequence(tester, (v) => aScene(_AConfig.a1, v));
    }, skip: skipProperGlassTests);

    testWidgets('A1 appearance-driven (unclamped)', (tester) async {
      await driveVisibilitySequence(
        tester,
        (v) => aScene(_AConfig.a1, v, viaAppearance: true),
      );
    }, skip: skipProperGlassTests);

    testWidgets('A2 real layer + ungrouped glass', (tester) async {
      await driveVisibilitySequence(tester, (v) => aScene(_AConfig.a2, v));
    }, skip: skipProperGlassTests);

    testWidgets('A3 fake layer + blend group + grouped', (tester) async {
      await driveVisibilitySequence(tester, (v) => aScene(_AConfig.a3, v));
    });

    testWidgets('A3 appearance-driven (unclamped)', (tester) async {
      await driveVisibilitySequence(
        tester,
        (v) => aScene(_AConfig.a3, v, viaAppearance: true),
      );
    });

    testWidgets('A4 fake layer + ungrouped glass', (tester) async {
      await driveVisibilitySequence(tester, (v) => aScene(_AConfig.a4, v));
    });

    testWidgets('A5 standalone FakeGlass (no layer)', (tester) async {
      await driveVisibilitySequence(tester, (v) => aScene(_AConfig.a5, v));
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
        await tester.pump();
        await tester.pump();
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
        await tester.pump();
        await tester.pump();
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

  group('C. clickup-like collapse scene', () {
    for (final fake in [false, true]) {
      testWidgets(
        'C ${fake ? 'fake' : 'real'}: pill collapse keeps state',
        (tester) async {
          await tester.pumpWidget(_CollapseScene(fake: fake, open: false));
          await tester.pumpAndSettle();
          await tester.pumpWidget(_CollapseScene(fake: fake, open: true));
          await tester.pumpAndSettle();
          _Probe.created.clear();
          await tester.pumpWidget(_CollapseScene(fake: fake, open: false));
          for (var frame = 0; frame < 50; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          expect(
            _Probe.created,
            hasLength(1),
            reason: 'expected exactly one probe State across the collapse',
          );
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

enum _AKind { grouped, plain, standaloneFake }

enum _ALayer { real, fake, none }

enum _AConfig {
  a1(_AKind.grouped, _ALayer.real),
  a2(_AKind.plain, _ALayer.real),
  a3(_AKind.grouped, _ALayer.fake),
  a4(_AKind.plain, _ALayer.fake),
  a5(_AKind.standaloneFake, _ALayer.none);

  const _AConfig(this.kind, this.layer);

  final _AKind kind;
  final _ALayer layer;

  bool get grouped => kind == _AKind.grouped;
}

const _toolbarAppearance = LiquidGlassAppearance.ios27RegularLight();

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
                      transitionBuilder: (child, animation) => SlideTransition(
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
    );
  }
}
