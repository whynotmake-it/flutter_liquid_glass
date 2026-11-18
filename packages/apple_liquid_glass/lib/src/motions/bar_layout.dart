import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/bar_frames.dart';
import 'package:apple_liquid_glass/src/motions/search_motion.dart';
import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// The measured geometry of a bar's glass buttons, read from the view
/// frames iOS 27 lays out (iPhone 16 Pro, 402 points; the simulator's
/// iPhone 18 Pro Max at 440; bars passport).
@immutable
class GlassBarMetrics {
  /// Creates metrics from explicit values.
  const GlassBarMetrics({
    required this.capsuleHeight,
    required this.buttonHeight,
    required this.capsulePadding,
    required this.buttonGap,
    required this.labelPadding,
    required this.iconPadding,
    required this.iconSize,
    this.groupGap = 12,
    this.backChevronInset = 12,
    this.backChevronWidth = 16.33,
    this.backChevronGap = 6,
    this.backTrailingPadding = 17,
  });

  /// The height of a capsule; no capsule is narrower.
  final double capsuleHeight;

  /// The height of a button inside its capsule.
  final double buttonHeight;

  /// The space between a capsule's edge and its first and last buttons.
  final double capsulePadding;

  /// The space between two buttons of one capsule.
  final double buttonGap;

  /// The space between two capsules of one run.
  final double groupGap;

  /// The space on each side of a button's label.
  final double labelPadding;

  /// The space on each side of a button's icon.
  final double iconPadding;

  /// The box icons are laid out in: a lone icon's capsule is round, the
  /// button [iconSize] plus twice [iconPadding] wide.
  final double iconSize;

  /// The space between a back button's leading edge and its chevron.
  final double backChevronInset;

  /// The width of the back chevron.
  final double backChevronWidth;

  /// The space between the back chevron and its label.
  final double backChevronGap;

  /// The space after the back button's label.
  final double backTrailingPadding;

  /// The narrowest a button gets: as wide as a lone icon's.
  double get minButtonWidth => iconSize + 2 * iconPadding;

  /// A navigation bar's buttons; a lone icon's capsule is the round 44 of
  /// the recordings, which sets the 22 point icon box.
  static const navigation = GlassBarMetrics(
    capsuleHeight: 44,
    buttonHeight: 36,
    capsulePadding: 4,
    buttonGap: 16,
    labelPadding: 12,
    iconPadding: 7,
    iconSize: 22,
  );

  /// A toolbar's buttons; a lone icon's capsule is round.
  static const toolbar = GlassBarMetrics(
    capsuleHeight: SearchBarGeometry.fieldHeight,
    buttonHeight: 38,
    capsulePadding: 5,
    buttonGap: 14,
    labelPadding: 11,
    iconPadding: 8,
    iconSize: 22,
  );
}

/// What a bar button shows, which sets how its content is padded.
enum GlassBarButtonKind {
  /// An icon, padded by [GlassBarMetrics.iconPadding].
  icon,

  /// A label, padded by [GlassBarMetrics.labelPadding].
  label,

  /// The back button: a chevron and an optional label, alone in its
  /// capsule, which it fills.
  back,

  /// Content of the app's own, at its laid-out width.
  custom,
}

/// One button to lay out.
@immutable
class GlassBarButtonSpec {
  /// A button [id] whose content is [contentWidth] wide.
  const GlassBarButtonSpec(this.id, this.contentWidth, this.kind);

  /// The button's identity across layouts.
  final Object id;

  /// The width of its content: the icon, the label, or for a back button
  /// its label alone (0 for none).
  final double contentWidth;

  /// What the button shows.
  final GlassBarButtonKind kind;
}

/// One capsule to lay out: adjacent buttons sharing one piece of glass.
@immutable
class GlassBarCapsuleSpec {
  /// A capsule of [buttons].
  const GlassBarCapsuleSpec(this.buttons);

  /// The buttons, in reading order.
  final List<GlassBarButtonSpec> buttons;
}

/// The identity of a button whose id another button of the same bar took
/// before it: the [index]-th repeat of [id] in reading order (from 1), as
/// UIKit's unique semantic id pairs a semantic id with an index.
@immutable
class GlassBarItemId {
  /// Identifies the [index]-th repeat of [id].
  const GlassBarItemId(this.id, this.index);

  /// The id the button carries.
  final Object id;

  /// How many buttons of the bar carry [id] before this one.
  final int index;

  @override
  bool operator ==(Object other) =>
      other is GlassBarItemId && other.id == id && other.index == index;

  @override
  int get hashCode => Object.hash(id, index);

  @override
  String toString() => 'GlassBarItemId($id, $index)';
}

/// The part of a bar a capsule belongs to: the run before the title, the
/// runs a toolbar's flexible spaces leave between the ends, or the run
/// after it.
///
/// It is the [GlassBarCapsuleLayout.segment] of a leading or trailing
/// capsule; a capsule of the center runs carries the pair of [center] and
/// the run's index, so a change pairs capsules only within one run.
enum GlassBarSegment {
  /// The run that starts at the leading side.
  leading,

  /// The runs between the leading and trailing ones.
  center,

  /// The run that ends at the trailing side.
  trailing,
}

