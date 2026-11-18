part of 'menu_motion.dart';

/// The submenu cards stacked over a menu's root list, oldest first: what
/// they show, how far each has grown out of its row, and where each
/// stands in the menu's frame, which the law gives as a value.
///
/// The law owns one stack. The stack reads the law's root list, its cap
/// and its root height, owns its cards' parts through the law, and writes
/// only its cards.
final class _CardStack {
  _CardStack(this._motion);

  final MenuMotion _motion;

  final List<_Card> _cards = [];

  MenuTuning get _tuning => _motion.tuning;

  /// The open cards, oldest first.
  List<_Card> get all => _cards;

  bool get isEmpty => _cards.isEmpty;

  bool get isNotEmpty => _cards.isNotEmpty;

  /// The index in the menu's cards (the root list 0) of the card that
  /// takes the highlight and the choice: the newest one not on its way
  /// back.
  int get top {
    var top = _cards.length;
    while (top > 0 && _cards[top - 1].backing) {
      top--;
    }
    return top;
  }

  /// The newest card not on its way back, or null.
  _Card? get focus {
    _Card? card;
    for (final open in _cards) {
      if (!open.backing) card = open;
    }
    return card;
  }

  /// The content of card [card] of the menu's cards; the root list for 0
  /// and for a card that is gone.
  MenuLayout layoutOf(int card) => card == 0 || card > _cards.length
      ? _motion._root
      : _cards[card - 1].layout;

  /// The height the cards add below the root list at time [t].
  double extra(double t) {
    var reach = _motion._rootHeight.target;
    var extra = 0.0;
    for (final card in _cards) {
      final bottom = card.top + math.min(card.layout.height, _motion._cap);
      if (bottom > reach) {
        extra += (bottom - reach) * card.progress.valueAt(t);
        reach = bottom;
      }
    }
    return extra;
  }

  /// The scale of card [card] of the menu's cards under the cards above
  /// it at time [t].
  double scaleUnder(int card, double t) {
    var scale = 1.0;
    for (var k = card; k < _cards.length; k++) {
      final q = _cards[k].progress.valueAt(t);
      scale *= 1 - (1 - _tuning.parentScale) * q;
    }
    return scale;
  }

  double _clampTop(double top, double height) {
    final cap = _motion._cap;
    final reach = math.max(cap, _motion._rootHeight.target);
    return math.max(0, math.min(top, reach - math.min(height, cap)));
  }

  /// Where [card] stands open in a menu whose frame is [menu].
  Rect frame(_Card card, Rect menu) => Rect.fromLTWH(
    menu.left,
    menu.top + card.top,
    _motion.menuWidth,
    math.min(card.layout.height, _motion._cap),
  );

  /// The flex of card [index] of the menu's cards at time [t] in a menu
  /// whose frame is [menu]; none for the root list or a card that is gone.
  MenuFlexShape flex(int index, Rect menu, double t) {
    if (index == 0 || index > _cards.length) return noMenuFlex;
    final card = _cards[index - 1];
    return menuFlexOf(card.flex.valuesAt(t), frame(card, menu), _motion._side);
  }

  /// The menu's cards at time [t], the root list first.
  List<MenuCard> at(double t) {
    final tuning = _tuning;
    final root = _motion._root;
    final result = <MenuCard>[];
    final count = _cards.length;
    for (var i = 0; i <= count; i++) {
      final scale = scaleUnder(i, t);
      final above = i < count ? _cards[i].progress.valueAt(t) : 0.0;
      final opacity = (1 - (1 - tuning.parentRowOpacity) * above).clamp(
        0.0,
        1.0,
      );
      if (i == 0) {
        result.add(
          MenuCard(
            layout: root,
            rect: Rect.fromLTWH(0, 0, _motion.menuWidth, root.height),
            scale: scale,
            rowOpacity: opacity,
            progress: 1,
          ),
        );
        continue;
      }
      final card = _cards[i - 1];
      final q = card.progress.valueAt(t);
      final rect = Rect.lerp(card.from, frame(card, Rect.zero), q)!;
      final parent = result[i - 1];
      final targets = parent.layout.targets;
      final row = card.source < targets.length
          ? parent.rect.top +
                targets[card.source].rect.center.dy -
                (i == 1 ? _motion.scrollOffset : 0)
          : card.from.center.dy;
      final ratio = scale == 0 ? 1.0 : parent.scale / scale;
      final onRow = ratio * row - _headerCenter(card.layout);
      final contentTop = onRow + (card.top - onRow) * q;
      final c = q.clamp(0.0, 1.0);
      final from = card.backFrom.clamp(1e-6, 1.0);
      result.add(
        MenuCard(
          layout: card.layout,
          rect: rect,
          scale: scale,
          rowOpacity: opacity,
          progress: q,
          contentTop: contentTop - rect.top,
          rowsOpacity: card.backing
              ? MenuMotion._ramp(c, tuning.cardRowsFadeOut * from, from)
              : MenuMotion._ramp(c, 0, tuning.cardRowsFadeIn),
          platterOpacity: math.sqrt(
            MenuMotion._ramp(c, 0, tuning.cardPlatterFade),
          ),
          headerBold: card.backing
              ? MenuMotion._ramp(c, tuning.cardHeaderBoldBack * from, from)
              : MenuMotion._ramp(
                  c,
                  tuning.cardHeaderBoldStart,
                  tuning.cardHeaderBoldEnd,
                ),
          chevronTurn: card.backing
              ? MenuMotion._ramp(c, tuning.cardChevronBack * from, from)
              : MenuMotion._ramp(c, 0, tuning.cardChevronTurn),
          closeOpacity: i == count
              ? _motion._cardFade.at(_motion._cardFadeProgress(t))
              : 1,
          backing: card.backing,
          source: card.source,
        ),
      );
    }
    return result;
  }

