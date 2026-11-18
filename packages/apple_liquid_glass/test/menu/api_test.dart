import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/menu_event.dart';
import 'package:apple_liquid_glass/src/motions/menu_layout.dart';
import 'package:apple_liquid_glass/src/motions/menu_metrics.dart';
import 'package:apple_liquid_glass/src/motions/menu_motion.dart';
import 'package:apple_liquid_glass/src/motions/menu_placed.dart';
import 'package:apple_liquid_glass/src/motions/menu_tuning.dart';
import 'package:apple_liquid_glass/src/motions/menu_values.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_content.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_entries.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

const _dir = 'test/fixtures/ios27-device/menu_api';

List<Map<String, Object?>> _rows(String name) => [
  for (final line in Fixtures.lines('$_dir/$name.jsonl'))
    if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
];

double _n(Map<String, Object?> row, String key) =>
    (row[key]! as num).toDouble();

final Map<String, Object?> _layoutJson = jsonDecode(
  Fixtures.read('$_dir/layout.json'),
) as Map<String, Object?>;

Map<String, Object?> _section(String key) =>
    _layoutJson['layout']! as Map<String, Object?>;

const _sort = GlassMenuSection(
  title: 'Sort by',
  singleSelection: true,
  children: [
    GlassMenuItem(
      title: 'Name',
      icon: Icon(IconData(1)),
      state: GlassMenuItemState.on,
    ),
    GlassMenuItem(title: 'Date', icon: Icon(IconData(2))),
    GlassMenuItem(title: 'Size', icon: Icon(IconData(3))),
  ],
);

const _rich1 = <GlassMenuEntry>[
  _sort,
  GlassMenuSection(
    children: [
      GlassMenuItem(
        title: 'Show hidden',
        icon: Icon(IconData(4)),
        state: GlassMenuItemState.on,
      ),
      GlassMenuItem(
        title: 'Mixed state',
        icon: Icon(IconData(5)),
        state: GlassMenuItemState.mixed,
      ),
    ],
  ),
  GlassMenuSection(
    children: [
      GlassMenuItem(
        title: 'With subtitle',
        subtitle: 'A second line of detail',
        icon: Icon(IconData(6)),
      ),
      GlassMenuItem(
        title: 'Disabled row',
        icon: Icon(IconData(7)),
        enabled: false,
      ),
      GlassMenuItem(
        title: 'Delete',
        icon: Icon(IconData(8)),
        destructive: true,
      ),
    ],
  ),
];

const _rich2 = <GlassMenuEntry>[
  GlassMenuSection(
    title: 'Color',
    palette: true,
    children: [
      GlassMenuItem(title: 'Red', icon: Icon(IconData(1))),
      GlassMenuItem(title: 'Orange', icon: Icon(IconData(1))),
      GlassMenuItem(title: 'Green', icon: Icon(IconData(1))),
      GlassMenuItem(title: 'Blue', icon: Icon(IconData(1)), state: .on),
      GlassMenuItem(title: 'Purple', icon: Icon(IconData(1))),
    ],
  ),
  GlassMenuSection(
    elementSize: .small,
    children: [
      GlassMenuItem(title: 'Cut', icon: Icon(IconData(2))),
      GlassMenuItem(title: 'Copy', icon: Icon(IconData(2))),
      GlassMenuItem(title: 'Paste', icon: Icon(IconData(2))),
      GlassMenuItem(title: 'Share', icon: Icon(IconData(2))),
    ],
  ),
  GlassMenuSection(
    elementSize: .medium,
    children: [
      GlassMenuItem(title: 'Bold', icon: Icon(IconData(3))),
      GlassMenuItem(title: 'Italic', icon: Icon(IconData(3))),
      GlassMenuItem(title: 'Underline', icon: Icon(IconData(3))),
    ],
  ),
  GlassMenuSection(
    title: 'Inline submenu',
    children: [
      GlassMenuItem(title: 'Inline one'),
      GlassMenuItem(title: 'Inline two'),
    ],
  ),
  GlassMenuItem(title: 'Plain row', icon: Icon(IconData(4))),
];

const _deeper = GlassSubmenu(
  title: 'Deeper',
  icon: Icon(IconData(13)),
  children: [
    GlassMenuItem(title: 'Deep one'),
    GlassMenuItem(title: 'Deep two'),
  ],
);

final _log = <String>[];

final _sub = <GlassMenuEntry>[
  const GlassMenuItem(title: 'Copy', icon: Icon(IconData(1))),
  const GlassMenuItem(title: 'Share', icon: Icon(IconData(2))),
  GlassSubmenu(
    title: 'More',
    icon: const Icon(IconData(3)),
    children: [
      GlassMenuItem(
        title: 'Sub one',
        icon: const Icon(IconData(11)),
        onPressed: () => _log.add('Sub one'),
      ),
      GlassMenuItem(
        title: 'Sub two',
        icon: const Icon(IconData(12)),
        onPressed: () => _log.add('Sub two'),
      ),
      _deeper,
    ],
  ),
  const GlassMenuItem(
    title: 'Delete',
    icon: Icon(IconData(4)),
    destructive: true,
  ),
];

Rect _element(MenuLayout layout, String title) {
  for (final element in layout.elements) {
    final entry = element.entry;
    final name = switch (entry) {
      GlassMenuItem(:final title) => title,
      GlassSubmenu(:final title) => title,
      _ => element.title,
    };
    if (name == title) return element.rect;
  }
  throw StateError('no $title');
}

MenuMotion _motion(
  List<GlassMenuEntry> entries, {
  MenuTuning tuning = MenuTuning.standard,
}) {
  final content = MenuContent(onChanged: ({required bool animate}) {});
  content.entries = entries;
  final motion = MenuMotion(
    tuning: tuning,
    source: MenuSource(
      Rect.fromCenter(
        center: const Offset(201, 150),
        width: 48,
        height: 48,
      ),
    ),
    layout: content.root,
    bounds: const Size(402, 874),
    padding: const EdgeInsets.only(top: 62, bottom: 34),
  );
  motion.submenuLayout = content.submenu;
  return motion;
}

