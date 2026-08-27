import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/basic_app.dart';
import 'package:liquid_glass_renderer_example/preset_store.dart';
import 'package:liquid_glass_renderer_example/shared.dart';

const _useTestBackground = bool.fromEnvironment(
  'LIQUID_GLASS_EXAMPLE_TEST_BACKGROUND',
);

void main() {
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProviderChannel,
          (_) async => Directory.systemTemp.path,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  testWidgets(
    'example uses deterministic imagery only under the test define',
    (tester) async {
      await tester.pumpWidget(const CupertinoApp(home: BasicApp()));
      await tester.pump();

      expect(find.byType(GridPaper), findsWidgets);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(CupertinoSwitch), findsOneWidget);
    },
    skip: !_useTestBackground,
  );

  test('example default glass uses the fitted frosted preset', () {
    expect(exampleDefaultGlassSettings.frost, 7);
  });

  testWidgets('settings has one close action and persistent preset controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(home: BasicApp(backgroundOverride: 'grid')),
    );
    await tester.pump();

    final openButton = find.widgetWithText(CupertinoButton, 'Settings');
    expect(
      find.ancestor(of: openButton, matching: find.byType(SafeArea)),
      findsOneWidget,
    );
    await tester.tap(openButton);
    await tester.pumpAndSettle();

    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Save current'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    for (final background in ['Image', 'Black', 'White', 'Grid']) {
      expect(find.text(background), findsOneWidget);
    }
    for (final control in [
      'Thickness',
      'Glass opacity',
      'Outer shadow',
      'Highlight',
      'Contour strength',
      'Contour width',
      'Transmission gamma',
      'Vibrancy',
      'Frost',
      'Chromatic aberration',
      'Saturation',
      'Peak displacement (px)',
      'Face reach',
    ]) {
      expect(find.text(control), findsOneWidget);
    }
    expect(find.text('REAL'), findsNothing);
    expect(find.text('FAKE'), findsNothing);
    expect(find.text('FULL'), findsNWidgets(7));
    expect(
      find.byTooltip('Available with the full renderer'),
      findsNWidgets(7),
    );
    expect(
      find.ancestor(of: find.text('Done'), matching: find.byType(SafeArea)),
      findsOneWidget,
    );

    await tester.tap(find.text('Matched toolbar'));
    expect(settingsNotifier.value.frost, 7);
  });

  testWidgets('settings uses a trailing split on desktop', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const CupertinoApp(home: BasicApp(backgroundOverride: 'grid')),
    );
    await tester.tap(find.widgetWithText(CupertinoButton, 'Settings'));
    await tester.pumpAndSettle();

    final panel = tester.getRect(
      find.byKey(const ValueKey('settings-sidebar-panel')),
    );
    expect(panel.width, closeTo(360, 0.1));
    expect(panel.right, closeTo(1200, 0.1));
    expect(find.byKey(const ValueKey('settings-bottom-panel')), findsNothing);
  });

  testWidgets('settings uses a bottom split and closes on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const CupertinoApp(home: BasicApp(backgroundOverride: 'grid')),
    );
    await tester.tap(find.widgetWithText(CupertinoButton, 'Settings'));
    await tester.pumpAndSettle();

    final panelFinder = find.byKey(
      const ValueKey('settings-bottom-panel'),
    );
    final panel = tester.getRect(panelFinder);
    expect(panel.height, closeTo(440, 0.1));
    expect(panel.bottom, closeTo(844, 0.1));
    expect(find.byKey(const ValueKey('settings-sidebar-panel')), findsNothing);
    expect(find.byKey(const ValueKey('settings-drag-handle')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('settings-drag-handle')),
        matching: find.byType(ClipRSuperellipse),
      ),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const ValueKey('settings-drag-handle')),
      const Offset(0, 360),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(panelFinder).height, closeTo(0, 0.1));
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('loupe page uses the pre-shader magnifier composition', (
    tester,
  ) async {
    await tester.pumpWidget(const CupertinoApp(home: LoupeExamplePage()));
    await tester.pump();

    expect(find.text('Loupe composition'), findsOneWidget);
    expect(find.byType(RawMagnifier), findsOneWidget);
    final magnifier = tester.widget<RawMagnifier>(find.byType(RawMagnifier));
    expect(magnifier.decoration.opacity, 1);
    expect(magnifier.clipBehavior, Clip.hardEdge);
  });

  test('all example platforms enable Impeller and Flutter GPU', () {
    final android = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final ios = File('ios/Runner/Info.plist').readAsStringSync();
    final macos = File('macos/Runner/Info.plist').readAsStringSync();

    expect(android, contains('io.flutter.embedding.android.EnableImpeller'));
    expect(android, contains('io.flutter.embedding.android.EnableFlutterGPU'));
    for (final plist in [ios, macos]) {
      expect(plist, contains('<key>FLTEnableImpeller</key>'));
      expect(plist, contains('<key>FLTEnableFlutterGPU</key>'));
    }
  });

  test('scalar YAML presets round-trip the unified material vector', () {
    const settings = LiquidGlassSettings.ios27ToolbarLight();
    final restored = PresetStore.fromYaml(PresetStore.toYaml(settings));
    expect(restored.toJson(), settings.toJson());
  });

  test('bundled seed presets are available to the persistent store', () async {
    final toolbar = await rootBundle.loadString(
      'assets/presets/ios27-toolbar-light.yaml',
    );
    final neutral = await rootBundle.loadString(
      'assets/presets/neutral-default.yaml',
    );
    expect(toolbar, contains('edgeRefraction:'));
    expect(neutral, contains('refractionSpread:'));
    expect(toolbar, contains('backdropScale:'));
    expect(
      PresetStore.fromYaml(toolbar).toJson(),
      const LiquidGlassSettings.ios27ToolbarLight().toJson(),
    );
  });
}