  static double _headerCenter(MenuLayout layout) {
    for (final element in layout.elements) {
      if (element.kind == MenuPlacedKind.cardHeader) {
        return element.rect.center.dy;
      }
    }
    return 0;
  }

  /// Opens a card at time [t] out of target [index] of card [card], the
  /// submenu target [source]: brings back the card on its way back into
  /// that row, or grows a new one laid out by the law's `submenuLayout`.
  /// Answers whether a card opened.
  bool open(double t, int card, int index, MenuTarget source) {
    final tuning = _tuning;
    final spring = card == 0
        ? tuning.submenuSpring
        : tuning.deeperSubmenuSpring;
    while (_cards.length > card) {
      final last = _cards.last;
      if (!last.backing) break;
      if (_cards.length == card + 1 && last.source == index) {
        last.backing = false;
        last.progress.retarget(t, 1, spring: spring);
        return true;
      }
      _motion._disownCard(_cards.removeLast());
    }
    if (_cards.length != card) return false;
    final layout = _motion.submenuLayout?.call(source);
    if (layout == null) return false;
    final shown = _motion.cards[card];
    final rowLocal =
        source.rect.center.dy - (card == 0 ? _motion.scrollOffset : 0);
    final rowCenter = shown.rect.top + rowLocal;
    final from = Rect.fromCenter(
      center: Offset(_motion.menuWidth / 2, rowCenter),
      width: tuning.cardStartWidth,
      height: source.rect.height,
    );
    final progress = _motion._ownCardProgress(spring);
    progress.retarget(t, 1);
    final opened = _Card(
      layout: layout,
      source: index,
      from: from,
      top: _clampTop(
        shown.rect.top +
            (rowLocal - tuning.cardLead) * (card == 0 ? 1 : tuning.parentScale),
        layout.height,
      ),
      progress: progress,
    );
    opened.flex = _motion._flexOf(() => frame(opened, _motion.menuRect));
    _cards.add(opened);
    return true;
  }

  /// Sends the top card back into its row at time [t]; answers the index
  /// of the card that takes over, or null when no card is on top.
  int? back(double t) {
    final top = this.top;
    if (top == 0) return null;
    final card = _cards[top - 1];
    card.backing = true;
    card.backFrom = card.progress.valueAt(t);
    card.progress.retarget(t, 0, spring: _tuning.backSpring);
    return top - 1;
  }

  /// Lays the cards out again from the targets that opened them, the root
  /// list laid out anew; answers the index of the first card whose target
  /// is gone, which closes with every card above it, or null.
  int? relayout() {
    for (var i = 0; i < _cards.length; i++) {
      final card = _cards[i];
      final parent = i == 0 ? _motion._root : _cards[i - 1].layout;
      final source = card.source < parent.targets.length
          ? parent.targets[card.source]
          : null;
      final layout = source == null || source.kind != .submenu
          ? null
          : _motion.submenuLayout?.call(source);
      if (layout == null) {
        drop(i);
        return i;
      }
      card.layout = layout;
      card.top = _clampTop(card.top, layout.height);
    }
    return null;
  }

  /// Drops the cards from [from] on.
  void drop(int from) {
    while (_cards.length > from) {
      _motion._disownCard(_cards.removeLast());
    }
  }

  /// Drops the cards on their way back that have reached their row by
  /// time [t].
  void dropGone(double t) {
    for (var i = _cards.length - 1; i >= 0; i--) {
      final card = _cards[i];
      if (card.backing && card.progress.valueAt(t) < _tuning.cardGone) {
        _motion._disownCard(_cards.removeAt(i));
      }
    }
  }
}

/// A submenu card stacked over the menu.
class _Card {
  _Card({
    required this.layout,
    required this.source,
    required this.from,
    required this.top,
    required this.progress,
  });

  MenuLayout layout;

  /// The index of the target in the card below that opened this one.
  final int source;

  /// The frame the card grows out of, in content coordinates.
  final Rect from;

  /// The top of the open card, in content coordinates.
  double top;

  final MotionValue<double> progress;

  /// The card's own flex: UIKit attaches one to each list, and a finger on a
  /// card leaves the list under it where it is.
  late final MenuFlex flex;
  bool backing = false;

  /// The progress the card had when it started back to its row.
  double backFrom = 1;
}
