import 'package:apple_liquid_glass/src/motions/bar_frames.dart';
import 'package:apple_liquid_glass/src/motions/bar_layout.dart';
import 'package:flutter_test/flutter_test.dart';

GlassBarCapsuleSpec _icons(List<String> ids, [double glyph = 22]) =>
    GlassBarCapsuleSpec([
      for (final id in ids)
        GlassBarButtonSpec(id, glyph, GlassBarButtonKind.icon),
    ]);

GlassBarCapsuleSpec _label(String id, double text) => GlassBarCapsuleSpec([
  GlassBarButtonSpec(id, text, GlassBarButtonKind.label),
]);

const _back = GlassBarCapsuleSpec([
  GlassBarButtonSpec('back', 0, GlassBarButtonKind.back),
]);

List<GlassBarCapsuleLayout> _nav({
  List<GlassBarCapsuleSpec> leading = const [],
  List<GlassBarCapsuleSpec> trailing = const [],
  bool rtl = false,
}) => layoutGlassBar(
  leading: leading,
  trailing: trailing,
  width: 402,
  top: 62,
  leadingInset: 16,
  trailingInset: 16,
  metrics: GlassBarMetrics.navigation,
  rtl: rtl,
);

void _expectCapsule(
  GlassBarCapsuleLayout capsule, {
  required double cx,
  required double w,
  double cy = 84,
  double h = 44,
}) {
  expect(capsule.rect.center.dx, closeTo(cx, 0.1));
  expect(capsule.rect.width, closeTo(w, 0.1));
  expect(capsule.rect.center.dy, closeTo(cy, 0.1));
  expect(capsule.rect.height, h);
}

void main() {
  test('the navigation bar lays its capsules out as the navseg pages read '
      'on the device', () {
    _expectCapsule(
      _nav(
        trailing: [
          _icons(['plus']),
        ],
      ).single,
      cx: 364,
      w: 44,
    );
    final page1 = _nav(
      leading: [_back],
      trailing: [
        _icons(['share']),
      ],
    );
    _expectCapsule(page1[0], cx: 38, w: 44);
    _expectCapsule(page1[1], cx: 364, w: 44);
    final page2 = _nav(
      leading: [_label('cancel', 54)],
      trailing: [
        _icons(['share2', 'heart'], 25.85),
      ],
    );
    _expectCapsule(page2[0], cx: 59, w: 86);
    _expectCapsule(page2[1], cx: 334.2, w: 103.7);
    final page4 = _nav(
      leading: [_back],
      trailing: [
        _icons(['heart4']),
        _label('done', 41.7),
      ],
    );
    _expectCapsule(page4[1], cx: 349.2, w: 73.7);
    _expectCapsule(page4[2], cx: 278.3, w: 44);
    expect(page4[1].id, (GlassBarSegment.trailing, 0));
    expect(page4[2].id, (GlassBarSegment.trailing, 1));
    expect(page4.every((c) => c.anonymous), isTrue);
  });

  test('items sit in their capsule, the back button fills its own', () {
    final page2 = _nav(
      trailing: [
        _icons(['share2', 'heart'], 25.85),
      ],
    );
    final items = page2.single.items;
    expect(items[0].rect.left, closeTo(page2.single.rect.left + 4, 1e-9));
    expect(items[1].rect.left - items[0].rect.right, closeTo(16, 1e-9));
    expect(items[0].rect.height, 36);
    final back = _nav(
      leading: [
        const GlassBarCapsuleSpec([
          GlassBarButtonSpec('back', 40, GlassBarButtonKind.back),
        ]),
      ],
    ).single;
    expect(back.rect.width, closeTo(12 + 16.33 + 6 + 40 + 17, 1e-9));
    expect(back.items.single.rect, back.rect);
  });

  test('the toolbar keeps 28 from the sides and centers the runs between '
      'flexible spaces', () {
    List<GlassBarCapsuleLayout> toolbar({
      List<GlassBarCapsuleSpec> leading = const [],
      List<GlassBarCapsuleSpec> trailing = const [],
      List<List<GlassBarCapsuleSpec>> center = const [],
    }) => layoutGlassBar(
      leading: leading,
      trailing: trailing,
      center: center,
      width: 402,
      top: 798,
      leadingInset: 28,
      trailingInset: 28,
      metrics: GlassBarMetrics.toolbar,
    );
    final ends = toolbar(
      leading: [
        _icons(['trash']),
      ],
      trailing: [
        _icons(['compose']),
      ],
    );
    _expectCapsule(ends[0], cx: 52, w: 48, cy: 822, h: 48);
    _expectCapsule(ends[1], cx: 350, w: 48, cy: 822, h: 48);
    final middle = toolbar(
      center: [
        [
          _icons(['play']),
        ],
      ],
    ).single;
    expect(middle.rect.center.dx, closeTo(201, 1e-9));
    expect(middle.segment, (GlassBarSegment.center, 0));
  });

  test('right to left mirrors the bar', () {
    final rtl = _nav(
      leading: [_back],
      trailing: [
        _icons(['share']),
      ],
      rtl: true,
    );
    _expectCapsule(rtl[0], cx: 402 - 38, w: 44);
    _expectCapsule(rtl[1], cx: 402 - 364, w: 44);
  });

  test('a capsule is never narrower than tall', () {
    final narrow = _nav(
      trailing: [
        const GlassBarCapsuleSpec([
          GlassBarButtonSpec('dot', 10, GlassBarButtonKind.custom),
        ]),
      ],
    ).single;
    expect(narrow.rect.width, 44);
    expect(narrow.items.single.rect.center.dx, narrow.rect.center.dx);
  });
}
