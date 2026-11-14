/// Widget-test helpers for glass: `expectGlassBudget` holds a screen to the
/// glass work it was reviewed at (copies of the screen read, live reads,
/// targets, filters, pictures and images a frame took).
///
/// For tests of apps and widget libraries that draw with
/// `liquid_glass_renderer`. It is a dev dependency: it imports
/// `flutter_test`, which an app does not ship, and reads the frame through
/// the renderer's public `GlassFrameReport` only.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/composer.dart';

/// Pumps a frame and checks what its glass took against matchers (an int or
/// a [Matcher]); what is left out is not checked.
///
/// Fails the test when the frame drew no glass. Returns the frame's report.
///
/// ```dart
/// await expectGlassBudget(tester, reads: lessThanOrEqualTo(4), liveReads: 0);
/// ```
Future<GlassFrameReport> expectGlassBudget(
  WidgetTester tester, {
  Object? reads,
  Object? liveReads,
  Object? issuedTargets,
  Object? filtersBuilt,
  Object? picturesRecorded,
  Object? imagesDrawn,
}) async {
  GlassFrameReport? seen;
  void note(GlassFrameReport report) => seen = report;
  GlassFrameReport.addListener(note);
  try {
    // A test only draws a frame something asked for.
    tester.binding.scheduleFrame();
    await tester.pump();
  } finally {
    GlassFrameReport.removeListener(note);
  }
  final report = seen;
  if (report == null) fail('The frame had no glass.');
  void check(int actual, Object? matcher, String what) {
    if (matcher != null) expect(actual, matcher, reason: '$what in\n$report');
  }

  check(report.reads.length, reads, 'reads');
  check(report.liveReads, liveReads, 'live reads');
  check(report.issuedTargets, issuedTargets, 'targets');
  check(report.filtersBuilt, filtersBuilt, 'filters');
  check(report.picturesRecorded, picturesRecorded, 'pictures');
  check(report.imagesDrawn, imagesDrawn, 'images');
  return report;
}
