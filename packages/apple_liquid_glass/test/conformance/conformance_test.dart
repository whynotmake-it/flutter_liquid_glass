import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

import 'checks.dart';
import 'harness.dart';
import 'known.dart';
import 'registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(MotionClock.debugReset);

  for (final entry in registry) {
    for (final check in checks) {
      if (!check.applies(entry)) continue;
      final key = pairKey(entry.id, check.name);
      testWidgets(key, (tester) async {
        final reason = await _guarded(tester, () => check.run(tester, entry));
        observed[key] = reason;
        judge(entry, check.name, reason);
      }, experimentalLeakTesting: LeakTesting.settings.withIgnoredAll());
    }
    testWidgets(pairKey(leakCheck, entry.id), (tester) async {
      leakSubjects.add(entry.id);
      await _guarded(tester, () => _exercise(tester, entry), semantics: false);
    });
  }
}

Future<void> _exercise(WidgetTester tester, Entry entry) async {
  final probe = await pumpEntry(tester, entry);
  if (entry.presents) {
    await present(tester, entry, probe);
    await close(tester, entry);
  } else {
    await tester.tap(entry.part ?? subject, warnIfMissed: false);
    await settle(tester);
  }
}

Future<String?> _guarded(
  WidgetTester tester,
  Future<void> Function() body, {
  bool semantics = true,
}) async {
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(reasonOf(details.exception));
  final handle = semantics ? tester.ensureSemantics() : null;
  try {
    await body();
  } on Object catch (error) {
    errors.add(reasonOf(error));
  } finally {
    try {
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
    } on Object catch (error) {
      errors.add(reasonOf(error));
    }
    FlutterError.onError = previous;
    handle?.dispose();
  }
  return errors.firstOrNull;
}
