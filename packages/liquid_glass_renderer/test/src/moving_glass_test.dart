import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/plan/plan_result.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_haze.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';

import 'shared.dart';
import 'submitted_scene_binding.dart';

const double _dpr = 2.625;
const Size _view = Size(400, 280);
const double _lens = 130;

// Rows of dark strokes on white, like a page of text, painted anew each
// frame as a page with live content is.
class _Page extends CustomPainter {
  const _Page(this.frame);

  final int frame;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final ink = Paint()..color = const Color(0xFF000000);
    var seed = 7;
    int next(int range) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return (seed >> 8) % range;
    }

    for (var line = 18.0; line < size.height; line += 30) {
      var x = 18.0;
      while (x < size.width - 18) {
        final glyph = 9.0 + next(6);
        final stroke = 1.5 + next(3) * 0.5;
        canvas
          ..drawRect(Rect.fromLTWH(x + 1, line + 4 + next(4), stroke, 14), ink)
          ..drawRect(Rect.fromLTWH(x + 1, line + 16, glyph - 2, 2), ink);
        x += glyph + (next(5) == 0 ? 7 : 0);
      }
    }
  }

  @override
  bool shouldRepaint(_Page oldDelegate) => frame != oldDelegate.frame;
}

Widget _scene(int frame, Offset at) => Directionality(
  textDirection: TextDirection.ltr,
  child: Stack(
    children: [
      Positioned.fill(
        child: RepaintBoundary(child: CustomPaint(painter: _Page(frame))),
      ),
      Positioned.fill(
        child: LiquidGlassLayer(
          settings: const LiquidGlassSettings.ios27Clear(sliderPosition: 0.92),
          child: Stack(
            children: [
              Positioned(
                left: at.dx,
                top: at.dy,
                width: _lens,
                height: _lens,
                child: const LiquidGlass(
                  shape: LiquidOval(),
                  appearance: LiquidGlassAppearance.ios27Clear(),
                  child: SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  ),
);

void main() {
  final binding = SubmittedSceneBinding()
    ..captureWidth = (_view.width * _dpr).round()
    ..captureHeight = (_view.height * _dpr).round();

  // Glass carried down and across a page that holds still shows the same
  // page in its middle, where it bends nothing, wherever it lies: the haze
  // averages the page on cells of the screen, and an image Impeller blurs
  // lies on the screen's grid of the blur's cells. Counted from the copy's
  // corner, the middle of the glass flickered in patches each step of the
  // copy: its most moved block of 16 pixels moved by 0.47 levels on average
  // under the haze, by 2.9 under Impeller's blur. What is left is a level
  // here and there, 0.12 and 0.07 a block.
  for (final haze in [true, false]) {
    testWidgets(
      haze
          ? 'glass carried over a still page keeps its haze still'
          : "glass carried over a still page keeps Impeller's blur still",
      (tester) async {
        await tester.runAsync(precacheLiquidGlass);
        final copies = glassReadsCopies;
        glassReadsCopies = true;
        debugGlassHaze = haze ? null : false;
        addTearDown(() {
          glassReadsCopies = copies;
          debugGlassHaze = null;
        });
        tester.view
          ..physicalSize = _view * _dpr
          ..devicePixelRatio = _dpr;
        addTearDown(tester.view.reset);
        GlassPlan? plan;
        GlassComposer.debugOnPlan = (_, next) => plan = next;
        addTearDown(() => GlassComposer.debugOnPlan = null);

        var frames = 0;
        Future<Uint8List> frame(Offset at) async {
          await tester.pumpWidget(_scene(frames++, at));
          binding
            ..captureNextScene = true
            ..scheduleFrame();
          await tester.pump();
          final image = (await tester.runAsync(() => binding.captured!))!;
          final bytes = (await tester.runAsync(image.toByteData))!;
          image.dispose();
          return bytes.buffer.asUint8List();
        }

        final width = binding.captureWidth;
        // The most a block of 16 x 16 pixels in the middle of the glass
        // moves on average from [last] to [next].
        double patchOf(Uint8List last, Uint8List next, Offset at) {
          final middleX = ((at.dx + _lens / 2) * _dpr).round();
          final middleY = ((at.dy + _lens / 2) * _dpr).round();
          var worst = 0.0;
          for (var by = -3; by < 3; by++) {
            for (var bx = -3; bx < 3; bx++) {
              var sum = 0;
              for (var y = 0; y < 16; y++) {
                for (var x = 0; x < 16; x++) {
                  final row = middleY + by * 16 + y;
                  final at = (row * width + middleX + bx * 16 + x) * 4 + 1;
                  sum += next[at] - last[at];
                }
              }
              worst = math.max(worst, sum.abs() / 256);
            }
          }
          return worst;
        }

        var at = const Offset(120, 60);
        const step = Offset(0.4, 0.4);
        await frame(at);
        var last = await frame(at += step);
        final placed = <Rect>{};
        var patches = 0.0;
        const steps = 24;
        for (var i = 0; i < steps; i++) {
          final next = await frame(at += step);
          final read = plan!.reads.singleWhere(
            (read) => read.glassMembers.isNotEmpty,
          );
          if (haze) {
            expect(read.source, isA<SceneRead>());
            expect(read.layout.haze, isNotNull);
            placed.add(read.layout.layer.rect);
          } else {
            expect(read.source, isA<ImageRead>());
            expect(read.layout.filter, isNotNull);
            placed.add(read.layout.imageBox!.rect);
          }
          patches += patchOf(last, next, at);
          last = next;
        }
        expect(placed.length, greaterThan(4), reason: 'the copy moved');
        expect(patches / steps, lessThan(0.2));
      },
      skip: skipProperGlassTests,
    );
  }
}
