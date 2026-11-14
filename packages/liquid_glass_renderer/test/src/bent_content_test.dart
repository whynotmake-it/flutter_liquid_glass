import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/rendering.dart';

const _key = ValueKey('page');
const _shape = Rect.fromLTWH(40, 30, 120, 70);
const _radius = 35.0;
const _red = Color(0xFFFF0000);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF000000);

class _Bent extends LeafRenderObjectWidget {
  const _Bent({
    required this.bends,
    required this.marks,
    this.color = _red,
    this.aberration = 0,
    this.aberrationDepth = 0,
    super.key,
  });

  final List<LiquidGlassContentBend> bends;
  final List<Rect> marks;
  final Color color;
  final double aberration;
  final double aberrationDepth;

  @override
  _RenderBent createRenderObject(BuildContext context) =>
      _RenderBent(bends, marks, color, aberration, aberrationDepth);
}

class _RenderBent extends RenderBox {
  _RenderBent(
    this.bends,
    this.marks,
    this.color,
    this.aberration,
    this.aberrationDepth,
  );

  final List<LiquidGlassContentBend> bends;
  final List<Rect> marks;
  final Color color;
  final double aberration;
  final double aberrationDepth;
  final bent = LiquidGlassBentContent();

  /// Whether the content was painted into the context of this box.
  bool paintedInPlace = false;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void dispose() {
    bent.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final rect = _shape.shift(offset);
    bent.paint(
      context,
      offset,
      rect: rect,
      radius: _radius,
      clip: Path()
        ..addRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(_radius)),
        ),
      bends: bends,
      devicePixelRatio: 1,
      aberration: aberration,
      aberrationDepth: aberrationDepth,
      content: (inner, offset) {
        paintedInPlace = identical(inner, context);
        for (final mark in marks) {
          inner.canvas.drawRect(mark.shift(offset), Paint()..color = color);
        }
      },
    );
  }
}

