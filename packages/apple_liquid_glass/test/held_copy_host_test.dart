@Tags(['macos_pixels'])
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/rendering.dart';
// Run with `flutter test --enable-impeller --enable-flutter-gpu`: without
// Impeller there is no glass to read.
//
// A read keeps what did not change in the rows it reads between frames, and
// shows what a fresh mount at the same place shows.

import 'package:liquid_glass_renderer/src/plan/plan.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';

const _viewSize = Size(300, 600);
const _dpr = 2.0;

class _CapturingView extends TestFlutterView {
  _CapturingView(WidgetTester tester)
    : super(
        view: tester.view,
        platformDispatcher: tester.platformDispatcher,
        display: tester.view.display,
      ) {
    physicalSize = _viewSize * _dpr;
    devicePixelRatio = _dpr;
  }

  ui.Image? last;

  @override
  void render(ui.Scene scene, {Size? size}) {
    last?.dispose();
    last = scene.toImageSync(
      (_viewSize.width * _dpr).toInt(),
      (_viewSize.height * _dpr).toInt(),
    );
  }
}

Widget _card(Color color) => SizedBox(
  height: 60,
  child: ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: Opacity(
      opacity: 0.8,
      child: ColoredBox(color: color),
    ),
  ),
);

Widget _row(int index, ValueListenable<Color> first) => RepaintBoundary(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ValueListenableBuilder(
        valueListenable: first,
        // A boundary of its own: the row around it paints nothing new.
        builder: (_, color, _) => RepaintBoundary(
          child: _card(index.isEven ? color : const Color(0xFF0000C0)),
        ),
      ),
      RepaintBoundary(
        child: _card(
          index.isEven ? const Color(0xFFC00000) : const Color(0xFF00C0C0),
        ),
      ),
    ],
  ),
);

Widget _page(
  _CapturingView view,
  ScrollController controller,
  ValueListenable<Color> first,
) => View(
  view: view,
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Stack(
      children: [
        ListView.builder(
          controller: controller,
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: 40,
          itemBuilder: (_, index) => _row(index, first),
        ),
        for (var i = 0; i < 4; i++)
          Positioned(
            left: 10.0 + 70 * i,
            width: 60,
            top: 10,
            height: 80,
            child: LiquidGlassLayer(
              settings:
                  const LiquidGlassSettings.ios27Regular(
                    brightness: Brightness.light,
                  ).copyWith(
                    glintStrength: 0.1 + i / 100,
                  ),
              child: const LiquidGlass(
                shape: LiquidRoundedSuperellipse(radius: 20),
                child: SizedBox.expand(),
              ),
            ),
          ),
      ],
    ),
  ),
);

Future<void> _loaded(WidgetTester tester) => tester.runAsync(
  () => Future<void>.delayed(const Duration(milliseconds: 200)),
);

// Flutter_tester's software Vulkan crashes under frames drawn back to back.
Future<void> _frame(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
}

Future<Uint8List> _pixels(WidgetTester tester, _CapturingView view) async {
  final data = (await tester.runAsync(view.last!.toByteData))!;
  return data.buffer.asUint8List();
}

Future<void> _expectSameAsFresh(
  WidgetTester tester,
  _CapturingView view,
  Uint8List moved,
  double offset,
  ValueListenable<Color> first,
) async {
  // A view keeps what it holds by a global key: only an empty view between
  // the two pages makes the second one new.
  await tester.pumpWidget(
    View(view: view, child: const SizedBox()),
    wrapWithView: false,
  );
  final fresh = ScrollController(initialScrollOffset: offset);
  addTearDown(fresh.dispose);
  await tester.pumpWidget(_page(view, fresh, first), wrapWithView: false);
  await _loaded(tester);
  await _frame(tester);
  await _frame(tester);
  final direct = await _pixels(tester, view);
  var off = 0;
  for (var i = 0; i < moved.length; i += 4) {
    if ((moved[i] - direct[i]).abs() > 3 ||
        (moved[i + 1] - direct[i + 1]).abs() > 3 ||
        (moved[i + 2] - direct[i + 2]).abs() > 3) {
      off++;
    }
  }
  expect(off, 0);
}

void main() {
  setUp(() {
    glassReadsCopies = true;
    // Every read stays in the scene while the test counts what it adds: the
    // rows under each are layers drawn apart, six targets a read.
    debugGlassPolicy = const PlanPolicy(maxTargets: 64);
  });
  tearDown(() {
    glassReadsCopies = false;
    debugGlassPolicy = const PlanPolicy();
  });

  testWidgets('a scrolled read adds fewer layers once they hold', (
    tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    final view = _CapturingView(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final first = ValueNotifier(const Color(0xFF00C000));
    addTearDown(first.dispose);
    await tester.pumpWidget(
      _page(view, controller, first),
      wrapWithView: false,
    );
    await _loaded(tester);
    await _frame(tester);

    GlassFrameReport? last;
    void listener(GlassFrameReport report) => last = report;
    GlassFrameReports.addListener(listener);
    addTearDown(() => GlassFrameReports.removeListener(listener));
    final replayed = <int>[];
    var offset = 0.0;
    for (var i = 0; i < 12; i++) {
      offset += 5;
      controller.jumpTo(offset);
      await _frame(tester);
      replayed.add(last!.layersReplayed);
    }
    expect(
      last!.reads.map((read) => read.source),
      everyElement(GlassReadSource.scene),
    );
    // Rows that stay under the glass add their pictures once. Bands that
    // overlap walk what an earlier one took this frame, down to what is still
    // free.
    expect(replayed.first, greaterThanOrEqualTo(8));
    expect(replayed.last, lessThanOrEqualTo(replayed.first ~/ 2));
    final moved = await _pixels(tester, view);
    await _expectSameAsFresh(tester, view, moved, offset, first);
  });

  testWidgets('a held row shows what changed in it', (tester) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    final view = _CapturingView(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final first = ValueNotifier(const Color(0xFF00C000));
    addTearDown(first.dispose);
    await tester.pumpWidget(
      _page(view, controller, first),
      wrapWithView: false,
    );
    await _loaded(tester);
    await _frame(tester);
    var offset = 0.0;
    for (var i = 0; i < 6; i++) {
      offset += 5;
      controller.jumpTo(offset);
      await _frame(tester);
    }
    first.value = const Color(0xFFC0C000);
    offset += 5;
    controller.jumpTo(offset);
    await _frame(tester);
    final moved = await _pixels(tester, view);
    await _expectSameAsFresh(tester, view, moved, offset, first);
  });

  testWidgets('a held row brings what the viewport cut when it was kept', (
    tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    final view = _CapturingView(tester);
    final controller = ScrollController(initialScrollOffset: 110);
    addTearDown(controller.dispose);
    final first = ValueNotifier(const Color(0xFF00C000));
    addTearDown(first.dispose);
    await tester.pumpWidget(
      _page(view, controller, first),
      wrapWithView: false,
    );
    await _loaded(tester);
    await _frame(tester);
    // The first row's first card lies above the screen, then comes back.
    var offset = 110.0;
    for (var i = 0; i < 20; i++) {
      offset -= 5;
      controller.jumpTo(offset);
      await _frame(tester);
    }
    final moved = await _pixels(tester, view);
    await _expectSameAsFresh(tester, view, moved, offset, first);
  });
}