/// Replays [name]: the first stroke opens the menu (at its lift, without
/// the tap delay), every later touch is fed at its time, shifted by the
/// difference between our menu's top and the device's; [check] runs at
/// every logged frame after the second stroke starts.
void _replay(
  String name,
  MenuMotion motion,
  void Function(double t, Map<String, Object?> frame) check, {
  double? deviceTop,
}) {
  final rows = _rows(name);
  final touches = rows.where((Map<String, Object?> r) => r['k'] == 'touch');
  final lift = touches.firstWhere((Map<String, Object?> r) => r['phase'] == 3);
  final menu = rows.firstWhere(
    (Map<String, Object?> r) =>
        r['k'] == 'frame' && r['cls'] == '_UIContextMenuView',
  );
  final t0 = _n(lift, 't');
  motion.open(0, sourceScale: 1);
  motion.advance(1);
  final top = deviceTop ?? _n(menu, 'y') - _n(menu, 'h') / 2;
  final dy = motion.menuRect.top - top;
  var started = false;
  for (final row in rows) {
    final t = _n(row, 't') - t0;
    if (t <= 1) continue;
    if (row['k'] == 'touch') {
      final at = Offset(_n(row, 'x'), _n(row, 'y') + dy);
      switch (row['phase']) {
        case 0:
          started = true;
          motion.pointerDown(t, at);
        case 1:
          motion.pointerMove(t, at);
        case 3:
          motion.pointerUp(t, at);
      }
    } else if (row['k'] == 'frame' && started) {
      motion.advance(t);
      check(t, row);
    }
  }
}

double _rms(List<double> errors) => errors.isEmpty
    ? 0
    : math.sqrt(
        errors.fold<double>(0, (double a, double e) => a + e * e) /
            errors.length,
      );

Rect _windowCard(MenuMotion motion, int index) {
  final card = motion.cards[index];
  final width = motion.menuWidth;
  final local = index == 0
      ? Rect.fromLTWH(0, 0, width, motion.visibleRootHeight)
      : card.rect;
  final content = motion.contentRect;
  final scale = motion.contentScale;
  return Rect.fromLTWH(
    content.left + (width / 2 + (local.left - width / 2) * card.scale) * scale,
    content.top + local.top * card.scale * scale,
    local.width * card.scale * scale,
    local.height * card.scale * scale,
  );
}

