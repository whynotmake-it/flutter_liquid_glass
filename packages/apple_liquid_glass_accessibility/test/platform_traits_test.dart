import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_accessibility/apple_liquid_glass_accessibility.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = EventChannel('apple_liquid_glass_accessibility');

final _ios = TargetPlatformVariant.only(TargetPlatform.iOS);

Map<String, Object?> _report({
  bool reduceTransparency = false,
  bool showBorders = false,
  bool? prefersCrossFade = false,
  double? glassTintAmount,
  bool? prefersReducedResourceUsage = false,
}) => {
  'reduceTransparency': reduceTransparency,
  'showBorders': showBorders,
  'prefersCrossFade': prefersCrossFade,
  'glassTintAmount': glassTintAmount,
  'prefersReducedResourceUsage': prefersReducedResourceUsage,
};

/// The platform side of the channel. It is set up inside a test body: a
/// handler made in `setUp` sends its events outside the test's fake async
/// zone, and they never arrive.
class _Platform {
  _Platform(Map<String, Object?> report) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          _channel,
          MockStreamHandler.inline(
            onListen: (arguments, events) {
              listens++;
              sink = events;
              events.success(report);
            },
            onCancel: (arguments) {
              cancels++;
              sink = null;
            },
          ),
        );
  }

  MockStreamHandlerEventSink? sink;
  int listens = 0;
  int cancels = 0;
}

late GlassTraits _seen;

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  Widget build(BuildContext context) {
    _seen = GlassTraits.of(context);
    return const SizedBox();
  }
}

Widget _app(Widget child, {bool reduceMotion = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: reduceMotion),
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

void main() {
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(_channel, null),
  );

  testWidgets(
    'feeds the reported settings into the traits',
    (tester) async {
      final platform = _Platform(
        _report(
          reduceTransparency: true,
          showBorders: true,
          glassTintAmount: 0.35,
          prefersReducedResourceUsage: true,
        ),
      );
      await tester.pumpWidget(
        _app(const GlassPlatformTraits(child: _Probe()), reduceMotion: true),
      );
      await tester.pumpAndSettle();
      expect(_seen.reduceTransparency, isTrue);
      expect(_seen.showBorders, isTrue);
      expect(_seen.prefersCrossFade, isFalse);
      expect(_seen.glassTintAmount, 0.35);
      expect(_seen.prefersReducedResourceUsage, isTrue);

      platform.sink!.success(_report(prefersCrossFade: true));
      await tester.pumpAndSettle();
      expect(_seen.reduceTransparency, isFalse);
      expect(_seen.showBorders, isFalse);
      expect(_seen.prefersCrossFade, isTrue);
      expect(_seen.glassTintAmount, 0);
      expect(_seen.prefersReducedResourceUsage, isFalse);
    },
    variant: _ios,
  );

  testWidgets(
    'an unreported cross-fade follows Reduce Motion',
    (tester) async {
      _Platform(_report(prefersCrossFade: null));
      await tester.pumpWidget(
        _app(const GlassPlatformTraits(child: _Probe()), reduceMotion: true),
      );
      await tester.pumpAndSettle();
      expect(_seen.prefersCrossFade, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'the first report keeps the subtree',
    (tester) async {
      _Platform(_report(showBorders: true));
      await tester.pumpWidget(_app(const GlassPlatformTraits(child: _Probe())));
      final before = tester.state(find.byType(_Probe));
      await tester.pumpAndSettle();
      expect(_seen.showBorders, isTrue);
      expect(tester.state(find.byType(_Probe)), same(before));
    },
    variant: _ios,
  );

  testWidgets(
    'every instance shares one subscription to the platform',
    (tester) async {
      final platform = _Platform(_report(reduceTransparency: true));
      await tester.pumpWidget(
        _app(
          const Column(
            children: [
              GlassPlatformTraits(child: SizedBox()),
              GlassPlatformTraits(child: _Probe()),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(platform.listens, 1);
      expect(_seen.reduceTransparency, isTrue);

      await tester.pumpWidget(
        _app(const Column(children: [GlassPlatformTraits(child: _Probe())])),
      );
      await tester.pumpAndSettle();
      expect(platform.cancels, 0);
      platform.sink!.success(_report(showBorders: true));
      await tester.pumpAndSettle();
      expect(_seen.showBorders, isTrue);

      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pumpAndSettle();
      expect(platform.cancels, 1);
    },
    variant: _ios,
  );

  testWidgets('reports nothing on other platforms', (tester) async {
    final platform = _Platform(_report());
    await tester.pumpWidget(
      _app(
        const GlassTraitsOverride(
          reduceTransparency: true,
          child: GlassPlatformTraits(child: _Probe()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(platform.listens, 0);
    expect(_seen.reduceTransparency, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
