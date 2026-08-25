import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer_example/basic_app.dart';
import 'package:liquid_glass_renderer_example/preset_store.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

const _useTestBackground = bool.fromEnvironment(
  'LIQUID_GLASS_EXAMPLE_TEST_BACKGROUND',
);

void main() {
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

  testWidgets('settings has one close action and persistent preset controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(home: BasicApp(backgroundOverride: 'grid')),
    );
    await tester.pump();

    await tester.tap(find.text('Settings').last);
    await tester.pump();

    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Save current'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
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
  });
}