/// The red, green, blue and alpha of [page], or of a layer that holds
/// nothing with none, under [marks] of [color] as the shape shows them
/// through [bends] and a parting.
Future<List<int> Function(int x, int y)> _pixels(
  WidgetTester tester,
  List<LiquidGlassContentBend> bends,
  List<Rect> marks, {
  Color? page = _black,
  Color color = _red,
  double aberration = 0,
  double aberrationDepth = 0,
}) async {
  tester.view.physicalSize = const Size(200, 140);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final bent = _Bent(
    key: ValueKey((bends, marks, color, aberration, aberrationDepth)),
    bends: bends,
    marks: marks,
    color: color,
    aberration: aberration,
    aberrationDepth: aberrationDepth,
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: _key,
      child: page == null ? bent : ColoredBox(color: page, child: bent),
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
      bytes.sublist((y * width + x) * 4, (y * width + x) * 4 + 4);
}

/// The red of a black page under [marks] as the shape shows them through
/// [bends].
Future<int Function(int x, int y)> _reds(
  WidgetTester tester,
  List<LiquidGlassContentBend> bends,
  List<Rect> marks,
) async {
  final pixels = await _pixels(tester, bends, marks);
  return (int x, int y) => pixels(x, y)[0];
}

/// How deep [at] lies inside the shape, and the outward normal of its
/// outline there.
(double, Offset) _rim(Offset at) {
  final from = at - _shape.center;
  final cornerX = from.dx.abs() - (_shape.width / 2 - _radius);
  final cornerY = from.dy.abs() - (_shape.height / 2 - _radius);
  final outsideX = math.max<double>(cornerX, 0);
  final outsideY = math.max<double>(cornerY, 0);
  final far = math.sqrt(outsideX * outsideX + outsideY * outsideY);
  final normal = far > 0
      ? Offset(outsideX / far, outsideY / far)
      : (cornerX > cornerY ? const Offset(1, 0) : const Offset(0, 1));
  return (
    _radius - far - math.min<double>(math.max(cornerX, cornerY), 0),
    Offset(normal.dx * from.dx.sign, normal.dy * from.dy.sign),
  );
}

/// What the laws give of red, green and blue, 0 to 1, in the middle of the
/// pixel at ([x], [y]) for content that fills [mark] with white, with the
/// outline worked out anew for every read.
List<double> _law(
  int x,
  int y, {
  required List<LiquidGlassContentBend> bends,
  required double aberration,
  required double aberrationDepth,
  required Rect mark,
}) {
  // The picture between the middles of its pixels.
  double ramp(double from) => (from + 0.5).clamp(0.0, 1.0);
  double shown(Offset at) {
    final (depth, normal) = _rim(at);
    var source = math.max<double>(depth, 0);
    for (final bend in bends) {
      source = bend.shownDepth(source);
    }
    source = math.min(source, _shape.shortestSide / 2);
    final read = at - normal * (source - depth);
    return (ramp(read.dx - mark.left) - ramp(read.dx - mark.right)) *
        (ramp(read.dy - mark.top) - ramp(read.dy - mark.bottom)) *
        ramp(depth);
  }

  final at = Offset(x + 0.5, y + 0.5);
  final (depth, normal) = _rim(at);
  // The outward normal mirrored, a third of the parting long.
  final third =
      Offset(
        normal.dx * -0.258819 + normal.dy * 0.965926,
        normal.dx * 0.965926 + normal.dy * 0.258819,
      ) *
      (aberration / 3);
  final own = shown(at);
  final red =
      shown(at + third * 3) / 2 +
      shown(at + third * 2) / 3 +
      shown(at + third) / 6;
  final green =
      own / 3 +
      (shown(at + third) + shown(at - third)) * 2 / 9 +
      (shown(at + third * 2) + shown(at - third * 2)) / 9;
  final blue =
      shown(at - third * 3) / 2 +
      shown(at - third * 2) / 3 +
      shown(at - third) / 6;
  final parted = (1 - depth / aberrationDepth).clamp(0.0, 1.0);
  return [
    for (final color in [red, green, blue]) own + (color - own) * parted,
  ];
}

/// Lines one device pixel thin, 2.1 points apart across and 2.3 down,
/// over the middle of [shape].
void _thinLines(Canvas canvas, Rect shape, Offset offset) {
  final paint = Paint()..color = _white;
  for (var i = 0; i < 40; i++) {
    canvas.drawRect(
      Rect.fromLTWH(
        shape.left + 20 + i * 2.1,
        shape.top + 20,
        1 / 3,
        30,
      ).shift(offset),
      paint,
    );
  }
  for (var i = 0; i < 12; i++) {
    canvas.drawRect(
      Rect.fromLTWH(
        shape.left + 30,
        shape.top + 22 + i * 2.3,
        60,
        1 / 3,
      ).shift(offset),
      paint,
    );
  }
}

class _Sharp extends LeafRenderObjectWidget {
  const _Sharp({
    required this.shape,
    required this.bent,
    required this.parted,
    super.key,
  });

  final Rect shape;
  final bool bent;
  final bool parted;

  @override
  _RenderSharp createRenderObject(BuildContext context) =>
      _RenderSharp(shape: shape, bentOn: bent, parted: parted);
}

class _RenderSharp extends RenderBox {
  _RenderSharp({
    required this.shape,
    required this.bentOn,
    required this.parted,
  });

  final Rect shape;
  final bool bentOn;
  final bool parted;
  final bent = LiquidGlassBentContent();

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void dispose() {
    bent.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!bentOn) return _thinLines(context.canvas, shape, offset);
    final rect = shape.shift(offset);
    bent.paint(
      context,
      offset,
      rect: rect,
      radius: _radius,
      clip: Path()
        ..addRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(_radius)),
        ),
      bends: const [LiquidGlassContentBend(amount: 6, height: 10)],
      devicePixelRatio: 3,
      aberration: parted ? 3.7 : 0,
      aberrationDepth: parted ? 14 : 0,
      content: (context, offset) => _thinLines(context.canvas, shape, offset),
    );
  }
}

