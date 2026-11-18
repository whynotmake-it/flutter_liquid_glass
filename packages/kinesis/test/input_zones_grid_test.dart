import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

/// Cells of 40 points: a full first row (a, b, c) and a second row that
/// starts under b (e, f), as a month that starts midweek.
const Map<String, Rect> _cells = {
  'a': Rect.fromLTWH(0, 0, 40, 40),
  'b': Rect.fromLTWH(40, 0, 40, 40),
  'c': Rect.fromLTWH(80, 0, 40, 40),
  'e': Rect.fromLTWH(40, 40, 40, 40),
  'f': Rect.fromLTWH(80, 40, 40, 40),
};

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('in a grid an arrow stays in its row or column and asks the '
      'host where no cell lies', (tester) async {
    final zones = InputZonesController<String>();
    final frames = ValueNotifier(0);
    addTearDown(zones.dispose);
    addTearDown(frames.dispose);
    final edges = <(String, TraversalDirection)>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: InputZones<String>(
            zones: [
              for (final id in _cells.keys)
                InputZone(id: id, interactions: [PressInteraction()]),
            ],
            frameOf: (id) => InputZoneFrame(_cells[id]!),
            frames: frames,
            controller: zones,
            axis: null,
            onEdge: (zone, direction) {
              edges.add((zone, direction));
              return true;
            },
            child: const SizedBox(width: 120, height: 80),
          ),
        ),
      ),
    );
    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }

    zones.requestFocus('e');
    await tester.pump();
    await press(LogicalKeyboardKey.arrowLeft);
    expect(zones.focusedZone, 'e', reason: 'a is in the row above');
    expect(edges, [('e', TraversalDirection.left)]);

    await press(LogicalKeyboardKey.arrowUp);
    expect(zones.focusedZone, 'b');
    await press(LogicalKeyboardKey.arrowLeft);
    expect(zones.focusedZone, 'a');
    await press(LogicalKeyboardKey.arrowDown);
    expect(zones.focusedZone, 'a', reason: 'e is in the next column');
    expect(edges.last, ('a', TraversalDirection.down));

    await press(LogicalKeyboardKey.arrowRight);
    await press(LogicalKeyboardKey.arrowRight);
    expect(zones.focusedZone, 'c');
    await press(LogicalKeyboardKey.arrowDown);
    expect(zones.focusedZone, 'f');
    await press(LogicalKeyboardKey.arrowLeft);
    expect(zones.focusedZone, 'e');
    expect(edges, hasLength(2));
  });
}
