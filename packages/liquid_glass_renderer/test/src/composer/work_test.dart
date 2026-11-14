// Run with `flutter test --enable-impeller --enable-flutter-gpu`: glass is
// drawn as on a device, and fake glass otherwise.
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:liquid_glass_test/liquid_glass_test.dart';
import 'package:material_ui/material_ui.dart';

import '../shared.dart';

const _row = 44.0;

Widget _button(double left, double top, LiquidGlassSettings settings) =>
    Positioned(
      left: left,
      top: top,
      width: 44,
      height: 44,
      child: LiquidGlassLayer(
        settings: settings,
        child: const LiquidGlass(
          shape: LiquidRoundedSuperellipse(borderRadius: 22),
          child: SizedBox.expand(),
        ),
      ),
    );

// A list scrolling under chrome: five buttons along the bottom over a list
// with [rows] rows, each its own colour.
Widget _screen(ScrollController controller, {int buttons = 5, int rows = 80}) {
  final settings = LiquidGlassSettings.ios27RegularLight();
  return Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(400, 800)),
      child: Stack(
        children: [
          Positioned.fill(
            child: ListView.builder(
              controller: controller,
              itemCount: rows,
              itemExtent: _row,
              itemBuilder: (_, i) => ColoredBox(
                color: Color(0xFF000000 | (i * 2654435761) & 0x7F7F7F),
              ),
            ),
          ),
          for (var i = 0; i < buttons; i++)
            _button(8 + i * 76.0, 700, settings),
        ],
      ),
    ),
  );
}

const _tiles = 12;

