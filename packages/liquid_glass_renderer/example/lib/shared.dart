import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

Animation<double> useRotatingAnimationController() {
  return useAnimationController(
    duration: const Duration(seconds: 5),
    lowerBound: 0,
    upperBound: 2 * pi,
  )..repeat();
}

class VerticalStripes extends StatelessWidget {
  const VerticalStripes({super.key, this.stripeThickness = 40.0});

  final double stripeThickness;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _VerticalStripesPainter(stripeThickness: stripeThickness),
      size: Size.infinite,
    );
  }
}

class _VerticalStripesPainter extends CustomPainter {
  const _VerticalStripesPainter({required this.stripeThickness});

  final double stripeThickness;

  @override
  void paint(Canvas canvas, Size size) {
    final blackPaint = Paint()..color = Colors.black;
    final whitePaint = Paint()..color = Colors.white;

    double currentX = 0;
    bool isBlack = true;

    while (currentX < size.width) {
      final rect = Rect.fromLTWH(currentX, 0, stripeThickness, size.height);

      canvas.drawRect(rect, isBlack ? blackPaint : whitePaint);

      currentX += stripeThickness;
      isBlack = !isBlack;
    }
  }

  @override
  bool shouldRepaint(covariant _VerticalStripesPainter oldDelegate) {
    return oldDelegate.stripeThickness != stripeThickness;
  }
}

class ImagePageView extends HookWidget {
  const ImagePageView({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageView.builder(
          itemBuilder: (context, index) {
            return switch (index) {
              <= 0 => Image.asset('assets/wallpaper.webp', fit: BoxFit.cover),
              1 => const Grid(),
              2 => const VerticalStripes(),
              _ => LayoutBuilder(
                builder: (context, constraints) => Image.network(
                  'https://picsum.photos/2000/2000?random=$index',
                  fit: BoxFit.cover,
                ),
              ),
            };
          },
        ),
        child,
      ],
    );
  }
}

class SettingsSheet extends HookWidget {
  const SettingsSheet({
    super.key,
    required this.settingsNotifier,
    required this.lightAngleAnimation,
  });

  final ValueNotifier<LiquidGlassSettings> settingsNotifier;

  final Animation<double> lightAngleAnimation;

  Future<void> show(BuildContext context) {
    return Navigator.push(
      context,
      ModalSheetRoute(
        barrierColor: Colors.black26,
        swipeDismissible: true,
        viewportPadding: const EdgeInsets.all(100),
        builder: (context) => this,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = useValueListenable(settingsNotifier);
    final lightAngle = useValueListenable(lightAngleAnimation);

    return Sheet(
      dragConfiguration: SheetDragConfiguration(),
      scrollConfiguration: const SheetScrollConfiguration(),
      initialOffset: SheetOffset(1),
      shrinkChildToAvoidDynamicOverlap: true,
      shrinkChildToAvoidStaticOverlap: true,
      snapGrid: SheetSnapGrid(snaps: [SheetOffset(0.5), SheetOffset(1)]),
      child: SafeArea(
        child: LiquidGlass(
          glassContainsChild: false,
          settings: LiquidGlassSettings(
            thickness: 30,
            blur: 20,
            lightIntensity: .5,
            lightAngle: lightAngle,
            ambientStrength: .5,
            chromaticAberration: 2,
            glassColor: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.4),
          ),
          shape: LiquidRoundedSuperellipse(borderRadius: Radius.circular(24)),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyLarge!,
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Settings',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Thickness:'),
                          Text(settings.thickness.toStringAsFixed(2)),
                        ],
                      ),
                      CupertinoSlider(
                        value: settings.thickness,
                        onChanged: (value) {
                          settingsNotifier.value = settings.copyWith(
                            thickness: value,
                          );
                        },
                        min: 0,
                        max: 160,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Light Intensity:'),
                          Text(settings.lightIntensity.toStringAsFixed(2)),
                        ],
                      ),
                      CupertinoSlider(
                        value: settings.lightIntensity,
                        onChanged: (value) {
                          settingsNotifier.value = settings.copyWith(
                            lightIntensity: value,
                          );
                        },
                        min: 0,
                        max: 5,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Ambient Strength:'),
                          Text(settings.ambientStrength.toStringAsFixed(2)),
                        ],
                      ),
                      CupertinoSlider(
                        value: settings.ambientStrength,
                        onChanged: (value) {
                          settingsNotifier.value = settings.copyWith(
                            ambientStrength: value,
                          );
                        },
                        min: 0,
                        max: 5,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Blur:'),
                          Text(settings.blur.toStringAsFixed(2)),
                        ],
                      ),
                      CupertinoSlider(
                        value: settings.blur,
                        onChanged: (value) {
                          settingsNotifier.value = settings.copyWith(
                            blur: value,
                          );
                        },
                        min: 0,
                        max: 40,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Liquid Factor™:'),
                          Text(settings.blend.toStringAsFixed(2)),
                        ],
                      ),
                      CupertinoSlider(
                        value: settings.blend,
                        onChanged: (value) {
                          settingsNotifier.value = settings.copyWith(
                            blend: value,
                          );
                        },
                        min: 0,
                        max: 200,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Chromatic Aberration:'),
                          Text(settings.chromaticAberration.toStringAsFixed(2)),
                        ],
                      ),
                      CupertinoSlider(
                        value: settings.chromaticAberration,
                        onChanged: (value) {
                          settingsNotifier.value = settings.copyWith(
                            chromaticAberration: value,
                          );
                        },
                        min: 0,
                        max: 10,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Refractive Index:'),
                          Text(settings.refractiveIndex.toStringAsFixed(2)),
                        ],
                      ),
                      CupertinoSlider(
                        value: settings.refractiveIndex,
                        onChanged: (value) {
                          settingsNotifier.value = settings.copyWith(
                            refractiveIndex: value,
                          );
                        },
                        min: 1,
                        max: 3,
                      ),
                    ],
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

class Grid extends StatelessWidget {
  const Grid({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFCEC5B4), Color(0xFFF2F0EA)],
        ),
      ),
      child: GridPaper(
        color: Color(0xFF0F0B0A).withValues(alpha: 0.2),
        interval: 100,
      ),
    );
  }
}
