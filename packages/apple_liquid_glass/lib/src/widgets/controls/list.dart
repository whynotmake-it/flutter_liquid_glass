import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/widgets/controls/list_accessory.dart';
import 'package:apple_liquid_glass/src/widgets/controls/list_style.dart';
import 'package:apple_liquid_glass/src/widgets/controls/state_colors.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';

part 'package:apple_liquid_glass/src/widgets/controls/list_marks.dart';
part 'package:apple_liquid_glass/src/widgets/controls/list_render.dart';
part 'package:apple_liquid_glass/src/widgets/controls/list_row.dart';

/// The page behind an inset grouped list.
///
/// UIKit: `systemGroupedBackground`. SwiftUI: a `List` with
/// `.insetGrouped`. Flutter: `CupertinoColors.systemGroupedBackground`.
class GlassListBackground extends StatelessWidget {
  /// Creates the background.
  const GlassListBackground({
    this.color = GlassColors.systemGroupedBackground,
    this.child,
    super.key,
  });

  /// The color of the page.
  final Color color;

  /// The list.
  final Widget? child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: GlassDynamicColor.resolve(color, context),
    child: child,
  );
}

/// One section of an inset grouped list, as iOS 27 settings screens draw
/// it: a header, rows on one rounded card, and a footer.
///
/// UIKit: a `UITableView` section, `.insetGrouped`. SwiftUI: `Section` in a
/// `List`. Flutter: `CupertinoListSection.insetGrouped`.
///
/// Pass the rows as [children], usually [GlassListRow]s, and an optional
/// [header] and [footer], usually [Text]. Sections stack in a scroll view,
/// such as a `ListView` over a [GlassListBackground]; for a long list
/// whose rows build lazily, use [GlassSliverListSection]. [style] changes
/// the look of the section and its rows.
///
/// ```dart
/// GlassListSection(
///   header: const Text('Network'),
///   footer: const Text('Shown to devices nearby.'),
///   children: [
///     GlassListRow(
///       leading: const Icon(CupertinoIcons.wifi),
///       title: const Text('Wi-Fi'),
///       detail: const Text('Home'),
///       accessory: GlassListAccessory.disclosureIndicator,
///       onPressed: () => debugPrint('open Wi-Fi'),
///     ),
///   ],
/// )
/// ```
///
/// It draws no glass on any renderer: the card is a plain fill that
/// looks the same under the liquid, fake and flat renderers and with no
/// `GlassScope` above.
///
/// [GlassListRow]s on the card draw the separators between them; other
/// children are laid out on the card as they are. The space between two
/// sections comes from their own headers and footers (35 points between a
/// card without a footer and one without a header). The card is 20 points
/// in from the edges with 26 point corners, and paints in a layer of its
/// own, so a scroll moving it composites that layer instead of repainting
/// its rows.
///
/// Fidelity. The insets, corners and spacing are measured on iOS 27.
class GlassListSection extends StatelessWidget {
  /// Creates a section.
  const GlassListSection({
    required this.children,
    this.header,
    this.footer,
    this.style,
    super.key,
  });

  /// The rows on the card.
  final List<Widget> children;

  /// The label above the card, usually a [Text]: 17 points semibold in the
  /// secondary color unless it sets its own style.
  final Widget? header;

  /// The label below the card, usually a [Text]: 13 points in the
  /// secondary color unless it sets its own style.
  final Widget? footer;

  /// The look of the section and its rows, over the theme's.
  final GlassListStyle? style;

  /// The separators of an iOS 27 table: 0x3C3C43 at 12 percent in light
  /// and 0x545458 at 50 percent in dark, lighter than the catalog's
  /// separator (list passport, simulator).
  static const separator = GlassDynamicColor.withBrightness(
    color: Color(0x1F3C3C43),
    darkColor: Color(0x80545458),
  );

  @override
  Widget build(BuildContext context) {
    final look = _sectionLook(context, style);
    final section = RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _Metrics.sectionInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionLabel.header(look: look, label: header),
            ClipRRect(
              borderRadius: const BorderRadius.all(
                Radius.circular(_Metrics.cornerRadius),
              ),
              child: ColoredBox(
                color: StateColors(context, const {})(look.backgroundColor),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < children.length; i++)
                      _RowPlace(
                        last: i == children.length - 1,
                        look: look,
                        child: children[i],
                      ),
                  ],
                ),
              ),
            ),
            _SectionLabel.footer(look: look, label: footer),
          ],
        ),
      ),
    );
    return SwipeGroup(child: section);
  }
}

/// A [GlassListSection] as a sliver that builds its rows lazily, for a
/// long list in a [CustomScrollView].
///
/// UIKit: a `UITableView` section of many cells. SwiftUI: `Section` in a
/// `List`. Flutter: `SliverList.builder`.
///
/// It looks like [GlassListSection]: [header], the [itemCount] rows that
/// [itemBuilder] builds on one rounded card, [footer]. Rows are built only
/// while they are in view, each in a layer of its own. With [ids], rows
/// insert, delete and reorder on the app's `withSpring` ([RawGlassList]).
class GlassSliverListSection extends StatelessWidget {
  /// Creates a section of [itemCount] rows built by [itemBuilder].
  const GlassSliverListSection({
    required this.itemBuilder,
    required this.itemCount,
    this.ids,
    this.header,
    this.footer,
    this.style,
    super.key,
  }) : assert(ids == null || ids.length == itemCount, 'One id per row.');