void main() {
  group('layout (device view tree)', () {
    test('the measured metrics match layout.json', () {
      final layout = _section('layout');
      const m = MenuMetrics.standard;
      expect(m.width, layout['menu_width']);
      expect(m.rowHeight, layout['row_height']);
      expect(m.subtitleRowHeight, layout['row_height_with_subtitle']);
      expect(m.topInset, layout['top_inset']);
      expect(
        m.maxHeight,
        (layout['max_height']! as Map<String, Object?>)['value'],
      );
      final header = layout['section_header']! as Map<String, Object?>;
      expect(m.headerHeight, header['height']);
    });

    test('titles of the default size keep the measured metrics', () {
      const m = MenuMetrics.standard;
      expect(m.scaled(titleSize: 17, availableWidth: 402), same(m));
      expect(m.scaled(titleSize: 14, availableWidth: 402), same(m));
    });

    test('at the third accessibility text size the menu is 370 wide on a '
        'phone, its rows 96.67 tall and a plain title 314 wide', () {
      final m = MenuMetrics.standard.scaled(titleSize: 40, availableWidth: 402);
      expect(m.width, 370);
      expect(m.rowHeight, closeTo(96.67, 1e-9));
      expect(m.plainTitleStart, 28);
      expect(m.titleEnd - m.plainTitleStart, 314);
      expect(m.width - m.chevronCenter, 31);

      final layout = MenuLayout.build(
        menuSpecs(_rich1, loadingLabel: 'Loading...'),
        metrics: m,
      );
      expect(layout.width, 370);
      for (final target in layout.targets) {
        expect(target.rect.right, lessThanOrEqualTo(370));
      }
    });

    test('larger titles grow the menu no wider than the space allows, and '
        'never narrower than it is', () {
      const m = MenuMetrics.standard;
      expect(
        m.scaled(titleSize: 19, availableWidth: 402).width,
        closeTo(278.3, 0.1),
      );
      expect(m.scaled(titleSize: 53, availableWidth: 402).width, 370);
      expect(
        m.scaled(titleSize: 53, availableWidth: 1200).width,
        closeTo(759.3, 0.1),
      );
      expect(m.scaled(titleSize: 53, availableWidth: 200).width, 250);
    });

    test('rich1: header, selection column, gaps, subtitle row', () {
      final layout = MenuLayout.build(
        menuSpecs(_rich1, loadingLabel: 'Loading...'),
      );
      expect(_element(layout, 'Sort by').top, 0);
      final tops = {
        'Name': 38.33,
        'Date': 80.33,
        'Size': 122.33,
        'Show hidden': 185.33,
        'Mixed state': 227.33,
        'With subtitle': 290.33,
        'Disabled row': 350.33,
        'Delete': 392.33,
      };
      for (final MapEntry(key: title, value: top) in tops.entries) {
        expect(
          _element(layout, title).top,
          moreOrLessEquals(top, epsilon: 0.02),
          reason: title,
        );
      }
      expect(_element(layout, 'With subtitle').height, 60);
      expect(layout.height, moreOrLessEquals(444.33, epsilon: 0.02));
      final name = layout.elements.firstWhere(
        (MenuPlaced e) =>
            e.entry is GlassMenuItem &&
            (e.entry! as GlassMenuItem).title == 'Name',
      );
      expect(name.checkCenter, moreOrLessEquals(27.7, epsilon: 0.05));
      expect(name.imageCenter, 55);
      expect(name.titleStart, 79);
      expect(name.titleEnd - name.titleStart, 143);
      final header = layout.elements.firstWhere(
        (MenuPlaced e) => e.kind == MenuPlacedKind.header,
      );
      expect(header.titleStart, 43);
      final separators = layout.elements.where(
        (MenuPlaced e) => e.kind == MenuPlacedKind.separator,
      );
      expect(separators.length, 2);
      expect(
        separators.first.rect.center.dy,
        moreOrLessEquals(164.33 + 10.5, epsilon: 0.02),
      );
      expect(separators.first.rect.left, 24);
      expect(separators.first.rect.right, 226);
      final disabled = layout.targets.where(
        (MenuTarget t) => (t.entry! as GlassMenuItem).title == 'Disabled row',
      );
      expect(disabled, isEmpty, reason: 'a disabled row takes no touch');
    });

    test('rich2: palette, small and medium cells, inline header', () {
      final layout = MenuLayout.build(
        menuSpecs(_rich2, loadingLabel: 'Loading...'),
      );
      final palette = layout.elements
          .where((MenuPlaced e) => e.kind == MenuPlacedKind.palette)
          .toList();
      expect(palette.length, 5);
      const xs = <double>[18.33, 61, 103.67, 146.33, 189];
      for (var i = 0; i < 5; i++) {
        expect(palette[i].rect.left, moreOrLessEquals(xs[i], epsilon: 0.03));
        expect(palette[i].rect.top, moreOrLessEquals(28.33, epsilon: 0.02));
        expect(palette[i].rect.width, moreOrLessEquals(42.67, epsilon: 0.01));
        expect(palette[i].rect.height, 54);
      }
      final small = layout.elements
          .where((MenuPlaced e) => e.kind == MenuPlacedKind.small)
          .toList();
      expect(small.first.rect.left, 8);
      expect(small.first.rect.top, moreOrLessEquals(82.33, epsilon: 0.02));
      expect(small.first.rect.width, moreOrLessEquals(58.33, epsilon: 0.2));
      expect(small.first.rect.height, moreOrLessEquals(51.67, epsilon: 0.01));
      final medium = layout.elements
          .where((MenuPlaced e) => e.kind == MenuPlacedKind.medium)
          .toList();
      expect([for (final e in medium) e.rect.left], [8, 86, 164]);
      expect(medium.first.rect.top, moreOrLessEquals(135, epsilon: 0.02));
      expect(
        _element(layout, 'Inline submenu').top,
        moreOrLessEquals(213, epsilon: 0.02),
      );
      expect(
        _element(layout, 'Inline one').top,
        moreOrLessEquals(251.33, epsilon: 0.02),
      );
      expect(
        _element(layout, 'Plain row').top,
        moreOrLessEquals(356.33, epsilon: 0.02),
      );
      expect(layout.height, moreOrLessEquals(408.33, epsilon: 0.02));
      final inline = layout.elements.firstWhere(
        (MenuPlaced e) =>
            e.entry is GlassMenuItem &&
            (e.entry! as GlassMenuItem).title == 'Inline one',
      );
      final plain = layout.elements.firstWhere(
        (MenuPlaced e) =>
            e.entry is GlassMenuItem &&
            (e.entry! as GlassMenuItem).title == 'Plain row',
      );
      expect(inline.titleStart, 28);
      expect(plain.titleStart, 64);
      expect(plain.imageCenter, 40);
    });

    test('a submenu card: header 62, rows after the inset', () {
      final layout = MenuLayout.build(
        menuSpecs(
          (_sub[2] as GlassSubmenu).children,
          loadingLabel: 'Loading...',
        ),
        header: menuRowSpec(_sub[2]),
      );
      expect(_element(layout, 'More').height, 62);
      expect(_element(layout, 'Sub one').top, 72);
      expect(layout.height, moreOrLessEquals(208, epsilon: 0.5));
      expect(layout.targets.first.kind, MenuTargetKind.back);
      expect(
        layout.targets.last.kind,
        MenuTargetKind.submenu,
        reason: 'Deeper opens the next card',
      );
    });

    test('a loading deferred group is one 42 pt row', () {
      final layout = MenuLayout.build(
        menuSpecs(
          [
            const GlassMenuItem(title: 'Copy', icon: Icon(IconData(1))),
            GlassMenuDeferred(() async => const []),
          ],
          loadingLabel: 'Loading...',
          resolve: (GlassMenuDeferred deferred) => null,
        ),
      );
      expect(layout.loading, isTrue);
      expect(layout.height, 104);
      final loading = layout.elements.last;
      expect(loading.kind, MenuPlacedKind.loading);
      expect(loading.imageCenter, 40);
      expect(loading.titleStart, 64);
    });

    test('an upward menu reverses groups and rows, a fixed order does not', () {
      final up = MenuLayout.build(
        menuSpecs(_rich1, loadingLabel: 'Loading...'),
        reversed: true,
      );
      expect(_element(up, 'Delete').top, lessThan(_element(up, 'Name').top));
      expect(_element(up, 'Sort by').top, lessThan(_element(up, 'Size').top));
      final content = MenuContent(onChanged: ({required bool animate}) {});
      content.entries = _rich1;
      content.order = GlassMenuOrder.fixed;
      final fixed = content.root(reversed: true);
      expect(
        _element(fixed, 'Name').top,
        lessThan(_element(fixed, 'Delete').top),
      );
    });

    test('right to left mirrors the cells', () {
      final layout = MenuLayout.build(
        menuSpecs(_rich2, loadingLabel: 'Loading...'),
        rtl: true,
      );
      final palette = layout.elements
          .where((MenuPlaced e) => e.kind == MenuPlacedKind.palette)
          .toList();
      expect(
        palette.first.rect.right,
        moreOrLessEquals(250 - 18.33, epsilon: 0.03),
      );
    });
  });

  group('submenu motion (device frames)', () {
    test('a tap opens the card: the menu grows, the root shrinks', () {
      final motion = _motion(_sub);
      final heights = <double>[];
      final widths = <double>[];
      final cardErrors = <double>[];
      final rootId = _listViewId('mm-sub-tap');
      _replay('mm-sub-tap', motion, (t, frame) {
        if (t > 4.5) return;
        if (frame['cls'] == '_UIContextMenuView') {
          final q = motion.cards.length < 2 ? 0.0 : motion.cards[1].progress;
          heights.add(q - (_n(frame, 'h') - 250) / 37.2);
        }
        if (frame['cls'] == '_UIContextMenuListView') {
          if ('${frame['id']}' == rootId) {
            widths.add(motion.rootBlob.rect.width - _n(frame, 'w'));
          } else if (motion.cards.length > 1) {
            final card = motion.cards[1].rect;
            cardErrors.add(card.width - _n(frame, 'w'));
            cardErrors.add(card.height - _n(frame, 'h'));
          }
        }
      });
      expect(motion.cards.length, 2);
      expect(heights.length, greaterThan(20));
      expect(_rms(heights), lessThan(0.01), reason: 'card progress');
      expect(_rms(widths), lessThan(0.1), reason: 'root list width');
      expect(cardErrors.length, greaterThan(20));
      expect(_rms(cardErrors), lessThan(1), reason: 'card frame');
    });

    test('the root glass width and height replay the native parent list', () {
      final motion = _motion([
        ..._sub,
        GlassMenuWidget(
          height: 62,
          builder: (BuildContext context) => const SizedBox.shrink(),
        ),
      ]);
      final errors = <double>[];
      final rootId = _listViewId('mm-sub-tap');
      _replay('mm-sub-tap', motion, (t, frame) {
        if (t > 4.5 ||
            frame['cls'] != '_UIContextMenuListView' ||
            '${frame['id']}' != rootId) {
          return;
        }
        errors.add(motion.rootBlob.rect.width - _n(frame, 'w'));
        errors.add(motion.rootBlob.rect.height - _n(frame, 'h'));
      });
      expect(errors.length, greaterThan(40));
      expect(_rms(errors), lessThan(0.1));
      final path = Platform.environment['MENU_FRAME_DUMP'];
      if (path != null) {
        File('$path/root-replay.json').writeAsStringSync(
          jsonEncode({'samples': errors.length, 'rms_pt': _rms(errors)}),
        );
      }
    });

    test('the header sends the card back into its row', () {
      final motion = _motion(_sub);
      final errors = <double>[];
      String? cardId;
      var back = false;
      _replay('mm-sub-back', motion, (double t, Map<String, Object?> frame) {
        if (frame['cls'] != '_UIContextMenuListView') return;
        if (_n(frame, 'h') > 200 && _n(frame, 'h') < 215) {
          cardId = '${frame['id']}';
        }
        if ('${frame['id']}' != cardId || motion.cards.length < 2) return;
        if (_n(frame, 'h') < 205) back = true;
        if (!back) return;
        final card = motion.cards[1].rect;
        errors.add(card.height - _n(frame, 'h'));
        errors.add(card.width - _n(frame, 'w'));
      });
      expect(errors.length, greaterThan(20));
      expect(_rms(errors), lessThan(1.5));
    });

    test('a deeper card grows on its own spring', () {
      final motion = _motion(_sub);
      final errors = <double>[];
      _replay('mm-sub-deeper', motion, (double t, Map<String, Object?> frame) {
        if (frame['cls'] != '_UIContextMenuListView') return;
        if (motion.cards.length < 3 || t > 5) return;
        if (_n(frame, 'w') < 229 || _n(frame, 'h') > 168) return;
        if (_n(frame, 'w') > 249.9 && _n(frame, 'h') > 165) return;
        final card = motion.cards[2].rect;
        errors.add(card.height - _n(frame, 'h'));
      });
      expect(errors.length, greaterThan(8));
      expect(_rms(errors), lessThan(2));
      expect(
        motion.cards.first.scale,
        moreOrLessEquals(0.97 * 0.97, epsilon: 1e-3),
      );
    });

    test(
      'a held finger opens the card after the dwell and fires a sub row',
      () {
        _log.clear();
        final motion = _motion(_sub);
        final rows = _rows('mm-sub-slide2');
        final t0 = _n(rows.first, 't');
        final evt = rows.firstWhere(
          (Map<String, Object?> r) => r['k'] == 'evt',
        );
        final lift = rows.lastWhere(
          (Map<String, Object?> r) => r['k'] == 'touch' && r['phase'] == 3,
        );
        double? opened;
        double? fired;
        void deliver() {
          for (final event in motion.drainEvents()) {
            if (event case MenuActivated(:final time, :final target)) {
              fired = time;
              (target.entry! as GlassMenuItem).onPressed?.call();
            }
          }
        }

        var dy = 0.0;
        for (final row in rows) {
          final t = _n(row, 't') - t0;
          if (row['k'] != 'touch') continue;
          while (motion.now + 0.004 < t) {
            motion.advance(motion.now + 0.004);
            if (opened == null && motion.cards.length > 1) opened = motion.now;
          }
          if (motion.isOpen && dy == 0) dy = motion.menuRect.top - 118.33;
          final at = Offset(_n(row, 'x'), _n(row, 'y') + dy);
          switch (row['phase']) {
            case 0:
              motion.pointerDown(t, at);
            case 1:
              motion.pointerMove(t, at);
            case 3:
              motion.pointerUp(t, at);
          }
        }
        motion.advance(motion.now + 0.1);
        deliver();
        expect(opened, isNotNull);
        expect((opened! - 6.021).abs(), lessThan(0.06));
        expect(_log, ['Sub two']);
        expect(
          fired! - (_n(lift, 't') - t0),
          moreOrLessEquals(_n(evt, 't') - _n(lift, 't'), epsilon: 0.008),
        );
      },
    );
  });

  group('live resize (device frames)', () {
    test('added rows grow the menu, a removed one shrinks it', () {
      var count = 3;
      final content = MenuContent(onChanged: ({required bool animate}) {});
      List<GlassMenuEntry> entries() => [
        for (var i = 0; i < count; i++)
          GlassMenuItem(title: 'Row $i', keepsMenuOpen: true),
      ];
      content.entries = entries();
      final motion = MenuMotion(
        source: MenuSource(
          Rect.fromCenter(
            center: const Offset(201, 150),
            width: 48,
            height: 48,
          ),
        ),
        layout: content.root,
        bounds: const Size(402, 874),
        padding: const EdgeInsets.only(top: 62, bottom: 34),
      );
      motion.submenuLayout = content.submenu;
      final rows = _rows('mm-resize');
      final t0 = _n(
        rows.firstWhere(
          (Map<String, Object?> r) => r['k'] == 'touch' && r['phase'] == 3,
        ),
        't',
      );
      motion.open(0, sourceScale: 1);
      motion.advance(1);
      final errors = <double>[];
      final segments = <int, List<double>>{};
      final start = motion.menuRect.height;
      double? deviceStart;
      var touches = 0;
      for (final row in rows) {
        final t = _n(row, 't') - t0;
        if (t <= 1) continue;
        if (row['k'] == 'evt') {
          touches++;
          count += row['title'] == 'Add row' ? 1 : -1;
          content.entries = entries();
          motion.updateLayout(t);
        } else if (row['k'] == 'touch' && touches == 3) {
          break;
        } else if (row['k'] == 'frame' && row['cls'] == '_UIContextMenuView') {
          motion.advance(t);
          deviceStart ??= _n(row, 'h');
          errors.add(
            motion.menuRect.height - start - (_n(row, 'h') - deviceStart),
          );
          (segments[touches] ??= []).add(errors.last);
        }
      }
      expect(errors.length, greaterThan(100));
      expect(_rms(segments[1]!), lessThan(0.5), reason: 'first row added');
      expect(_rms(segments[3]!), lessThan(0.3), reason: 'row removed');
      expect(
        _rms(segments[2]!),
        lessThan(6),
        reason:
            'the second add started 0.02 s earlier after its action on the '
            'device than the first: the delay jitters with the display link',
      );
    });
  });
  group('continuous resize', () {
    List<GlassMenuEntry> rows(int count) => [
      for (var i = 0; i < count; i++)
        GlassMenuItem(title: 'Row $i', keepsMenuOpen: true),
    ];

    MenuMotion open(MenuContent content) {
      final motion = MenuMotion(
        source: MenuSource(
          Rect.fromCenter(
            center: const Offset(201, 150),
            width: 48,
            height: 48,
          ),
        ),
        layout: content.root,
        bounds: const Size(402, 874),
        padding: const EdgeInsets.only(top: 62, bottom: 34),
      );
      motion.submenuLayout = content.submenu;
      motion.open(0, sourceScale: 1);
      motion.advance(1);
      return motion;
    }

    test('content that grows every frame grows the menu while it grows', () {
      final content = MenuContent(onChanged: ({required bool animate}) {});
      content.entries = rows(2);
      final motion = open(content);
      final start = motion.visibleRootHeight;
      var t = 1.0;
      for (var count = 3; count <= 7; count++) {
        t += 1 / 60;
        content.entries = rows(count);
        motion.updateLayout(t);
      }
      expect(motion.visibleRootHeight, greaterThan(start));
      motion.advance(t + 2);
      expect(
        motion.visibleRootHeight,
        moreOrLessEquals(content.root(reversed: false).height, epsilon: 0.01),
      );
    });

    test('a change taken back before its delay resizes nothing', () {
      final content = MenuContent(onChanged: ({required bool animate}) {});
      content.entries = rows(3);
      final motion = open(content);
      final start = motion.visibleRootHeight;
      content.entries = rows(4);
      motion.updateLayout(1.001);
      content.entries = rows(3);
      motion.updateLayout(1.002);
      for (var t = 1.01; t < 2; t += 0.01) {
        motion.advance(t);
        expect(motion.visibleRootHeight, moreOrLessEquals(start));
      }
    });
  });
  group('touches around a submenu, as on an iPhone 16 Pro', () {
    MenuMotion opened() {
      final motion = _motion([
        ..._sub,
        for (var i = 0; i < 5; i++) GlassMenuItem(title: 'Row $i'),
      ]);
      motion.open(0, sourceScale: 1);
      motion.advance(1);
      final more = _element(motion.layout, 'More');
      motion.pointerDown(1, motion.menuRect.topLeft + more.center);
      motion.pointerUp(1.02, motion.menuRect.topLeft + more.center);
      motion.advance(3);
      expect(motion.cards, hasLength(2));
      return motion;
    }

    Rect shownCard(MenuMotion motion) {
      final rest = motion.cards[1].rect.shift(motion.menuRect.topLeft);
      final flex = motion.cardFlex(1);
      return Rect.fromCenter(
        center: rest.center + flex.shift,
        width: rest.width + flex.width,
        height: rest.height + flex.height,
      );
    }

    test('a finger on the card stretches the card alone and lights it; a lift '
        'off the menu leaves it open and chooses nothing', () {
      final motion = opened();
      final rest = shownCard(motion);
      final root = motion.rootBlob.rect;
      final start = rest.center.translate(0, 31);
      motion.pointerDown(3, start);
      for (var i = 1; i <= 10; i++) {
        motion.pointerMove(3 + i * 0.05, start.translate(0, 22.3 * i));
      }
      motion.advance(5);
      final stretched = shownCard(motion);
      // The device, settled under the still finger: a card of 250 x 208, the
      // finger 31 points below its center, then 223 points down.
      expect(stretched.width, moreOrLessEquals(243.6, epsilon: 1));
      expect(stretched.height, moreOrLessEquals(213.3, epsilon: 1));
      expect(
        stretched.center.dy - rest.center.dy,
        moreOrLessEquals(8.2, epsilon: 1),
      );
      expect(
        motion.rootBlob.rect.top,
        moreOrLessEquals(root.top, epsilon: 0.2),
      );
      expect(
        motion.rootBlob.rect.height,
        moreOrLessEquals(root.height, epsilon: 0.2),
      );
      expect(motion.rootGlow, isNull);
      expect(motion.cardGlow(1), isNotNull);
      final past = Offset(rest.center.dx, motion.menuRect.bottom + 19);
      motion.pointerMove(5, past);
      motion.pointerUp(5.1, past);
      motion.advance(8);
      expect(motion.cards, hasLength(2));
      expect(motion.isOpen, isTrue);
      expect(shownCard(motion).height, moreOrLessEquals(208, epsilon: 0.1));
    });

    test('a finger on the parent under the card moves, lights and highlights '
        'nothing; its lift in place closes the card', () {
      final motion = opened();
      final card = shownCard(motion);
      final root = motion.rootBlob.rect;
      final parent = Offset(card.center.dx, card.bottom + 6);
      expect(motion.rootBlob.rect.contains(parent), isTrue);
      motion.pointerDown(3, parent);
      motion.pointerMove(3.05, parent.translate(0, 8));
      motion.advance(4);
      expect(
        motion.rootBlob.rect.height,
        moreOrLessEquals(root.height, epsilon: 0.2),
      );
      expect(
        shownCard(motion).height,
        moreOrLessEquals(card.height, epsilon: 0.01),
      );
      expect(motion.touchGlow, isNull);
      motion.pointerUp(4, parent);
      motion.advance(6);
      expect(motion.cards, hasLength(1));
      expect(motion.isOpen, isTrue);
    });

    test('a finger from the parent lifted far past the menu does nothing', () {
      final motion = opened();
      final card = shownCard(motion);
      final parent = Offset(card.center.dx, card.bottom + 6);
      motion.pointerDown(3, parent);
      motion.pointerMove(3.1, Offset(parent.dx, motion.menuRect.bottom + 140));
      motion.pointerUp(3.2, Offset(parent.dx, motion.menuRect.bottom + 140));
      motion.advance(5);
      expect(motion.cards, hasLength(2));
      expect(motion.isOpen, isTrue);
    });
  });

  group('touches beside the menu, as on an iPhone 16 Pro', () {
    MenuMotion opened() {
      final motion = _motion(_sub);
      motion.open(0, sourceScale: 1);
      motion.advance(1);
      return motion;
    }

    test('a still finger holds the menu open and closes it at the lift', () {
      final motion = opened();
      final beside = motion.menuRect.centerRight.translate(6, 0);
      motion.pointerDown(1, beside);
      motion.advance(2.2);
      expect(motion.isOpen, isTrue);
      motion.pointerUp(2.2, beside);
      motion.advance(2.2 + MenuTuning.standard.dismissDelay + 0.001);
      expect(motion.isOpen, isFalse);
    });

    test('a finger that moves closes it, and sliding onto a row highlights '
        'and chooses nothing', () {
      final motion = opened();
      final beside = motion.menuRect.centerRight.translate(6, 0);
      motion.pointerDown(1, beside);
      motion.pointerMove(1.03, beside.translate(-10, 0));
      expect(motion.isOpen, isTrue);
      expect(motion.rowAt(beside.translate(-10, 0)), isNotNull);
      motion.advance(1.03);
      expect(motion.highlighted, isNull);
      motion.pointerMove(1.08, beside.translate(-20, 0));
      expect(motion.isOpen, isFalse);
      _log.clear();
      motion.pointerUp(1.1, beside.translate(-20, 0));
      motion.advance(2);
      expect(_log, isEmpty);
    });
  });

  group('idle frames', () {
    test('a finger resting on a submenu row lets the clock doze until the '
        'card opens', () {
      final motion = _motion(_sub);
      motion.open(0, sourceScale: 1);
      motion.advance(1);
      expect(motion.isSettled, isTrue);
      expect(motion.wakeTime, isNull);
      final more = _element(motion.layout, 'More');
      motion.pointerDown(1, motion.menuRect.topLeft + more.center);
      motion.advance(1.01);
      expect(
        motion.wakeTime,
        moreOrLessEquals(1 + MenuTuning.standard.flexDelay),
        reason: 'nothing moves before the flex takes up the touch',
      );
      motion.advance(1.4);
      expect(motion.isSettled, isFalse);
      expect(
        motion.wakeTime,
        moreOrLessEquals(1 + MenuTuning.standard.hoverOpenDelay),
      );
      motion.advance(motion.wakeTime!);
      expect(motion.cards, hasLength(2));
      expect(motion.wakeTime, isNull);
    });
  });
  group('submenu close and hand-back (device frames + film)', () {
    test(
      'a closing card reverses continuously, including its pending start',
      () {
        for (final delay in [0.001, 0.08, 0.15, 0.24]) {
          final motion = _motion(_sub);
          motion.open(0, sourceScale: 1);
          motion.advance(1);
          final more = motion.layout.targets.indexWhere(
            (MenuTarget target) => target.kind == MenuTargetKind.submenu,
          );
          motion.select(1, more);
          motion.advance(2);
          final settled = _windowCard(motion, 1);
          motion.close(2);
          motion.advance(2 + delay);
          final before = _windowCard(motion, 1);
          motion.open(2 + delay);
          final after = _windowCard(motion, 1);
          expect(after.left, closeTo(before.left, 1e-8));
          expect(after.top, closeTo(before.top, 1e-8));
          expect(after.width, closeTo(before.width, 1e-8));
          expect(after.height, closeTo(before.height, 1e-8));
          motion.advance(4);
          final restored = _windowCard(motion, 1);
          expect(restored.left, closeTo(settled.left, 0.05));
          expect(restored.top, closeTo(settled.top, 0.05));
          expect(restored.width, closeTo(settled.width, 0.05));
          expect(restored.height, closeTo(settled.height, 0.05));
        }
      },
    );

    for (final name in ['mm-sub-tap', 'mm-sub-back', 'mm-sub-deeper']) {
      test('$name opening and hand-back replay native window bounds', () {
        final fit = jsonDecode(
          Fixtures.read('$_dir/card-container.json'),
        ) as Map<String, Object?>;
        final records = fit['records']! as Map<String, Object?>;
        final record = records[name]! as Map<String, Object?>;
        final motion = _motion(
          [
            ..._sub,
            GlassMenuWidget(
              height: 62,
              builder: (BuildContext context) => const SizedBox.shrink(),
            ),
          ],
          tuning: MenuTuning(
            submenuDelay: _n(record, 'submenu_delay'),
            deeperSubmenuDelay:
                (record['deeper_delay'] as num?)?.toDouble() ?? 0.04,
            backDelay: (record['back_delay'] as num?)?.toDouble() ?? 0.022,
          ),
        );
        final rows = _rows(name);
        final initial = rows.firstWhere(
          (Map<String, Object?> row) =>
              row['k'] == 'frame' && row['cls'] == '_UIContextMenuView',
        );
        final listIds = rows
            .where((row) => row['cls'] == '_UIContextMenuListView')
            .map((row) => '${row['id']}')
            .toSet()
            .toList();
        double? dy;
        final errors = <double>[];
        final frames = <Map<String, Object?>>[];
        _replay(name, motion, (double t, Map<String, Object?> row) {
          dy ??=
              motion.menuRect.top - (_n(initial, 'y') - _n(initial, 'h') / 2);
          if (!motion.isOpen || row['cls'] != '_UIContextMenuListView') return;
          final index = listIds.indexOf('${row['id']}');
          if (index < 0 || index >= motion.cards.length) return;
          final rect = _windowCard(motion, index);
          final expected = Rect.fromCenter(
            center: Offset(_n(row, 'x'), _n(row, 'y') + dy!),
            width: _n(row, 'w'),
            height: _n(row, 'h'),
          );
          errors.addAll([
            rect.center.dx - expected.center.dx,
            rect.center.dy - expected.center.dy,
            rect.width - expected.width,
            rect.height - expected.height,
          ]);
          frames.add({
            't': t,
            'index': index,
            'actual': [rect.left, rect.top, rect.width, rect.height],
            'native': [
              expected.left,
              expected.top,
              expected.width,
              expected.height,
            ],
          });
        });
        final path = Platform.environment['MENU_FRAME_DUMP'];
        if (path != null) {
          File('$path/opening-$name.json').writeAsStringSync(
            jsonEncode({'rms_pt': _rms(errors), 'frames': frames}),
          );
        }
        expect(frames.length, greaterThan(50));
        expect(_rms(errors), lessThan(1.5), reason: '$name window bounds');
      });
    }

    for (final name in ['mm-sub-select', 'mm-sub-tap', 'mm-sub-deeper']) {
      test('$name closing cards replay their native window bounds', () {
        final fit = jsonDecode(
          Fixtures.read('$_dir/card-container.json'),
        ) as Map<String, Object?>;
        final records = fit['records']! as Map<String, Object?>;
        final record = records[name]! as Map<String, Object?>;
        final motion = _motion(
          [
            ..._sub,
            GlassMenuWidget(
              height: 62,
              builder: (BuildContext context) => const SizedBox.shrink(),
            ),
          ],
          tuning: MenuTuning(
            dismissDelay: _n(record, 'start_after_lift'),
            submenuCloseDelay: _n(record, 'start_after_lift'),
          ),
        );
        final rows = _rows(name);
        final initial = rows.firstWhere(
          (Map<String, Object?> row) =>
              row['k'] == 'frame' && row['cls'] == '_UIContextMenuView',
        );
        final listIds = rows
            .where((row) => row['cls'] == '_UIContextMenuListView')
            .map((row) => '${row['id']}')
            .toSet()
            .toList();
        double? dy;
        final errors = <double>[];
        final frames = <Map<String, Object?>>[];
        _replay(name, motion, (double t, Map<String, Object?> row) {
          dy ??=
              motion.menuRect.top - (_n(initial, 'y') - _n(initial, 'h') / 2);
          if (!motion.isClosing || row['cls'] != '_UIContextMenuListView') {
            return;
          }
          final index = listIds.indexOf('${row['id']}');
          final cards = motion.cards;
          if (index < 0 || index >= cards.length) return;
          final card = cards[index];
          final alpha = index == cards.length - 1
              ? card.closeOpacity
              : motion.contentOpacity;
          if (alpha <= 0) return;
          final width = motion.menuWidth;
          final local = index == 0
              ? Rect.fromLTWH(0, 0, width, motion.visibleRootHeight)
              : card.rect;
          final rect = _windowCard(motion, index);
          final nativeScale = _n(row, 'w') / (local.width * card.scale);
          final expected = Rect.fromCenter(
            center: Offset(_n(row, 'x'), _n(row, 'y') + dy! * nativeScale),
            width: _n(row, 'w'),
            height: _n(row, 'h'),
          );
          errors.addAll([
            rect.center.dx - expected.center.dx,
            rect.center.dy - expected.center.dy,
            rect.width - expected.width,
            rect.height - expected.height,
          ]);
          frames.add({
            't': t,
            'index': index,
            'actual': [rect.left, rect.top, rect.width, rect.height],
            'native': [
              expected.left,
              expected.top,
              expected.width,
              expected.height,
            ],
          });
        });
        final path = Platform.environment['MENU_FRAME_DUMP'];
        if (path != null) {
          File('$path/carrier-$name.json').writeAsStringSync(
            jsonEncode({'rms_pt': _rms(errors), 'frames': frames}),
          );
        }
        expect(frames.length, greaterThan(25));
        expect(_rms(errors), lessThan(1), reason: '$name window bounds');
      });
    }

    double closeStart(String name) {
      final motion = _motion(_sub);
      final rows = _rows(name);
      final touches = rows
          .where((Map<String, Object?> r) => r['k'] == 'touch')
          .toList();
      final t0 = _n(touches.firstWhere((r) => r['phase'] == 3), 't');
      final lift = _n(touches.last, 't') - t0;
      motion.open(0, sourceScale: 1);
      motion.advance(1);
      final menu = rows.firstWhere(
        (Map<String, Object?> r) =>
            r['k'] == 'frame' && r['cls'] == '_UIContextMenuView',
      );
      final dy = motion.menuRect.top - (_n(menu, 'y') - _n(menu, 'h') / 2);
      for (final row in touches.skip(2)) {
        final t = _n(row, 't') - t0;
        while (motion.now + 0.001 < t) {
          motion.advance(motion.now + 0.001);
        }
        final at = Offset(_n(row, 'x'), _n(row, 'y') + dy);
        switch (row['phase']) {
          case 0:
            motion.pointerDown(t, at);
          case 3:
            motion.pointerUp(t, at);
        }
      }
      while (!motion.isClosing && motion.now < lift + 0.2) {
        motion.advance(motion.now + 0.001);
      }
      return motion.now - lift;
    }

    double deviceStart(String name) {
      final rows = _rows(name);
      final lift = _n(
        rows.lastWhere(
          (Map<String, Object?> r) => r['k'] == 'touch' && r['phase'] == 3,
        ),
        't',
      );
      String? before;
      for (final row in rows) {
        if (row['k'] != 'frame' || row['cls'] != '_UIContextMenuView') {
          continue;
        }
        final shape = '${row['w']} ${row['h']} ${row['y']}';
        if (_n(row, 't') > lift && before != null && shape != before) {
          return _n(row, 't') - lift;
        }
        before = shape;
      }
      throw StateError('no close in $name');
    }

    test('the menu glass closes with its container', () {
      final fixture = jsonDecode(
        Fixtures.read('$_dir/glass-close.json'),
      ) as Map<String, Object?>;
      final carriers =
          (jsonDecode(Fixtures.read('$_dir/card-container.json'))
                  as Map<String, Object?>)['records']!
              as Map<String, Object?>;
      final motion = _motion(_sub);
      motion.open(0, sourceScale: 1);
      motion.advance(1);
      final more = motion.layout.targets.indexWhere(
        (MenuTarget target) => target.kind == MenuTargetKind.submenu,
      );
      motion.select(1, more);
      motion.advance(2);
      final start = motion.rootBlob.rect.width;
      motion.close(2);
      final model = <double>[];
      for (var k = 0; k <= 480; k++) {
        motion.advance(2 + k / 1200);
        model.add(motion.rootBlob.rect.width / start);
      }
      double at(double t) {
        if (t <= 0) return 1;
        final x = t * 1200;
        final i = x.floor();
        if (i >= model.length - 1) return model.last;
        return model[i] + (model[i + 1] - model[i]) * (x - i);
      }

      final outside = <double>[];
      for (final MapEntry(:key, :value)
          in (fixture['records']! as Map<String, Object?>).entries) {
        final record = value! as Map<String, Object?>;
        final samples = [
          for (final raw in record['samples']! as List<Object?>)
            (raw! as List<Object?>).cast<num>(),
        ];
        final w0 = samples.first[1].toDouble();
        var best = (delay: 0.0, rms: double.infinity);
        for (var d = 0.0; d <= 0.1; d += 0.0005) {
          final errors = [
            for (final s in samples)
              if (s[0] < d + 0.3) w0 * at(s[0] - d) - s[1],
          ];
          final rms = _rms(errors);
          if (rms < best.rms) best = (delay: d, rms: rms);
        }
        expect(best.rms, lessThan(0.6), reason: key);
        final carrier = carriers[key] as Map<String, Object?>?;
        final lift = carrier?['start_after_lift'] as num?;
        if (lift != null) {
          expect(
            best.delay,
            moreOrLessEquals(lift.toDouble(), epsilon: 0.0015),
            reason: '$key glass and container start together',
          );
        }
        if (record['kind'] == 'outside') {
          outside.add(best.delay);
        } else {
          expect(
            best.delay,
            moreOrLessEquals(
              MenuTuning.standard.submenuCloseDelay,
              epsilon: 0.001,
            ),
          );
        }
      }
      outside.sort();
      expect(
        MenuTuning.standard.dismissDelay,
        inInclusiveRange(outside.first, outside.last + 0.001),
      );
      expect(MenuTuning.standard.cardContainerDelay, 0);
    });

    test('a card row closes the menu sooner than a touch outside it', () {
      final select = closeStart('mm-sub-select');
      final outside = closeStart('mm-sub-tap');
      final deviceSelect = deviceStart('mm-sub-select');
      final deviceOutside = deviceStart('mm-sub-tap');
      expect(select, moreOrLessEquals(0.031, epsilon: 0.002));
      expect(outside, moreOrLessEquals(0.059, epsilon: 0.002));
      expect(
        (deviceOutside - deviceSelect) - (outside - select),
        inInclusiveRange(-0.0085, 0.0085),
        reason:
            'the container shows the close a frame or two after it '
            'starts; the two closes keep their gap',
      );
      expect(
        (deviceSelect - select) - (deviceOutside - outside),
        inInclusiveRange(-0.0085, 0.0085),
      );
    });

    test('a card going back hands its header to its row', () {
      final motion = _motion(_sub);
      motion.open(0, sourceScale: 1);
      motion.advance(1);
      final more = motion.layout.targets.indexWhere(
        (MenuTarget target) => target.kind == MenuTargetKind.submenu,
      );
      motion.select(1, more);
      motion.advance(2);
      final row = motion.layout.targets[more].rect.center.dy;
      final open = motion.cards[1];
      expect(open.headerBold, 1);
      expect(open.chevronTurn, 1);
      expect(open.source, more);
      expect(open.contentTop + open.rect.top + 31, closeTo(row - 5, 1e-3));
      expect(motion.back(2), isTrue);
      double? last;
      MenuCard? card;
      for (var t = 2.0; t < 3.5; t += 0.001) {
        motion.advance(t);
        if (motion.cards.length < 2) break;
        card = motion.cards[1];
        final header = card.scale * (card.rect.top + card.contentTop + 31);
        final rowShown = motion.cards.first.scale * row;
        if (last != null) {
          expect((header - last).abs(), lessThan(0.5), reason: 'at $t');
        }
        last = header;
        if (card.progress < 0.01) {
          expect(header, closeTo(rowShown, 0.05));
        }
      }
      expect(card, isNotNull);
      expect(card!.headerBold, 0);
      expect(card.chevronTurn, 0);
      expect(card.rowsOpacity, 0);
      expect(card.platterOpacity, lessThan(0.2));
      expect(motion.cards.length, 1);
    });

    test('the open card shrinks with the close and fades late', () {
      final motion = _motion(_sub);
      motion.open(0, sourceScale: 1);
      motion.advance(1);
      final more = motion.layout.targets.indexWhere(
        (MenuTarget target) => target.kind == MenuTargetKind.submenu,
      );
      motion.select(1, more);
      motion.advance(2);
      final before = motion.contentRect;
      motion.close(2);
      motion.advance(2.0001);
      expect(motion.contentRect.top, closeTo(before.top, 0.5));
      expect(motion.cards.last.closeOpacity, greaterThan(0.95));
      var faded = false;
      for (var t = 2.0; t < 3; t += 0.004) {
        motion.advance(t);
        if (!motion.isPresented || motion.cards.length < 2) break;
        final p = motion.progress;
        final alpha = motion.cards.last.closeOpacity;
        if (p > 0.6) expect(alpha, greaterThan(0.4));
        if (p < 0.2 - 0.02) {
          expect(alpha, 0);
          faded = true;
        }
      }
      expect(faded, isTrue);
    });
  });
  group('submenu card look (device film and stills)', () {
    final film = jsonDecode(
      Fixtures.read('$_dir/film-sub.json'),
    ) as Map<String, Object?>;

    test('the pill left by a card going back fades out with it', () {
      final pill = film['back_pill_light']! as Map<String, Object?>;
      final rows = [
        for (final row in pill['rows']! as List<Object?>)
          [for (final v in row! as List<Object?>) (v! as num).toDouble()],
      ];
      const tuning = MenuTuning.standard;
      final spring = tuning.backSpring;
      final w = 2 * math.pi / spring.response;
      double q(double t) {
        final s = t - 0.105;
        return (1 + w * s) * math.exp(-w * s);
      }

      double shown(double t) => q(t) < tuning.cardGone
          ? 0
          : math.sqrt((q(t) / tuning.cardPlatterFade).clamp(0.0, 1.0));
      final base = rows.last[1];
      final first = rows[1];
      final scale = (first[1] - base) / shown(first[0]);
      for (final row in rows.skip(1).take(3)) {
        expect(
          base + scale * shown(row[0]),
          closeTo(row[1], 0.5),
          reason: 'at ${row[0]} s',
        );
      }
      expect(shown(rows.last[0]), 0);
      expect(shown(rows[rows.length - 2][0]), greaterThan(0));
    });
  });
}

/// The id of the root list view in capture [name].
String _listViewId(String name) {
  final view = _rows(
    name,
  ).firstWhere((r) => r['cls'] == '_UIContextMenuListView');
  return '${view['id']}';
}
