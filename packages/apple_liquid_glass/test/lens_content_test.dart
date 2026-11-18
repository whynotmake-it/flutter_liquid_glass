import 'dart:typed_data';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/liquid/lens_content.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

const _key = ValueKey('page');
const _lens = Rect.fromLTWH(40, 30, 114, 70);
const _red = Color(0xFFFF0000);
const _white = Color(0xFFFFFFFF);

class _Shown extends LeafRenderObjectWidget {
  const _Shown({
    required this.frame,
    required this.marks,
    required this.color,
    super.key,
  });

  final GlassFrame frame;
  final List<Rect> marks;
  final Color color;

  @override
  _RenderShown createRenderObject(BuildContext context) =>
      _RenderShown(frame, marks, color);
}

class _RenderShown extends RenderBox {
  _RenderShown(this.frame, this.marks, this.color);

  final GlassFrame frame;
  final List<Rect> marks;
  final Color color;
  final shown = LensContentBend();
  int contents = 0;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void dispose() {
    shown.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) => shown.paint(
    context,
    offset,
    frame: frame,
    size: size,
    content: (context, offset) {
      contents++;
      for (final mark in marks) {
        context.canvas.drawRect(mark.shift(offset), Paint()..color = color);
      }
    },
  );
}

/// The red, green and blue of a black page under [marks] of [color] as
/// the lens at [_lens] lifted by [lift] shows them, with the renderer's
/// programs loaded.
Future<List<int> Function(int x, int y)> _pixels(
  WidgetTester tester,
  List<Rect> marks, {
  double lift = 1,
  Color color = _red,
}) async {
  await tester.runAsync(precacheLiquidGlass);
  tester.view.physicalSize = const Size(200, 140);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _key,
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: _Shown(
          key: ValueKey((marks, lift, color)),
          frame: GlassFrame(rect: _lens, lift: lift),
          marks: marks,
          color: color,
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
  return (int x, int y) =>
      bytes.sublist((y * width + x) * 4, (y * width + x) * 4 + 3);
}

/// The red of a black page under red [marks] as the lens at [_lens] lifted
/// by [lift] shows them.
Future<int Function(int x, int y)> _reds(
  WidgetTester tester,
  List<Rect> marks, {
  double lift = 1,
}) async {
  final pixels = await _pixels(tester, marks, lift: lift);
  return (int x, int y) => pixels(x, y)[0];
}

/// What the laws give of red, green and blue, 0 to 1, in the middle of the
/// row [row] pt under the straight top of a lifted lens 70 pt high, for a
/// white line that fills the tenth row under it.
///
/// A read ahead lies up and to the left there, 15 degrees off the edge, so
/// 0.2588 of the parting counts across the rows.
List<double> _law(int row) {
  double shown(double depth) {
    final source = LensContentLaw.shownDepth(
      depth < 0 ? 0 : depth,
      height: 70,
    );
    // The picture between the middles of two of its rows.
    final line =
        (source - 9 + 0.5).clamp(0.0, 1.0) -
        (source - 10 + 0.5).clamp(0.0, 1.0);
    return line * (depth + 0.5).clamp(0.0, 1.0);
  }

  final depth = row + 0.5;
  final step = LensContentLaw.parting(70) / 3 * 0.258819;
  final own = shown(depth);
  final red =
      shown(depth - 3 * step) / 2 +
      shown(depth - 2 * step) / 3 +
      shown(depth - step) / 6;
  final green =
      own / 3 +
      (shown(depth - step) + shown(depth + step)) * 2 / 9 +
      (shown(depth - 2 * step) + shown(depth + 2 * step)) / 9;
  final blue =
      shown(depth + 3 * step) / 2 +
      shown(depth + 2 * step) / 3 +
      shown(depth + step) / 6;
  final parted = (1 - depth / LensContentLaw.partingDepth(70)).clamp(0.0, 1.0);
  return [
    for (final color in [red, green, blue]) own + (color - own) * parted,
  ];
}

void main() {
  group('the law', () {
    test('a tab bar lens shows at its rim what lies 14 pt inside it, and '
        'never what lies nearer than 8.4 pt', () {
      double shown(double depth) =>
          LensContentLaw.shownDepth(depth, height: 70);
      expect(shown(0), moreOrLessEquals(14, epsilon: 1e-9));
      expect(shown(1), moreOrLessEquals(9.494, epsilon: 2e-3));
      expect(shown(4.2), moreOrLessEquals(8.385, epsilon: 2e-3));
      expect(shown(8), moreOrLessEquals(9.068, epsilon: 2e-3));
      var nearest = double.infinity;
      for (var depth = 0.0; depth <= 35; depth += 0.05) {
        if (shown(depth) < nearest) nearest = shown(depth);
      }
      expect(nearest, moreOrLessEquals(8.383, epsilon: 5e-3));
    });

    test('from 11.2 pt deep everything shows in place', () {
      expect(LensContentLaw.shownDepth(11.2, height: 70), 11.2);
      expect(LensContentLaw.shownDepth(20, height: 70), 20);
      // A segmented control's lens bends by its own height first, and the
      // lift's bend reaches as deep as on a tab bar.
      expect(LensContentLaw.shownDepth(11.2, height: 44), 11.2);
      expect(
        LensContentLaw.shownDepth(0, height: 44),
        moreOrLessEquals(9.207, epsilon: 2e-3),
      );
    });

    test('a lens parts by 1 / 19 of its height at the rim, to nothing 0.2 '
        'of it deep', () {
      expect(
        LensContentLaw.parting(70),
        moreOrLessEquals(3.684, epsilon: 1e-3),
      );
      expect(
        LensContentLaw.parting(70, lift: 0.5),
        moreOrLessEquals(1.842, epsilon: 1e-3),
      );
      expect(LensContentLaw.parting(70, lift: 0), 0);
      expect(LensContentLaw.partingDepth(70), 14);
    });

    test('the bends grow with the lift', () {
      expect(LensContentLaw.shownDepth(3, height: 70, lift: 0), 3);
      // Half the first bend reads 7 pt deep, where half the second still
      // reaches.
      expect(
        LensContentLaw.shownDepth(0, height: 70, lift: 0.5),
        moreOrLessEquals(7.639, epsilon: 2e-3),
      );
    });
  });

  group('the picture', () {
    // A line across the lens 9 to 10 pt under its top.
    final line = Rect.fromLTWH(_lens.left, _lens.top + 9, _lens.width, 1);
    final x = _lens.center.dx.round();
    int row(double depth) => (_lens.top + depth).floor();

    testWidgets('a resting lens shows its content as it is, without a '
        'picture', (tester) async {
      final reds = await _reds(tester, [line], lift: 0);
      expect(reds(x, row(9)), 255);
      expect(reds(x, row(8)), 0);
      expect(reds(x, row(1)), 0);
      expect(
        tester.renderObject<_RenderShown>(find.byType(_Shown)).contents,
        1,
      );
    });

    testWidgets('a lifted lens shows a line 9 pt deep twice, under the rim '
        'and 7 to 10 pt deep, its colors parted', (tester) async {
      final pixels = await _pixels(tester, [line], color: _white);
      for (var depth = 0; depth < 16; depth++) {
        final law = _law(depth);
        for (var channel = 0; channel < 3; channel++) {
          expect(
            pixels(x, row(depth + 0.0))[channel],
            closeTo(law[channel] * 255, 8),
            reason: 'row $depth channel $channel',
          );
        }
      }
      // 3.5 and 4.5 pt deep the lens shows what lies nearer than 8.5 pt,
      // in every color: none of the line.
      for (final depth in [3.0, 4.0]) {
        expect(pixels(x, row(depth)), everyElement(lessThan(10)));
      }
      // A read ahead lies up under the top, where what is shown lies
      // nearer the rim: blue leads into the line and red trails out of it.
      final into = pixels(x, row(6));
      final out = pixels(x, row(9));
      expect(into[2], greaterThan(into[0] + 30));
      expect(out[0], greaterThan(out[2] + 30));
      // 11.5 pt deep and deeper what lies there.
      expect(pixels(x, row(11)), everyElement(lessThan(10)));
      expect(pixels(x, row(13)), everyElement(lessThan(10)));
    });

    testWidgets('what lies deeper than the bends shows pixel for pixel', (
      tester,
    ) async {
      final mark = Rect.fromLTWH(_lens.center.dx, _lens.top + 30, 1, 10);
      final reds = await _reds(tester, [mark]);
      final column = mark.left.round();
      for (var y = row(30); y < row(40); y++) {
        expect(reds(column, y), greaterThan(252));
        expect(reds(column - 1, y), lessThan(3));
        expect(reds(column + 1, y), lessThan(3));
      }
      expect(reds(column, row(29)), lessThan(3));
      expect(reds(column, row(40)), lessThan(3));
    });

    testWidgets('nothing shows outside the lens', (tester) async {
      final reds = await _reds(tester, const [Rect.fromLTWH(0, 0, 200, 140)]);
      expect(reds(_lens.center.dx.round(), _lens.center.dy.round()), 255);
      expect(reds(_lens.left.round() - 2, _lens.center.dy.round()), 0);
      expect(reds(_lens.center.dx.round(), _lens.top.round() - 2), 0);
      // The corner of the lens's box lies outside its capsule.
      expect(reds(_lens.left.round() + 2, _lens.top.round() + 2), 0);
    });
  });
}
