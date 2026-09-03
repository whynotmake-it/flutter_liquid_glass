import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/app.dart';
import 'package:liquid_glass_renderer_example/preset_store.dart';
import 'package:liquid_glass_renderer_example/state.dart';
import 'package:liquid_glass_renderer_example/widgets/bottom_bar.dart';

void main() {
  setUp(() {
    settingsNotifier.value = exampleDefaultGlassSettingsForBrightness(
      Brightness.light,
    );
    appearanceNotifier.value = exampleDefaultAppearanceFor(Brightness.light);
    fakeNotifier.value = false;
    backgroundNotifier.value = 'grid';
  });

  testWidgets('workbench renders the showcase and shared glass layer', (
    tester,
  ) async {
    await tester.pumpWidget(const CupertinoApp(home: GlassWorkbench()));
    await tester.pump();

    expect(find.text('Liquid Glass'), findsOneWidget);
    expect(find.text('One glass layer. Every widget.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('glass-layer-0-0')),
      findsOneWidget,
    );
    expect(find.byType(LiquidGlassBottomBar), findsOneWidget);
    expect(find.byType(GridPaper), findsOneWidget);
  });

  testWidgets('bottom bar switches pages without losing the shared layer', (
    tester,
  ) async {
    await tester.pumpWidget(const CupertinoApp(home: GlassWorkbench()));
    await tester.pump();

    await tester.tap(find.text('Playground'));
    await tester.pumpAndSettle();
    expect(find.text('Playground'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('glass-layer-0-1')), findsOneWidget);

    await tester.tap(find.text('Showcase').last);
    await tester.pumpAndSettle();
    expect(find.text('One glass layer. Every widget.'), findsOneWidget);
  });

  testWidgets('scrolling nested controls does not emit retained-layer errors', (
    tester,
  ) async {
    await tester.pumpWidget(const CupertinoApp(home: GlassWorkbench()));
    await tester.pump();

    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('workbench follows platform dark appearance', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(const CupertinoApp(home: GlassWorkbench()));
    await tester.pump();

    expect(
      settingsNotifier.value,
      const LiquidGlassSettings.ios27ToolbarDark(),
    );
    expect(find.byKey(const ValueKey('glass-layer-0-0')), findsOneWidget);
  });

  test('bundled presets round-trip and include fitted fields', () {
    const settings = LiquidGlassSettings.ios27ToolbarLight();
    const appearance = LiquidGlassAppearance.ios27ToolbarLight();
    final restored = PresetStore.fromYaml(
      PresetStore.toYaml((settings: settings, appearance: appearance)),
    );
    expect(restored.settings.toJson(), settings.toJson());
    expect(restored.appearance.toJson(), appearance.toJson());

    final toolbar = File('assets/presets/ios27-toolbar-light.yaml')
        .readAsStringSync();
    expect(toolbar, contains('backdropScale:'));
  });
}
