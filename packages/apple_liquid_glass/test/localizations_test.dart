import 'dart:io';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _German extends DefaultGlassLocalizations {
  const _German();

  @override
  String get sheetGrabberLabel => 'Blattgriff';
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

Future<GlassLocalizations> _read(
  WidgetTester tester, {
  List<LocalizationsDelegate<Object?>>? delegates,
}) async {
  late GlassLocalizations strings;
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFF000000),
      localizationsDelegates: delegates,
      builder: (context, child) => Builder(
        builder: (context) {
          strings = GlassLocalizations.of(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return strings;
}

void main() {
  testWidgets('an app that loads no strings reads English', (tester) async {
    final strings = await _read(tester);
    expect(strings, isA<DefaultGlassLocalizations>());
    expect(strings.sheetGrabberLabel, 'Sheet grabber');
  });

  testWidgets('outside any Localizations it still reads English', (
    tester,
  ) async {
    late GlassLocalizations strings;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          strings = GlassLocalizations.of(context);
          return const SizedBox();
        },
      ),
    );
    expect(strings.popoverDismissLabel, 'Dismiss popover');
  });

  testWidgets('an app replaces the strings with its own delegate', (
    tester,
  ) async {
    final strings = await _read(
      tester,
      delegates: const [
        _GermanDelegate(),
        DefaultWidgetsLocalizations.delegate,
      ],
    );
    expect(strings.sheetGrabberLabel, 'Blattgriff');
    expect(strings.sheetDismissLabel, 'Dismiss sheet');
  });

  testWidgets('the default delegate loads English', (tester) async {
    final strings = await _read(
      tester,
      delegates: const [
        DefaultGlassLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
    );
    expect(strings.alertLabel, 'Alert');
  });

  test('the English values of the controls', () {
    const strings = DefaultGlassLocalizations();
    expect(strings.backButtonLabel, 'Back');
    expect(strings.closeButtonLabel, 'Close');
    expect(strings.searchLabel, 'Search');
    expect(strings.clearTextLabel, 'Clear text');
    expect(strings.moreInfoLabel, 'More info');
    expect(strings.pageValue(2, 5), 'page 2 of 5');
    expect(strings.incrementLabel, 'Increment');
    expect(strings.decrementLabel, 'Decrement');
    expect(strings.percentValue(0.426), '43%');
    expect(strings.sheetDetentValue(1, 3), 'Detent 1 of 3');
  });

  test('every string has a caller in the widgets, so no widget says its '
      'own words in place of one', () {
    const declaring = 'lib/src/foundation/localizations.dart';
    final declared = File(declaring).readAsStringSync();
    final members = [
      for (final match in RegExp(
        r'^  String (?:get )?(\w+)(?:\(.*\))?;$',
        multiLine: true,
      ).allMatches(declared))
        match.group(1)!,
    ];
    expect(members, hasLength(greaterThan(30)));
    final sources = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            !file.path.endsWith(declaring.substring(4)))
          file.readAsStringSync(),
    ].join('\n').replaceAll(RegExp('//.*'), '');
    expect(
      [
        for (final member in members)
          if (!RegExp('\\.$member\\b').hasMatch(sources)) member,
      ],
      isEmpty,
    );
  });
}
