// The gallery's tour (test/gallery_test.dart) on a device's own engine and
// GPU backend, where `flutter test` on the host runs flutter_tester's.
//
// On Linux the engine draws with Impeller's OpenGL ES backend, the one an
// Android device without a usable Vulkan driver falls back to. It draws
// into one color attachment a pass, gives a texture one filter for all its
// samplers and aborts the process on what it cannot encode, so glass that
// only Metal and Vulkan draw fails here:
//
// flutter create --platforms linux .
// xvfb-run flutter test integration_test/gallery_device_test.dart -d linux
//   --enable-impeller --enable-flutter-gpu
import 'dart:io' show Platform;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/gallery_test.dart' as gallery;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Every final shader variant and every atlas pass draws once, as an app
  // that warms up at startup has them drawn.
  testWidgets('glass warms up on this backend', (tester) async {
    await tester.runAsync(() => precacheGlass(warmUp: true));
    await tester.pump();
    // The tour is worth its time on Linux only on the backend it is there
    // for. Flutter GPU names none: rendering into a mip level is what
    // Impeller's OpenGL ES backend lacks. The engine's own log does not
    // reach the test's output, so neither does a pass it refuses without
    // aborting.
    if (Platform.isLinux) {
      expect(
        gpu.gpuContext.doesSupportFramebufferRenderMipmap,
        isFalse,
        reason: 'the Linux engine should draw with OpenGL ES',
      );
    }
  });

  gallery.galleryTests(onDevice: true);
}
