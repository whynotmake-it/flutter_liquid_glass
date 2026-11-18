import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

const _frame = Duration(milliseconds: 16);

Widget _app(
  GlassRenderer renderer,
  Widget child, {
  bool disableAnimations = false,
}) => MediaQuery(
  data: MediaQueryData(disableAnimations: disableAnimations),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(
      renderer: renderer,
      child: Center(child: child),
    ),
  ),
);

final class _CountingRenderer extends GlassRenderer {
  const _CountingRenderer(this.inner, this.onSurface);

  final GlassRenderer inner;
  final VoidCallback onSurface;

  @override
  Widget buildSurface(BuildContext context, GlassSurfaceDetails details) {
    onSurface();
    return inner.buildSurface(context, details);
  }
}

class _Label extends StatefulWidget {
  const _Label(this.builds);

  final List<int> builds;

  @override
  State<_Label> createState() => _LabelState();
}

class _LabelState extends State<_Label> {
  late final int id = widget.builds.length;

  @override
  Widget build(BuildContext context) {
    widget.builds.add(id);
    return const SizedBox(width: 120, height: 44);
  }
}

class _Probe {
  int builds = 0;
  ValueListenable<GlassFrame>? body;
  Set<WidgetState> states = {};

  Widget build(BuildContext context, GlassButtonDetails details) {
    builds++;
    body = details.body;
    states = details.states;
    return GlassSurface.live(frame: details.body, child: details.label);
  }
}

Widget _keyApp(Widget child, {Map<ShortcutActivator, Intent>? shortcuts}) =>
    WidgetsApp(
      color: const Color(0xFF000000),
      shortcuts: shortcuts,
      builder: (context, _) => Center(child: child),
    );

