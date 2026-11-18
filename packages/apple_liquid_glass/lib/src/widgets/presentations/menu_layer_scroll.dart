import 'package:apple_liquid_glass/src/widgets/presentations/menu_appearance.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_layer_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The scrolling of an open menu's root list: its offset, which the motion
/// hears, a drag that starts it, the rows the keys reveal, and the lock
/// while a submenu card covers it.
@internal
class MenuLayerScroll {
  /// Creates the scrolling of the root list of the layer it is given.
  MenuLayerScroll(this._layer) {
    _controller.addListener(_scrolled);
  }

  final MenuLayerScope _layer;
  final _controller = ScrollController();
  bool _locked = false;

  void _scrolled() {
    if (_controller.hasClients) _layer.motion.scrollOffset = _controller.offset;
  }

  bool _started(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _layer.command((motion, t) => motion.pointerScrolled(t));
    }
    return false;
  }

  /// Scrolls target [index] of the root list into view when the keys move
  /// to it below or above the visible part.
  void reveal(int index) {
    final built = _layer.built;
    if (built.top != 0 || !_controller.hasClients) return;
    final target = built.targetAt(index);
    if (target == null) return;
    final visible = _layer.motion.visibleRootHeight;
    final offset = _controller.offset;
    final rect = target.rect;
    if (rect.top < offset) {
      _controller.jumpTo(rect.top);
    } else if (rect.bottom > offset + visible) {
      _controller.jumpTo(rect.bottom - visible);
    }
  }

  /// Locks the root list while a submenu card covers it: a scroll under way
  /// stops where it is.
  void lock({required bool locked}) {
    if (locked && !_locked && _controller.hasClients) {
      (_controller.position as ScrollPositionWithSingleContext).goIdle();
    }
    _locked = locked;
  }

  /// The root list's [content] in a scroll view in [style], which takes no
  /// scrolling while locked.
  Widget body(Widget content, MenuAppearance style) {
    return NotificationListener<ScrollNotification>(
      onNotification: _started,
      child: RawScrollbar(
        controller: _controller,
        thumbColor: style.secondaryColor,
        thickness: MenuAppearance.scrollThickness,
        radius: const Radius.circular(MenuAppearance.scrollThickness / 2),
        mainAxisMargin: _layer.motion.cornerRadius / 2,
        crossAxisMargin: MenuAppearance.scrollInset,
        child: CustomScrollView(
          controller: _controller,
          physics: _locked ? const NeverScrollableScrollPhysics() : null,
          slivers: [SliverToBoxAdapter(child: content)],
        ),
      ),
    );
  }

  /// Releases the scroll controller.
  void dispose() => _controller.dispose();
}
