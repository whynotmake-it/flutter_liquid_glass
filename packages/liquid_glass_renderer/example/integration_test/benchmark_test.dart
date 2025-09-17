import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Performance Tests', () {
    const duration = Duration(seconds: 5);

    testWidgets('measures performance of liquid glass rendering', (
      tester,
    ) async {
      await binding.traceAction(() async {
        await tester.pumpFrames(
          const _SingleTestApp(withGlass: false),
          duration,
        );
      }, reportKey: 'basic_test_baseline');

      await binding.traceAction(() async {
        await tester.pumpFrames(
          const _SingleTestApp(withGlass: true),
          duration,
        );
      }, reportKey: 'basic_test_with_glass');
    });

    testWidgets('measures performance with multiple liquid glass elements', (
      tester,
    ) async {
      await binding.traceAction(() async {
        await tester.pumpFrames(
          const _MultiTestApp(withGlass: false),
          duration,
        );
      }, reportKey: 'multi_test_baseline');

      await binding.traceAction(() async {
        await tester.pumpFrames(
          const _MultiTestApp(withGlass: true, useLayer: false),
          duration,
        );
      }, reportKey: 'multi_test_with_separate_glass');

      await binding.traceAction(() async {
        await tester.pumpFrames(
          const _MultiTestApp(withGlass: true, useLayer: true),
          duration,
        );
      }, reportKey: 'multi_test_with_glass_layer');
    });
  });
}

/// Grid paper background widget for benchmarks
class _GridPaperBackground extends StatelessWidget {
  final Widget child;

  const _GridPaperBackground({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFCEC5B4), Color(0xFFF2F0EA)],
            ),
          ),
          child: GridPaper(
            color: const Color(0xFF0F0B0A).withValues(alpha: 0.2),
            interval: 100,
            child: const SizedBox.expand(),
          ),
        ),
        child,
      ],
    );
  }
}

class _SingleTestApp extends StatelessWidget {
  const _SingleTestApp({this.withGlass = true});

  final bool withGlass;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: 200,
      height: 200,
      child: const Center(
        child: Text(
          'Liquid Glass',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
    return MaterialApp(
      home: Scaffold(
        body: _GridPaperBackground(
          child: Center(
            child: withGlass
                ? LiquidGlass(
                    key: const Key('liquid_glass_widget'),
                    shape: LiquidRoundedSuperellipse(
                      borderRadius: Radius.circular(20),
                    ),
                    settings: const LiquidGlassSettings(
                      thickness: 40,
                      blur: 20,
                    ),
                    child: content,
                  )
                : content,
          ),
        ),
      ),
    );
  }
}

class _MultiTestApp extends StatelessWidget {
  const _MultiTestApp({this.withGlass = true, this.useLayer = false});

  final bool withGlass;

  final bool useLayer;

  @override
  Widget build(BuildContext context) {
    const settings = LiquidGlassSettings(
      thickness: 30,
      blur: 15,
      lightIntensity: 0.5,
      ambientStrength: 0.3,
      chromaticAberration: 0.02,
    );

    final content = Column(
      children: List.generate(5, (index) {
        final listItem = Container(
          width: 150,
          height: 100,
          color: Colors.primaries[index % Colors.primaries.length],
          child: Center(
            child: Text(
              'Item $index',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        );
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: switch ((withGlass, useLayer)) {
            (true, false) => LiquidGlass(
              key: Key('liquid_glass_$index'),
              shape: LiquidRoundedSuperellipse(
                borderRadius: Radius.circular(15),
              ),
              settings: settings,
              child: listItem,
            ),
            (true, true) => LiquidGlass.inLayer(
              shape: LiquidRoundedSuperellipse(
                borderRadius: Radius.circular(15),
              ),
              child: Container(
                key: Key('liquid_glass_$index'),
                decoration: ShapeDecoration(
                  shape: LiquidRoundedSuperellipse(
                    borderRadius: Radius.circular(15),
                  ),
                ),
                child: listItem,
              ),
            ),
            (false, _) => listItem,
          },
        );
      }),
    );
    return MaterialApp(
      home: Scaffold(
        body: _GridPaperBackground(
          child: switch (useLayer) {
            true => LiquidGlassLayer(child: content, settings: settings),
            false => content,
          },
        ),
      ),
    );
  }
}
