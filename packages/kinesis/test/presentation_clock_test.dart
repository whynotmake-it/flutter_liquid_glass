import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis/testing.dart';

final class _Card extends Motion with Presented {
  _Card({super.clock});

  late final Presence _show = own(Presence(openSpring: Spring.snappy));
  double? opened;
  double? left;

  @override
  PresenceStatus get presence => _show.status;

  @override
  void open(double t) {
    opened = t;
    _show.open(t);
  }

  @override
  bool leave(double t, DismissTrigger trigger) {
    left = t;
    _show.hide(t);
    return true;
  }
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a portal under a clock scope commits, opens and leaves on '
      'that clock', (tester) async {
    final clock = ManualMotionClock(start: 5);
    final controller = PresentationPortalController();
    final cards = <_Card>[];
    final environments = <PresentationEnvironment>[];
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, _) => builder(context),
        ),
        home: MotionClockScope(
          clock: clock,
          child: PresentationPortal(
            controller: controller,
            presentation: Presentation<void, _Card>(
              motion: (environment) {
                environments.add(environment);
                final card = _Card(clock: environment.clock);
                cards.add(card);
                return card;
              },
              builder: (context, motion) => const SizedBox.expand(),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    controller.present();
    await tester.pump();
    expect(environments.single.clock, same(clock));
    expect(environments.single.time, 5);
    expect(cards.single.opened, 5);

    clock.advanceTo(6);
    controller.dismiss(DismissTrigger.programmatic);
    expect(cards.single.left, 6);
    clock.advanceTo(8);
    await tester.pump();
    expect(controller.isPresented, isFalse);
  });
}