/// The red of every device pixel of a black page at three device pixels a
/// point, under [_thinLines] painted as they are or through a bent shape.
Future<(Uint8List, int)> _sharp(
  WidgetTester tester,
  Rect shape, {
  required bool bent,
  required bool parted,
}) async {
  tester.view.physicalSize = const Size(1200, 420);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _key,
      child: ColoredBox(
        color: _black,
        child: _Sharp(
          key: ValueKey((shape, bent, parted)),
          shape: shape,
          bent: bent,
          parted: parted,
        ),
      ),
    ),
  );
  return (await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_key),
    );
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData();
    final width = image.width;
    image.dispose();
    return (bytes!.buffer.asUint8List(), width);
  }))!;
}

void main() {
  const bend = LiquidGlassContentBend(amount: 10, height: 10);
  // A line across the shape 12 to 14 px under its top, deeper than the
  // bends below reach.
  final line = Rect.fromLTWH(_shape.left, _shape.top + 12, _shape.width, 2);
  final x = _shape.center.dx.round();
  int row(int depth) => _shape.top.round() + depth;
  bool inPlace(WidgetTester tester) =>
      tester.renderObject<_RenderBent>(find.byType(_Bent)).paintedInPlace;

  test('a bend shows at the rim what lies its amount deeper, along a '
      'quarter circle to nothing at its height', () {
    expect(bend.shownDepth(0), 10);
    // Half way the quarter circle has fallen to 1 - sqrt(0.75).
    expect(bend.shownDepth(5), moreOrLessEquals(6.340, epsilon: 1e-3));
    expect(bend.shownDepth(10), 10);
    expect(bend.shownDepth(20), 20);
    expect(bend.shownDepth(-1), -1);
  });

  testWidgets('without a bend the content is painted as it is, into the '
      'context it was given', (tester) async {
    final reds = await _reds(tester, const [], [line]);
    expect(reds(x, row(12)), 255);
    expect(reds(x, row(13)), 255);
    expect(reds(x, row(11)), 0);
    expect(reds(x, row(0)), 0);
    expect(inPlace(tester), isTrue);
  });

  testWidgets('a bend shows a line deeper than it reaches in place and '
      'again under the rim', (tester) async {
    // 0.5 px deep a bend of 18 over 10 shows what lies 0.5 + 18 * (1 -
    // sqrt(1 - 0.95 * 0.95)) = 12.9 px deep, the line, and 1.5 px deep
    // what lies 10.0 px deep, nothing.
    final reds = await _reds(
      tester,
      const [LiquidGlassContentBend(amount: 18, height: 10)],
      [line],
    );
    expect(inPlace(tester), isFalse);
    expect(reds(x, row(12)), greaterThan(252));
    expect(reds(x, row(13)), greaterThan(252));
    expect(reds(x, row(14)), lessThan(3));
    expect(reds(x, row(1)), lessThan(3));
    expect(reds(x, row(5)), lessThan(3));
    expect(reds(x, row(0)), greaterThan(150));
  });

  testWidgets('bends apply in order, each to what the one before it shows', (
    tester,
  ) async {
    // The first reads 10 px deep at the rim, where the second reaches no
    // more: together they show there what one shows, not the line.
    final reds = await _reds(tester, const [bend, bend], [line]);
    expect(reds(x, row(0)), lessThan(3));
    expect(reds(x, row(12)), greaterThan(252));
  });

  testWidgets('what the bends do not reach shows pixel for pixel, and '
      'nothing shows outside the clip', (tester) async {
    final mark = Rect.fromLTWH(_shape.center.dx, _shape.top + 30, 1, 10);
    final reds = await _reds(
      tester,
      const [bend],
      [
        mark,
        const Rect.fromLTWH(0, 0, 10, 140),
      ],
    );
    final column = mark.left.round();
    for (var y = row(30); y < row(40); y++) {
      expect(reds(column, y), greaterThan(252));
      expect(reds(column - 1, y), lessThan(3));
      expect(reds(column + 1, y), lessThan(3));
    }
    expect(reds(5, 70), 0);
  });

  group('with a parting', () {
    const bends = [LiquidGlassContentBend(amount: 6, height: 10)];
    // Three rows across the shape, 9 to 12 px under its top.
    final band = Rect.fromLTWH(_shape.left, _shape.top + 9, _shape.width, 3);

    Future<List<int> Function(int x, int y)> parted(
      WidgetTester tester,
      List<Rect> marks, {
      Color? page = _black,
      Color color = _white,
      List<LiquidGlassContentBend> through = bends,
    }) => _pixels(
      tester,
      through,
      marks,
      page: page,
      color: color,
      aberration: 3.7,
      aberrationDepth: 14,
    );

    testWidgets('the colors of what the bends show part by the law: red '
        'reads ahead, blue behind and green around', (tester) async {
      final pixels = await parted(tester, [band]);
      expect(inPlace(tester), isFalse);
      for (var depth = 0; depth < 16; depth++) {
        final law = _law(
          x,
          row(depth),
          bends: bends,
          aberration: 3.7,
          aberrationDepth: 14,
          mark: band,
        );
        for (var channel = 0; channel < 3; channel++) {
          expect(
            pixels(x, row(depth))[channel],
            closeTo(law[channel] * 255, 6),
            reason: 'row $depth channel $channel',
          );
        }
      }
      // Under the straight top a read ahead lies up, so above the band blue
      // shows first and below it red shows last.
      final above = pixels(x, row(8));
      final below = pixels(x, row(12));
      expect(above[2], greaterThan(above[0] + 50));
      expect(below[0], greaterThan(below[2] + 15));
    });

    testWidgets('around a corner the reads follow the outline as it turns', (
      tester,
    ) async {
      // A band along the left end of the shape, 8 to 16 px inside its box.
      final mark = Rect.fromLTWH(_shape.left + 8, _shape.top, 8, _shape.height);
      final pixels = await parted(tester, [mark]);
      final center = Offset(_shape.left + _radius, _shape.center.dy);
      var parts = 0;
      for (final degrees in [120, 135, 150, 165, 180, 195, 210, 225, 240]) {
        for (var depth = 1; depth < 14; depth++) {
          final at =
              center +
              Offset.fromDirection(degrees * math.pi / 180, _radius - depth);
          final px = at.dx.floor();
          final py = at.dy.floor();
          // The clip smooths the pixels its edge crosses, which the laws
          // leave out.
          if (_rim(Offset(px + 0.5, py + 0.5)).$1 < 1) continue;
          final law = _law(
            px,
            py,
            bends: bends,
            aberration: 3.7,
            aberrationDepth: 14,
            mark: mark,
          );
          final pixel = pixels(px, py);
          for (var channel = 0; channel < 3; channel++) {
            expect(
              pixel[channel],
              closeTo(law[channel] * 255, 12),
              reason: '$degrees degrees, $depth deep, channel $channel',
            );
          }
          if ((pixel[0] - pixel[2]).abs() > 40) parts++;
        }
      }
      expect(parts, greaterThan(10));
    });

    testWidgets('every color covers what lies under the content by its own '
        'reads', (tester) async {
      final light = await parted(tester, [band]);
      final lights = [
        for (var depth = 0; depth < 16; depth++) light(x, row(depth)),
      ];
      final dark = await parted(tester, [band], page: _white, color: _black);
      for (var depth = 0; depth < 16; depth++) {
        final pixel = dark(x, row(depth));
        for (var channel = 0; channel < 3; channel++) {
          expect(
            pixel[channel],
            closeTo(255 - lights[depth][channel], 2),
            reason: 'row $depth channel $channel',
          );
        }
      }
    });

    testWidgets('in a layer that holds nothing under it the content covers '
        'by its widest color', (tester) async {
      final pixels = await parted(tester, [band], page: null);
      var partedRows = 0;
      for (var depth = 0; depth < 16; depth++) {
        final pixel = pixels(x, row(depth));
        final widest = math.max(pixel[0], math.max(pixel[1], pixel[2]));
        expect(pixel[3], closeTo(widest, 2), reason: 'row $depth');
        if (pixel[0] != pixel[2]) partedRows++;
      }
      expect(partedRows, greaterThan(2));
    });

    testWidgets('what neither the bends nor the parting reach shows pixel '
        'for pixel, and nothing shows outside the clip', (tester) async {
      final mark = Rect.fromLTWH(_shape.center.dx, _shape.top + 30, 1, 10);
      final pixels = await parted(tester, [
        mark,
        const Rect.fromLTWH(0, 0, 10, 140),
      ]);
      final column = mark.left.round();
      for (var y = row(30); y < row(40); y++) {
        for (var channel = 0; channel < 3; channel++) {
          expect(pixels(column, y)[channel], greaterThan(252));
          expect(pixels(column - 1, y)[channel], lessThan(3));
          expect(pixels(column + 1, y)[channel], lessThan(3));
        }
      }
      expect(pixels(5, 70), [0, 0, 0, 255]);
    });

    testWidgets('translucent content of one color shows one color where the '
        'shader draws it and where the picture does', (
      tester,
    ) async {
      final pixels = await parted(
        tester,
        [_shape],
        color: const Color(0x80FFFFFF),
      );
      final seen = <int>{};
      for (var y = _shape.top.round(); y < _shape.bottom; y++) {
        for (var x = _shape.left.round(); x < _shape.right; x++) {
          // Nearer the rim the reads beside a point leave the shape.
          if (_rim(Offset(x + 0.5, y + 0.5)).$1 < 8) continue;
          seen.add(pixels(x, y)[0]);
        }
      }
      expect(seen.reduce(math.max) - seen.reduce(math.min), lessThan(2));
    });

    testWidgets('content that holds one color everywhere stays that color to '
        'the rim', (tester) async {
      final pixels = await parted(tester, [_shape]);
      for (var depth = 1; depth < 16; depth++) {
        expect(pixels(x, row(depth)), [255, 255, 255, 255]);
      }
      expect(pixels(_shape.left.round() + 3, _shape.center.dy.round()), [
        255,
        255,
        255,
        255,
      ]);
    });

    testWidgets('a parting without a bend parts the content in place', (
      tester,
    ) async {
      final pixels = await parted(tester, [band], through: const []);
      expect(inPlace(tester), isFalse);
      final above = pixels(x, row(8));
      expect(above[2], greaterThan(above[0] + 50));
      expect(pixels(x, row(10))[1], greaterThan(252));
    });

    testWidgets('more than two bends are shown and not parted', (
      tester,
    ) async {
      const one = LiquidGlassContentBend(amount: 2, height: 10);
      final pixels = await parted(
        tester,
        [band],
        through: const [one, one, one],
      );
      for (var depth = 0; depth < 16; depth++) {
        final pixel = pixels(x, row(depth));
        expect(pixel[0], pixel[2], reason: 'row $depth');
      }
    });
  });

  group('at three device pixels a point', () {
    // At 256.34 the shape's device pixels add up to a hair past 360, so
    // its picture comes out a pixel wider than the shape.
    for (final left in [40.37, 256.34]) {
      for (final parted in [false, true]) {
        testWidgets('the middle of a shape at $left shows device-pixel lines '
            'pixel for pixel, ${parted ? 'parted' : 'not parted'}', (
          tester,
        ) async {
          final shape = Rect.fromLTWH(left, 30.21, 120, 70);
          final (want, width) = await _sharp(
            tester,
            shape,
            bent: false,
            parted: parted,
          );
          final (got, _) = await _sharp(
            tester,
            shape,
            bent: true,
            parted: parted,
          );
          final middle = shape.deflate(22);
          var lines = 0;
          for (var y = (middle.top * 3).ceil(); y < middle.bottom * 3; y++) {
            for (var x = (middle.left * 3).ceil(); x < middle.right * 3; x++) {
              final i = (y * width + x) * 4;
              expect(got[i], closeTo(want[i], 2), reason: '$x, $y');
              if (want[i] > 250) lines++;
            }
          }
          expect(lines, greaterThan(1000));
        });
      }
    }
  });
}