  /// Builds the row at an index, usually a [GlassListRow].
  final IndexedWidgetBuilder itemBuilder;

  /// The number of rows.
  final int itemCount;

  /// What identifies each row across changes of the rows, or null to
  /// identify them by position, which animates nothing.
  final List<Object>? ids;

  /// The label above the card; see [GlassListSection.header].
  final Widget? header;

  /// The label below the card; see [GlassListSection.footer].
  final Widget? footer;

  /// The look of the section and its rows, over the theme's.
  final GlassListStyle? style;

  @override
  Widget build(BuildContext context) {
    final look = _sectionLook(context, style);
    const radius = Radius.circular(_Metrics.cornerRadius);
    final card = StateColors(context, const {})(look.backgroundColor);
    Widget piece(BuildContext context, int i) {
      final last = i == itemCount - 1;
      return RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.vertical(
            top: i == 0 ? radius : Radius.zero,
            bottom: last ? radius : Radius.zero,
          ),
          child: ColoredBox(
            color: card,
            child: _RowPlace(
              last: last,
              look: look,
              child: itemBuilder(context, i),
            ),
          ),
        ),
      );
    }

    final indexOf = {for (final (i, id) in (ids ?? const []).indexed) id: i};
    final section = SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: _Metrics.sectionInset),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: _SectionLabel.header(look: look, label: header),
          ),
          if (ids case final ids?)
            RawGlassList(
              ids: ids,
              itemBuilder: (context, id) => piece(context, indexOf[id]!),
            )
          else
            SliverList.builder(itemCount: itemCount, itemBuilder: piece),
          SliverToBoxAdapter(
            child: _SectionLabel.footer(look: look, label: footer),
          ),
        ],
      ),
    );
    return SwipeGroup(child: section);
  }
}

GlassListStyle _sectionLook(BuildContext context, GlassListStyle? style) {
  final label = GlassTheme.labelColorOf(context);
  return (style ?? const GlassListStyle())
      .merge(GlassListStyle.maybeOf(context))
      .merge(
        GlassListStyle(
          backgroundColor: const WidgetStatePropertyAll(
            GlassColors.secondarySystemGroupedBackground,
          ),
          overlayColor: const WidgetStatePropertyAll(GlassColors.systemGray4),
          separatorColor: const WidgetStatePropertyAll(
            GlassListSection.separator,
          ),
          foregroundColor: WidgetStatePropertyAll(label),
          secondaryColor: const WidgetStatePropertyAll(
            GlassColors.secondaryLabel,
          ),
          iconColor: WidgetStatePropertyAll(
            GlassTheme.primaryColorOf(context) ?? GlassColors.systemBlue,
          ),
          disclosureColor: WidgetStatePropertyAll(
            GlassTheme.tertiaryLabelColorOf(context),
          ),
        ),
      );
}

/// The metrics of an inset grouped list on a 402 point screen (list
/// passport, simulator view tree and screenshots).
abstract final class _Metrics {
  /// How far a section's card stands in from the screen's edges.
  static const double sectionInset = 20;

  /// The corner radius of a section's card, fitted to its outline (0.3
  /// pt).
  static const double cornerRadius = 26;

  /// The leading inset of a row's text, of the separators and of the
  /// header and footer labels, and the trailing inset of a row without an
  /// accessory.
  static const double contentInset = 16;

  /// The trailing inset of a row's accessory or control.
  static const double accessoryInset = 20;

  /// The gap between a row's title and its detail, and between the text
  /// and the accessory.
  static const double gap = 8;

  /// The height of a single-line row.
  static const double minRowHeight = 53;

  /// The space above and below a row's text.
  static const double rowPadding = 15.5;

  /// The width of the leading slot, which centers a symbol 28 points from
  /// the card's edge.
  static const double leadingWidth = 24;

  /// The gap after the leading slot.
  static const double leadingGap = 16;

  /// The point size of a row's leading symbol.
  static const double leadingIconSize = 22;

  /// The thickness of a separator.
  static const double separatorThickness = 1;

  /// The space above a section header's label.
  static const double headerTop = 11.67;

  /// The space between a section header's label and its card.
  static const double headerBottom = 6;

  /// The space above a card without a header.
  static const double noHeaderTop = 17.67;

  /// The space between a card and its footer's label.
  static const double footerTop = 7.67;

  /// The space below a section footer's label.
  static const double footerBottom = 6.67;

  /// The space below a card without a footer.
  static const double noFooterBottom = 17.33;

  /// The size of the disclosure chevron's glyph box.
  static const Size chevronSize = Size(10.33, 14);

  /// The box of a checkmark or an info button.
  static const double glyphSize = 22;

  /// A row's title and detail.
  static const body = TextStyle(fontSize: 17, fontWeight: FontWeight.w400);

  /// The line under a row's title.
  static const subtitle = TextStyle(fontSize: 15, fontWeight: FontWeight.w400);

  /// A section's header.
  static const header = TextStyle(fontSize: 17, fontWeight: FontWeight.w600);

  /// A section's footer.
  static const footer = TextStyle(fontSize: 13, fontWeight: FontWeight.w400);
}
