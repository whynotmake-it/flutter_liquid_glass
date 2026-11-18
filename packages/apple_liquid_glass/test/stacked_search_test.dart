import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

Widget _app(
  TextEditingController search,
  ScrollController scroll, {
  double keyboard = 0,
  VoidCallback? onItem,
}) => MediaQuery(
  data: MediaQueryData(
    size: const Size(402, 874),
    devicePixelRatio: 3,
    padding: const EdgeInsets.only(top: 62, bottom: 34),
    viewInsets: EdgeInsets.only(bottom: keyboard),
  ),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(
      renderer: const FlatGlassRenderer(),
      child: GlassPageScaffold(
        navigationBar: GlassNavigationBar(
          largeTitle: const Text('Notes'),
          trailing: [
            if (onItem != null)
              GlassBarItem(
                onPressed: onItem,
                icon: const SizedBox.square(key: Key('item'), dimension: 24),
              ),
          ],
          searchField: GlassSearchField(
            key: const Key('field'),
            controller: search,
          ),
        ),
        child: GlassContentScroll(
          child: ListView(
            controller: scroll,
            children: [
              for (var i = 0; i < 40; i++)
                SizedBox(height: 50, child: Text('Row $i')),
            ],
          ),
        ),
      ),
    ),
  ),
);

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(_frame);
  }
}

Rect _field(WidgetTester tester) =>
    tester.getRect(find.byKey(const Key('field')));

double _lift(WidgetTester tester) => 168 - _field(tester).top;

double _opacityAbove(WidgetTester tester, Finder child) => tester
    .widget<MotionTransition>(
      find.ancestor(of: child, matching: find.byType(MotionTransition)).first,
    )
    .opacity!
    .value;

