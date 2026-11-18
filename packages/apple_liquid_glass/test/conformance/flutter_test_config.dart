import 'dart:async';

import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

import 'known.dart';

/// Turns leak tracking on for the suite as Flutter's own test config does,
/// and holds the leaks found to the known-failures list.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  LeakTesting.enable();
  LeakTracking.warnForUnsupportedPlatforms = false;
  // Every subject is built through this suite's helpers, so they cannot
  // count as the test helpers whose objects Flutter's config ignores.
  LeakTesting.settings = LeakTesting.settings.withIgnored(
    createdByTestHelpers: true,
    testHelperExceptions: [RegExp('/test/conformance/')],
  );
  LeakTesting.collectedLeaksReporter = reportLeaks;
  await testMain();
}
