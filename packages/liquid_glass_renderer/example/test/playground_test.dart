import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/app.dart';
import 'package:liquid_glass_renderer_example/playground/inspector/inspector.dart';
import 'package:liquid_glass_renderer_example/playground/playground_state.dart';
import 'package:liquid_glass_renderer_example/playground/presets.dart';

void main() {
  group('GlassMaterial', () {
    test('presets follow brightness only where Apple does', () {
      final light = GlassMaterial.preset(
        style: GlassStyle.toolbar,
        brightness: Brightness.light,
      );
      expect(
        light.settings,
        withTestFrost(const LiquidGlassSettings.ios27ToolbarLight()),
      );
      expect(
        light.withBrightness(Brightness.dark).settings,
        withTestFrost(const LiquidGlassSettings.ios27ToolbarDark()),
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

    test('the Liquid Glass slider keeps edits and owns clear glass blur', () {
      final edited =
          GlassMaterial.preset(
            style: GlassStyle.clear,
            brightness: Brightness.light,
          ).withSettings(
            LiquidGlassSettings.ios27Clear().copyWith(refractionAmount: 12),
          );

      final tinted = edited.withTintAmount(1);

      expect(tinted.edited, isTrue);
      expect(tinted.settings.refractionAmount, 12);
      expect(tinted.settings.tintAmount, 1);
      expect(
        tinted.settings.frost,
        withTestFrost(
          LiquidGlassSettings(frost: LiquidGlassSettings.ios27ClearFrost(1)),
        ).frost,
      );
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
        contains('  refractionAmount: 28.0,\n'),
        isNot(contains('smoothRefraction')),
      ),
    );
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
