import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/app.dart';
import 'package:liquid_glass_renderer_example/bottom_bar/ios_bottom_bar.dart';
import 'package:liquid_glass_renderer_example/loupe/liquid_glass_loupe.dart';
import 'package:liquid_glass_renderer_example/playground/backdrops.dart';
import 'package:liquid_glass_renderer_example/playground/inspector/grouped_list.dart';
import 'package:liquid_glass_renderer_example/playground/inspector/inspector.dart';
import 'package:liquid_glass_renderer_example/playground/inspector/material_sections.dart';
import 'package:liquid_glass_renderer_example/playground/playground_state.dart';
import 'package:liquid_glass_renderer_example/playground/presets.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/draggable_glass.dart';

void main() {
  group('GlassMaterial', () {
    test('presets follow brightness only where Apple does', () {
      final light = GlassMaterial.preset(
        style: GlassStyle.toolbar,
        brightness: Brightness.light,
      );
      expect(
        light.settings,
        withTestFrost(LiquidGlassSettings.ios27ToolbarLight()),
      );
      expect(
        light.withBrightness(Brightness.dark).settings,
        withTestFrost(LiquidGlassSettings.ios27ToolbarDark()),
      );

      final clear = GlassMaterial.preset(
        style: GlassStyle.clear,
        brightness: Brightness.light,
      );
      expect(
        clear.withBrightness(Brightness.dark).appearance,
        clear.appearance,
      );
    });

    test('the Liquid Glass slider keeps edits and owns the mix', () {
      for (final style in [
        GlassStyle.clear,
        GlassStyle.toolbar,
        GlassStyle.regular,
      ]) {
        final preset = GlassMaterial.preset(
          style: style,
          brightness: Brightness.light,
        );
        final edited = preset.withSettings(
          preset.settings.copyWith(
            frost: 7,
            refractionAmount: 12,
            frostMix: .2,
          ),
        );
        final tinted = edited.withTintAmount(1);

        expect(tinted.edited, isTrue);
        expect(tinted.settings.frost, 7, reason: '$style');
        expect(tinted.settings.refractionAmount, 12, reason: '$style');
        expect(tinted.settings.tintAmount, 1, reason: '$style');
        expect(tinted.settings.frostMix, 1, reason: '$style');

        final cleared = edited.withTintAmount(0);
        expect(cleared.settings.frost, 7, reason: '$style');
        expect(
          cleared.settings.frostMix,
          closeTo(.65, 1e-12),
          reason: '$style',
        );
        expect(
          edited.withTintAmount(.5).settings.frostMix,
          closeTo(.825, 1e-12),
          reason: '$style',
        );
      }
    });

    test('an unedited material follows the preset at every position', () {
      for (final style in [
        GlassStyle.clear,
        GlassStyle.toolbar,
        GlassStyle.regular,
      ]) {
        final preset = GlassMaterial.preset(
          style: style,
          brightness: Brightness.light,
        );
        for (final (position, mix) in [
          (0.0, .65),
          (.5, .825),
          (1.0, 1.0),
        ]) {
          final moved = preset.withTintAmount(position);
          expect(
            moved.settings.frost,
            withTestFrost(const LiquidGlassSettings()).frost,
            reason: '$style $position',
          );
          expect(
            moved.settings.frostMix,
            closeTo(mix, 1e-12),
            reason: '$style $position',
          );
        }
      }
    });

    test('the loupe ignores the Liquid Glass slider', () {
      final loupe = GlassMaterial.preset(
        style: GlassStyle.loupe,
        brightness: Brightness.light,
      );
      expect(GlassStyle.loupe.followsSlider, isFalse);
      expect(loupe.withTintAmount(1).settings, loupe.settings);
      final edited = loupe.withSettings(
        loupe.settings.copyWith(refractionAmount: 20),
      );
      expect(edited.withTintAmount(1).settings, edited.settings);
    });

    test('reset restores the preset at the current slider position', () {
      final material = GlassMaterial.preset(
        style: GlassStyle.toolbar,
        brightness: Brightness.dark,
      ).withTintAmount(0.5).withSettings(const LiquidGlassSettings());

      final reset = material.reset();

      expect(reset.edited, isFalse);
      expect(
        reset.settings,
        withTestFrost(
          LiquidGlassSettings.ios27Toolbar(
            brightness: Brightness.dark,
            tintAmount: 0.5,
          ),
        ),
      );
    });
  });

  test('settingsSource lists only fields that differ from the defaults', () {
    expect(
      settingsSource(const LiquidGlassSettings()),
      'const LiquidGlassSettings()',
    );
    expect(
      settingsSource(loupeSettings),
      allOf(
        startsWith('const LiquidGlassSettings(\n'),
        contains('  refractionHeight: 8.0,\n'),
        contains('  refractionAmount: 34.5,\n'),
        contains('  dispersion: -0.06,\n'),
      ),
    );
  });

  test('the dispersion track is fine near zero and reaches ±2', () {
    expect(trackToDispersion(0.02), 0);
    expect(trackToDispersion(1), maxDispersion);
    expect(trackToDispersion(-1), -maxDispersion);
    expect(trackToDispersion(1 / 3).abs(), lessThan(0.08));
    for (final dispersion in [-1.5, -0.07, 0.0, 0.3, 2.0]) {
      expect(
        trackToDispersion(dispersionToTrack(dispersion)),
        closeTo(dispersion, 1e-9),
      );
    }
  });

  testWidgets('the lighting section edits the inner shadow', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final material = ValueNotifier(
      GlassMaterial.preset(
        style: GlassStyle.regular,
        brightness: Brightness.light,
      ),
    );
    addTearDown(material.dispose);
    await tester.pumpWidget(
      CupertinoApp(
        home: SingleChildScrollView(
          child: MaterialSections(material: material),
        ),
      ),
    );

    expect(find.text('Inner Shadow'), findsOneWidget);
    final slider = find.descendant(
      of: find.ancestor(
        of: find.text('Inner Shadow'),
        matching: find.byType(SliderRow),
      ),
      matching: find.byType(CupertinoSlider),
    );
    tester.widget<CupertinoSlider>(slider).onChanged!(0.5);
    await tester.pump();
    expect(material.value.settings.bevelShadowStrength, 0.5);
    expect(material.value.edited, isTrue);
  });

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
  }

  testWidgets('the settings sheet opens on demand and closes again', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PlaygroundApp());
    await tester.pump();

    expect(find.byType(Inspector), findsNothing);
    expect(find.byType(LiquidGlassLayer), findsOneWidget);

    await openSettings(tester);
    expect(find.byType(Inspector), findsOneWidget);
    expect(find.byType(LiquidGlassLayer), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(Inspector), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling the settings past their top drags the sheet away', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PlaygroundApp());
    await tester.pump();
    await openSettings(tester);
    final list = find.byType(Inspector);
    double scrollOffset() => tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .position
        .pixels;

    await tester.drag(list, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(scrollOffset(), greaterThan(0));

    // Pump at display frame rate. With pumpAndSettle's default 100 ms steps
    // the sheet springs back open instead of dismissing.
    const frame = Duration(milliseconds: 16);
    await tester.fling(list, const Offset(0, 600), 2000);
    await tester.pumpAndSettle(frame);
    expect(scrollOffset(), 0);
    expect(list, findsOneWidget, reason: 'the gesture began mid-scroll');

    await tester.fling(list, const Offset(0, 600), 2000);
    await tester.pumpAndSettle(frame);
    expect(list, findsNothing);
  });

  group('the settings sheet displaces the stage content', () {
    const frame = Duration(milliseconds: 16);

    Rect rectOf(WidgetTester tester, Finder finder) =>
        tester.getRect(finder.first);

    testWidgets('above the half-height phone sheet', (tester) async {
      const window = Size(390, 844);
      tester.view
        ..physicalSize = window
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const PlaygroundApp());
      await tester.pump();
      final bar = find.byType(IosBottomBar);
      final settings = find.bySemanticsLabel('Settings');
      final closedBar = rectOf(tester, bar);
      final closedSettings = rectOf(tester, settings);
      final backdrop = rectOf(tester, find.byType(BackdropPager));
      expect(backdrop, Offset.zero & window);
      expect(closedBar.bottom, window.height - 20);

      await tester.tap(settings);
      final sheet = find.byType(Inspector);
      var tracked = 0;
      for (var i = 0; i < 60; i++) {
        await tester.pump(frame);
        final top = rectOf(tester, sheet).top;
        if (top >= window.height) continue;
        expect(
          rectOf(tester, bar).bottom,
          moreOrLessEquals(top - 20),
          reason: 'the bar rides 20 pt above the moving sheet',
        );
        tracked++;
      }
      expect(tracked, greaterThan(5));
      await tester.pumpAndSettle();

      final open = rectOf(tester, sheet);
      expect(open.top, window.height / 2);
      expect(rectOf(tester, bar).bottom, window.height / 2 - 20);
      expect(rectOf(tester, bar).size, closedBar.size);
      expect(rectOf(tester, settings), closedSettings);
      expect(rectOf(tester, find.byType(BackdropPager)), backdrop);

      await tester.drag(sheet, const Offset(0, -300));
      await tester.pumpAndSettle(frame);
      expect(
        rectOf(tester, sheet).top,
        window.height / 2,
        reason: 'the sheet never rises above half height',
      );

      await tester.tap(settings);
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(rectOf(tester, bar), closedBar);
      expect(tester.takeException(), isNull);
    });

    testWidgets('beside the wide side sheet', (tester) async {
      const window = Size(1280, 800);
      tester.view
        ..physicalSize = window
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const PlaygroundApp());
      await tester.pump();
      final settings = find.bySemanticsLabel('Settings');
      final closedSettings = rectOf(tester, settings);
      await openSettings(tester);
      await tester.tap(find.text('Blend'));
      await tester.pump();
      await tester.tap(settings);
      await tester.pumpAndSettle();

      final shape = find.byType(DraggableGlass);
      final closedShape = rectOf(tester, shape);
      final backdrop = rectOf(tester, find.byType(BackdropPager));
      expect(backdrop, Offset.zero & window);

      await tester.tap(settings);
      final sheet = find.byType(Inspector);
      var tracked = 0;
      for (var i = 0; i < 60; i++) {
        await tester.pump(frame);
        final shift = closedShape.left - rectOf(tester, shape).left;
        if (shift > 1 && shift < 197) tracked++;
      }
      expect(tracked, greaterThan(5), reason: 'the shift follows the sheet');
      await tester.pumpAndSettle();

      final open = rectOf(tester, sheet);
      final openShape = rectOf(tester, shape);
      expect(
        openShape,
        closedShape.shift(Offset(-(window.width - open.left) / 2, 0)),
      );
      expect(openShape.right, lessThan(open.left));
      expect(rectOf(tester, settings), closedSettings);
      expect(rectOf(tester, find.byType(BackdropPager)), backdrop);

      await tester.drag(shape.first, const Offset(20, 0));
      await tester.pump();
      expect(
        rectOf(tester, shape),
        openShape.shift(const Offset(20, 0)),
        reason: 'the displaced stage stays interactive',
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the playground renders one stage layer and switches scenes', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PlaygroundApp());
    await tester.pump();
    await openSettings(tester);

    expect(find.text('Liquid Glass'), findsWidgets);
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    expect(find.text('Refraction'), findsWidgets);

    await tester.tap(find.text('Blend'));
    await tester.pump();
    expect(find.byType(LiquidGlassBlendGroup), findsOneWidget);
    expect(find.text('Blend'), findsNWidgets(2), reason: 'Blend slider');

    await tester.tap(find.text('Colors'));
    await tester.pump();
    expect(find.text('Clear'), findsWidgets);
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the loupe scene shows package loupes over the backdrop', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PlaygroundApp());
    await tester.pump();
    await openSettings(tester);
    await tester.tap(find.text('Loupe').first);
    await tester.pump();

    final loupes = tester.widgetList<LiquidGlassLoupe>(
      find.byType(LiquidGlassLoupe),
    );
    expect(loupes, hasLength(2));
    expect(loupes.map((loupe) => loupe.magnification), everyElement(1.25));
    expect(find.byType(LiquidGlassLoupeSource), findsOneWidget);
    expect(find.text('Magnification'), findsOneWidget);

    await tester.drag(find.byType(LiquidGlassLoupe).first, const Offset(40, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
