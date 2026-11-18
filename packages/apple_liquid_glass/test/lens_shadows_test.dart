import 'dart:typed_data';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/liquid/lens_shadows.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart'
    show LiquidGlass, LiquidGlassContentBend, LiquidGlassLayer;

import 'glass_shown.dart';

const _key = ValueKey('page');
const _lens = Rect.fromLTWH(40, 30, 114, 70);

/// Grey levels of a white page under the shadows of a lens drawn at [rect].
Future<int Function(double x, double y)> _levels(
  WidgetTester tester, {
  Rect rect = _lens,
  LiquidShape shape = LiquidRoundedSuperellipse.capsule,
  double lift = 1,
  bool small = false,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(200, 140);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _key,
      child: ColoredBox(
        color: const Color(0xFFFFFFFF),
        child: LensShadows(
          key: ValueKey((rect, shape, lift, small, brightness)),
          frame: ValueNotifier(
            GlassFrame(shape: shape, rect: rect, lift: lift),
          ),
          small: small,
          brightness: brightness,
        ),
      ),
    ),
  );
  final (Uint8List bytes, int width) = (await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_key),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData();
    final width = image.width;
    image.dispose();
    return (bytes!.buffer.asUint8List(), width);
  }))!;
  return (double x, double y) => bytes[(y.floor() * width + x.floor()) * 4];
}

