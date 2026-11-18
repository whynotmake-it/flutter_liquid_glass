import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

// Run with `flutter test --enable-impeller --enable-flutter-gpu`: the
// composited layer adds several retained engine layers in one, which only
// Impeller's compositor checks for real.
const _key = ValueKey('scene');
const _size = Size(120, 80);
const _radius = BorderRadius.all(Radius.circular(18));

Widget _scene(Widget transition, {int stripe = 0}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: RepaintBoundary(
      key: _key,
      child: SizedBox(
        width: 300,
        height: 220,
        child: ColoredBox(
          color: const Color(0xFF203040),
          child: Stack(
            children: [
              Positioned(
                left: 10 + stripe.toDouble(),
                top: 0,
                width: 6,
                height: 220,
                child: const ColoredBox(color: Color(0xFFFFCC00)),
              ),
              Positioned(
                left: 90,
                top: 70,
                width: _size.width,
                height: _size.height,
                child: transition,
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

const _content = DecoratedBox(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFFFF3B30), Color(0xFF34C759)],
    ),
  ),
);

Matrix4 _transform(Offset offset, double scale, double rotation) {
  final center = _size.center(Offset.zero);
  final transform = Matrix4.translationValues(
    offset.dx + center.dx,
    offset.dy + center.dy,
    0,
  );
  transform.rotateZ(rotation);
  transform.scaleByDouble(scale, scale, 1, 1);
  transform.translateByDouble(-center.dx, -center.dy, 0, 1);
  return transform;
}

Widget _chain(double opacity, double blur) => Transform(
  transform: _transform(const Offset(-20, 15), 1.2, 0.2),
  child: ClipRRect(
    borderRadius: _radius,
    child: Opacity(
      opacity: opacity,
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: _content,
      ),
    ),
  ),
);

Future<Uint8List> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(boundary.toImage))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

int _differing(Uint8List a, Uint8List b) {
  var differing = 0;
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 1) differing++;
  }
  return differing;
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('one layer draws a transform, clip, opacity and blur as the '
      'widget chain does, also when retained', (tester) async {
    final offset = MotionValue(const Offset(-20, 15));
    final scale = MotionValue<double>(1.2);
    final rotation = MotionValue<double>(0.2);
    final opacity = MotionValue<double>(0.6);
    final blur = MotionValue<double>(2);
    final transition = MotionTransition(
      offset: offset,
      scale: scale,
      rotation: rotation,
      opacity: opacity,
      blur: blur,
      borderRadius: _radius,
      child: _content,
    );

    await tester.pumpWidget(_scene(_chain(0.6, 2)));
    final chain = await _capture(tester);
    await tester.pumpWidget(_scene(transition));
    expect(_differing(chain, await _capture(tester)), 0);

    await tester.pumpWidget(_scene(_chain(0.6, 2), stripe: 30));
    final moved = await _capture(tester);
    await tester.pumpWidget(_scene(transition, stripe: 30));
    expect(_differing(moved, await _capture(tester)), 0);

    await tester.pumpWidget(_scene(_chain(0.3, 2), stripe: 30));
    final faded = await _capture(tester);
    await tester.pumpWidget(_scene(transition, stripe: 30));
    opacity.snap(opacity.clock.now, 0.3);
    await tester.pump(const Duration(milliseconds: 16));
    expect(_differing(faded, await _capture(tester)), 0);
  }, skip: !ui.ImageFilter.isShaderFilterSupported);
}
