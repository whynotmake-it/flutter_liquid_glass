import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_appearance.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(MotionClock.debugReset);

  Future<List<String>> pumpMenu(
    WidgetTester tester, {
    VoidCallback? onPressed,
    GlassMenuStyle? style,
    GlassMenuStyle? themeStyle,
  }) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final log = <String>[];
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(settings, builder) =>
            GlassPageRoute<T>(builder: builder, settings: settings),
        builder: (context, child) => GlassScope(
          renderer: const FlatGlassRenderer(),
          data: GlassThemeData(
            styles: [?themeStyle],
          ),
          child: child!,
        ),
        home: Center(
          child: GlassMenuAnchor(
            key: const Key('source'),
            style: style,
            menuChildren: [
              for (final title in ['Copy', 'Share'])
                GlassMenuItem(title: title, onPressed: () => log.add(title)),
              GlassMenuItem(
                title: 'Delete',
                destructive: true,
                onPressed: () => log.add('Delete'),
              ),
            ],
            builder: (context, controller, child) => RawGlassButton(
              onPressed: onPressed ?? controller.open,
              builder: (context, details) => details.label,
              child: child!,
            ),
            child: const SizedBox(width: 120, height: 44, child: Text('Face')),
          ),
        ),
      ),
    );
    return log;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets(
    'a raw button whose action opens the menu opens it on a tap and '
    'chooses a row',
    (
      tester,
    ) async {
      final log = await pumpMenu(tester);
      await tester.tap(find.byKey(const Key('source')));
      await settle(tester);
      expect(find.text('Copy'), findsOneWidget);
      await tester.tap(find.text('Copy'));
      await settle(tester);
      expect(log, ['Copy']);
      expect(find.text('Copy'), findsNothing);
    },
  );

  testWidgets('with onPressed a tap calls it and opens no menu', (
    tester,
  ) async {
    var pressed = 0;
    await pumpMenu(tester, onPressed: () => pressed++);
    await tester.tap(find.byKey(const Key('source')));
    await settle(tester);
    expect(pressed, 1);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('the theme styles the rows and the menu style overrides it', (
    tester,
  ) async {
    Color? color(String title) => tester
        .renderObject<RenderParagraph>(find.text(title))
        .text
        .style
        ?.color;
    await pumpMenu(
      tester,
      themeStyle: const GlassMenuStyle(
        textStyle: TextStyle(color: Color(0xFF00AA00)),
        destructiveColor: Color(0xFFAA00AA),
      ),
      style: const GlassMenuStyle(destructiveColor: Color(0xFF0000AA)),
    );
    await tester.tap(find.byKey(const Key('source')));
    await settle(tester);
    expect(color('Copy'), const Color(0xFF00AA00));
    expect(color('Delete'), const Color(0xFF0000AA));
  });

  testWidgets('a row field the theme style leaves null keeps its default', (
    tester,
  ) async {
    Color? color(String title) => tester
        .renderObject<RenderParagraph>(find.text(title))
        .text
        .style
        ?.color;
    await pumpMenu(
      tester,
      themeStyle: const GlassMenuStyle(
        textStyle: TextStyle(color: Color(0xFF00AA00)),
      ),
    );
    await tester.tap(find.byKey(const Key('source')));
    await settle(tester);
    expect(color('Copy'), const Color(0xFF00AA00));
    expect(color('Delete'), MenuAppearance.light.destructiveColor);
  });
}
