import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/motions/presence_motion.dart';
import 'package:apple_liquid_glass/src/motions/touch_glow.dart';
import 'package:apple_liquid_glass/src/surfaces/highlight.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);
const _body = Size(120, 44);
const _screen = ValueKey('screen');

Widget _app(
  GlassRenderer renderer,
  Widget child, {
  bool highContrast = false,
  bool reduceMotion = false,
}) => MediaQuery(
  data: MediaQueryData(highContrast: highContrast),
  child: MotionTraitsOverride(
    traits: MotionTraits(reduceMotion: reduceMotion),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: GlassScope(
        renderer: renderer,
        child: RepaintBoundary(
          key: _screen,
          child: ColoredBox(
            color: const Color(0xFFFFFFFF),
            child: Center(child: child),
          ),
        ),
      ),
    ),
  ),
);

Widget _surface(
  WidgetStatesController states, {
  MotionSelection<GlassFrame>? frame,
  Color? focusColor,
}) => SizedBox.fromSize(
  size: _body,
  child: GlassSurface.live(
    frame: frame ?? MotionSelection(() => const GlassFrame()),
    states: states,
    focusColor: focusColor,
    child: const SizedBox.expand(),
  ),
);

Color _cupertinoRing(Color base) =>
    HSLColor.fromColor(base.withValues(alpha: 0.8))
        .withLightness(0.69)
        .withSaturation(0.835)
        .toColor();

/// The ring's color of an untinted body at standard contrast.
final _ring = _cupertinoRing(GlassColors.systemBlue.color);

Future<GlassHighlightLook> _look(
  WidgetTester tester, {
  Color? focusColor,
  Color? base,
  bool highContrast = false,
}) async {
  late GlassHighlightLook look;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(highContrast: highContrast),
      child: Builder(
        builder: (context) {
          look = GlassHighlightLook.of(
            context,
            focusColor: focusColor,
            base: base,
          );
          return const SizedBox();
        },
      ),
    ),
  );
  return look;
}

RenderGlassHighlight _box(WidgetTester tester) =>
    tester.renderObject<RenderGlassHighlight>(find.byType(GlassHighlightBox));

bool _near(Color a, Color b) =>
    (a.a - b.a).abs() < 1e-3 &&
    (a.r - b.r).abs() < 1e-3 &&
    (a.g - b.g).abs() < 1e-3 &&
    (a.b - b.b).abs() < 1e-3;

/// The paths [finder] fills in a color near [color].
List<Path> _filled(WidgetTester tester, Finder finder, Color color) {
  final found = <Path>[];
  expect(
    finder,
    paints..everything((method, arguments) {
      if (method != #drawPath) return true;
      final paint = arguments[1] as Paint;
      if (paint.style == PaintingStyle.fill && _near(paint.color, color)) {
        found.add(arguments[0] as Path);
      }
      return true;
    }),
  );
  return found;
}

/// The color of the screen at [at], relative to the body's top left.
Future<Color> _pixel(WidgetTester tester, Offset at) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_screen),
  );
  final origin = tester.getTopLeft(find.byType(GlassSurface));
  final point = origin + at;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData();
    final width = image.width;
    image.dispose();
    final i = (point.dy.floor() * width + point.dx.floor()) * 4;
    return data!.buffer.asUint8List().sublist(i, i + 4);
  });
  return Color.fromARGB(bytes![3], bytes[0], bytes[1], bytes[2]);
}

/// Whether [color] is bluish, as the ring is over white.
bool _blue(Color color) => color.b - color.r > 0.15;

/// The focus rings [finder] paints.
List<Path> _rings(WidgetTester tester, Finder finder) =>
    _filled(tester, finder, _ring);

/// Whether [finder] paints the hover response.
bool _hovers(WidgetTester tester, Finder finder) =>
    _filled(tester, finder, GlassHighlights.hoverColor).isNotEmpty;

Future<void> _settle(WidgetTester tester, [int frames = 60]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(_frame);
  }
}

