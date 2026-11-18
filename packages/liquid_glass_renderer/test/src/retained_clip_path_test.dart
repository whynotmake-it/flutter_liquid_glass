import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/clip_shape.dart';
import 'package:liquid_glass_renderer/src/rendering/retained_glass_clip.dart';
import 'package:material_ui/material_ui.dart';

class _NotchClipper extends CustomClipper<Path> {
  _NotchClipper(this.inset) : super(reclip: inset);

  final ValueNotifier<double> inset;

  @override
  Path getClip(Size size) => const StadiumBorder().getOuterPath(
    Rect.fromLTRB(inset.value, 0, size.width, size.height),
  );

  @override
  bool shouldReclip(_NotchClipper oldClipper) => oldClipper.inset != inset;
}

void main() {
  testWidgets('a held clipper keeps its path across glass repaints', (
    tester,
  ) async {
    final inset = ValueNotifier<double>(0);
    addTearDown(inset.dispose);
    final clipper = _NotchClipper(inset);
    final tint = ValueNotifier<Color>(const Color(0xC00040FF));
    addTearDown(tint.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 200,
            child: ValueListenableBuilder(
              valueListenable: tint,
              builder: (context, color, _) => LiquidGlassLayer(
                fake: true,
                settings: const LiquidGlassSettings(
                  frost: LiquidGlassFrost.sigma(0),
                ),
                defaultAppearance: LiquidGlassAppearance(tint: color),
                child: ClipPath(
                  clipper: clipper,
                  child: const LiquidGlass(
                    shape: LiquidRoundedRectangle(radius: 20),
                    child: SizedBox(width: 260, height: 180),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    ClipShape? shape() {
      final layers = tester.layers.whereType<NativeClipLayer>().toList();
      expect(layers, hasLength(1));
      return layers.single.shape;
    }

    final first = shape();
    expect(first, isA<PathClip>());

    tint.value = const Color(0xC0FF4000);
    await tester.pump();
    expect(identical(shape(), first), isTrue);

    inset.value = 20;
    await tester.pump();
    final reclipped = shape();
    expect(identical(reclipped, first), isFalse);
    expect(reclipped!.bounds.left, 20);
  });

  testWidgets('a clipper rebuilt equal keeps its path', (tester) async {
    final inset = ValueNotifier<double>(0);
    addTearDown(inset.dispose);
    final tint = ValueNotifier<Color>(const Color(0xC00040FF));
    addTearDown(tint.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 200,
            child: ValueListenableBuilder(
              valueListenable: tint,
              builder: (context, color, _) => LiquidGlassLayer(
                fake: true,
                settings: const LiquidGlassSettings(
                  frost: LiquidGlassFrost.sigma(0),
                ),
                defaultAppearance: LiquidGlassAppearance(tint: color),
                child: ClipPath(
                  clipper: _NotchClipper(inset),
                  child: const LiquidGlass(
                    shape: LiquidRoundedRectangle(radius: 20),
                    child: SizedBox(width: 260, height: 180),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    ClipShape? shape() =>
        tester.layers.whereType<NativeClipLayer>().single.shape;

    final first = shape();
    tint.value = const Color(0xC0FF4000);
    await tester.pump();
    expect(identical(shape(), first), isTrue);
  });

  testWidgets('an oval that moves whole keeps its path', (tester) async {
    final shift = ValueNotifier<double>(0);
    addTearDown(shift.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 200,
            child: LiquidGlassLayer(
              fake: true,
              settings: const LiquidGlassSettings(
                frost: LiquidGlassFrost.sigma(0),
              ),
              child: ValueListenableBuilder(
                valueListenable: shift,
                builder: (context, dx, _) => Padding(
                  padding: EdgeInsets.only(left: dx),
                  child: const Align(
                    alignment: Alignment.topLeft,
                    child: ClipOval(
                      child: LiquidGlass(
                        shape: LiquidRoundedRectangle(radius: 20),
                        child: SizedBox(width: 200, height: 160),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    ClipShape? shape() =>
        tester.layers.whereType<NativeClipLayer>().single.shape;

    final first = shape();
    expect(first, isA<OvalClip>());
    shift.value = 30;
    await tester.pump();
    expect(identical(shape(), first), isTrue);
  });
}
