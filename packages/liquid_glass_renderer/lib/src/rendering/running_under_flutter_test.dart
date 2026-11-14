// Whether the code runs under `flutter test`, selected per platform: `dart:io`
// does not exist on the web, which is never a test host.
export 'running_under_flutter_test_io.dart'
    if (dart.library.js_interop) 'running_under_flutter_test_web.dart';