void main() {
  setUp(MotionClock.debugReset);

  test('the hover rule is a pressed wash at half strength on the glow '
      'spring', () {
    expect(GlassHighlights.hoverGain, 0.5);
    expect(
      GlassHighlights.hoverColor.a,
      closeTo(TouchGlowMotion.washOffset * GlassHighlights.hoverGain, 1e-6),
    );
    expect(GlassHighlights.hoverColor.a, closeTo(0.025, 1e-6));
    expect(
      HoverTuning.spring.response,
      TouchGlowTuning.fallSpring.response,
    );
    expect(
      HoverTuning.spring.resolve(reduceMotion: true).isImmediate,
      isTrue,
    );
  });

  testWidgets("the ring's color is Cupertino's", (tester) async {
    final ring = (await _look(
      tester,
      base: const Color(0xFF007AFF),
    )).focusColor;
    final hsl = HSLColor.fromColor(ring);
    expect(hsl.alpha, closeTo(0.8, 1e-3));
    expect(hsl.lightness, closeTo(0.69, 1e-2));
    expect(hsl.saturation, closeTo(0.835, 1e-2));
    expect(hsl.hue, closeTo(211, 1));
    const given = Color(0x80FF0000);
    expect((await _look(tester, focusColor: given)).focusColor, given);
    expect(
      (await _look(tester, focusColor: given, highContrast: true)).focusColor.a,
      1,
    );
  });

  testWidgets('a base without a hue rings in systemBlue, as Cupertino rings '
      'its default', (tester) async {
    for (final base in [
      const Color(0xFFFFFFFF),
      const Color(0xFF8E8E93),
      const Color(0xFF000000),
    ]) {
      final ring = (await _look(tester, base: base)).focusColor;
      expect(_near(ring, _ring), isTrue, reason: '$base');
    }
  });

  testWidgets('a part that draws no ring draws none under Increase '
      'Contrast either', (tester) async {
    final look = await _look(
      tester,
      focusColor: GlassHighlights.noRing,
      highContrast: true,
    );
    expect(look.focusColor.a, 0);
  });

  group('the flat renderer', () {
    const renderer = FlatGlassRenderer();

    testWidgets('a focused body fills the ring outside its shape', (
      tester,
    ) async {
      final states = WidgetStatesController({WidgetState.focused});
      addTearDown(states.dispose);
      await tester.pumpWidget(_app(renderer, _surface(states)));
      final ring = _rings(tester, find.byType(GlassSurface)).single;
      for (final outside in [
        Offset(_body.width + 1.75, _body.height / 2),
        Offset(_body.width / 2, -1.75),
        Offset(-1.75, _body.height / 2),
      ]) {
        expect(ring.contains(outside), isTrue, reason: '$outside');
      }
      for (final off in [
        Offset(_body.width / 2, _body.height / 2),
        Offset(_body.width - 2, _body.height / 2),
        Offset(_body.width + 4, _body.height / 2),
      ]) {
        expect(ring.contains(off), isFalse, reason: '$off');
      }
    });

    testWidgets('the ring follows a moving, stretched frame without a '
        'rebuild', (tester) async {
      final states = WidgetStatesController({WidgetState.focused});
      addTearDown(states.dispose);
      final x = MotionValue<double>(0);
      final frame = MotionSelection(
        () => GlassFrame(
          rect: Rect.fromLTWH(x.value, 0, _body.width, _body.height),
          scaleX: 1.2,
        ),
      );
      await tester.pumpWidget(_app(renderer, _surface(states, frame: frame)));
      final built = tester.state(find.byType(GlassSurface));
      x.snap(x.clock.now, 30);
      await tester.pump();
      expect(tester.state(find.byType(GlassSurface)), same(built));
      final right = 30 + _body.width / 2 + _body.width * 0.6;
      final toBody = Matrix4.inverted(frame.value.bodyIn(_body).toBox!);
      bool ringHas(Offset inBox) => _rings(
        tester,
        find.byType(GlassSurface),
      ).single.contains(MatrixUtils.transformPoint(toBody, inBox));
      expect(ringHas(Offset(right + 1.75, _body.height / 2)), isTrue);
      expect(ringHas(Offset(_body.width + 1.75, _body.height / 2)), isFalse);
    });

    testWidgets('a transparent focus color draws no ring', (tester) async {
      final states = WidgetStatesController({WidgetState.focused});
      addTearDown(states.dispose);
      const none = Color(0x00000000);
      await tester.pumpWidget(
        _app(renderer, _surface(states, focusColor: none)),
      );
      final surface = find.byType(GlassSurface);
      expect(_rings(tester, surface), isEmpty);
      expect(_filled(tester, surface, none), isEmpty);
    });

    testWidgets('a hovered body takes the wash', (tester) async {
      final states = WidgetStatesController({WidgetState.hovered});
      addTearDown(states.dispose);
      await tester.pumpWidget(_app(renderer, _surface(states)));
      await _settle(tester);
      expect(_hovers(tester, find.byType(GlassSurface)), isTrue);
      states.update(WidgetState.hovered, false);
      await _settle(tester);
      expect(_hovers(tester, find.byType(GlassSurface)), isFalse);
    });
  });

  for (final renderer in const [
    FlatGlassRenderer(),
    LiquidGlassRenderer(),
    FakeGlassRenderer(),
  ]) {
    group('${renderer.runtimeType}', () {
      final outside = Offset(_body.width + 1.75, _body.height / 2);

      testWidgets('draws the ring outside a focused body only', (
        tester,
      ) async {
        final states = WidgetStatesController();
        addTearDown(states.dispose);
        await tester.pumpWidget(_app(renderer, _surface(states)));
        expect(_blue(await _pixel(tester, outside)), isFalse);
        states.update(WidgetState.focused, true);
        await tester.pump();
        expect(_blue(await _pixel(tester, outside)), isTrue);
        expect(
          _blue(await _pixel(tester, Offset(_body.width / 2, 22))),
          isFalse,
        );
        states.update(WidgetState.focused, false);
        await tester.pump();
        expect(_blue(await _pixel(tester, outside)), isFalse);
      });

      testWidgets('the ring follows a moving frame', (tester) async {
        final states = WidgetStatesController({WidgetState.focused});
        addTearDown(states.dispose);
        final x = MotionValue<double>(0);
        final frame = MotionSelection(
          () => GlassFrame(
            rect: Rect.fromLTWH(x.value, 0, _body.width, _body.height),
          ),
        );
        await tester.pumpWidget(_app(renderer, _surface(states, frame: frame)));
        expect(_blue(await _pixel(tester, outside)), isTrue);
        x.snap(x.clock.now, 30);
        await tester.pump();
        expect(_blue(await _pixel(tester, outside)), isFalse);
        expect(_blue(await _pixel(tester, outside.translate(30, 0))), isTrue);
      });

      testWidgets('Increase Contrast draws an opaque ring', (tester) async {
        final states = WidgetStatesController({WidgetState.focused});
        addTearDown(states.dispose);
        await tester.pumpWidget(
          _app(renderer, _surface(states), highContrast: true),
        );
        final ring = _box(tester).highlight.look.focusColor;
        expect(ring.a, 1);
        expect(_near(ring, _ring), isFalse);
      });

      testWidgets('hover eases in and out', (tester) async {
        final states = WidgetStatesController();
        addTearDown(states.dispose);
        await tester.pumpWidget(_app(renderer, _surface(states)));
        final highlight = _box(tester).highlight;
        states.update(WidgetState.hovered, true);
        await tester.pump(_frame);
        await tester.pump(_frame);
        expect(highlight.hovered, inExclusiveRange(0, 0.9));
        await _settle(tester);
        expect(highlight.hovered, closeTo(1, 1e-3));
        states.update(WidgetState.hovered, false);
        await tester.pump(_frame);
        await tester.pump(_frame);
        expect(highlight.hovered, inExclusiveRange(0.1, 1));
        await _settle(tester);
        expect(highlight.hovered, 0);
      });

      testWidgets('under Reduce Motion hover switches at once', (
        tester,
      ) async {
        final states = WidgetStatesController();
        addTearDown(states.dispose);
        await tester.pumpWidget(
          _app(renderer, _surface(states), reduceMotion: true),
        );
        states.update(WidgetState.hovered, true);
        await tester.pump(_frame);
        expect(_box(tester).highlight.hovered, 1);
        states.update(WidgetState.hovered, false);
        await tester.pump(_frame);
        expect(_box(tester).highlight.hovered, 0);
      });
    });
  }

  testWidgets('a body without states paints exactly as before', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const FlatGlassRenderer(),
        SizedBox.fromSize(
          size: _body,
          child: const GlassSurface(child: SizedBox.expand()),
        ),
      ),
    );
    expect(find.byType(GlassHighlightBox), findsNothing);
  });

  testWidgets('a button focused from the keyboard draws the ring; a tap '
      'and a touch hover light nothing', (tester) async {
    await tester.pumpWidget(
      _app(
        const FlatGlassRenderer(),
        GlassButton(onPressed: () {}, child: const Text('Go')),
      ),
    );
    final button = find.byType(GlassButton);
    await tester.tap(button);
    await _settle(tester);
    expect(_rings(tester, button), isEmpty);
    expect(_box(tester).highlight.hovered, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    Focus.of(tester.element(find.text('Go'))).requestFocus();
    await _settle(tester, 2);
    expect(_rings(tester, button), hasLength(1));
    await tester.tap(button);
    await _settle(tester);
    expect(_rings(tester, button), isEmpty);
  });

  testWidgets('a mouse over a button eases its hover in', (tester) async {
    await tester.pumpWidget(
      _app(
        const FlatGlassRenderer(),
        GlassButton(onPressed: () {}, child: const Text('Go')),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(find.byType(GlassButton)),
    );
    await _settle(tester);
    expect(_box(tester).highlight.hovered, closeTo(1, 1e-3));
    await mouse.removePointer();
    await _settle(tester);
    expect(_box(tester).highlight.hovered, 0);
  });

  for (final (name, control) in <(String, Widget)>[
    ('switch', GlassSwitch(value: false, onChanged: (_) {})),
    ('slider', GlassSlider(value: 0.5, onChanged: (_) {})),
  ]) {
    testWidgets('a $name rings itself from the keyboard, not from a tap, '
        'and takes the hover', (tester) async {
      await tester.pumpWidget(
        _app(
          const FlatGlassRenderer(),
          SizedBox(width: 200, child: Center(child: control)),
        ),
      );
      final subject = find.byWidget(control);
      await tester.tap(subject);
      await _settle(tester);
      expect(_rings(tester, subject), isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      Focus.of(
        tester.element(
          find
              .descendant(of: subject, matching: find.byType(GlassSurface))
              .first,
        ),
      ).requestFocus();
      await _settle(tester, 2);
      expect(_rings(tester, subject), hasLength(1));
      await tester.tap(subject);
      await _settle(tester);
      expect(_rings(tester, subject), isEmpty);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(subject));
      await _settle(tester);
      final boxes = tester.renderObjectList<RenderGlassHighlight>(
        find.byType(GlassHighlightBox),
      );
      expect(boxes.map((box) => box.highlight.hovered), everyElement(1));
      await mouse.removePointer();
      await _settle(tester);
    });
  }

  group('a part that is not glass', () {
    Widget part(
      WidgetStatesController states, {
      bool inside = false,
      bool wash = false,
    }) => Builder(
      builder: (context) => SizedBox.fromSize(
        size: _body,
        child: GlassHighlightPaint.of(
          context,
          states: states,
          hoverColor: const Color(0x40FF0000),
          shape: const LiquidRoundedRectangle(radius: 0),
          inside: inside,
          wash: wash,
          child: const ColoredBox(color: Color(0xFF00FF00)),
        ),
      ),
    );

    for (final inside in [false, true]) {
      testWidgets('draws the ring ${inside ? 'inside' : 'outside'} its box', (
        tester,
      ) async {
        final states = WidgetStatesController({WidgetState.focused});
        addTearDown(states.dispose);
        await tester.pumpWidget(
          _app(const FlatGlassRenderer(), part(states, inside: inside)),
        );
        final rings = _rings(tester, find.byType(GlassHighlightPaint));
        expect(rings, hasLength(1));
        final box = Offset.zero & _body;
        final bounds = rings.single.getBounds();
        if (inside) {
          expect(bounds, box);
          expect(rings.single.contains(_body.center(Offset.zero)), isFalse);
        } else {
          expect(bounds, box.inflate(3.5));
          expect(rings.single.contains(const Offset(1, 1)), isFalse);
        }
        states.update(WidgetState.focused, false);
        await tester.pump();
        expect(_rings(tester, find.byType(GlassHighlightPaint)), isEmpty);
      });
    }

    for (final wash in [false, true]) {
      testWidgets(
        'fills its hover ${wash ? 'over the part as a wash' : 'under it'}',
        (tester) async {
          final states = WidgetStatesController({WidgetState.hovered});
          addTearDown(states.dispose);
          await tester.pumpWidget(
            _app(const FlatGlassRenderer(), part(states, wash: wash)),
          );
          await _settle(tester);
          final calls = <(Symbol, BlendMode)>[];
          expect(
            find.byType(GlassHighlightPaint),
            paints..everything((method, arguments) {
              if (method == #drawRect || method == #drawPath) {
                calls.add((method, (arguments[1] as Paint).blendMode));
              }
              return true;
            }),
          );
          expect(
            calls,
            wash
                ? [(#drawRect, BlendMode.srcOver), (#drawPath, BlendMode.plus)]
                : [
                    (#drawPath, BlendMode.srcOver),
                    (#drawRect, BlendMode.srcOver),
                  ],
          );
        },
      );
    }
  });

  /// Tabs into the part [inside] holds and returns its highlight.
  Future<GlassHighlight> focusFromKeyboard(
    WidgetTester tester,
    Finder inside,
  ) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    Focus.of(tester.element(inside)).requestFocus();
    await _settle(tester, 2);
    return tester
        .renderObject<RenderGlassHighlightPaint>(
          find.ancestor(of: inside, matching: find.byType(GlassHighlightPaint)),
        )
        .highlight;
  }

  testWidgets('a page control rings its capsule from the keyboard and shows '
      'half its platter under a mouse', (tester) async {
    await tester.pumpWidget(
      _app(
        const FlatGlassRenderer(),
        GlassPageControl(count: 4, page: 1, onChanged: (_) {}),
      ),
    );
    final control = find.byType(GlassPageControl);
    final paint = find.descendant(
      of: control,
      matching: find.byType(GlassHighlightPaint),
    );
    expect(_rings(tester, paint), isEmpty);
    final highlight = await focusFromKeyboard(
      tester,
      find.descendant(of: paint, matching: find.byType(CustomPaint)).first,
    );
    expect(highlight.focused, isTrue);
    expect(_rings(tester, paint), hasLength(1));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(control));
    await _settle(tester);
    expect(highlight.hovered, closeTo(1, 1e-3));
    final platter = GlassDynamicColor.resolve(
      const GlassDynamicColor.withBrightness(
        color: Color(0xFFF0F0F2),
        darkColor: Color(0xFF1F1F1F),
      ),
      tester.element(control),
    );
    expect(
      _filled(
        tester,
        paint,
        platter.withValues(alpha: GlassHighlights.hoverGain),
      ),
      hasLength(1),
    );
    await mouse.removePointer();
    await _settle(tester);
  });

  testWidgets('a focused list row rings inside its edge in place of a full '
      'fill, and a mouse fills it at half strength', (tester) async {
    await tester.pumpWidget(
      _app(
        const FlatGlassRenderer(),
        SizedBox(
          width: 402,
          child: GlassListSection(
            children: [
              GlassListRow(title: const Text('General'), onPressed: () {}),
            ],
          ),
        ),
      ),
    );
    final row = find.byType(GlassListRow);
    final overlay = GlassDynamicColor.resolve(
      GlassColors.systemGray4,
      tester.element(row),
    );
    final highlight = await focusFromKeyboard(tester, find.text('General'));
    expect(highlight.focused, isTrue);
    expect(_rings(tester, row), hasLength(1));
    expect(
      _rings(tester, row).single.getBounds().size,
      tester.getSize(row),
    );
    expect(_filled(tester, row, overlay), isEmpty);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(row));
    await _settle(tester);
    expect(
      _filled(
        tester,
        row,
        overlay.withValues(alpha: GlassHighlights.hoverGain),
      ),
      hasLength(1),
    );
    await mouse.removePointer();
    await _settle(tester);
  });

  testWidgets("a search field's clear button clears on a tap, takes the "
      'keyboard focus with a ring and the hover wash', (tester) async {
    final controller = TextEditingController(text: 'glass');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        const FlatGlassRenderer(),
        SizedBox(
          width: 340,
          child: GlassSearchField(controller: controller),
        ),
      ),
    );
    final clear = find.descendant(
      of: find.byType(GlassSearchField),
      matching: find.byType(GlassHighlightPaint),
    );
    expect(clear, findsOneWidget);
    final highlight = await focusFromKeyboard(
      tester,
      find.descendant(of: clear, matching: find.byType(CustomPaint)).first,
    );
    expect(highlight.focused, isTrue);
    expect(_rings(tester, clear), hasLength(1));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(clear));
    await _settle(tester);
    expect(highlight.hovered, closeTo(1, 1e-3));
    final field = tester.renderObject<RenderGlassHighlight>(
      find.byType(GlassHighlightBox),
    );
    expect(field.highlight.hovered, closeTo(1, 1e-3));
    expect(field.highlight.look.focusColor.a, 0);
    await mouse.removePointer();
    await tester.tap(clear);
    await _settle(tester);
    expect(controller.text, isEmpty);
  });

  testWidgets("a focused day's ring is opaque under Increase Contrast", (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _app(
        const FlatGlassRenderer(),
        SizedBox(
          width: 360,
          child: GlassDatePicker(
            value: DateTime(2026, 11, 17),
            onChanged: (_) {},
            focusNode: node,
          ),
        ),
        highContrast: true,
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    node.requestFocus();
    await _settle(tester, 2);
    final rings = <Color>[];
    expect(
      find.byType(GlassDatePicker),
      paints..everything((method, arguments) {
        if (method != #drawPath) return true;
        final path = arguments[0] as Path;
        final paint = arguments[1] as Paint;
        if (path.fillType == PathFillType.evenOdd &&
            paint.blendMode == BlendMode.srcOver) {
          rings.add(paint.color);
        }
        return true;
      }),
    );
    expect(rings, hasLength(1));
    expect(rings.single.a, 1);
    expect(_blue(rings.single), isTrue);
  });
}
