import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_adaptive_brightness/src/liquid_glass_adaptive_brightness.dart';

const _immediate = LiquidGlassAdaptiveBrightnessSettings(
  interval: Duration.zero,
  smoothing: Duration.zero,
);

void main() {
  group('BackdropBrightnessFilter', () {
    test('flips only once luminance leaves the hysteresis band', () {
      final filter = BackdropBrightnessFilter(
        settings: _immediate,
        initial: Brightness.light,
      );
      expect(filter.value.hasSample, isFalse);

      expect(filter.add(.2, Duration.zero).brightness, Brightness.dark);
      expect(filter.add(.54, Duration.zero).brightness, Brightness.dark);
      expect(filter.add(.56, Duration.zero).brightness, Brightness.light);
      expect(filter.add(.46, Duration.zero).brightness, Brightness.light);
      expect(filter.add(.44, Duration.zero).brightness, Brightness.dark);
    });

    test('first sample picks its side of the threshold directly', () {
      final filter = BackdropBrightnessFilter(
        settings: _immediate,
        initial: Brightness.dark,
      );
      expect(filter.add(.51, Duration.zero).brightness, Brightness.light);
    });

    test('smooths samples exponentially with the configured time constant', () {
      final filter = BackdropBrightnessFilter(
        settings: const LiquidGlassAdaptiveBrightnessSettings(
          smoothing: Duration(milliseconds: 100),
        ),
        initial: Brightness.dark,
      )..add(0, Duration.zero);

      final value = filter.add(1, const Duration(milliseconds: 100));
      expect(value.luminance, closeTo(1 - 0.36787944, 1e-6));
      expect(value.brightness, Brightness.light);
    });
  });

  group('averageLuminance', () {
    test('weights premultiplied pixels by coverage', () {
      final pixels = Uint8List.fromList([
        255, 255, 255, 255, // opaque white
        0, 0, 0, 255, // opaque black
        0, 0, 0, 0, // uncovered
      ]);
      expect(
        averageLuminance(ByteData.sublistView(pixels)),
        closeTo(.5, 1e-9),
      );
    });

    test('uses Rec.709 weights', () {
      final pixels = Uint8List.fromList([0, 255, 0, 255]);
      expect(
        averageLuminance(ByteData.sublistView(pixels)),
        closeTo(.7152, 1e-9),
      );
    });

    test('returns null when nothing is covered', () {
      expect(averageLuminance(ByteData(8)), isNull);
    });
  });

  group('LiquidGlassAdaptiveBrightness', () {
    testWidgets('follows the content beneath it', (tester) async {
      final source = LiquidGlassBrightnessSource();
      final color = ValueNotifier(Colors.white);
      addTearDown(color.dispose);
      final changes = <LiquidGlassBackdropBrightness>[];

      await tester.pumpWidget(
        _Scene(
          source: source,
          backdrop: ValueListenableBuilder(
            valueListenable: color,
            builder: (context, color, _) => ColoredBox(color: color),
          ),
          bar: LiquidGlassAdaptiveBrightness(
            source: source,
            settings: _immediate,
            onChanged: changes.add,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await _settle(tester);
      expect(source.isAttached, isTrue);
      expect(changes.last.brightness, Brightness.light);
      expect(changes.last.luminance, closeTo(1, .01));

      color.value = Colors.black;
      await _settle(tester);
      expect(changes.last.brightness, Brightness.dark);
      expect(changes.last.luminance, closeTo(0, .01));
    });

    testWidgets('samples only the region beneath each instance', (
      tester,
    ) async {
      final source = LiquidGlassBrightnessSource();
      LiquidGlassBackdropBrightness? top;
      LiquidGlassBackdropBrightness? bottom;

      await tester.pumpWidget(
        _Scene(
          source: source,
          backdrop: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: ColoredBox(color: Colors.white)),
              Expanded(child: ColoredBox(color: Colors.black)),
            ],
          ),
          bar: Column(
            children: [
              Expanded(
                child: LiquidGlassAdaptiveBrightness(
                  source: source,
                  settings: _immediate,
                  onChanged: (value) => top = value,
                  child: const SizedBox.expand(),
                ),
              ),
              Expanded(
                child: LiquidGlassAdaptiveBrightness(
                  source: source,
                  settings: _immediate,
                  onChanged: (value) => bottom = value,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      );
      await _settle(tester);
      expect(top?.brightness, Brightness.light);
      expect(bottom?.brightness, Brightness.dark);
    });

    testWidgets('exposes the estimate to descendants', (tester) async {
      final source = LiquidGlassBrightnessSource();
      await tester.pumpWidget(
        _Scene(
          source: source,
          backdrop: const ColoredBox(color: Colors.white),
          bar: LiquidGlassAdaptiveBrightness(
            source: source,
            settings: _immediate,
            initialBrightness: Brightness.dark,
            child: Builder(
              builder: (context) => Text(
                LiquidGlassAdaptiveBrightness.of(context).brightness.name,
                textDirection: TextDirection.ltr,
              ),
            ),
          ),
        ),
      );
      expect(find.text('dark'), findsOneWidget);
      await _settle(tester);
      expect(find.text('light'), findsOneWidget);
    });
  });
}

/// Lets the asynchronous readback land and the resulting rebuild paint.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pump();
}

class _Scene extends StatelessWidget {
  const _Scene({
    required this.source,
    required this.backdrop,
    required this.bar,
  });

  final LiquidGlassBrightnessSource source;
  final Widget backdrop;
  final Widget bar;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          Positioned.fill(
            child: LiquidGlassBrightnessBackdrop(
              source: source,
              child: backdrop,
            ),
          ),
          Positioned.fill(child: bar),
        ],
      ),
    );
  }
}
