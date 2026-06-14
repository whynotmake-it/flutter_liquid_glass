import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

// TODO import from experimental once that is done

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

    testWidgets('measures performance of a translating liquid glass element', (
      tester,
    ) async {
      // Exercises the translation fast path: a large glass element slides every
      // frame, which previously re-baked a full-screen geometry texture per
      // frame (memory spikes). It should now reuse the cached matte.
      await binding.traceAction(() async {
        await tester.pumpFrames(
          const _AnimatedTranslateTestApp(),
          duration,
        );
      }, reportKey: 'animated_translate_with_glass');
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
          const _MultiTestApp(withGlass: true, shareLayer: false),
          duration,
        );
      }, reportKey: 'multi_test_with_separate_glass');

      await binding.traceAction(() async {
        await tester.pumpFrames(
          const _MultiTestApp(withGlass: true, shareLayer: true),
          duration,
        );
      }, reportKey: 'multi_test_with_glass_layer');
    });
  });
}

enum RenderMode { filter, layer }

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
    final settings = const LiquidGlassSettings(thickness: 40, blur: 20);
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

    final glass = Center(
      child: withGlass
          ? LiquidGlassLayer(
              settings: settings,
              child: LiquidGlass(
                shape: LiquidRoundedSuperellipse(borderRadius: 20),
                child: Container(
                  key: const Key('liquid_glass_widget'),
                  decoration: ShapeDecoration(
                    shape: LiquidRoundedSuperellipse(borderRadius: 20),
                  ),
                  child: content,
                ),
              ),
            )
          : content,
    );

    return MaterialApp(
      home: Scaffold(
        body: _GridPaperBackground(
          child: LiquidGlassLayer(settings: settings, child: glass),
        ),
      ),
    );
  }
}

/// A large glass panel that continuously translates, mimicking an animated
/// sheet. Drives the Phase 1 translation fast path (zero per-frame texture
/// allocations).
class _AnimatedTranslateTestApp extends StatefulWidget {
  const _AnimatedTranslateTestApp();

  @override
  State<_AnimatedTranslateTestApp> createState() =>
      _AnimatedTranslateTestAppState();
}

class _AnimatedTranslateTestAppState extends State<_AnimatedTranslateTestApp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const settings = LiquidGlassSettings(thickness: 50, blur: 2);
    return MaterialApp(
      home: Scaffold(
        body: _GridPaperBackground(
          child: LiquidGlassLayer(
            settings: settings,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, _controller.value * 400 - 200),
                  child: child,
                );
              },
              child: Center(
                child: LiquidGlass(
                  shape: LiquidRoundedSuperellipse(borderRadius: 32),
                  child: const SizedBox(width: 320, height: 480),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MultiTestApp extends StatelessWidget {
  const _MultiTestApp({this.withGlass = true, this.shareLayer = false});

  final bool withGlass;

  final bool shareLayer;

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
          child: switch ((withGlass, shareLayer)) {
            (true, true) => LiquidGlass(
              key: Key('liquid_glass_$index'),
              shape: LiquidRoundedSuperellipse(borderRadius: 15),
              child: listItem,
            ),
            (true, false) => LiquidGlassLayer(
              settings: settings,
              child: LiquidGlass(
                key: Key('liquid_glass_$index'),
                shape: LiquidRoundedSuperellipse(borderRadius: 15),
                child: listItem,
              ),
            ),

            (false, _) => listItem,
          },
        );
      }),
    );

    return switch (shareLayer) {
      false => MaterialApp(
        home: Scaffold(
          body: _GridPaperBackground(child: Center(child: content)),
        ),
      ),

      true => MaterialApp(
        home: Scaffold(
          body: _GridPaperBackground(
            child: LiquidGlassLayer(
              settings: settings,
              child: Center(child: content),
            ),
          ),
        ),
      ),
    };
  }
}
