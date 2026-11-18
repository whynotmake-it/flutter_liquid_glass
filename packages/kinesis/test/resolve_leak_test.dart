import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

class _Host extends SingleChildRenderObjectWidget {
  const _Host();

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHost();
}

class _RenderHost extends RenderProxyBox with MotionResolveHost {
  @override
  void performLayout() {
    super.performLayout();
    scheduleResolve();
  }

  @override
  void resolve() {}
}

// Leaks are collected once every test of the file has run, and a leak
// fails the file then.
void main() {
  LeakTesting.enable();
  LeakTracking.warnForUnsupportedPlatforms = false;

  testWidgets('a view whose last resolve host goes disposes its resolve '
      'phase', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const _Host());
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const _Host());
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });
}
