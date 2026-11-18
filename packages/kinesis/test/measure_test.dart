import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis/testing.dart';

class _Painter extends CustomPainter {
  _Painter(this.log);

  final List<String> log;

  @override
  void paint(Canvas canvas, Size size) => log.add('paint');

  @override
  bool shouldRepaint(_Painter oldDelegate) => true;
}

class _Measured extends StatefulWidget {
  const _Measured({required this.log});

  final List<String> log;

  @override
  State<_Measured> createState() => _MeasuredState();
}

class _MeasuredState extends State<_Measured> {
  double width = 10;

  void grow(double to) => setState(() => width = to);

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MotionMeasure(
            onSize: (_, size) => widget.log.add('size ${size.width}'),
            child: SizedBox(width: width, height: 5),
          ),
          CustomPaint(painter: _Painter(widget.log)),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('stamps a size on the clock of the motions around it', (
    tester,
  ) async {
    final clock = ManualMotionClock(start: 5);
    double? at;
    await tester.pumpWidget(
      MotionClockScope(
        clock: clock,
        child: Center(
          child: MotionMeasure(
            onSize: (t, _) => at = t,
            child: const SizedBox(width: 10, height: 5),
          ),
        ),
      ),
    );
    expect(at, 5);
  });

  testWidgets('reports the first size and each change before paint', (
    tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(_Measured(log: log));
    expect(log, ['size 10.0', 'paint']);
    log.clear();
    final state = tester.state<_MeasuredState>(find.byType(_Measured));
    state.grow(10);
    await tester.pump();
    expect(log, ['paint']);
    log.clear();
    state.grow(30);
    await tester.pump();
    expect(log, ['size 30.0', 'paint']);
  });
}