// Two buttons far apart over one still card of [_tiles] tiles, and under each
// button a mark that [top] or [bottom] moves. The lower mark lies over the
// upper button, so each button has a read of its own.
Widget _overCard(ValueNotifier<double> top, ValueNotifier<double> bottom) {
  final settings = LiquidGlassSettings.ios27RegularLight();
  Widget mark(ValueNotifier<double> left, double y) => ValueListenableBuilder(
    valueListenable: left,
    builder: (_, left, _) => Positioned(
      left: left,
      top: y,
      width: 20,
      height: 20,
      child: const RepaintBoundary(
        child: ColoredBox(color: Color(0xFFFFFFFF)),
      ),
    ),
  );
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: Stack(
              children: [
                for (var i = 0; i < _tiles; i++)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: i * 800 / _tiles,
                    height: 800 / _tiles,
                    child: RepaintBoundary(
                      child: ColoredBox(
                        color: Color(0xFF000000 | (i * 2654435761) & 0x7F7F7F),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        mark(top, 60),
        _button(8, 50, settings),
        mark(bottom, 710),
        _button(8, 700, settings),
      ],
    ),
  );
}

// The glass slots of the frame that hold what their glass shows.
int _filledSlots(WidgetTester tester) {
  var filled = 0;
  void visit(Layer layer) {
    if (layer is GlassSlotLayer && layer.firstChild != null) filled++;
    if (layer is! ContainerLayer) return;
    for (
      var child = layer.firstChild;
      child != null;
      child = child.nextSibling
    ) {
      visit(child);
    }
  }

  visit(tester.binding.renderViews.first.debugLayer!);
  return filled;
}

void main() {
  setUp(() => debugGlassCopies = true);
  tearDown(() => debugGlassCopies = null);

  group('a frame nothing changed', () {
    testWidgets('makes no filter, picture or image and replays nothing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_screen(controller));
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // The first frame someone listens to plans, to say why.
      await expectGlassBudget(tester);
      final report = await expectGlassBudget(
        tester,
        filtersBuilt: 0,
        picturesRecorded: 0,
        imagesDrawn: 0,
      );
      expect(report.planned, isFalse, reason: '$report');
      expect(report.layersReplayed, 0, reason: '$report');
      expect(report.repaintsAsked, 0, reason: '$report');
      expect(report.reads.first.changed, isFalse, reason: '$report');
    }, skip: skipProperGlassTests);
  });

  group('a frame nothing changed in stands on the last plan', () {
    Future<GlassFrameReport> settled(
      WidgetTester tester,
      ScrollController controller,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_screen(controller));
      for (var i = 0; i < 90; i++) {
        tester.binding.scheduleFrame();
        await tester.pump(const Duration(milliseconds: 16));
      }
      await expectGlassBudget(tester);
      return expectGlassBudget(tester);
    }

    testWidgets('until a read is due its image', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // An image dear enough that a read waits some frames for it: at its
      // measured price a button with a haze, three passes a frame, is due
      // one in the frame after the first that is listened to, which plans.
      debugGlassPrices = const PlanPrices(imageGpu: 3);
      addTearDown(() => debugGlassPrices = const PlanPrices());
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_screen(controller));
      final reports = <GlassFrameReport>[];
      for (var i = 0; i < 120; i++) {
        reports.add(await expectGlassBudget(tester));
      }
      final bought = reports.indexWhere((report) => report.imagesDrawn > 0);
      expect(bought, greaterThan(0), reason: reports.last.toString());
      expect(reports[bought].planned, isTrue);
      expect(reports[bought - 1].planned, isFalse);
      expect(reports.last.planned, isFalse);
      expect(reports.last.imageReads, reports.last.reads.length);
    }, skip: skipProperGlassTests);

    testWidgets('but not when the page moved', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await settled(tester, controller);
      controller.jumpTo(30);
      final report = await expectGlassBudget(tester);
      expect(report.planned, isTrue, reason: '$report');
      expect(report.reads.first.changed, isTrue, reason: '$report');
    }, skip: skipProperGlassTests);

    // A paint empties the slot the plan fills; the plan is shown into it
    // again as it was.
    testWidgets('and shows it again when glass painted', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await settled(tester, controller);
      final filled = _filledSlots(tester);
      expect(filled, greaterThan(0));
      for (final glass in find.byType(LiquidGlassLayer).evaluate()) {
        glass.renderObject!.markNeedsPaint();
      }
      final report = await expectGlassBudget(tester);
      expect(report.planned, isFalse, reason: '$report');
      expect(report.imagesDrawn, 0, reason: '$report');
      expect(_filledSlots(tester), filled);
    }, skip: skipProperGlassTests);

    testWidgets('but not when the glass went away', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await settled(tester, controller);
      await tester.pumpWidget(_screen(controller, buttons: 4));
      final report = await expectGlassBudget(tester);
      expect(report.reads.first.glass, 4, reason: '$report');
    }, skip: skipProperGlassTests);
  });

  group('a scroll frame', () {
    testWidgets('makes no more filters than reads that changed', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_screen(controller));
      for (var i = 0; i < 30; i++) {
        controller.jumpTo(i * 3);
        await tester.pump(const Duration(milliseconds: 16));
      }

      controller.jumpTo(100);
      final report = await expectGlassBudget(tester, liveReads: 0);
      final changed = report.reads.where((read) => read.changed).length;
      expect(
        report.filtersBuilt,
        lessThanOrEqualTo(changed),
        reason: '$report',
      );
      expect(report.repaintsAsked, 0, reason: '$report');
    }, skip: skipProperGlassTests);

    testWidgets('replays in proportion to what it shows, not to the list', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Future<int> replayed(int rows) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_screen(controller, rows: rows));
        for (var i = 0; i < 12; i++) {
          controller.jumpTo(i * 3);
          await tester.pump(const Duration(milliseconds: 16));
        }
        controller.jumpTo(60);
        final report = await expectGlassBudget(tester);
        return report.layersReplayed;
      }

      expect(await replayed(2000), lessThanOrEqualTo(await replayed(40) + 2));
    }, skip: skipProperGlassTests);
  });

  // The engine retains the read nothing changed under, with what it kept of
  // the card inside: the other read adds a layer of its own.
  testWidgets('a part of the page two reads keep goes into a scene once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final top = ValueNotifier<double>(0);
    final bottom = ValueNotifier<double>(0);
    addTearDown(top.dispose);
    addTearDown(bottom.dispose);
    await tester.pumpWidget(_overCard(top, bottom));
    top.value = 10;
    bottom.value = 10;
    await expectGlassBudget(tester);

    for (final mark in [bottom, top, bottom]) {
      mark.value += 10;
      final report = await expectGlassBudget(tester, reads: 2, imagesDrawn: 0);
      expect(
        report.reads.where((read) => read.changed),
        hasLength(1),
        reason: '$report',
      );
      expect(report.layersReplayed, lessThan(_tiles), reason: '$report');
    }
  }, skip: skipProperGlassTests);

  testWidgets('a texture under glass stays in a scene read', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: Stack(
            children: [
              const Positioned.fill(child: Texture(textureId: 1)),
              _button(8, 100, LiquidGlassSettings.ios27RegularLight()),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final report = await expectGlassBudget(tester, liveReads: 0);
    expect(report.reads.single.source, GlassReadSource.scene);
    expect(report.reads.single.changed, isTrue);
  }, skip: skipProperGlassTests);

  group('the report', () {
    testWidgets('says what the frame read and made', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_screen(controller));
      await tester.pump();

      final report = await expectGlassBudget(tester);
      final text = '$report';
      expect(report.reads, isNotEmpty);
      expect(text, contains('reads ${report.reads.length}'));
      expect(text, contains('R0 '));
      expect(report.walk, isNot(Duration.zero));
    }, skip: skipProperGlassTests);

    testWidgets('names a layer type nobody registered', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = LiquidGlassSettings.ios27RegularLight();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: Stack(
              children: [
                const Positioned.fill(child: _Foreign()),
                _button(8, 100, settings),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      final report = await expectGlassBudget(tester, liveReads: 1);
      expect(
        report.notes.join('\n'),
        allOf(
          contains('_ForeignLayer (unregistered)'),
          contains('LiquidGlassUnderlay.registerLayer'),
        ),
      );
    }, skip: skipProperGlassTests);

    testWidgets('stops when nobody listens', (tester) async {
      final seen = <GlassFrameReport>[];
      void note(GlassFrameReport report) => seen.add(report);
      GlassFrameReport.addListener(note);
      GlassFrameReport.removeListener(note);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_screen(controller));
      await tester.pump();
      expect(seen, isEmpty);
    });

    testWidgets('shows over the app in an overlay', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        GlassPlanOverlay(child: _screen(controller)),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('reads '), findsOneWidget);
    }, skip: skipProperGlassTests);
  });
}

class _ForeignLayer extends ContainerLayer {}

class _Foreign extends LeafRenderObjectWidget {
  const _Foreign();

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderForeign();
}

class _RenderForeign extends RenderBox {
  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    context.pushLayer(_ForeignLayer(), (context, offset) {}, offset);
  }
}
