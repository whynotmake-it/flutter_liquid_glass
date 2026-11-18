import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

/// A label whose node tells when it is described: only describing a node
/// reads whether it is checked.
class _Counted extends SemanticsProperties {
  const _Counted(String label, this.described) : super(label: label);

  final VoidCallback described;

  @override
  bool? get checked {
    described();
    return null;
  }
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a moving frame describes the zones that are shown, not the '
      'ones that are absent, and describes a zone again as it appears', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    List<String> labels() {
      final found = <String>[];
      bool visit(SemanticsNode node) {
        found.add(node.label);
        node.visitChildren(visit);
        return true;
      }

      final owner = tester.renderObject(find.byType(SizedBox)).owner!;
      visit(owner.semanticsOwner!.rootSemanticsNode!);
      return found;
    }

    final frames = ValueNotifier<double>(0);
    addTearDown(frames.dispose);
    var shown = false;
    final described = <String, int>{'a': 0, 'b': 0};
    InputZone<String> zone(String id) => InputZone(
      id: id,
      interactions: [PressInteraction()],
      semantics: _Counted(id, () => described[id] = described[id]! + 1),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: InputZones<String>(
            zones: [zone('a'), zone('b')],
            frameOf: (id) => switch (id) {
              'a' => InputZoneFrame(Rect.fromLTWH(frames.value, 0, 40, 40)),
              _ when shown => const InputZoneFrame(
                Rect.fromLTWH(100, 0, 40, 40),
              ),
              _ => null,
            },
            frames: frames,
            child: const SizedBox(width: 200, height: 40),
          ),
        ),
      ),
    );
    await tester.pump();
    described.updateAll((id, count) => 0);
    for (var i = 1; i <= 5; i++) {
      frames.value = i.toDouble();
      await tester.pump();
    }
    expect(described['a'], greaterThan(0));
    expect(described['b'], 0, reason: 'an absent zone is not described');

    shown = true;
    frames.value = 6;
    await tester.pump();
    expect(described['b'], greaterThan(0));
    expect(labels(), contains('b'));

    shown = false;
    frames.value = 7;
    await tester.pump();
    expect(labels(), isNot(contains('b')));
    handle.dispose();
  });
}
