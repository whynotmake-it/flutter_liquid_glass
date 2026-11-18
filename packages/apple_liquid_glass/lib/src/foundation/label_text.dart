import 'package:flutter/widgets.dart';

/// The text a screen reader would read for a label widget, or null when
/// the widget holds none.
///
/// It reads, in this order: the `data` of a `Text`, or the plain text of
/// its span; the plain text of a `RichText`; an `Icon`'s `semanticLabel`;
/// the `label` of a `Semantics`' properties when it has one; otherwise
/// the same of the child of any single-child render widget (`Padding`,
/// `Align`, `SizedBox`, ...) or proxy widget (`DefaultTextStyle`,
/// `Opacity`, ...), or of the first child of a multi-child one (`Row`,
/// `Column`, `Flex`, `Stack`) that has any. Any other widget has none.
///
/// A control uses it only as the default for its label when the caller
/// gives no semantic label; a given label always wins.
String? glassLabelTextOf(Widget? label) => switch (label) {
  Text(:final String data) => data,
  Text(:final InlineSpan textSpan) => textSpan.toPlainText(),
  RichText(:final text) => text.toPlainText(),
  Icon(:final semanticLabel) => semanticLabel,
  Semantics(:final properties) when properties.label != null =>
    properties.label,
  SingleChildRenderObjectWidget(:final child) => glassLabelTextOf(child),
  ProxyWidget(:final child) => glassLabelTextOf(child),
  MultiChildRenderObjectWidget(:final children) =>
    children.map(glassLabelTextOf).nonNulls.firstOrNull,
  _ => null,
};
