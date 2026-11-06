import 'dart:io' show Platform;

/// Whether the code runs under `flutter test`, which sets `FLUTTER_TEST` to
/// `true` for the test process.
bool get runningUnderFlutterTest {
  try {
    return Platform.environment['FLUTTER_TEST'] == 'true';
  } on Object {
    // An embedder that hides the environment is not a test host.
    return false;
  }
}