void main() {
  setUp(MotionClock.debugReset);

  for (final (name, renderer) in [
    ('flat', const FlatGlassRenderer()),
    ('liquid', const LiquidGlassRenderer()),
  ]) {
    testWidgets('$name: a press builds on its state changes only while the '
        'body lifts and returns', (tester) async {
      var surfaces = 0;
      final counting = _CountingRenderer(renderer, () => surfaces++);
      final probe = _Probe();
      final labels = <int>[];
      var presses = 0;
      await tester.pumpWidget(
        _app(
          counting,
          RawGlassButton(
            onPressed: () => presses++,
            builder: probe.build,
            child: _Label(labels),
          ),
        ),
      );
      expect(probe.builds, 1);
      expect(probe.body!.value, const GlassFrame());

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(RawGlassButton)),
      );
      await tester.pump(_frame);
      expect(probe.states, contains(WidgetState.pressed));
      final pressed = probe.builds;
      expect(pressed, 2);
      final scales = <double>[];
      for (var i = 0; i < 12; i++) {
        await tester.pump(_frame);
        scales.add(probe.body!.value.scaleX);
      }
      expect(scales.last, greaterThan(1.01));
      expect(probe.body!.value.glow, isNotNull);
      expect(probe.builds, pressed);

      await gesture.up();
      await tester.pump(_frame);
      expect(presses, 1);
      expect(probe.builds, pressed + 1);
      for (var i = 0; i < 90; i++) {
        await tester.pump(_frame);
      }
      expect(probe.body!.value, const GlassFrame());
      expect(probe.builds, pressed + 1);
      expect(surfaces, probe.builds);

      // Under Impeller the liquid layer swaps its fake glass for full glass
      // once its shaders load, which moves the label; count label builds
      // only from there.
      final settled = labels.length;
      final again = await tester.startGesture(
        tester.getCenter(find.byType(RawGlassButton)),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(_frame);
      }
      await again.up();
      await tester.pumpAndSettle();
      expect(presses, 2);
      expect(probe.builds, pressed + 3);
      expect(labels.length, settled);
      expect(labels.toSet(), {0});
    });
  }

  testWidgets('a renderer switch mid-press keeps the press, its motion and '
      'its label', (tester) async {
    final probe = _Probe();
    final labels = <int>[];
    var presses = 0;
    final rawButton = RawGlassButton(
      onPressed: () => presses++,
      builder: probe.build,
      child: _Label(labels),
    );
    Widget button(GlassRenderer renderer) => _app(renderer, rawButton);
    await tester.pumpWidget(button(const FlatGlassRenderer()));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(RawGlassButton)),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(_frame);
    }
    final builds = probe.builds;
    final before = probe.body!.value.scaleX;
    expect(before, greaterThan(1));

    await tester.pumpWidget(button(const LiquidGlassRenderer()));
    expect(probe.builds, builds);
    expect(find.byType(LiquidGlass), findsOneWidget);
    await tester.pump(_frame);
    expect(probe.body!.value.scaleX, greaterThanOrEqualTo(before));
    expect(
      tester.widget<LiquidGlass>(find.byType(LiquidGlass)).frame!.value.glow,
      isNotNull,
    );

    await gesture.up();
    await tester.pump(_frame);
    expect(presses, 1);
    expect(labels.toSet(), {0});
    await tester.pumpAndSettle();
  });

  testWidgets('a release beyond the slop does not press', (tester) async {
    var presses = 0;
    await tester.pumpWidget(
      _app(
        const FlatGlassRenderer(),
        RawGlassButton(
          onPressed: () => presses++,
          builder: _Probe().build,
          child: const SizedBox(width: 100, height: 44),
        ),
      ),
    );
    final center = tester.getCenter(find.byType(RawGlassButton));
    final gesture = await tester.startGesture(center);
    await tester.pump(_frame);
    await gesture.moveTo(center + const Offset(0, 50));
    await tester.pump(_frame);
    await gesture.up();
    await tester.pump(_frame);
    expect(presses, 1);

    final far = await tester.startGesture(center);
    await tester.pump(_frame);
    await far.moveTo(center + const Offset(0, 22 + 71));
    await tester.pump(_frame);
    await far.up();
    await tester.pump(_frame);
    expect(presses, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('in a scroll view the body lifts at once, and a scroll that '
      'takes the touch drops it without a press', (tester) async {
    final probe = _Probe();
    var presses = 0;
    await tester.pumpWidget(
      _app(
        const FlatGlassRenderer(),
        SizedBox(
          height: 400,
          child: ListView(
            children: [
              const SizedBox(height: 100),
              Center(
                child: RawGlassButton(
                  onPressed: () => presses++,
                  builder: probe.build,
                  child: const SizedBox(width: 100, height: 44),
                ),
              ),
              const SizedBox(height: 600),
            ],
          ),
        ),
      ),
    );
    final center = tester.getCenter(find.byType(RawGlassButton));
    final tap = await tester.startGesture(center);
    for (var i = 0; i < 5; i++) {
      await tester.pump(_frame);
    }
    expect(probe.body!.value.scaleX, greaterThan(1.01));
    await tap.up();
    await tester.pumpAndSettle();
    expect(presses, 1);

    final swipe = await tester.startGesture(center);
    for (var i = 0; i < 5; i++) {
      await tester.pump(_frame);
    }
    expect(probe.body!.value.scaleX, greaterThan(1.01));
    for (var i = 1; i <= 6; i++) {
      await swipe.moveTo(center - Offset(0, 12.0 * i));
      await tester.pump(_frame);
    }
    await swipe.up();
    await tester.pumpAndSettle();
    expect(presses, 1);
    expect(probe.body!.value, const GlassFrame());
  });

  testWidgets('under a WidgetsApp Space and Enter press it, and an app '
      'that rebinds the keys presses it with its own', (tester) async {
    var presses = 0;
    Widget button() => RawGlassButton(
      onPressed: () => presses++,
      builder: _Probe().build,
      autofocus: true,
      child: const SizedBox(width: 100, height: 44),
    );
    await tester.pumpWidget(_keyApp(button()));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(presses, 2);

    presses = 0;
    await tester.pumpWidget(
      _keyApp(
        button(),
        shortcuts: {
          ...WidgetsApp.defaultShortcuts,
          const SingleActivator(LogicalKeyboardKey.space):
              const DoNothingAndStopPropagationIntent(),
          const SingleActivator(LogicalKeyboardKey.keyP):
              const ActivateIntent(),
        },
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(presses, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    expect(presses, 1);
  });

  testWidgets('it reads as one button over its 44 point target, below the '
      'region, and the accessibility tap presses it', (tester) async {
    final semantics = tester.ensureSemantics();
    var presses = 0;
    await tester.pumpWidget(
      _app(
        const FlatGlassRenderer(),
        RawGlassButton(
          onPressed: () => presses++,
          builder: _Probe().build,
          semanticLabel: 'Done',
          child: const SizedBox(width: 100, height: 30),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Done')),
      matchesSemantics(
        label: 'Done',
        rect: const Rect.fromLTWH(0, -7, 100, 44),
        textDirection: TextDirection.ltr,
        isButton: true,
        hasTapAction: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
      ),
    );
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    tester.semantics.tap(find.semantics.byLabel('Done'));
    expect(presses, 1);

    await tester.pumpWidget(
      _app(
        const FlatGlassRenderer(),
        RawGlassButton(
          key: const ValueKey('disabled'),
          onPressed: null,
          builder: _Probe().build,
          semanticLabel: 'Done',
          child: const SizedBox(width: 100, height: 30),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Done')),
      matchesSemantics(
        label: 'Done',
        rect: const Rect.fromLTWH(0, -7, 100, 44),
        textDirection: TextDirection.ltr,
        isButton: true,
        hasEnabledState: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('a tap in the 44 point extension presses it; one beyond does '
      'not; the body keeps its size', (tester) async {
    var presses = 0;
    await tester.pumpWidget(
      _app(
        const FlatGlassRenderer(),
        RawGlassButton(
          onPressed: () => presses++,
          builder: _Probe().build,
          child: const SizedBox(width: 100, height: 30),
        ),
      ),
    );
    expect(tester.getSize(find.byType(RawGlassButton)), const Size(100, 30));
    final center = tester.getCenter(find.byType(RawGlassButton));
    await tester.tapAt(center + const Offset(0, -21));
    await tester.pumpAndSettle();
    expect(presses, 1);
    await tester.tapAt(center + const Offset(0, 23));
    await tester.pumpAndSettle();
    expect(presses, 1);
  });

  testWidgets('without onPressed it is disabled and takes no press', (
    tester,
  ) async {
    final probe = _Probe();
    await tester.pumpWidget(
      _app(
        const FlatGlassRenderer(),
        RawGlassButton(
          onPressed: null,
          builder: probe.build,
          child: const SizedBox(width: 100, height: 44),
        ),
      ),
    );
    expect(probe.states, {WidgetState.disabled});
    await tester.tap(find.byType(RawGlassButton));
    await tester.pump(_frame);
    expect(probe.body!.value, const GlassFrame());
    expect(probe.builds, 1);
  });

  for (final (name, wrap) in [
    (
      'MediaQuery.disableAnimations',
      (Widget child) => _app(
        const FlatGlassRenderer(),
        child,
        disableAnimations: true,
      ),
    ),
    (
      'MotionTraitsOverride',
      (Widget child) => _app(
        const FlatGlassRenderer(),
        MotionTraitsOverride(
          traits: const MotionTraits(reduceMotion: true),
          child: child,
        ),
      ),
    ),
  ]) {
    testWidgets('Reduce Motion from $name keeps the glow and drops the '
        'lift', (tester) async {
      final probe = _Probe();
      await tester.pumpWidget(
        wrap(
          RawGlassButton(
            onPressed: () {},
            builder: probe.build,
            child: const SizedBox(width: 100, height: 44),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(RawGlassButton)),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(_frame);
      }
      expect(probe.body!.value.scaleX, 1);
      expect(probe.body!.value.glow, isNotNull);
      await gesture.up();
      await tester.pumpAndSettle();
    });
  }

  group('GlassButton', () {
    Color? labelColor(WidgetTester tester) => tester
        .widget<DefaultTextStyle>(
          find
              .ancestor(
                of: find.text('Go'),
                matching: find.byType(DefaultTextStyle),
              )
              .first,
        )
        .style
        .color;

    Glass glassOf(WidgetTester tester) =>
        tester.widget<GlassSurface>(find.byType(GlassSurface)).glass;

    Color? tintOf(WidgetTester tester) => GlassDynamicColor.maybeResolve(
      glassOf(tester).tint,
      tester.element(find.byType(GlassSurface)),
    );

    testWidgets('regular, prominent and disabled looks', (tester) async {
      await tester.pumpWidget(
        _app(
          const FlatGlassRenderer(),
          GlassButton(onPressed: () {}, child: const Text('Go')),
        ),
      );
      expect(labelColor(tester), isSameColorAs(const Color(0xFF000000)));
      expect(glassOf(tester), const Glass.regular());
      expect(tester.getSize(find.byType(GlassButton)).height, 44);

      await tester.pumpWidget(
        _app(
          const FlatGlassRenderer(),
          GlassButton.prominent(onPressed: () {}, child: const Text('Go')),
        ),
      );
      expect(labelColor(tester), isSameColorAs(const Color(0xFFFFFFFF)));
      expect(tintOf(tester), isSameColorAs(const Color(0xFF0088FF)));

      await tester.pumpWidget(
        _app(
          const FlatGlassRenderer(),
          const GlassButton.prominent(onPressed: null, child: Text('Go')),
        ),
      );
      expect(labelColor(tester), isSameColorAs(const Color(0x4C3C3C43)));
      expect(tintOf(tester), isSameColorAs(const Color(0xFFD1D1D6)));
    });

    testWidgets('a style overrides per state and can build the whole body', (
      tester,
    ) async {
      const style = GlassButtonStyle(
        foregroundColor: WidgetStateProperty.fromMap({
          WidgetState.pressed: Color(0xFFFF0000),
        }),
      );
      await tester.pumpWidget(
        _app(
          const FlatGlassRenderer(),
          GlassButton.clear(
            onPressed: () {},
            style: style,
            child: const Text('Go'),
          ),
        ),
      );
      expect(labelColor(tester), isSameColorAs(const Color(0xFF000000)));
      expect(glassOf(tester), const Glass.clear());
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(GlassButton)),
      );
      await tester.pump(_frame);
      expect(labelColor(tester), isSameColorAs(const Color(0xFFFF0000)));
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _app(
          const FlatGlassRenderer(),
          GlassButton(
            onPressed: () {},
            style: GlassButtonStyle(
              builder: (context, details) => GlassSurface.live(
                frame: details.body,
                role: GlassRole.bar,
                child: details.label,
              ),
            ),
            child: const Text('Go'),
          ),
        ),
      );
      expect(
        tester.widget<GlassSurface>(find.byType(GlassSurface)).role,
        GlassRole.bar,
      );
    });
  });

  testWidgets('disabling a button under a finger ends the press quietly', (
    tester,
  ) async {
    Widget button(VoidCallback? onPressed) => _app(
      const FlatGlassRenderer(),
      GlassButton(onPressed: onPressed, child: const Text('Go')),
    );
    await tester.pumpWidget(button(() {}));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GlassButton)),
    );
    await tester.pump(_frame);
    await tester.pumpWidget(button(null));
    expect(tester.takeException(), isNull);
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
