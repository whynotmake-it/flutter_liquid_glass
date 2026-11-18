import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/running_under_flutter_test.dart';

void main() {
  test('flutter test is recognized', () {
    expect(runningUnderFlutterTest, isTrue);
  });
}
