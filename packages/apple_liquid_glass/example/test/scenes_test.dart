import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/app.dart';
import 'package:apple_liquid_glass_example/scenes/lava_page.dart';
import 'package:apple_liquid_glass_example/scenes/lens_page.dart';
import 'package:apple_liquid_glass_example/scenes/pads_page.dart';
import 'package:apple_liquid_glass_example/settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

Future<void> _frames(WidgetTester tester, [int count = 60]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(_frame);
  }
}

// Opens [scene] as the gallery does: pushed over a page.
Future<void> _open(
  WidgetTester tester,
  Widget scene, {
  GalleryRenderer renderer = GalleryRenderer.flat,
}) async {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    GalleryApp(
      settings: GallerySettings(renderer: renderer),
      home: _Launcher(scene),
    ),
  );
  await _frames(tester, 10);
  await tester.tap(find.text('Open scene'));
  await _frames(tester, 90);
}

class _Launcher extends StatelessWidget {
  const _Launcher(this.scene);

  final Widget scene;

  @override
  Widget build(BuildContext context) => Center(
    child: GestureDetector(
      onTap: () => Navigator.of(
        context,
      ).push(GlassPageRoute<void>(builder: (context) => scene)),
      child: const Text('Open scene'),
    ),
  );
}

void main() {
  // Real glass with `--enable-impeller --enable-flutter-gpu`, fake without.
  for (final (name, page) in const <(String, Widget)>[
    ('Lava', LavaPage()),
    ('Pads', PadsPage()),
    ('Lens', LensPage()),
  ]) {
    testWidgets("$name draws with liquid glass, under the gallery's bar", (
      tester,
    ) async {
      await _open(tester, page, renderer: GalleryRenderer.liquid);
      expect(find.byType(GlassSurface), findsWidgets);
      expect(find.bySemanticsLabel('Settings'), findsOneWidget);
      await _frames(tester, 30);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Lava: the drops move by themselves, and the buttons add and '
      'take them', (tester) async {
    await _open(tester, const LavaPage());
    Iterable<GlassSurface> drops() => tester
        .widgetList<GlassSurface>(
          find.descendant(
            of: find.descendant(
              of: find.byType(LavaPage),
              matching: find.byType(GlassGroup),
            ),
            matching: find.byType(GlassSurface),
          ),
        )
        .where((surface) => surface.frame != null);
    expect(drops(), hasLength(9));
    final before = [for (final drop in drops()) drop.frame!.value.rect];
    await _frames(tester);
    final after = [for (final drop in drops()) drop.frame!.value.rect];
    expect(after, isNot(before));

    await tester.tap(find.bySemanticsLabel('Add a drop'));
    await _frames(tester, 10);
    expect(drops(), hasLength(10));
    await tester.tap(find.bySemanticsLabel('Take a drop'));
    await tester.tap(find.bySemanticsLabel('Take a drop'));
    await _frames(tester, 10);
    expect(drops(), hasLength(8));
  });

  testWidgets('Pads: a pressed pad fills with its color, and two fingers '
      'play two pads', (tester) async {
    await _open(tester, const PadsPage());
    List<GlassSurface> pads() => [
      ...tester
          .widgetList<GlassSurface>(
            find.descendant(
              of: find.byType(PadsPage),
              matching: find.byType(GlassSurface),
            ),
          )
          .where((surface) => surface.frame?.value.tint != null),
    ];
    expect(pads(), hasLength(16));
    double filled(int pad) => pads()[pad].frame!.value.tintAmount;
    expect(filled(0), 0);

    final notes = find.descendant(
      of: find.byType(PadsPage),
      matching: find.text('C'),
    );
    final first = await tester.startGesture(tester.getCenter(notes.at(0)));
    final second = await tester.startGesture(
      tester.getCenter(notes.at(1)),
      pointer: 99,
    );
    await _frames(tester, 30);
    expect(filled(0), greaterThan(0.8));
    expect(filled(5), greaterThan(0.8));
    expect(filled(1), 0);

    await first.up();
    await second.up();
    await _frames(tester, 90);
    expect(filled(0), closeTo(0, 0.01));

    // The pattern plays without a finger.
    await tester.tap(find.bySemanticsLabel('Play'));
    await _frames(tester, 30);
    expect(
      [for (var i = 0; i < 16; i++) filled(i)].any((f) => f > 0.1),
      isTrue,
    );
    await tester.tap(find.bySemanticsLabel('Stop'));
    await _frames(tester, 90);
  });

  testWidgets('Lens: the lens follows the finger, and a second one joins '
      'it', (tester) async {
    await _open(tester, const LensPage());
    final page = find.byType(LensPage);
    Finder lenses() => find.descendant(
      of: find.descendant(of: page, matching: find.byType(GlassGroup)),
      matching: find.byType(GlassSurface),
    );
    expect(lenses(), findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(lenses()));
    // The first move is the recognizer's slop.
    await gesture.moveBy(const Offset(30, 30));
    await _frames(tester, 2);
    final before = tester.getCenter(lenses());
    await gesture.moveBy(const Offset(40, 60));
    await _frames(tester, 2);
    final moved = tester.getCenter(lenses()) - before;
    expect(moved.dx, closeTo(40, 0.01));
    expect(moved.dy, closeTo(60, 0.01));
    await gesture.up();

    final size = tester.getSize(lenses());
    await tester.tap(find.text('Capsule'));
    await _frames(tester);
    expect(tester.getSize(lenses()).width, greaterThan(size.width));

    await tester.tap(find.bySemanticsLabel('Add a lens'));
    await _frames(tester);
    expect(lenses(), findsNWidgets(2));
  });
}
