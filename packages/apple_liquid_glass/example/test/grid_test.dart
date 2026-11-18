import 'dart:async';
import 'dart:convert';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/perf/grid.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('every cell shows, moves, reports and closes its sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final stage = GridStageController();
    final flips = <bool>[];
    final runner = GridRunner(
      stage: stage,
      setGlass: ({required on}) => flips.add(on),
    );
    await tester.pumpWidget(
      GlassScope(
        renderer: const FlatGlassRenderer(),
        child: WidgetsApp(
          color: const Color(0xFF007AFF),
          pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
            settings: settings,
            pageBuilder: (context, _, _) => builder(context),
          ),
          home: GridStage(controller: stage),
        ),
      ),
    );
    for (final cell in gridCells) {
      Map<String, Object?>? result;
      unawaited(
        runner
            .runCell(
              cell,
              windowMs: 400,
              pairs: 1,
              settleMs: 40,
            )
            .then((value) => result = value),
      );
      for (var i = 0; i < 500 && result == null; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(result?['cell'], cell.name);
      expect(jsonDecode(jsonEncode(result)), isA<Map<String, Object?>>());
      expect(flips.last, isFalse);
      expect(
        find.byWidgetPredicate((w) => w is SizedBox && w.height == 420),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
    expect(flips, contains(true));
  });
}