// Steps at 120 Hz and reads the large title's opacity against the lift, and
// returns the opacity at each of [lifts], interpolated.
Future<List<double>> _fadeAgainstLift(
  WidgetTester tester,
  List<double> lifts,
) async {
  final title = find.text('Notes').last;
  final samples = <(double, double)>[
    (_lift(tester), _opacityAbove(tester, title)),
  ];
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(microseconds: 8333));
    samples.add((_lift(tester), _opacityAbove(tester, title)));
  }
  return [
    for (final lift in lifts)
      () {
        for (var i = 1; i < samples.length; i++) {
          final (a, oa) = samples[i - 1];
          final (b, ob) = samples[i];
          if ((a - lift) * (b - lift) <= 0 && a != b) {
            return oa + (ob - oa) * (lift - a) / (b - a);
          }
        }
        throw StateError('the page never passed a lift of $lift');
      }(),
  ];
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('at rest the field stands under the large title, 44 points '
      'tall, 16 from the sides and 10 above the content', (tester) async {
    await _phone(tester);
    final search = TextEditingController();
    final scroll = ScrollController();
    addTearDown(search.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_app(search, scroll));
    await tester.pump();
    expect(_field(tester), const Rect.fromLTRB(16, 168, 386, 212));
    expect(tester.getTopLeft(find.text('Row 0')).dy, 222);
  });

  testWidgets('the field keeps its placeholder out of its glass, which a '
      'surface fades with its content', (tester) async {
    await _phone(tester);
    final search = TextEditingController();
    final scroll = ScrollController();
    addTearDown(search.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_app(search, scroll));
    await tester.pump();
    final placeholder = find.descendant(
      of: find.byKey(const Key('field')),
      matching: find.byType(Text),
    );
    expect(placeholder, findsOneWidget);
    expect(
      find.ancestor(of: placeholder, matching: find.byType(GlassSurface)),
      findsNothing,
    );
  });

  testWidgets('a scroll folds the field away before the large title moves', (
    tester,
  ) async {
    await _phone(tester);
    final search = TextEditingController();
    final scroll = ScrollController();
    addTearDown(search.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_app(search, scroll));
    await tester.pump();
    final title = find.text('Notes').last;
    final rest = tester.getTopLeft(title).dy;
    scroll.jumpTo(30);
    await tester.pump();
    expect(tester.getTopLeft(title).dy, rest);
    await tester.tapAt(_field(tester).center);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.context?.widget,
      isNot(isA<EditableText>()),
      reason: 'a field folded past half takes no touch',
    );
    scroll.jumpTo(80);
    await tester.pump();
    expect(tester.getTopLeft(title).dy, rest - (80 - 54));
  });

  testWidgets('focused, the page rises until the field sits under the status '
      'bar, the field narrows and the close button ends the search', (
    tester,
  ) async {
    await _phone(tester);
    final search = TextEditingController();
    final scroll = ScrollController();
    addTearDown(search.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_app(search, scroll));
    await tester.pump();
    await tester.tap(find.byKey(const Key('field')));
    await _settle(tester);
    expect(_field(tester), const Rect.fromLTRB(16, 62, 332, 106));
    expect(tester.getTopLeft(find.text('Row 0')).dy, 222 - 106);
    final close = find.bySemanticsLabel('Close');
    expect(tester.getCenter(close).dx, closeTo(386 - 22, 1));
    search.text = 'milk';
    await tester.tap(close);
    await _settle(tester);
    expect(search.text, isEmpty);
    expect(_field(tester), const Rect.fromLTRB(16, 168, 386, 212));
    expect(tester.getTopLeft(find.text('Row 0')).dy, 222);
  });

  testWidgets('the large title fades in time, on the way up and on the way '
      'back, as the layers of an iPhone 16 Pro do', (tester) async {
    await _phone(tester);
    final search = TextEditingController();
    final scroll = ScrollController();
    addTearDown(search.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_app(search, scroll));
    await tester.pump();
    final title = find.text('Notes').last;
    expect(_opacityAbove(tester, title), 1);

    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    const lifts = [20.0, 30.0, 40.0, 50.0, 60.0];
    final up = await _fadeAgainstLift(tester, lifts);
    for (final (i, native) in const [0.36, 0.23, 0.14, 0.085, 0.047].indexed) {
      expect(up[i], closeTo(native, 0.04), reason: 'up, lift ${lifts[i]}');
    }
    await _settle(tester);
    expect(_opacityAbove(tester, title), lessThan(0.001));

    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pump();
    final back = await _fadeAgainstLift(tester, lifts);
    for (final (i, native) in const [0.36, 0.20, 0.067, 0.0, 0.0].indexed) {
      expect(back[i], closeTo(native, 0.06), reason: 'back, lift ${lifts[i]}');
    }
    await _settle(tester);
    expect(_opacityAbove(tester, title), greaterThan(0.999));
  });

  testWidgets('the bar item stays where it is and fades while the field rises '
      'through its spot, and takes no touch once it has faded', (tester) async {
    await _phone(tester);
    final search = TextEditingController();
    final scroll = ScrollController();
    addTearDown(search.dispose);
    addTearDown(scroll.dispose);
    var pressed = 0;
    await tester.pumpWidget(_app(search, scroll, onItem: () => pressed++));
    await tester.pump();
    final item = find.byKey(const Key('item'));
    final rest = tester.getRect(item);
    expect(_opacityAbove(tester, item), 1);

    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(_frame);
    }
    expect(_lift(tester), greaterThan(10));
    expect(tester.getRect(item), rest);
    final fading = _opacityAbove(tester, item);
    expect(fading, inExclusiveRange(0, 1));
    expect(fading, _opacityAbove(tester, find.text('Notes').last));

    await _settle(tester);
    expect(tester.getRect(item), rest);
    expect(_opacityAbove(tester, item), lessThan(0.001));
    await tester.tapAt(rest.center);
    await tester.pump();
    expect(pressed, 0);
  });

  testWidgets('an open search that goes away leaves the bar shown', (
    tester,
  ) async {
    await _phone(tester);
    final search = TextEditingController();
    final scroll = ScrollController();
    addTearDown(search.dispose);
    addTearDown(scroll.dispose);
    late StateSetter set;
    var searching = true;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          set = setState;
          return MediaQuery(
            data: const MediaQueryData(
              size: Size(402, 874),
              devicePixelRatio: 3,
              padding: EdgeInsets.only(top: 62, bottom: 34),
            ),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: GlassScope(
                renderer: const FlatGlassRenderer(),
                child: GlassPageScaffold(
                  navigationBar: GlassNavigationBar(
                    largeTitle: const Text('Notes'),
                    searchField: searching
                        ? GlassSearchField(
                            key: const Key('field'),
                            controller: search,
                          )
                        : null,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          );
        },
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('field')));
    await _settle(tester);
    final title = find.text('Notes').last;
    expect(_opacityAbove(tester, title), lessThan(0.001));
    set(() => searching = false);
    await _settle(tester);
    expect(_opacityAbove(tester, title), 1);
    expect(tester.getTopLeft(title).dy, 62 + 54 + 3.67);
  });
}
