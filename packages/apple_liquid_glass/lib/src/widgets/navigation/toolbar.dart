import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/widgets/controls/button.dart';
import 'package:apple_liquid_glass/src/widgets/controls/search_field.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar_entry.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/chrome.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/search_host.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// The look of toolbars, set on the theme.
@immutable
class GlassToolbarStyle extends GlassStyle<GlassToolbarStyle> {
  /// Creates a style.
  const GlassToolbarStyle({this.itemStyle});

  /// The theme's [GlassToolbarStyle] at [context], or null without one: the
  /// look between a widget's own style and its defaults.
  static GlassToolbarStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassToolbarStyle>(context);

  /// The look of the toolbar's items and of its search's close button.
  final GlassBarItemStyle? itemStyle;

  /// This style over [other].
  @override
  GlassToolbarStyle merge(GlassToolbarStyle? other) {
    if (other == null) return this;
    return GlassToolbarStyle(
      itemStyle: itemStyle?.merge(other.itemStyle) ?? other.itemStyle,
    );
  }

  /// The style between this one and [other] at [t].
  @override
  GlassToolbarStyle lerp(GlassToolbarStyle other, double t) {
    if (identical(this, other)) return this;
    return GlassToolbarStyle(
      itemStyle: GlassBarItemStyle.lerp(itemStyle, other.itemStyle, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassToolbarStyle && other.itemStyle == itemStyle;

  @override
  int get hashCode => itemStyle.hashCode;
}

/// An iOS 27 toolbar: glass capsules floating over the bottom of the
/// screen.
///
/// UIKit: `UIToolbar` with `toolbarItems`. SwiftUI: `toolbar` with
/// `ToolbarItem(placement: .bottomBar)`. Flutter: a bottom bar of
/// `CupertinoButton`s.
///
/// The [items] stand in capsules 48 points tall, adjacent items sharing
/// one, a [GlassBarSpacer.flexible] where UIKit puts its flexible space;
/// capsules that come within 12 points fuse on liquid glass. They sit 28
/// points from the sides and the bottom of the screen
/// (`_UIToolbarPaddingSpec` phoneSides and phoneBottom), or 8 points above a
/// keyboard (phoneKeyboard), read from UIKit's tuning on iOS 27 and the
/// capsule frames on an iPhone 16 Pro. Put it in a [GlassPageScaffold]'s
/// toolbar. The glass pages of a navigator share one toolbar, as UIKit's
/// navigation controller does: when a page's items change, or another
/// page comes, its capsules change as `setToolbarItems(_:animated:)` changes
/// them (device recordings, replayed).
///
/// A [GlassBarItem.custom] holding a [GlassSearchField] makes it iOS 27's
/// bottom search bar (`UISearchController` in the toolbar), drawn with its
/// page: the field fills the room between the items before and after it,
/// 12 points from each, every item 48 points tall. Focusing the field
/// starts the search as the keyboard starts to rise: on one spring (0.25
/// s, bounce 0.1) the field widens to 8 points from the sides and rises to
/// 10 points above the keyboard, the other items swell to 1.2 and fade
/// where they stand, and a close button travels in with the field from its
/// resting place, growing from 1.2 and sharpening from a blur. The close
/// button ends the search 0.067 s later: the text clears, the keyboard
/// leaves, the field and the close button return from where they were,
/// without following the keyboard down, and the items come back from the
/// focused layout. Tapping elsewhere leaves the search active, as in UIKit
/// (read from UIKit, notes private; search passport, simulator and iPhone
/// 16 Pro recordings). UIKit aims the field at the keyboard's final top;
/// Flutter reports the keyboard as it rises, so the field follows it
/// there. Without a keyboard the search starts 0.3 s after the focus, a
/// guard of this package: UIKit has no such wait.
class GlassToolbar extends StatefulWidget implements PreferredSizeWidget {
  /// Creates a toolbar of [items].
  const GlassToolbar({
    required this.items,
    this.closeSemanticLabel,
    super.key,
  });

  /// The capsules' items, leading to trailing.
  final List<GlassBarEntry> items;

  /// What accessibility reads for the search's close button; the localized
  /// "Close" when null.
  final String? closeSemanticLabel;

  /// The height of the toolbar's items.
  static const double height = SearchBarGeometry.fieldHeight;

  /// The space between the screen's sides and the outer items.
  static const double sideInset = SearchBarGeometry.restInset;

  /// The space between the screen's bottom and the items.
  static const double bottomInset = SearchBarGeometry.restInset;

  /// The space between a keyboard and the items (read from UIKit).
  static const double keyboardInset = 8;

  /// How close glass items come before they fuse: the spacing of the glass
  /// container a bar's capsules share (bars passport: 12, constant through
  /// item changes).
  static const double fusion = 12;

  @override
  Size get preferredSize => const Size.fromHeight(height + bottomInset);

  @override
  State<GlassToolbar> createState() => _GlassToolbarState();
}

class _GlassToolbarState extends State<GlassToolbar> {
  late final _bar = GlassBarClient(this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bar.resolve(context);
  }

  @override
  void dispose() {
    _bar.dispose();
    super.dispose();
  }

  static Widget _button(GlassBarItem item) => switch (item) {
    GlassBarCustomItem(:final child) => child,
    GlassBarButton(:final onPressed, :final icon, :final label) ||
    GlassBarProminentButton(
      :final onPressed,
      :final icon,
      :final label,
    ) => GlassButton(onPressed: onPressed, child: icon ?? label!),
  };

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final link = _bar.target;
    final search = items.indexWhere(
      (entry) => entry is GlassBarCustomItem && entry.child is GlassSearchField,
    );
    final shown = GlassTabShown.of(context);
    if (!shown) _bar.withdraw();
    if (search >= 0) {
      if (shown) link.host.declareToolbar(link, null, by: this);
      return _SearchBar(
        leading: [
          for (final entry in items.take(search))
            if (entry is GlassBarItem) _button(entry),
        ],
        field: (items[search] as GlassBarCustomItem).child,
        trailing: [
          for (final entry in items.skip(search + 1))
            if (entry is GlassBarItem) _button(entry),
        ],
        closeSemanticLabel:
            widget.closeSemanticLabel ??
            GlassLocalizations.of(context).closeButtonLabel,
      );
    }
    if (shown) link.host.declareToolbar(link, items, by: this);
    final standalone = _bar.standalone;
    if (standalone == null) {
      return SizedBox(height: widget.preferredSize.height);
    }
    final keyboard = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
    return Padding(
      padding: EdgeInsets.only(
        bottom: keyboard > 0
            ? keyboard + GlassToolbar.keyboardInset
            : GlassToolbar.bottomInset,
      ),
      child: SizedBox(
        height: GlassToolbar.height,
        child: GlassBarView(host: standalone, only: GlassBarKind.toolbar),
      ),
    );
  }
}

class _SearchBar extends StatefulWidget {
  const _SearchBar({
    required this.leading,
    required this.field,
    required this.trailing,
    required this.closeSemanticLabel,
  });

  final List<Widget> leading;
  final Widget field;
  final List<Widget> trailing;
  final String closeSemanticLabel;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> with SearchLaw {
  late final MotionClock _clock;
  late final _motion = SearchMotion(clock: _clock);
  late final _progress = _motion.select((m) => m.progress);
  late final _swell = _motion.select(
    (m) => 1 + (SearchMotion.appearScale - 1) * m.progress,
  );
  late final _fade = _motion.select((m) => 1 - m.progress);
  late final _arriveScale = _motion.select(
    (m) =>
        SearchMotion.appearScale + (1 - SearchMotion.appearScale) * m.progress,
  );
  late final _arriveBlur = _motion.select(
    (m) => SearchMotion.appearBlur * (1 - m.progress),
  );
  @override
  late final ValueListenable<bool> returned = _motion.select(
    (m) => m.progress == 0,
  );

  @override
  void initState() {
    super.initState();
    _clock = MotionClockScope.of(context);
  }

  @override
  void begin(double t, {required double keyboard}) {
    if (_motion.isFocused) return;
    if (keyboard > 0) {
      _motion.focus(t);
    } else {
      _motion.focusAfterKeyboard(t);
    }
  }

  @override
  void end(double t) => _motion.unfocus(t);

  @override
  void keyboardRose(double t) =>
      _motion.keyboardRose(t, lag: SearchMotion.keyboardLag);

  @override
  Widget build(BuildContext context) {
    final rtl = context.isRightToLeft;
    final itemStyle = GlassToolbarStyle.maybeOf(context)?.itemStyle;
    Widget item(_Slot slot, Widget child) => LayoutId(
      id: slot,
      child: MotionTransition(scale: _swell, opacity: _fade, child: child),
    );
    return MotionScope(
      motion: _motion,
      child: SearchHost(
        law: this,
        field: widget.field,
        closeLabel: widget.closeSemanticLabel,
        closeColor: itemStyle?.foregroundColor?.resolve(const {}),
        builder: (context, parts) => CustomMultiChildLayout(
          delegate: _SearchLayout(
            progress: _progress,
            leading: widget.leading.length,
            trailing: widget.trailing.length,
            keyboard: parts.keyboard,
            returning: parts.held,
            rtl: rtl,
          ),
          children: [
            for (var i = 0; i < widget.leading.length; i++)
              item((_SlotKind.leading, i), widget.leading[i]),
            LayoutId(id: (_SlotKind.field, 0), child: parts.field),
            for (var i = 0; i < widget.trailing.length; i++)
              item((_SlotKind.trailing, i), widget.trailing[i]),
            LayoutId(
              id: (_SlotKind.close, 0),
              child: MotionTransition(
                opacity: _progress,
                scale: _arriveScale,
                blur: _arriveBlur,
                child: parts.close,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _SlotKind { leading, trailing, field, close }

typedef _Slot = (_SlotKind, int);

/// Places a bottom search bar's items, field and close button where the
/// transition's progress has them: the field between its resting and its
/// focused capsule; the close button with it on the way in and where it
/// stood on the way back; the items where they rest on the way in and
/// coming back from the focused layout without a keyboard. It stands as
/// tall as the field above the keyboard needs, and lays out again as the
/// progress or the keyboard moves, without a build.
class _SearchLayout extends MultiChildLayoutDelegate {
  _SearchLayout({
    required this.progress,
    required this.leading,
    required this.trailing,
    required this.keyboard,
    required this.returning,
    required this.rtl,
  }) : super(relayout: Listenable.merge([progress, keyboard, returning]));

  final ValueListenable<double> progress;
  final int leading;
  final int trailing;
  final ValueListenable<double> keyboard;
  final ValueListenable<bool> returning;
  final bool rtl;

  @override
  Size getSize(BoxConstraints constraints) => constraints.constrain(
    Size(
      constraints.maxWidth,
      math.max(
        RawGlassSearchField.height + SearchBarGeometry.restInset,
        keyboard.value +
            SearchBarGeometry.keyboardGap +
            RawGlassSearchField.height,
      ),
    ),
  );

  @override
  void performLayout(Size size) {
    const h = RawGlassSearchField.height;
    final item = BoxConstraints(
      minWidth: h,
      minHeight: h,
      maxHeight: h,
      maxWidth: size.width,
    );
    List<double> measure(int count, _SlotKind kind) => [
      for (var i = 0; i < count; i++) layoutChild((kind, i), item).width,
    ];
    final leadWidths = measure(leading, _SlotKind.leading);
    final trailWidths = measure(trailing, _SlotKind.trailing);
    final rest = searchBarLayout(
      width: size.width,
      bottom: size.height - SearchBarGeometry.restInset,
      focused: false,
      leading: leadWidths,
      trailing: trailWidths,
      rtl: rtl,
    );
    SearchBarGeometry focusedAbove(double keyboard) => searchBarLayout(
      width: size.width,
      bottom: size.height - keyboard - SearchBarGeometry.keyboardGap,
      focused: true,
      leading: leadWidths,
      trailing: trailWidths,
      rtl: rtl,
    );
    final focused = focusedAbove(keyboard.value);
    final bare = focusedAbove(0);
    final p = progress.value;
    final back = returning.value;
    Rect slotOf(Rect resting, Rect away) =>
        back ? lerpRect(resting, away, p) : resting;
    for (var i = 0; i < leading; i++) {
      positionChild(
        (_SlotKind.leading, i),
        slotOf(rest.leading[i], bare.leading[i]).topLeft,
      );
    }
    for (var i = 0; i < trailing; i++) {
      positionChild(
        (_SlotKind.trailing, i),
        slotOf(rest.trailing[i], bare.trailing[i]).topLeft,
      );
    }
    final field = lerpRect(rest.field, focused.field, p);
    layoutChild((_SlotKind.field, 0), BoxConstraints.tight(field.size));
    positionChild((_SlotKind.field, 0), field.topLeft);
    final close = back ? focused.close : lerpRect(rest.close, focused.close, p);
    layoutChild((_SlotKind.close, 0), BoxConstraints.tight(close.size));
    positionChild((_SlotKind.close, 0), close.topLeft);
  }

  @override
  bool shouldRelayout(_SearchLayout oldDelegate) =>
      leading != oldDelegate.leading ||
      trailing != oldDelegate.trailing ||
      rtl != oldDelegate.rtl ||
      !identical(progress, oldDelegate.progress) ||
      !identical(keyboard, oldDelegate.keyboard) ||
      !identical(returning, oldDelegate.returning);
}
