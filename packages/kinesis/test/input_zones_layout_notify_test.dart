import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

class _Frames extends ChangeNotifier {
  Size size = const Size(40, 28);

  void resize(Size to) {
    size = to;
    notifyListeners();
  }
}

/// A box that resizes its zone from its own layout, as a bar that measures
/// its items there does.
class _MeasuresInLayout extends LeafRenderObjectWidget {
  const _MeasuresInLayout(this.frames, this.to);

  final _Frames frames;
  final Size to;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasuresInLayout(frames, to);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasuresInLayout renderObject,
  ) {
    if (renderObject.to == to) return;
    renderObject.to = to;
    renderObject.markNeedsLayout();
  }
}

class _RenderMeasuresInLayout extends RenderBox {
  _RenderMeasuresInLayout(this.frames, this.to);

  final _Frames frames;
  Size to;

  @override
  void performLayout() {
    size = constraints.constrain(const Size(200, 44));
    if (frames.size != to) frames.resize(to);
  }
}

void main() {
  testWidgets('a zone may change its size from inside the layout of the '
      'content it lies on', (tester) async {
    final frames = _Frames();
    addTearDown(frames.dispose);
    Widget host(Size to) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: InputZones<String>(
          zones: [
            InputZone(
              id: 'a',
              interactions: [PressInteraction(onTap: (_) {})],
              semantics: const SemanticsProperties(
                label: 'Item a',
                button: true,
              ),
            ),
          ],
          frameOf: (_) => InputZoneFrame(Offset.zero & frames.size),
          frames: frames,
          child: _MeasuresInLayout(frames, to),
        ),
      ),
    );

    await tester.pumpWidget(host(const Size(40, 28)));
    await tester.pumpWidget(host(const Size(60, 28)));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.bySemanticsLabel('Item a')), const Size(60, 28));
  });
}
