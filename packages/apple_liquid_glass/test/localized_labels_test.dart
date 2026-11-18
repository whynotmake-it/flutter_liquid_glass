import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _German extends DefaultGlassLocalizations {
  const _German();

  @override
  String get searchLabel => 'Suche';

  @override
  String get loadingLabel => 'Laden';
}

class _GermanDelegate extends LocalizationsDelegate<GlassLocalizations> {
  const _GermanDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<GlassLocalizations> load(Locale locale) =>
      SynchronousFuture<GlassLocalizations>(const _German());

  @override
  bool shouldReload(_GermanDelegate old) => false;
}

Widget _app(Widget child) => MediaQuery(
  data: const MediaQueryData(
    size: Size(402, 874),
    devicePixelRatio: 3,
    padding: EdgeInsets.only(top: 62, bottom: 34),
  ),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Localizations(
      locale: const Locale('de'),
      delegates: const [
        _GermanDelegate(),
        DefaultWidgetsLocalizations.delegate,
      ],
      child: GlassScope(renderer: const FlatGlassRenderer(), child: child),
    ),
  ),
);

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('the search circle of the tab bar reads the localized label', (
    tester,
  ) async {
    await _phone(tester);
    final search = GlassSearchController();
    addTearDown(search.dispose);
    await tester.pumpWidget(
      _app(
        GlassTabScaffold(
          tabBar: GlassTabBar(
            destinations: [
              for (final name in ['Home', 'Library'])
                GlassTabDestination(
                  icon: const SizedBox.square(dimension: 24),
                  label: Text(name),
                ),
            ],
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            searchController: search,
          ),
          tabBuilder: (context, i) => const SizedBox(),
          searchBuilder: (context) => const SizedBox(),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Suche'), findsOneWidget);
    expect(find.bySemanticsLabel('Search'), findsNothing);
  });

  testWidgets('a deferred menu group loads under the localized title', (
    tester,
  ) async {
    await _phone(tester);
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        localizationsDelegates: const [
          _GermanDelegate(),
          DefaultWidgetsLocalizations.delegate,
        ],
        pageRouteBuilder: <T>(settings, builder) =>
            GlassPageRoute<T>(builder: builder, settings: settings),
        builder: (context, child) =>
            GlassScope(renderer: const FlatGlassRenderer(), child: child!),
        home: Align(
          alignment: const Alignment(0, -0.6),
          child: GlassMenuAnchor(
            menuChildren: [
              GlassMenuDeferred(() => Completer<List<GlassMenuEntry>>().future),
            ],
            builder: (context, controller, child) => GlassButton(
              onPressed: controller.open,
              child: const Text('More'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('More'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Laden'), findsOneWidget);
    expect(find.text('Loading...'), findsNothing);
  });
}
