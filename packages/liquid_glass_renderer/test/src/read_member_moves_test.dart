// Run with `flutter test --enable-impeller --enable-flutter-gpu`: glass over a
// copy is drawn by a runtime effect, which only Impeller draws. Without them
// the drawing test returns early.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_read.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';

import 'shared.dart';

const _viewSize = Size(300, 300);

// Keeps the image of every scene the view is given.
class _CapturingView extends TestFlutterView {
  _CapturingView(WidgetTester tester)
    : super(
        view: tester.view,
        platformDispatcher: tester.platformDispatcher,
        display: tester.view.display,
      ) {
    physicalSize = _viewSize * 2;
    devicePixelRatio = 2;
  }

  ui.Image? last;

  @override
  void render(ui.Scene scene, {Size? size}) {
    last?.dispose();
    last = scene.toImageSync(
      _viewSize.width.toInt() * 2,
      _viewSize.height.toInt() * 2,
    );
  }

  Future<Uint8List> bytes(WidgetTester tester) async {
    final data = (await tester.runAsync(last!.toByteData))!;
    return data.buffer.asUint8List();
  }
}

final class _Painter implements ReadPainter {
  @override
  ui.ImageFilter readFilter(GlassRead read, CornerRead corner) =>
      throw UnimplementedError();

  @override
  Object pageKey(GlassRead read, PageCopy page) => throw UnimplementedError();

  @override
  ui.Picture recordPage(
    GlassRead read,
    PageCopy page,
    Matrix4 screenToCanvas,
  ) => throw UnimplementedError();
}

Widget _button(double left, double top) => Positioned(
  left: left,
  top: top,
  width: 80,
  height: 40,
  child: LiquidGlassLayer(
    settings: LiquidGlassSettings.ios27RegularLight(),
    child: const LiquidGlass(
      shape: LiquidRoundedSuperellipse(borderRadius: 20),
      child: SizedBox.expand(),
    ),
  ),
);

// Hard edges under every button, where any shift of a read shows.
Widget _stripes() => Column(
  children: [
    for (var i = 0; i < 30; i++)
      Container(
        height: 10,
        color: Color(0xFF000000 | (i * 2654435761) & 0xFFFFFF),
      ),
  ],
);

// The first button rests; the second lies [shift] away from its place.
Widget _scene(_CapturingView view, ValueListenable<Offset> shift) => View(
  view: view,
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Stack(
      children: [
        _stripes(),
        _button(20, 20),
        ValueListenableBuilder(
          valueListenable: shift,
          builder: (_, value, child) =>
              Transform.translate(offset: value, child: child),
          child: SizedBox.fromSize(
            size: _viewSize,
            child: Stack(children: [_button(120, 20)]),
          ),
        ),
      ],
    ),
  ),
);

int _readLayersOf(WidgetTester tester, _CapturingView view) {
  final root = tester.binding.renderViews
      .firstWhere((candidate) => identical(candidate.flutterView, view))
      .debugLayer!;
  var count = 0;
  void walk(Layer layer) {
    if (layer is ReadLayer) count++;
    if (layer is ContainerLayer) {
      var child = layer.firstChild;
      while (child != null) {
        walk(child);
        child = child.nextSibling;
      }
    }
  }

  walk(root);
  return count;
}

(double, int) _difference(Uint8List a, Uint8List b) {
  var sum = 0;
  var most = 0;
  for (var i = 0; i < a.length; i++) {
    if (i % 4 == 3) continue;
    final delta = (a[i] - b[i]).abs();
    sum += delta;
    if (delta > most) most = delta;
  }
  return (sum / (a.length * 3 / 4), most);
}

void main() {
  setUp(() => debugGlassCopies = true);
  tearDown(() {
    debugGlassCopies = null;
    debugGlassPolicy = const PlanPolicy();
  });

  test('a painter role is equal for the same painter at the same place', () {
    final painter = _Painter();
    const at = Offset(12.5, 40);
    expect(
      PainterRole(painter, originOnScreen: at),
      PainterRole(painter, originOnScreen: at),
    );
    expect(
      PainterRole(painter, originOnScreen: at).hashCode,
      PainterRole(painter, originOnScreen: at).hashCode,
    );
    expect(
      PainterRole(painter, originOnScreen: at),
      isNot(PainterRole(painter, originOnScreen: at + const Offset(0, 0.5))),
    );
    expect(
      PainterRole(painter, originOnScreen: at),
      isNot(PainterRole(_Painter(), originOnScreen: at)),
    );
  });

  testWidgets('a read draws a member that moved where it now is, in the frame '
      'it moves', (tester) async {
    if (skipProperGlassTests) return;
    final view = _CapturingView(tester);
    final shift = ValueNotifier(Offset.zero);
    addTearDown(shift.dispose);
    const moved = Offset(13.5, 37);

    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await tester.pump();
    }

    Future<void> clear() => tester.pumpWidget(
      View(view: view, child: const SizedBox()),
      wrapWithView: false,
    );

    debugGlassPolicy = const PlanPolicy(maxShapes: 0);
    await clear();
    shift.value = moved;
    await tester.pumpWidget(_scene(view, shift), wrapWithView: false);
    await settle();
    expect(_readLayersOf(tester, view), 2);
    final apart = await view.bytes(tester);

    debugGlassPolicy = const PlanPolicy();
    await clear();
    shift.value = Offset.zero;
    await tester.pumpWidget(_scene(view, shift), wrapWithView: false);
    await settle();
    expect(_readLayersOf(tester, view), 1);
    final layers = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .toList();
    expect(layers, hasLength(2));
    final resting = layers.first.ask().role;
    final before = layers.last.ask().role! as PainterRole;

    shift.value = moved;
    await tester.pump();
    expect(_readLayersOf(tester, view), 1);
    final joined = await view.bytes(tester);
    final (mean, most) = _difference(apart, joined);
    expect(mean, lessThan(0.25), reason: 'mean $mean, most $most');

    expect(identical(layers.first.ask().role, resting), isTrue);
    final after = layers.last.ask().role! as PainterRole;
    expect(after, isNot(before));
    expect(after.originOnScreen - before.originOnScreen, moved);
    await clear();
  });
}
