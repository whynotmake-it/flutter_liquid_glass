import 'package:flutter_gpu/gpu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const expectFallback = bool.fromEnvironment('EXPECT_FLUTTER_GPU_FALLBACK');
  test(
    'flutter_gpu context is available',
    () {
      expect(gpuContext, isNotNull);
      expect(
        gpuContext.defaultColorFormat,
        isNot(equals(PixelFormat.unknown)),
      );
    },
    skip: expectFallback,
  );
}
