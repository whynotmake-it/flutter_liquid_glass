import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/foundation/touch_glow.dart';
import 'package:apple_liquid_glass/src/surfaces/flat.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'glass_shown.dart';

Widget _app(GlassRenderer renderer, Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: GlassScope(
    renderer: renderer,
    child: Center(child: child),
  ),
);

class _Counted extends StatefulWidget {
  const _Counted(this.builds);

  final List<int> builds;

  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  late final int id = widget.builds.length;

  @override
  Widget build(BuildContext context) {
    widget.builds.add(id);
    return const SizedBox(width: 100, height: 44);
  }
}

void main() {
  setUp(MotionClock.debugReset);

  test('a capsule is a stadium in any box', () {
    final outline = LiquidRoundedSuperellipse.capsule.getOuterPath(
      const Rect.fromLTWH(0, 0, 100, 44),
    );
    expect(outline.contains(const Offset(2, 22)), isTrue);
    expect(outline.contains(const Offset(50, 1)), isTrue);
    expect(outline.contains(const Offset(3, 3)), isFalse);
    expect(outline.getBounds(), const Rect.fromLTWH(0, 0, 100, 44));
  });

  test('a frame draws its content where it draws the body', () {
    const size = Size(100, 40);
    const frame = GlassFrame(
      rect: Rect.fromLTWH(10, 0, 100, 40),
      scaleX: 1.2,
      scaleY: 0.5,
    );
    final body = frame.bodyIn(size);
    expect(
      body.drawnRect,
      Rect.fromCenter(center: const Offset(60, 20), width: 120, height: 20),
    );
    expect(
      MatrixUtils.transformRect(body.childToBox!, Offset.zero & size),
      body.drawnRect,
    );
    expect(
      MatrixUtils.transformRect(body.toBox!, body.bounds),
      body.drawnRect,
    );
    expect(const GlassFrame().bodyIn(size).childToBox, isNull);
  });

  for (final renderer in const [
    FlatGlassRenderer(),
    LiquidGlassRenderer(),
  ]) {
    testWidgets('${renderer.runtimeType}: a live body smaller than its box '
        'draws its content centered on the body', (tester) async {
      const body = Rect.fromLTWH(2, 2, 37, 24);
      await tester.pumpWidget(
        _app(
          renderer,
          SizedBox(
            width: 63,
            height: 28,
            child: GlassSurface.live(
              frame: MotionSelection(() => const GlassFrame(rect: body)),
              child: const Center(
                child: SizedBox.square(dimension: 10, key: Key('content')),
              ),
            ),
          ),
        ),
      );
      final box = tester.getTopLeft(find.byType(GlassSurface));
      expect(
        tester.getCenter(find.byKey(const Key('content'))),
        offsetMoreOrLessEquals(box + body.center),
      );
    });
  }

  group('flat', () {
    testWidgets('a live surface repaints for a frame and never rebuilds', (
      tester,
    ) async {
      final frames = _Frames(const GlassFrame());
      final builds = <int>[];
      await tester.pumpWidget(
        _app(
          const FlatGlassRenderer(),
          GlassSurface.live(frame: frames.selection, child: _Counted(builds)),
        ),
      );
      final body = tester.renderObject<RenderFlatGlass>(
        find.byElementPredicate(
          (element) =>
              element is RenderObjectElement &&
              element.renderObject is RenderFlatGlass,
        ),
      );
      expect(body.debugNeedsPaint, isFalse);
      frames.value = const GlassFrame(scaleX: 1.1, scaleY: 1.1);
      await tester.pump();
      expect(builds, [0]);
      expect(
        body,
        paints
          ..rsuperellipse(color: const Color(0x1A000000))
          ..rsuperellipse(color: const Color(0xD9FFFFFF)),
      );
    });

    testWidgets('a translucent lens shows what is under it, not its own '
        'shadow, and casts the shadow outside', (tester) async {
      const lens = GlassLens(
        restingShadow: BoxShadow(
          color: Color(0x24000000),
          offset: Offset(0, 1),
          blurRadius: 7.794,
        ),
      );
      const screen = Key('screen');
      debugDisableShadows = false;
      try {
        for (final (lift, inside) in [(0.0, 0xEC), (1.0, 0xFB)]) {
          await tester.pumpWidget(
            RepaintBoundary(
              key: screen,
              child: ColoredBox(
                color: const Color(0xFFFFFFFF),
                child: _app(
                  const FlatGlassRenderer(),
                  SizedBox(
                    width: 120,
                    height: 40,
                    child: GlassSurface.live(
                      role: GlassRole.lens,
                      lens: lens,
                      glass: const Glass.regular(tint: Color(0x13000000)),
                      frame: MotionSelection(() => GlassFrame(lift: lift)),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          );
          final origin = tester.getTopLeft(find.byType(GlassSurface));
          final image = await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(screen),
            );
            final image = await boundary.toImage();
            final data = await image.toByteData();
            final width = image.width;
            image.dispose();
            return (data!.buffer.asUint8List(), width);
          });
          final (bytes, width) = image!;
          int red(Offset at) {
            final point = origin + at;
            return bytes[(point.dy.floor() * width + point.dx.floor()) * 4];
          }

          expect(
            red(const Offset(30, 20)),
            closeTo(inside, 2),
            reason: '$lift',
          );
          expect(
            red(const Offset(60, 20)),
            closeTo(inside, 2),
            reason: '$lift',
          );
          expect(red(const Offset(60, 42)), lessThan(0xFB), reason: '$lift');
        }
      } finally {
        debugDisableShadows = true;
      }
    });

    testWidgets("a lens rests on the shadow its control measured: a slider's "
        "thumb casts one, a switch's knob and a selection none", (
      tester,
    ) async {
      Iterable<FlatGlassLook> lenses(Widget control) sync* {
        yield* tester
            .renderObjectList<RenderFlatGlass>(
              find.descendant(
                of: find.byWidget(control),
                matching: find.byElementPredicate(
                  (element) =>
                      element is RenderObjectElement &&
                      element.renderObject is RenderFlatGlass,
                ),
              ),
            )
            .map((body) => body.look)
            .where((look) => look.liftRim != null);
      }

      final slider = GlassSlider(value: 0.5, onChanged: (_) {});
      final knob = GlassSwitch(value: false, onChanged: (_) {});
      final segmented = GlassSegmentedControl<String>(
        segments: const [
          GlassSegment(value: 'a', label: Text('One')),
          GlassSegment(value: 'b', label: Text('Two')),
        ],
        groupValue: 'a',
        onChanged: (_) {},
      );
      await tester.pumpWidget(
        _app(
          const FlatGlassRenderer(),
          SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [slider, knob, segmented],
            ),
          ),
        ),
      );
      final thumb = lenses(slider).single.restingShadow!;
      expect(thumb.color, isSameColorAs(const Color(0x24000000)));
      expect(thumb.offset, const Offset(0, 1));
      expect(thumb.blurSigma, moreOrLessEquals(5, epsilon: 1e-3));
      expect(lenses(knob).single.restingShadow, isNull);
      expect(lenses(segmented).single.restingShadow, isNull);
    });

    test('a track has a fill only; a tint, then the scheme, fills the '
        'body', () {
      const light = GlassTraits();
      const dark = GlassTraits(brightness: .dark);
      expect(
        FlatGlassLook.of(GlassRole.track, const Glass.regular(), light).fill,
        isSameColorAs(const Color(0x33787880)),
      );
      expect(
        FlatGlassLook.of(
          GlassRole.track,
          const Glass.regular(),
          const GlassTraits(highContrast: true),
        ).fill,
        isSameColorAs(const Color(0x47787880)),
      );
      final tinted = FlatGlassLook.of(
        GlassRole.control,
        const Glass.regular(tint: Color(0xFF0088FF)),
        dark,
        scheme: const GlassColorScheme(
          surfaces: {GlassRole.control: Color(0xFF123456)},
        ),
      );
      expect(tinted.fill, const Color(0xFF0088FF));
      expect(tinted.shadow, isSameColorAs(const Color(0x40000000)));
      final bar = FlatGlassLook.of(
        GlassRole.bar,
        const Glass.regular(),
        light,
        scheme: const GlassColorScheme(
          surfaces: {GlassRole.bar: Color(0xFF123456)},
        ),
      );
      expect(bar.fill, const Color(0xFF123456));
      expect(bar.rim, isSameColorAs(const Color(0x1F000000)));
      expect(bar.shadow, isNull);
    });
  });

  group('liquid', () {
    testWidgets('a lone surface draws on a glass layer of its own', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const LiquidGlassRenderer(),
          const GlassSurface(child: SizedBox(width: 100, height: 44)),
        ),
      );
      expect(find.byType(LiquidGlassLayer), findsOneWidget);
      expect(find.byType(LiquidGlass), findsOneWidget);
    });

    testWidgets('a resting lens or knob and a track draw flat', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const LiquidGlassRenderer(),
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassSurface(
                role: GlassRole.lens,
                child: SizedBox(width: 60, height: 30),
              ),
              GlassSurface(
                role: GlassRole.track,
                child: SizedBox(width: 60, height: 30),
              ),
            ],
          ),
        ),
      );
      expect(findShown(LiquidGlass), findsNothing);
      expect(
        tester.allRenderObjects.whereType<RenderFlatGlass>().toSet(),
        hasLength(2),
      );
    });

    testWidgets('glass takes the Liquid Glass slider from the traits', (
      tester,
    ) async {
      for (final glass in [const Glass.regular(), const Glass.clear()]) {
        await tester.pumpWidget(
          _app(
            const LiquidGlassRenderer(),
            GlassTraitsOverride(
              glassTintAmount: 0.6,
              child: GlassSurface(
                glass: glass,
                child: const SizedBox(width: 60, height: 30),
              ),
            ),
          ),
        );
        final settings = tester
            .widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer))
            .frame!
            .value
            .settings;
        expect(settings.sliderPosition, 0.6, reason: '$glass');
      }
    });

    testWidgets('a lifted lens pulls by its description and bends and parts '
        'colors by its height', (tester) async {
      Future<LiquidGlassSettings> lifted(GlassLens lens, Rect? rect) async {
        await tester.pumpWidget(
          _app(
            const LiquidGlassRenderer(),
            GlassSurface.live(
              key: ValueKey((lens, rect)),
              role: GlassRole.lens,
              lens: lens,
              frame: MotionSelection(() => GlassFrame(lift: 1, rect: rect)),
              child: const SizedBox(width: 114, height: 70),
            ),
          ),
        );
        return tester
            .widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer))
            .frame!
            .value
            .settings;
      }

      const rect = Rect.fromLTWH(0, 0, 114, 70);
      final large = await lifted(
        const GlassLens(pull: 9, pullHeight: 36),
        rect,
      );
      expect(large.backdropShrink, 0);
      expect(large.backdropPull, 9);
      expect(large.backdropPullDepth, 36);
      expect(large.dispersion, 0);
      expect(large.frost, const LiquidGlassFrost.sigma(0));
      expect(large.refractionAmount, moreOrLessEquals(10.5));
      expect(large.refractionHeight, moreOrLessEquals(7));
      expect(large.aberration, moreOrLessEquals(3.684, epsilon: 1e-3));
      expect(large.aberrationDepth, moreOrLessEquals(14));

      final small = await lifted(
        const GlassLens(pull: 9, pullHeight: 36, small: true),
        const Rect.fromLTWH(0, 0, 58, 38.33),
      );
      expect(small.backdropPull, 9);
      expect(small.refractionAmount, moreOrLessEquals(11.5, epsilon: 1e-2));
      expect(small.refractionHeight, moreOrLessEquals(6.9, epsilon: 1e-2));
      expect(small.aberration, 0);
      expect(small.frost, const LiquidGlassFrost.sigma(0));

      final still = await lifted(const GlassLens(small: true), null);
      expect(still.backdropPull, 0);
      expect(still.refractionAmount, 0);
      expect(still.aberration, 0);
    });

    testWidgets('the glass of a lifted knob lifts black to a tenth of white, '
        'and the glass of a selection changes no color', (tester) async {
      Future<LiquidGlassAppearance> lifted(GlassLens lens, double lift) async {
        await tester.pumpWidget(
          _app(
            const LiquidGlassRenderer(),
            GlassSurface.live(
              key: ValueKey((lens, lift)),
              role: GlassRole.lens,
              lens: lens,
              frame: MotionSelection(() => GlassFrame(lift: lift)),
              child: const SizedBox(width: 58, height: 38),
            ),
          ),
        );
        return tester
            .widget<LiquidGlass>(findShown(LiquidGlass))
            .frame!
            .value
            .appearance!;
      }

      final knob = await lifted(const GlassLens(small: true), 1);
      expect(
        knob.tint,
        const Color.from(alpha: 0.1, red: 1, green: 1, blue: 1),
      );
      expect(knob.visibility, 1);
      expect(knob.colorModel, const LiquidGlassColorModel.direct());
      // The face comes with the glass, by its visibility.
      final rising = await lifted(const GlassLens(small: true), 0.1);
      expect(rising.tint, knob.tint);
      expect(rising.visibility, GlassFrame.glassnessAt(0.1));

      final selection = await lifted(const GlassLens(), 1);
      expect(selection.tint.a, 0);
      expect(selection.colorModel, const LiquidGlassColorModel.direct());
    });

    testWidgets('each control describes its lens by its own measurement', (
      tester,
    ) async {
      for (final (control, lens) in <(Widget, GlassLens)>[
        (
          GlassTabBar(
            destinations: const [
              GlassTabDestination(
                icon: SizedBox.square(dimension: 24),
                label: Text('Tab'),
              ),
              GlassTabDestination(
                icon: SizedBox.square(dimension: 24),
                label: Text('Tab'),
              ),
            ],
            selectedIndex: 0,
            onDestinationSelected: (_) {},
          ),
          const GlassLens(pull: 9, pullHeight: 36),
        ),
        (
          GlassSegmentedControl<int>(
            segments: const [
              GlassSegment(value: 0, label: Text('One')),
              GlassSegment(value: 1, label: Text('Two')),
            ],
            groupValue: 0,
            onChanged: (_) {},
          ),
          const GlassLens(pull: 9, pullHeight: 36),
        ),
        (
          GlassSwitch(value: true, onChanged: (_) {}),
          const GlassLens(pull: 9, pullHeight: 36, small: true),
        ),
        (
          GlassSlider(value: 0.5, onChanged: (_) {}),
          const GlassLens(
            small: true,
            restingShadow: BoxShadow(
              color: Color(0x24000000),
              offset: Offset(0, 1),
              blurRadius: 7.794,
            ),
          ),
        ),
      ]) {
        await tester.pumpWidget(_app(const FlatGlassRenderer(), control));
        final surface = tester.widget<GlassSurface>(
          find.byWidgetPredicate(
            (w) => w is GlassSurface && w.role == GlassRole.lens,
          ),
        );
        expect(surface.lens, lens, reason: '${control.runtimeType}');
      }
    });

    testWidgets('a group draws its members on one layer and blends them '
        'when they merge', (tester) async {
      Widget row(GlassMerge merge) => _app(
        const LiquidGlassRenderer(),
        GlassGroup(
          merge: merge,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassSurface(child: SizedBox(width: 44, height: 44)),
              GlassSurface(child: SizedBox(width: 44, height: 44)),
            ],
          ),
        ),
      );
      await tester.pumpWidget(row(const GlassMerge.none()));
      expect(find.byType(LiquidGlassLayer), findsOneWidget);
      expect(find.byType(LiquidGlass), findsNWidgets(2));
      expect(find.byType(LiquidGlassBlendGroup), findsNothing);
      await tester.pumpWidget(row(const GlassMerge.spacing(12)));
      expect(find.byType(LiquidGlassLayer), findsOneWidget);
      expect(
        tester
            .widget<LiquidGlassBlendGroup>(find.byType(LiquidGlassBlendGroup))
            .blend,
        12,
      );
    });

    testWidgets('a touch lights its own shape, in the layer of its group', (
      tester,
    ) async {
      final frames = _Frames(const GlassFrame());
      await tester.pumpWidget(
        _app(
          const LiquidGlassRenderer(),
          GlassGroup(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const GlassSurface(child: SizedBox(width: 44, height: 44)),
                GlassSurface.live(
                  frame: frames.selection,
                  child: const SizedBox(width: 100, height: 44),
                ),
              ],
            ),
          ),
        ),
      );
      LiquidGlassGlow? glow(int index) => tester
          .widgetList<LiquidGlass>(find.byType(LiquidGlass))
          .elementAt(index)
          .frame!
          .value
          .glow;
      expect(find.byType(LiquidGlassLayer), findsOneWidget);
      expect(glow(1), isNull);
      frames.value = const GlassFrame(glow: _touch);
      await tester.pump();
      final lit = glow(1)!;
      expect(glow(0), isNull);
      expect(lit.center, _touch.center);
      expect(lit.wash, _touch.wash);
      expect(lit.gain, closeTo(0.3 * TouchGlowGain.spotGain(.light), 1e-9));
      frames.value = const GlassFrame();
      await tester.pump();
      expect(glow(1), isNull);
    });

    for (final merge in const [GlassMerge.none(), GlassMerge.spacing(12)]) {
      testWidgets('a surface in the content of a surface in a group that '
          '${merge == const GlassMerge.none() ? 'does not merge' : 'merges'} '
          'draws and glows in a layer of its own', (tester) async {
        final frames = _Frames(const GlassFrame());
        await tester.pumpWidget(
          _app(
            const LiquidGlassRenderer(),
            GlassGroup(
              merge: merge,
              child: GlassSurface(
                child: SizedBox(
                  width: 200,
                  height: 100,
                  child: Center(
                    child: GlassSurface.live(
                      frame: frames.selection,
                      child: const SizedBox(width: 60, height: 44),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        frames.value = const GlassFrame(glow: _touch);
        await tester.pump();

        expect(find.byType(LiquidGlassLayer), findsNWidgets(2));
        final glass = tester.widgetList<LiquidGlass>(find.byType(LiquidGlass));
        expect(glass.first.frame!.value.glow, isNull);
        expect(glass.last.frame!.value.glow?.center, _touch.center);
        final inner = find.byWidget(glass.last);
        expect(
          find.ancestor(of: inner, matching: find.byType(LiquidGlassLayer)),
          findsNWidgets(2),
        );
        expect(
          find.ancestor(
            of: inner,
            matching: find.byType(LiquidGlassBlendGroup),
          ),
          merge == const GlassMerge.none() ? findsNothing : findsOneWidget,
          reason: 'the outer blend group lies above the inner layer only',
        );
      });
    }
  });

  group('liquid settings and rest', () {
    testWidgets('a lens bends its content only where its layer draws real '
        'glass, for either renderer and in every state of full glass', (
      tester,
    ) async {
      addTearDown(() => debugOverrideLiquidGlassSupport(null));
      final content = ValueNotifier<GlassLensContent?>(null);
      const unavailable = LiquidGlassSupport.unavailable('No shader filters.');
      final fakeLayer = find.byWidgetPredicate(
        (widget) => '${widget.runtimeType}' == 'ConsolidatedFakeGlassLayer',
      );
      for (final support in const [
        LiquidGlassSupport.pending(),
        unavailable,
        null,
      ]) {
        debugOverrideLiquidGlassSupport(support);
        for (final renderer in const [
          LiquidGlassRenderer(),
          FakeGlassRenderer(),
        ]) {
          await tester.pumpWidget(
            _app(
              renderer,
              GlassSurface.live(
                key: ValueKey((renderer, support)),
                role: GlassRole.lens,
                frame: MotionSelection(
                  () => const GlassFrame(
                    lift: 1,
                    rect: Rect.fromLTWH(0, 0, 114, 70),
                  ),
                ),
                lensContent: content,
                child: const SizedBox(width: 114, height: 70),
              ),
            ),
          );
          final real = fakeLayer.evaluate().isEmpty;
          expect(find.byType(LiquidGlassLayer), findsOneWidget);
          expect(
            content.value != null,
            real,
            reason: '$renderer, ${support ?? 'loaded'}',
          );
        }
      }
      await tester.pumpWidget(const SizedBox());
      content.dispose();
    });

    testWidgets('fake glass takes the glow; a lone clear surface and the '
        'dark appearance get their iOS 27 settings', (tester) async {
      final frames = _Frames(const GlassFrame());
      LiquidGlassLayerFrame layer() => tester
          .widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer))
          .frame!
          .value;
      await tester.pumpWidget(
        _app(
          const FakeGlassRenderer(),
          GlassSurface.live(
            frame: frames.selection,
            child: const SizedBox(width: 100, height: 44),
          ),
        ),
      );
      frames.value = const GlassFrame(glow: _touch);
      await tester.pump();
      expect(
        tester.widget<LiquidGlass>(find.byType(LiquidGlass)).frame!.value.glow,
        isNotNull,
      );

      await tester.pumpWidget(
        _app(
          const LiquidGlassRenderer(),
          const GlassSurface(
            glass: Glass.clear(),
            child: SizedBox(width: 100, height: 44),
          ),
        ),
      );
      expect(layer().settings, const LiquidGlassSettings.ios27Clear());
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(platformBrightness: .dark),
          child: _app(
            const LiquidGlassRenderer(),
            const GlassSurface(child: SizedBox(width: 100, height: 44)),
          ),
        ),
      );
      expect(
        layer().settings,
        const LiquidGlassSettings.ios27Regular(brightness: .dark),
      );
    });

    testWidgets('a group is clear glass while all its members are', (
      tester,
    ) async {
      LiquidGlassSettings layer() => tester
          .widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer))
          .frame!
          .value
          .settings;
      LiquidGlassSettings scope() => LiquidGlassLayer.settingsOf(
        tester.element(find.byType(SizedBox).first),
      );
      Widget group(GlassRenderer renderer, List<Glass> members) => _app(
        renderer,
        GlassGroup(
          merge: const GlassMerge.spacing(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final glass in members)
                GlassSurface(
                  glass: glass,
                  child: const SizedBox(width: 44, height: 44),
                ),
            ],
          ),
        ),
      );
      const clear = LiquidGlassSettings.ios27Clear();
      const regular = LiquidGlassSettings.ios27Regular(brightness: .light);
      for (final renderer in [
        const LiquidGlassRenderer(),
        const FakeGlassRenderer(),
      ]) {
        await tester.pumpWidget(
          group(renderer, const [Glass.clear(), Glass.clear()]),
        );
        expect(layer(), clear, reason: '$renderer');
        await tester.pump();
        expect(scope(), clear, reason: '$renderer');

        await tester.pumpWidget(
          group(renderer, const [Glass.clear(), Glass.regular()]),
        );
        expect(layer(), regular, reason: '$renderer');
        await tester.pump();
        expect(scope(), regular, reason: '$renderer');

        await tester.pumpWidget(group(renderer, const [Glass.clear()]));
        await tester.pump();
        expect(layer(), clear, reason: '$renderer');
        expect(scope(), clear, reason: '$renderer');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a still surface in place of a lifted live one draws at rest', (
      tester,
    ) async {
      final frames = _Frames(
        const GlassFrame(scaleX: 1.2, scaleY: 1.2),
      );
      LiquidGlassShapeFrame shape() =>
          tester.widget<LiquidGlass>(find.byType(LiquidGlass)).frame!.value;
      await tester.pumpWidget(
        _app(
          const LiquidGlassRenderer(),
          GlassSurface.live(
            frame: frames.selection,
            child: const SizedBox(width: 100, height: 44),
          ),
        ),
      );
      expect(shape().scaleX, 1.2);
      await tester.pumpWidget(
        _app(
          const LiquidGlassRenderer(),
          const GlassSurface(child: SizedBox(width: 100, height: 44)),
        ),
      );
      expect(shape().scaleX, 1);
    });
  });

  testWidgets("a frame's opacity fades the glass on both renderers", (
    tester,
  ) async {
    final frames = _Frames(const GlassFrame(opacity: 0.25));
    Widget surface(GlassRenderer renderer) => _app(
      renderer,
      GlassSurface.live(
        frame: frames.selection,
        child: const SizedBox(width: 100, height: 44),
      ),
    );
    await tester.pumpWidget(surface(const LiquidGlassRenderer()));
    final liquid = tester
        .widget<LiquidGlass>(find.byType(LiquidGlass))
        .frame!
        .value;
    expect(liquid.appearance!.visibility, closeTo(0.25, 1e-9));
    await tester.pumpWidget(surface(const FlatGlassRenderer()));
    expect(
      tester.layers.whereType<OpacityLayer>().map((layer) => layer.alpha),
      contains(64),
    );
    frames.value = const GlassFrame();
    await tester.pump();
    expect(
      tester.layers.whereType<OpacityLayer>().map((layer) => layer.alpha),
      isNot(contains(64)),
    );
  });

  testWidgets('an outline body is its path on the flat renderer and its '
      "field in a layer of its own on the liquid one", (tester) async {
    final edge = Path();
    edge.moveTo(0, 0);
    edge.lineTo(100, 0);
    edge.lineTo(100, 44);
    edge.lineTo(50, 60);
    edge.lineTo(0, 44);
    edge.close();
    final field = LiquidGlassField(
      samples: Float32List(2 * 2 * 4),
      columns: 2,
      rows: 2,
      origin: Offset.zero,
      step: 60,
      edge: edge,
    );
    final frames = _Frames(
      GlassFrame(outline: GlassOutline(edge, field: () => field)),
    );
    Widget surface(GlassRenderer renderer, {bool grouped = false}) {
      final body = GlassSurface.live(
        frame: frames.selection,
        child: const RepaintBoundary(child: SizedBox(width: 100, height: 60)),
      );
      return _app(
        renderer,
        grouped ? GlassGroup(child: body) : body,
      );
    }

    await tester.pumpWidget(surface(const FlatGlassRenderer()));
    final at = tester.getTopLeft(find.byType(GlassSurface));
    final clip = tester.layers.whereType<ClipPathLayer>().single.clipPath!;
    expect(clip.getBounds(), edge.getBounds().shift(at));
    expect(clip.contains(at + const Offset(50, 58)), isTrue);
    expect(clip.contains(at + const Offset(4, 58)), isFalse);
    await tester.pumpWidget(surface(const LiquidGlassRenderer()));
    LiquidGlassLayerFrame layer() => tester
        .widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer))
        .frame!
        .value;
    expect(layer().field!.samples, same(field.samples));
    expect(
      tester.widget<LiquidGlass>(find.byType(LiquidGlass)).frame!.value.rect,
      const Rect.fromLTWH(0, 0, 100, 60),
    );
    frames.value = const GlassFrame();
    await tester.pump();
    expect(layer().field, isNull);

    frames.value = GlassFrame(outline: GlassOutline(edge));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(surface(const LiquidGlassRenderer()));
    expect(
      find.byType(LiquidGlass),
      findsNothing,
      reason: 'an outline without a field draws flat',
    );
    frames.value = GlassFrame(outline: GlassOutline(edge, field: () => field));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      surface(const LiquidGlassRenderer(), grouped: true),
    );
    expect(
      find.byType(LiquidGlass),
      findsNothing,
      reason: 'a shared layer has no field for one member',
    );
  });

  testWidgets('a still frame makes no new renderer shape or field, through '
      'rebuilds and republished frames', (tester) async {
    final edge = Path();
    edge.addRect(const Rect.fromLTWH(0, 0, 100, 60));
    var sampled = 0;
    final still = GlassFrame(
      shape: const LiquidRoundedSuperellipse(radius: 12),
      outline: GlassOutline(
        edge,
        field: () {
          sampled++;
          return LiquidGlassField(
            samples: Float32List(2 * 2 * 4),
            columns: 2,
            rows: 2,
            origin: Offset.zero,
            step: 60,
            edge: edge,
          );
        },
      ),
    );
    final frames = _Frames(still);
    Widget surface() => _app(
      const LiquidGlassRenderer(),
      GlassSurface.live(
        frame: frames.selection,
        child: const SizedBox(width: 100, height: 60),
      ),
    );
    await tester.pumpWidget(surface());
    LiquidShape shape() =>
        tester.widget<LiquidGlass>(find.byType(LiquidGlass)).frame!.value.shape;
    LiquidGlassField? field() => tester
        .widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer))
        .frame!
        .value
        .field;
    final firstShape = shape();
    final firstField = field();
    expect(firstField, isNotNull);
    for (var i = 0; i < 3; i++) {
      await tester.pumpWidget(surface());
      frames.value = still;
      await tester.pump();
    }
    expect(shape(), same(firstShape));
    expect(field(), same(firstField));
    expect(sampled, 1);
  });

  testWidgets('flat content reports where it is drawn', (tester) async {
    final frames = _Frames(const GlassFrame());
    const key = Key('content');
    await tester.pumpWidget(
      _app(
        const FlatGlassRenderer(),
        GlassSurface.live(
          frame: frames.selection,
          child: const SizedBox(key: key, width: 100, height: 44),
        ),
      ),
    );
    final box = tester.renderObject<RenderBox>(find.byKey(key));
    final rest = box.localToGlobal(Offset.zero);
    frames.value = const GlassFrame(rect: Rect.fromLTWH(10, 0, 100, 44));
    await tester.pump();
    expect(box.localToGlobal(Offset.zero), rest + const Offset(10, 0));
  });

  group('theme', () {
    testWidgets('a renderer switch rebuilds surfaces and keeps their '
        "content's state", (tester) async {
      final builds = <int>[];
      final frames = _Frames(const GlassFrame());
      Widget surface(GlassRenderer renderer) => _app(
        renderer,
        GlassSurface.live(frame: frames.selection, child: _Counted(builds)),
      );
      await tester.pumpWidget(surface(const FlatGlassRenderer()));
      expect(find.byType(LiquidGlass), findsNothing);
      await tester.pumpWidget(surface(const LiquidGlassRenderer()));
      expect(find.byType(LiquidGlass), findsOneWidget);
      await tester.pumpWidget(surface(const FakeGlassRenderer()));
      expect(
        tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).fake,
        isTrue,
      );
      expect(builds.toSet(), {0});
    });

    testWidgets('a renderer reader rebuilds only when the renderer '
        'changes', (tester) async {
      var reads = 0;
      final reader = Builder(
        builder: (context) {
          GlassRendererScope.of(context);
          reads++;
          return const SizedBox();
        },
      );
      Widget scoped(GlassRenderer renderer, GlassThemeData theme) =>
          GlassScope(renderer: renderer, data: theme, child: reader);
      await tester.pumpWidget(
        scoped(const LiquidGlassRenderer(), const GlassThemeData()),
      );
      await tester.pumpWidget(
        scoped(
          const LiquidGlassRenderer(),
          const GlassThemeData(primaryColor: Color(0xFF123456)),
        ),
      );
      expect(reads, 1);
      await tester.pumpWidget(
        scoped(const FlatGlassRenderer(), const GlassThemeData()),
      );
      expect(reads, 2);
    });

    testWidgets('without a scope above, glass draws flat', (tester) async {
      late GlassRenderer renderer;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            renderer = GlassRendererScope.of(context);
            return const SizedBox();
          },
        ),
      );
      expect(renderer, const FlatGlassRenderer());
      expect(
        GlassRendererScope.maybeOf(tester.element(find.byType(SizedBox))),
        isNull,
      );
    });

    testWidgets('adaptive draws the capable renderer while full glass '
        'loads, then the one it picks', (tester) async {
      debugOverrideLiquidGlassSupport(const LiquidGlassSupport.pending());
      addTearDown(() => debugOverrideLiquidGlassSupport(null));
      const renderer = AdaptiveGlassRenderer(fallback: FlatGlassRenderer());
      await tester.pumpWidget(
        _app(
          renderer,
          const GlassSurface(child: SizedBox(width: 100, height: 44)),
        ),
      );
      expect(find.byType(LiquidGlass), findsOneWidget);
      debugOverrideLiquidGlassSupport(null);
      final support = liquidGlassSupport.value;
      await tester.pump();
      expect(
        find.byType(LiquidGlass),
        support == _capable ? findsOneWidget : findsNothing,
      );
    });

    testWidgets('adaptive draws what precacheGlass found from its '
        'first frame', (tester) async {
      await tester.runAsync(precacheGlass);
      final support = liquidGlassSupport.value;
      await tester.pumpWidget(
        _app(
          const AdaptiveGlassRenderer(fallback: FlatGlassRenderer()),
          const GlassSurface(child: SizedBox(width: 100, height: 44)),
        ),
      );
      expect(
        find.byType(LiquidGlass),
        support == _capable ? findsOneWidget : findsNothing,
      );
    });

    testWidgets('adaptive draws its fallback while the system prefers '
        'reduced resource usage', (tester) async {
      debugOverrideLiquidGlassSupport(const LiquidGlassSupport.pending());
      addTearDown(() => debugOverrideLiquidGlassSupport(null));
      Widget app({required bool reduced}) => _app(
        const AdaptiveGlassRenderer(fallback: FlatGlassRenderer()),
        GlassTraitsOverride(
          prefersReducedResourceUsage: reduced,
          child: const GlassSurface(child: SizedBox(width: 100, height: 44)),
        ),
      );
      await tester.pumpWidget(app(reduced: true));
      expect(find.byType(LiquidGlass), findsNothing);
      await tester.pumpWidget(app(reduced: false));
      expect(find.byType(LiquidGlass), findsOneWidget);
      await tester.pumpWidget(app(reduced: true));
      expect(find.byType(LiquidGlass), findsNothing);
    });

    testWidgets('adaptive draws its fallback from the first frame where '
        'the engine draws no shader filters', (tester) async {
      debugOverrideLiquidGlassSupport(
        const LiquidGlassSupport.unavailable('No shader filters.'),
      );
      addTearDown(() => debugOverrideLiquidGlassSupport(null));
      await tester.pumpWidget(
        _app(
          const AdaptiveGlassRenderer(fallback: FlatGlassRenderer()),
          const GlassSurface(child: SizedBox(width: 100, height: 44)),
        ),
      );
      expect(find.byType(LiquidGlass), findsNothing);
    });
  });

  testWidgets('a clip follows the frames of its glass without a rebuild', (
    tester,
  ) async {
    final frames = _Frames(
      const GlassFrame(rect: Rect.fromLTWH(10, 0, 40, 20)),
    );
    final builds = <int>[];
    await tester.pumpWidget(
      _app(
        const FlatGlassRenderer(),
        GlassClip.live(frame: frames.selection, child: _Counted(builds)),
      ),
    );
    final box = tester.renderObject<RenderClipPath>(find.byType(ClipPath));
    Rect clip() => box.clipper!.getClip(box.size).getBounds();
    expect(clip(), const Rect.fromLTWH(10, 0, 40, 20));
    frames.value = const GlassFrame(
      rect: Rect.fromLTWH(10, 0, 40, 20),
      scaleX: 2,
    );
    await tester.pump();
    expect(clip(), const Rect.fromLTWH(-10, 0, 80, 20));
    expect(builds, [0]);
  });

  testWidgets("a renderer's frame listener paints a frame published in "
      "a frame's resolve phase in that frame", (tester) async {
    final frames = _Frames(const GlassFrame(rect: Rect.fromLTWH(0, 0, 10, 10)));
    final painted = <double>[];
    Widget app(double left) => Directionality(
      textDirection: TextDirection.ltr,
      child: GlassRendererScope(
        renderer: _Listening(painted),
        child: Column(
          children: [
            _Resolving(
              onResolve: () => frames.value = GlassFrame(
                rect: Rect.fromLTWH(left, 0, 10, 10),
              ),
            ),
            GlassSurface.live(
              frame: frames.selection,
              child: const SizedBox(width: 40, height: 10),
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(app(0));
    await tester.pumpWidget(app(5));
    expect(painted.last, 5);
    await tester.pumpWidget(app(7));
    expect(painted.last, 7);
  });

  test('a clip of a shape is the shape the glass draws', () {
    const shapes = [
      LiquidRoundedSuperellipse(radius: 12),
      LiquidRoundedRectangle(radius: 12),
      LiquidOval(),
    ];
    final clips = [
      for (final shape in shapes)
        GlassClip(shape: shape).build(_NoContext()).runtimeType,
    ];
    expect(clips, [ClipRSuperellipse, ClipRRect, ClipOval]);
  });
}

final class _NoContext extends Fake implements BuildContext {}

const _capable = LiquidGlassSupport.available(
  deviceClass: LiquidGlassDeviceClass.capable,
);

const _touch = GlassTouchGlow(
  wash: 0.04,
  center: Offset(30, 22),
  radius: 20,
  spot: 0.3,
);

/// Frames a test writes; the surface follows them as a selection.
final class _Frames {
  _Frames(this._frame);

  GlassFrame _frame;
  final _version = MotionValue<double>(0);

  late final MotionSelection<GlassFrame> selection = MotionSelection(() {
    _version.value;
    return _frame;
  });

  GlassFrame get value => _frame;

  set value(GlassFrame frame) {
    _frame = frame;
    _version.snap(MotionClock.instance.now, _version.value + 1);
  }
}

/// Paints the left edge of its surface's frame in a layer of its own,
/// marked only by a listener added to the details' frame.
final class _Listening extends GlassRenderer {
  const _Listening(this.painted);

  final List<double> painted;

  @override
  Widget buildSurface(BuildContext context, GlassSurfaceDetails details) =>
      _FrameProbe(frame: details.frame, painted: painted);
}

class _FrameProbe extends LeafRenderObjectWidget {
  const _FrameProbe({required this.frame, required this.painted});

  final ValueListenable<GlassFrame> frame;
  final List<double> painted;

  @override
  _RenderFrameProbe createRenderObject(BuildContext context) =>
      _RenderFrameProbe(frame, painted);
}

class _RenderFrameProbe extends RenderBox {
  _RenderFrameProbe(this.frame, this.painted);

  final ValueListenable<GlassFrame> frame;
  final List<double> painted;

  @override
  bool get isRepaintBoundary => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    frame.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    frame.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() => size = constraints.constrain(const Size(40, 10));

  @override
  void paint(PaintingContext context, Offset offset) =>
      painted.add(frame.value.rect!.left);
}

/// Runs [onResolve] in the resolve phase of every frame that lays it out.
class _Resolving extends LeafRenderObjectWidget {
  const _Resolving({required this.onResolve});

  final VoidCallback onResolve;

  @override
  _RenderResolving createRenderObject(BuildContext context) =>
      _RenderResolving(onResolve);

  @override
  void updateRenderObject(BuildContext context, _RenderResolving renderObject) {
    renderObject.onResolve = onResolve;
    renderObject.markNeedsLayout();
  }
}

class _RenderResolving extends RenderBox with MotionResolveHost {
  _RenderResolving(this.onResolve);

  VoidCallback onResolve;

  @override
  void performLayout() {
    size = constraints.constrain(const Size(10, 10));
    scheduleResolve();
  }

  @override
  void resolve() => onResolve();
}
