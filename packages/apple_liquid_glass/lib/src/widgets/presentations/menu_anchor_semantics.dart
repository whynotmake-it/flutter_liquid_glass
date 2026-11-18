part of 'menu_anchor.dart';

/// Merges the control into one node that is expanded while the menu shows
/// and opens it on a long press, as large as the anchor's minimum target.
class _ControlSemantics extends SingleChildRenderObjectWidget {
  const _ControlSemantics({
    required this.expanded,
    required this.onLongPress,
    required super.child,
  });

  final bool expanded;
  final VoidCallback? onLongPress;

  @override
  _RenderControlSemantics createRenderObject(BuildContext context) =>
      _RenderControlSemantics(
        expanded: expanded,
        onLongPress: onLongPress,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderControlSemantics renderObject,
  ) {
    renderObject.expanded = expanded;
    renderObject.onLongPress = onLongPress;
  }
}

class _RenderControlSemantics extends RenderProxyBox {
  _RenderControlSemantics({
    required this._expanded,
    required this._onLongPress,
  });

  bool get expanded => _expanded;
  bool _expanded;
  set expanded(bool value) {
    if (value == _expanded) return;
    _expanded = value;
    markNeedsSemanticsUpdate();
  }

  VoidCallback? get onLongPress => _onLongPress;
  VoidCallback? _onLongPress;
  set onLongPress(VoidCallback? value) {
    if ((value == null) == (_onLongPress == null)) {
      _onLongPress = value;
      return;
    }
    _onLongPress = value;
    markNeedsSemanticsUpdate();
  }

  @override
  Rect get semanticBounds => glassButtonReach.takes(Offset.zero & size);

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
    config.isMergingSemanticsOfDescendants = true;
    config.isExpanded = _expanded;
    if (_onLongPress != null) config.onLongPress = () => _onLongPress?.call();
  }
}
