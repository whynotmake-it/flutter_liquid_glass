part of 'selector.dart';

/// The tab bar's semantics node, holding its tabs: without a tab that
/// shows (a bar given no room), it is no tab bar.
class _TabBarNode extends SingleChildRenderObjectWidget {
  const _TabBarNode({
    required this.frames,
    required this.hasTabs,
    required super.child,
  });

  final Listenable frames;
  final bool Function() hasTabs;

  @override
  _RenderTabBarNode createRenderObject(BuildContext context) =>
      _RenderTabBarNode(frames, hasTabs);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTabBarNode renderObject,
  ) {
    renderObject.frames = frames;
    renderObject.hasTabs = hasTabs;
  }
}

class _RenderTabBarNode extends RenderProxyBox {
  _RenderTabBarNode(this._frames, this.hasTabs);

  bool Function() hasTabs;

  Listenable _frames;
  Listenable get frames => _frames;
  set frames(Listenable value) {
    if (identical(value, _frames)) return;
    if (attached) _frames.removeListener(markNeedsSemanticsUpdate);
    _frames = value;
    if (attached) _frames.addListener(markNeedsSemanticsUpdate);
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _frames.addListener(markNeedsSemanticsUpdate);
  }

  @override
  void detach() {
    _frames.removeListener(markNeedsSemanticsUpdate);
    super.detach();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
    config.explicitChildNodes = true;
    if (hasTabs()) config.role = SemanticsRole.tabBar;
  }
}

/// [selection] heard in the frame it moves: the items move in the resolve
/// phase, after the layout that places them, where only a render listener
/// hears them.
final class _HeardInResolve implements Listenable {
  const _HeardInResolve(this.selection);

  final MotionSelection<Object?> selection;

  @override
  void addListener(VoidCallback listener) =>
      selection.addRenderListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      selection.removeRenderListener(listener);
}

/// The selector's box: its semantics node, and where it takes touches,
/// inside [frame]'s body (a bar under a collapse spans its group, and what
/// is beside the bar or the circle stays free) and, for the 44 point
/// target the region below grows, past its own size.
class _SelectorBox extends SingleChildRenderObjectWidget {
  const _SelectorBox({
    required this.frame,
    required this.label,
    required super.child,
  });

  final ValueListenable<GlassFrame>? frame;
  final String? label;

  @override
  _RenderSelectorBox createRenderObject(BuildContext context) =>
      _RenderSelectorBox(
        frame: frame,
        label: label,
        direction: Directionality.maybeOf(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSelectorBox renderObject,
  ) {
    renderObject.frame = frame;
    renderObject.label = label;
    renderObject.direction = Directionality.maybeOf(context);
  }
}

class _RenderSelectorBox extends RenderProxyBox {
  _RenderSelectorBox({
    required this.frame,
    required this._label,
    required this._direction,
  });

  ValueListenable<GlassFrame>? frame;

  String? _label;
  String? get label => _label;
  set label(String? value) {
    if (value == _label) return;
    _label = value;
    markNeedsSemanticsUpdate();
  }

  TextDirection? _direction;
  TextDirection? get direction => _direction;
  set direction(TextDirection? value) {
    if (value == _direction) return;
    _direction = value;
    markNeedsSemanticsUpdate();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final rect = frame?.value.rect;
    if (rect != null && !rect.contains(position)) return false;
    if (!hitTestChildren(result, position: position)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
    config.explicitChildNodes = true;
    if (_label case final label?) {
      config.label = label;
      config.textDirection = _direction;
    }
  }
}
