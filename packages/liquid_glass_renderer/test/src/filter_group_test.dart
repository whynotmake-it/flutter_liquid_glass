// Run with `flutter test --enable-impeller --enable-flutter-gpu`: glass over a
// copy is drawn by a runtime effect, which only Impeller draws. Without them
// these tests return early.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/group_matte.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _viewSize = Size(300, 300);

// Keeps the image of every scene the view is given: a boundary's image is
// taken outside a frame, which the composer does not plan.
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

Widget _button(
  double left,
  double top, {
  double width = 80,
  double height = 40,
}) => Positioned(
  left: left,
  top: top,
  width: width,
  height: height,
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

Widget _scene(_CapturingView view, List<Widget> children) => View(
  view: view,
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Stack(
      children: [_stripes(), ...children],
    ),
  ),
);

Future<(Uint8List, int)> _draw(
  WidgetTester tester,
  _CapturingView view,
  List<Widget> children, {
  required bool groups,
}) async {
  // Nothing shares when no site fits a matte with another.
  debugGlassPolicy = PlanPolicy(maxShapes: groups ? 16 : 0);
  addTearDown(() => debugGlassPolicy = const PlanPolicy());
  await tester.pumpWidget(
    View(view: view, child: const SizedBox()),
    wrapWithView: false,
  );
  await tester.pumpWidget(_scene(view, children), wrapWithView: false);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump();
  await tester.pump();
  final bytes = await view.bytes(tester);
  return (bytes, _layersOf(tester, view));
}

int _layersOf(WidgetTester tester, _CapturingView view) {
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
  setUp(() {
    debugGlassCopies = true;
    GroupMatte.debugRenders = 0;
  });
  tearDown(() => debugGlassCopies = null);

  Future<void> expectSame(
    WidgetTester tester,
    List<Widget> children, {
    required int layersOn,
    required int layersOff,
  }) async {
    if (skipProperGlassTests) return;
    final view = _CapturingView(tester);
    final (off, countOff) = await _draw(
      tester,
      view,
      children,
      groups: false,
    );
    final (on, countOn) = await _draw(tester, view, children, groups: true);
    expect(countOff, layersOff);
    expect(countOn, layersOn);
    final (mean, most) = _difference(off, on);
    expect(mean, lessThan(0.25), reason: 'mean $mean, most $most');
    await tester.pumpWidget(
      View(view: view, child: const SizedBox()),
      wrapWithView: false,
    );
  }

  testWidgets('buttons apart draw as they do alone, in one layer', (
    tester,
  ) async {
    await expectSame(
      tester,
      [
        _button(20, 20),
        _button(120, 20),
        _button(20, 80),
        _button(120, 80),
      ],
      layersOn: 1,
      layersOff: 4,
    );
  });

  testWidgets('buttons of different tints draw in one layer as they do alone', (
    tester,
  ) async {
    Widget tinted(double left, double top, Color tint) => Positioned(
      left: left,
      top: top,
      width: 80,
      height: 40,
      child: LiquidGlassLayer(
        settings: LiquidGlassSettings.ios27RegularLight(),
        child: LiquidGlass(
          shape: const LiquidRoundedSuperellipse(borderRadius: 20),
          appearance: LiquidGlassAppearance.ios27RegularLight(tint: tint),
          child: const SizedBox.expand(),
        ),
      ),
    );
    await expectSame(
      tester,
      [
        tinted(20, 20, const Color(0x00007AFF)),
        tinted(120, 20, const Color(0xFF0088FF)),
        tinted(20, 80, const Color(0x00007AFF)),
        tinted(120, 80, const Color(0xCCFF3B30)),
      ],
      layersOn: 1,
      layersOff: 4,
    );
  });

  testWidgets('something painted over a later button leaves it out', (
    tester,
  ) async {
    await expectSame(
      tester,
      [
        _button(20, 20),
        const Positioned(
          left: 120,
          top: 20,
          width: 80,
          height: 40,
          child: ColoredBox(color: Color(0xFFFF0000)),
        ),
        _button(120, 20),
      ],
      layersOn: 2,
      layersOff: 2,
    );
  });

  testWidgets('something painted beside a later button leaves it in', (
    tester,
  ) async {
    await expectSame(
      tester,
      [
        _button(20, 20),
        const Positioned(
          left: 106,
          top: 30,
          width: 8,
          height: 20,
          child: RepaintBoundary(
            child: ColoredBox(color: Color(0xFFFF0000)),
          ),
        ),
        _button(120, 20),
      ],
      layersOn: 1,
      layersOff: 2,
    );
  });

  testWidgets('glass under other clips groups with its own neighbours', (
    tester,
  ) async {
    Widget card(double top, List<Widget> buttons) => Positioned(
      left: 10,
      top: top,
      width: 280,
      height: 80,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(children: buttons),
      ),
    );
    await expectSame(
      tester,
      [
        card(10, [_button(10, 20), _button(110, 20)]),
        card(110, [_button(10, 20), _button(110, 20)]),
      ],
      layersOn: 2,
      layersOff: 4,
    );
  });

  testWidgets('an opacity around one button leaves it out', (tester) async {
    await expectSame(
      tester,
      [
        _button(20, 20),
        _button(120, 20),
        Positioned(
          left: 20,
          top: 80,
          width: 80,
          height: 40,
          child: Opacity(
            opacity: 0.5,
            child: LiquidGlassLayer(
              settings: LiquidGlassSettings.ios27RegularLight(),
              child: const LiquidGlass(
                shape: LiquidRoundedSuperellipse(borderRadius: 20),
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      ],
      layersOn: 2,
      layersOff: 3,
    );
  });

  testWidgets('glass that overlaps stays apart', (tester) async {
    await expectSame(
      tester,
      [_button(20, 20), _button(60, 30)],
      layersOn: 2,
      layersOff: 2,
    );
  });

  testWidgets('glass moving together renders its matte once', (tester) async {
    if (skipProperGlassTests) return;
    final view = _CapturingView(tester);
    final offset = ValueNotifier<double>(0);
    addTearDown(offset.dispose);
    await tester.pumpWidget(
      _scene(view, [
        ValueListenableBuilder(
          valueListenable: offset,
          builder: (_, value, child) =>
              Transform.translate(offset: Offset(0, value), child: child),
          child: SizedBox.fromSize(
            size: _viewSize,
            child: Stack(children: [_button(20, 20), _button(120, 20)]),
          ),
        ),
      ]),
      wrapWithView: false,
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pump();
    final rendered = GroupMatte.debugRenders;
    expect(rendered, greaterThan(0));
    for (var i = 1; i <= 10; i++) {
      offset.value = i * 3.3;
      await tester.pump();
    }
    expect(GroupMatte.debugRenders, rendered);
    expect(_layersOf(tester, view), 1);
    await tester.pumpWidget(
      View(view: view, child: const SizedBox()),
      wrapWithView: false,
    );
  });
}
