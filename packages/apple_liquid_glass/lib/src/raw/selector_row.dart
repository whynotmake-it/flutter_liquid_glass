part of 'selector.dart';

/// The items of a selector in their slots, each as two children, its
/// regular look and a copy of its selected look, which shows inside the
/// lens and over it, then the items fading out, and the lens last when the
/// look gives one; laying them out publishes the slots to the selector's
/// motion in the resolve phase.
class _SelectorRow extends MultiChildRenderObjectWidget {
  const _SelectorRow({
    required this.motion,
    required this.frames,
    required this.kind,
    required this.keys,
    required this.ghosts,
    required this.itemWidths,
    required this.proportional,
    required this.collapse,
    required this.hosted,
    required this.showsLens,
    required this.hasLens,
    required this.lensContent,
    required super.children,
  });

  final SelectorMotion motion;
  final _SelectorFrames frames;
  final GlassSelectorMotion kind;
  final List<Object> keys;
  final List<Object> ghosts;
  final List<double?>? itemWidths;
  final bool proportional;
  final GlassSelectorCollapse? collapse;
  final bool hosted;
  final bool showsLens;

  /// Whether the last child is the lens.
  final bool hasLens;

  /// How the lens's renderer shows the selected copies, or null as they
  /// are.
  final ValueListenable<GlassLensContent?> lensContent;

  @override
  MultiChildRenderObjectElement createElement() => _SelectorRowElement(this);

  @override
  _RenderSelectorRow createRenderObject(BuildContext context) =>
      _RenderSelectorRow(
        motion: motion,
        frames: frames,
        kind: kind,
        keys: keys,
        ghosts: ghosts,
        itemWidths: itemWidths,
        proportional: proportional,
        collapse: collapse,
        hosted: hosted,
        showsLens: showsLens,
        hasLens: hasLens,
        lensContent: lensContent,
        direction: Directionality.maybeOf(context) ?? TextDirection.ltr,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSelectorRow renderObject,
  ) {
    renderObject.motion = motion;
    renderObject.frames = frames;
    renderObject.kind = kind;
    renderObject.keys = keys;
    renderObject.ghosts = ghosts;
    renderObject.itemWidths = itemWidths;
    renderObject.proportional = proportional;
    renderObject.collapse = collapse;
    renderObject.hosted = hosted;
    renderObject.showsLens = showsLens;
    renderObject.hasLens = hasLens;
    renderObject.lensContent = lensContent;
    renderObject.direction =
        Directionality.maybeOf(context) ?? TextDirection.ltr;
  }
}

// The selected copies are drawn only inside the lens; like an
// IndexedStack's hidden children, they are offstage to finders.
class _SelectorRowElement extends MultiChildRenderObjectElement {
  _SelectorRowElement(_SelectorRow super.widget);

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    final items = children.length - ((widget as _SelectorRow).hasLens ? 1 : 0);
    var i = 0;
    for (final child in children) {
      if (i >= items || i.isEven) visitor(child);
      i++;
    }
  }
}