void main() {
  group('the law', () {
    test('the ring is a 4 pt band inside the moved outline with a 3 pt '
        'Gaussian edge', () {
      expect(LensShadowLaw.ringAt(2), moreOrLessEquals(0.495, epsilon: 1e-3));
      expect(LensShadowLaw.ringAt(0), moreOrLessEquals(0.409, epsilon: 1e-3));
      expect(LensShadowLaw.ringAt(4), moreOrLessEquals(0.409, epsilon: 1e-3));
      expect(LensShadowLaw.ringAt(-9), lessThan(0.002));
      expect(LensShadowLaw.ringAt(13), lessThan(0.002));
    });

    test('the ring is 0.1 on a selection and by the appearance on a knob', () {
      for (final brightness in Brightness.values) {
        expect(
          LensShadowLaw.ringOpacity(small: false, brightness: brightness),
          0.1,
        );
      }
      expect(
        LensShadowLaw.ringOpacity(small: true, brightness: Brightness.dark),
        0.4,
      );
      expect(
        LensShadowLaw.ringOpacity(small: true, brightness: Brightness.light),
        0.15,
      );
    });

    test('the inner shadow is the surroundings 7 pt above, blurred', () {
      expect(LensShadowLaw.innerAt(0), moreOrLessEquals(0.5, epsilon: 1e-6));
      expect(LensShadowLaw.innerAt(-7), moreOrLessEquals(0.990, epsilon: 1e-3));
      expect(LensShadowLaw.innerAt(3), moreOrLessEquals(0.159, epsilon: 1e-3));
    });

    test('a selection of 70 bends its content by 14 over 11.2 and shows '
        'nothing shallower than 7.27', () {
      final bend = LensShadowLaw.contentBend(70, small: false);
      expect(bend.amount, moreOrLessEquals(14));
      expect(bend.height, moreOrLessEquals(11.2));
      final shown = bend.shownDepth;
      expect(shown(0), moreOrLessEquals(14));
      expect(shown(4.2), moreOrLessEquals(7.271, epsilon: 2e-3));
      expect(shown(11.2), 11.2);
      expect(shown(30), 30);
      var least = double.infinity;
      for (var d = 0.0; d < 11.2; d += 0.01) {
        if (shown(d) < least) least = shown(d);
      }
      expect(least, moreOrLessEquals(7.271, epsilon: 2e-3));
      expect(
        LensShadowLaw.contentBend(38, small: true),
        const LiquidGlassContentBend(amount: 0, height: 0),
      );
    });
  });

  group('the picture', () {
    testWidgets('a lifted selection darkens the lens 10 pt under its top and '
        'the page 6 pt under its bottom, and nothing in its middle', (
      tester,
    ) async {
      final level = await _levels(tester);
      final x = _lens.center.dx;
      // The ring's peak, 0.0495, with 0.009 of the inner shadow over it.
      expect(level(x, _lens.top + 10), closeTo(240, 2));
      expect(level(x, _lens.bottom + 6), closeTo(242, 2));
      expect(level(x, _lens.center.dy), 255);
      expect(level(x, _lens.top - 4), 255);
      expect(level(_lens.left - 12, _lens.center.dy), 255);
      // The ring follows the outline around the ends: its peak 2 pt inside.
      expect(level(_lens.left + 2, _lens.center.dy + 8), closeTo(242, 2));
    });

    testWidgets('the inner shadow of a selection is a crescent under the '
        'top: bent away from the rim, absent at the sides and the bottom', (
      tester,
    ) async {
      final level = await _levels(tester);
      final x = _lens.center.dx;
      // Ring 0.0089 and inner 0.0278 four points deep; ring 0.0008 and
      // inner 0.0138 one point deep.
      expect(level(x, _lens.top + 4), closeTo(246, 2));
      expect(level(x, _lens.top + 1), closeTo(251, 2));
      expect(level(x, _lens.bottom - 14), 255);
    });

    testWidgets('a knob takes the ring at 0.4 in dark mode and 0.15 in light '
        'mode, and its inner shadow unbent', (tester) async {
      const knob = Rect.fromLTWH(60, 40, 58, 38);
      final dark = await _levels(
        tester,
        rect: knob,
        small: true,
        brightness: Brightness.dark,
      );
      // Ring 0.198 and inner 0.009.
      expect(dark(knob.center.dx, knob.top + 10), closeTo(203, 3));
      expect(dark(knob.center.dx, knob.bottom + 6), closeTo(205, 3));
      final light = await _levels(tester, rect: knob, small: true);
      expect(light(knob.center.dx, knob.top + 10), closeTo(234, 2));
      // Unbent, the inner shadow is 0.059 at the top edge, where the ring
      // adds 0.001.
      expect(light(knob.center.dx, knob.top + 0.5), closeTo(240, 3));
    });

    testWidgets('a lens at rest paints nothing, and one that appears paints '
        'by how far its glass has', (tester) async {
      final rest = await _levels(tester, lift: 0);
      final half = await _levels(
        tester,
        lift: GlassFrame.restingLift + 0.12,
      );
      final full = await _levels(tester);
      final x = _lens.center.dx;
      final y = _lens.bottom + 6;
      expect(rest(x, y), 255);
      expect(half(x, y), closeTo(249, 2));
      expect(full(x, y), closeTo(242, 2));
    });

    testWidgets('a lens with tight corners shades by the distance to its '
        'outline without piling up in the corners', (tester) async {
      const rect = Rect.fromLTWH(50, 30, 90, 60);
      final level = await _levels(
        tester,
        rect: rect,
        shape: const LiquidRoundedRectangle(radius: 4),
      );
      expect(level(rect.left + 2, rect.center.dy + 8), closeTo(242, 2));
      var darkest = 255;
      for (var y = rect.top - 12; y < rect.bottom + 20; y++) {
        for (var x = rect.left - 12; x < rect.right + 12; x++) {
          final value = level(x, y);
          if (value < darkest) darkest = value;
        }
      }
      // Ring and inner shadow together reach 0.075 where they overlap.
      expect(darkest, greaterThanOrEqualTo(234));
    });
  });

  group('on the liquid renderer', () {
    Widget app(Widget child) => MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GlassScope(
          renderer: const LiquidGlassRenderer(),
          child: Center(child: child),
        ),
      ),
    );

    testWidgets('a lifted lens casts no drop shadow and shades nothing in '
        'its glass; its shadows are drawn over it', (tester) async {
      await tester.pumpWidget(
        app(
          GlassSurface.live(
            role: GlassRole.lens,
            frame: MotionSelection(() => const GlassFrame(lift: 1)),
            child: const SizedBox(width: 114, height: 70),
          ),
        ),
      );
      expect(findShown(LensShadows), findsOneWidget);
      final glass = tester.widget<LiquidGlass>(findShown(LiquidGlass));
      expect(glass.frame!.value.shadows, isEmpty);
      final settings = tester
          .widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer))
          .frame!
          .value
          .settings;
      expect(settings.bevelShadowStrength, 0);
      for (final role in GlassRole.values) {
        final shadows = LiquidGlassRenderer.shadowsOf(
          role,
          LiquidGlassRenderer.materialOf(
            const Glass.regular(),
            Brightness.light,
          ),
        );
        expect(
          shadows.isEmpty,
          role == GlassRole.lens || role == GlassRole.track,
          reason: '$role',
        );
      }
    });

    testWidgets('a resting lens shows no shadows', (tester) async {
      await tester.pumpWidget(
        app(
          GlassSurface.live(
            role: GlassRole.lens,
            frame: MotionSelection(GlassFrame.new),
            child: const SizedBox(width: 114, height: 70),
          ),
        ),
      );
      expect(findShown(LensShadows), findsNothing);
    });
  });
}