/// Lays out a bar [width] wide with its capsules' top at [top]:
/// [leading] from [leadingInset], [trailing] ending [trailingInset] from
/// the far side, and each of [center], the runs a toolbar's flexible
/// spaces leave between them, centered in an equal share of the room
/// between; capsules of a run [GlassBarMetrics.groupGap] apart. Capsules
/// are anonymous, keyed by their place from their run's edge, so a change
/// pairs them by the nearest center within their segment, as UIKit's bars
/// pair their groups. [rtl] mirrors the bar.
List<GlassBarCapsuleLayout> layoutGlassBar({
  required List<GlassBarCapsuleSpec> leading,
  required List<GlassBarCapsuleSpec> trailing,
  required double width,
  required double top,
  required double leadingInset,
  required double trailingInset,
  required GlassBarMetrics metrics,
  List<List<GlassBarCapsuleSpec>> center = const [],
  bool rtl = false,
}) {
  final out = <GlassBarCapsuleLayout>[];
  var x = leadingInset;
  for (var i = 0; i < leading.length; i++) {
    final c = _capsule(leading[i], x, top, metrics, GlassBarSegment.leading, i);
    out.add(c);
    x = c.rect.right + metrics.groupGap;
  }
  final leadingEnd = leading.isEmpty ? leadingInset : x - metrics.groupGap;
  var right = width - trailingInset;
  for (var i = 0; i < trailing.length; i++) {
    final c = _capsule(
      trailing[trailing.length - 1 - i],
      0,
      top,
      metrics,
      GlassBarSegment.trailing,
      i,
    );
    final shifted = _shift(c, right - c.rect.width);
    out.add(shifted);
    right = shifted.rect.left - metrics.groupGap;
  }
  final trailingStart = trailing.isEmpty
      ? width - trailingInset
      : right + metrics.groupGap;
  if (center.isNotEmpty) {
    final share = (trailingStart - leadingEnd) / center.length;
    for (var r = 0; r < center.length; r++) {
      final segment = (GlassBarSegment.center, r);
      final run = [
        for (var i = 0; i < center[r].length; i++)
          _capsule(center[r][i], 0, top, metrics, segment, i),
      ];
      if (run.isEmpty) continue;
      final runWidth =
          run.fold<double>(0, (a, c) => a + c.rect.width) +
          metrics.groupGap * (run.length - 1);
      var cx = leadingEnd + share * r + (share - runWidth) / 2;
      for (final c in run) {
        out.add(_shift(c, cx));
        cx += c.rect.width + metrics.groupGap;
      }
    }
  }
  if (!rtl) return out;
  return [
    for (final c in out)
      GlassBarCapsuleLayout(
        c.id,
        _mirror(c.rect, width),
        [
          for (final i in c.items)
            GlassBarItemLayout(i.id, _mirror(i.rect, width)),
        ],
        segment: c.segment,
        anonymous: c.anonymous,
      ),
  ];
}

/// The width of a button of [spec] in a bar of [metrics].
@internal
double glassBarButtonWidth(GlassBarButtonSpec spec, GlassBarMetrics metrics) =>
    switch (spec.kind) {
      GlassBarButtonKind.back =>
        metrics.backChevronInset +
            metrics.backChevronWidth +
            (spec.contentWidth <= 0
                ? metrics.backChevronInset
                : metrics.backChevronGap +
                      spec.contentWidth +
                      metrics.backTrailingPadding),
      GlassBarButtonKind.icon => math.max(
        metrics.minButtonWidth,
        spec.contentWidth + 2 * metrics.iconPadding,
      ),
      GlassBarButtonKind.label => math.max(
        metrics.minButtonWidth,
        spec.contentWidth + 2 * metrics.labelPadding,
      ),
      GlassBarButtonKind.custom => spec.contentWidth,
    };

/// The capsule of [spec] from [start], keyed by its [index] in its
/// [segment]'s run.
GlassBarCapsuleLayout _capsule(
  GlassBarCapsuleSpec spec,
  double start,
  double top,
  GlassBarMetrics metrics,
  Object segment,
  int index,
) {
  final buttons = spec.buttons;
  final widths = [for (final b in buttons) glassBarButtonWidth(b, metrics)];
  // A back button fills its capsule: the chevron sits on the glass's edge.
  final fills =
      buttons.length == 1 && buttons.first.kind == GlassBarButtonKind.back;
  final inner =
      widths.fold<double>(0, (a, w) => a + w) +
      metrics.buttonGap * math.max(0, widths.length - 1);
  final total = math.max(
    metrics.capsuleHeight,
    fills ? inner : inner + 2 * metrics.capsulePadding,
  );
  final rect = Rect.fromLTWH(start, top, total, metrics.capsuleHeight);
  final itemHeight = fills ? metrics.capsuleHeight : metrics.buttonHeight;
  final itemTop = top + (metrics.capsuleHeight - itemHeight) / 2;
  var x = start + (total - inner) / 2;
  final items = <GlassBarItemLayout>[];
  for (var i = 0; i < widths.length; i++) {
    items.add(
      GlassBarItemLayout(
        buttons[i].id,
        Rect.fromLTWH(x, itemTop, widths[i], itemHeight),
      ),
    );
    x += widths[i] + metrics.buttonGap;
  }
  return GlassBarCapsuleLayout(
    (segment, index),
    rect,
    items,
    segment: segment,
    anonymous: true,
  );
}

GlassBarCapsuleLayout _shift(GlassBarCapsuleLayout c, double left) {
  final d = Offset(left - c.rect.left, 0);
  return GlassBarCapsuleLayout(
    c.id,
    c.rect.shift(d),
    [for (final i in c.items) GlassBarItemLayout(i.id, i.rect.shift(d))],
    segment: c.segment,
    anonymous: c.anonymous,
  );
}

Rect _mirror(Rect r, double width) =>
    Rect.fromLTRB(width - r.right, r.top, width - r.left, r.bottom);
