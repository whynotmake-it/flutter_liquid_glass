import 'package:apple_liquid_glass_accessibility/apple_liquid_glass_accessibility.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the platform reports its settings', (tester) async {
    final features = await AppleAccessibilityFeatures.watch().first;
    expect(
      features.prefersCrossFade,
      defaultTargetPlatform == TargetPlatform.iOS ? isNotNull : isNull,
    );
  });
}
