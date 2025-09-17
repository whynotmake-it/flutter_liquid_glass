import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

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

class _TestApp extends StatelessWidget {
  const _TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: _GridPaperBackground(
          child: Center(
            child: LiquidGlass(
              key: const Key('liquid_glass_widget'),
              shape: LiquidRoundedSuperellipse(
                borderRadius: Radius.circular(20),
              ),
              settings: const LiquidGlassSettings(thickness: 40, blur: 20),
              child: Container(
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Baseline Performance Tests', () {
    testWidgets(
      'measures baseline rendering performance without liquid glass',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _GridPaperBackground(
                child: Center(
                  child: Container(
                    key: const Key('baseline_widget'),
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Center(
                      child: Text(
                        'Baseline',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        final baselineWidget = find.byKey(const Key('baseline_widget'));
        expect(baselineWidget, findsOneWidget);

        await binding.traceAction(() async {
          for (int i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
        }, reportKey: 'baseline_rendering_timeline');
      },
    );

    testWidgets('measures baseline performance with multiple elements', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _GridPaperBackground(
              child: Column(
                children: List.generate(5, (index) {
                  return Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Container(
                      key: Key('baseline_$index'),
                      width: 150,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.primaries[index % Colors.primaries.length]
                            .withOpacity(0.3),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.white, width: 1),
                      ),
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
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      );

      for (int i = 0; i < 5; i++) {
        expect(find.byKey(Key('baseline_$i')), findsOneWidget);
      }

      await binding.traceAction(() async {
        for (int i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }, reportKey: 'multiple_baseline_timeline');
    });

    testWidgets('measures baseline performance with animated elements', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _GridPaperBackground(
              child: Center(child: AnimatedBaselineDemo()),
            ),
          ),
        ),
      );

      final animatedWidget = find.byKey(const Key('animated_baseline'));
      expect(animatedWidget, findsOneWidget);

      await binding.traceAction(() async {
        for (int i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }, reportKey: 'animated_baseline_timeline');
    });
  });

  group('LiquidGlass Performance Tests', () {
    testWidgets('measures performance of liquid glass rendering', (
      tester,
    ) async {
      await tester.pumpWidget(const _TestApp());

      final liquidGlassWidget = find.byKey(const Key('liquid_glass_widget'));
      expect(liquidGlassWidget, findsOneWidget);

      await binding.traceAction(() async {
        // Pump 1000 frames
        for (int i = 0; i < 1000; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }, reportKey: 'liquid_glass_rendering_timeline');
    });

    testWidgets('measures performance with multiple liquid glass elements', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _GridPaperBackground(
              child: Column(
                children: List.generate(5, (index) {
                  return Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: LiquidGlass(
                      key: Key('liquid_glass_$index'),
                      shape: LiquidRoundedSuperellipse(
                        borderRadius: Radius.circular(15),
                      ),
                      settings: const LiquidGlassSettings(
                        thickness: 8,
                        blur: 15,
                      ),
                      child: Container(
                        width: 150,
                        height: 100,
                        color:
                            Colors.primaries[index % Colors.primaries.length],
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
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      );

      for (int i = 0; i < 5; i++) {
        expect(find.byKey(Key('liquid_glass_$i')), findsOneWidget);
      }

      await binding.traceAction(() async {
        for (int i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }, reportKey: 'multiple_liquid_glass_timeline');
    });

    testWidgets('measures performance with animated liquid glass', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _GridPaperBackground(
              child: Center(child: AnimatedLiquidGlassDemo()),
            ),
          ),
        ),
      );

      final animatedWidget = find.byKey(const Key('animated_liquid_glass'));
      expect(animatedWidget, findsOneWidget);

      await binding.traceAction(() async {
        for (int i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }, reportKey: 'animated_liquid_glass_timeline');
    });
  });
}

class AnimatedBaselineDemo extends StatefulWidget {
  const AnimatedBaselineDemo({super.key});

  @override
  State<AnimatedBaselineDemo> createState() => _AnimatedBaselineDemoState();
}

class _AnimatedBaselineDemoState extends State<AnimatedBaselineDemo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 10,
      end: 30,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          key: const Key('animated_baseline'),
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            color: Colors.purple.withOpacity(0.3),
            borderRadius: BorderRadius.circular(_animation.value),
            border: Border.all(
              color: Colors.white,
              width: _animation.value / 15,
            ),
          ),
          child: const Center(
            child: Text(
              'Animated\nBaseline',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }
}

class AnimatedLiquidGlassDemo extends StatefulWidget {
  const AnimatedLiquidGlassDemo({super.key});

  @override
  State<AnimatedLiquidGlassDemo> createState() =>
      _AnimatedLiquidGlassDemoState();
}

class _AnimatedLiquidGlassDemoState extends State<AnimatedLiquidGlassDemo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 10,
      end: 30,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return LiquidGlass(
          key: const Key('animated_liquid_glass'),
          shape: LiquidRoundedSuperellipse(
            borderRadius: Radius.circular(_animation.value),
          ),
          settings: LiquidGlassSettings(
            thickness: _animation.value / 2,
            blur: _animation.value,
          ),
          child: Container(
            width: 200,
            height: 200,
            color: Colors.purple,
            child: const Center(
              child: Text(
                'Animated\nLiquid Glass',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
