part of 'glass_form.dart';

/// A container: what it gives its children is its own [world].
@internal
abstract class OpenNode extends FormNode {
  /// Creates the node.
  OpenNode(ContainerLayer super.layer);

  /// What its children inherit.
  late final FormWorld world = FormWorld(_noTransform);

  static final Matrix4 _noTransform = Matrix4.identity();

  /// The first child.
  FormNode? first;

  /// The union of what its children cover.
  Rect bounds = Rect.zero;

  /// One past its last descendant in paint order.
  int end = 0;

  @override
  Rect get extent => bounds;

  /// Whether the frame's composing edits this layer's children.
  bool get composes => false;

  bool _holdsComposed = false;

  @override
  bool get holdsComposed => _holdsComposed;

  /// Whether a flat copy draws it or what it holds otherwise than another
  /// does, so that no layer kept of it serves both.
  bool get drawnByKind => _drawnByKind;
  bool _drawnByKind = false;

  /// The pictures it holds, at any depth. The engine fades one picture by
  /// itself and draws more than one into a layer first, which is a pass.
  @protected
  int leaves = 0;

  /// Whether its children show at all.
  bool get shows => true;

  /// Writes [world] from [outside] and the layer's values; true when any
  /// differs.
  bool updateWorld(FormWorld outside);

  /// Adds to [out] what the layer applies to what it holds, around a read of
  /// [band].
  void enter(SceneOut out, Rect band) {}

  /// The passes [enter] costs a copy: one for each layer it pushes that is
  /// drawn apart, and what a blur takes beside. A [flat] copy
  /// ([SceneOut.flat]) leaves some of them out.
  int saves({required bool flat}) => 0;

  /// Whether [saves] differs for a flat copy.
  bool get savesByKind => false;

  /// Set while reading the layer when what [enter] adds or what it holds
  /// changed.
  @protected
  bool edited = false;

  @override
  void removedFrom(GlassForm form) {
    form._logGone(bounds);
  }

  @override
  bool refreshIn(GlassForm form, FormWorld outside) {
    form._enter(this);
    final moved = updateWorld(outside);
    if (moved) {
      changedAt = form.frame;
      form._log(order, bounds);
      form._suppress++;
    }
    var changed = moved;
    if (shows) {
      if (_walkChildren(form)) changed = true;
    } else {
      _holdsComposed = composes;
      if (first != null || !bounds.isEmpty) {
        if (!moved) form._log(order, bounds);
        first = null;
        changed = true;
        edited = true;
      }
    }
    if (moved) {
      form._suppress--;
    }
    if (saves(flat: false) > 0) form._saving.add(this);
    end = form._next;
    if (changed) {
      _recomputeBounds();
      changedAt = form.frame;
      if (moved) form._log(order, bounds);
    }
    if (edited) {
      edited = false;
      contentAt = form.frame;
    }
    return changed;
  }

  /// What the layer may draw beyond its children, in its parent's coordinates.
  Rect get extra => Rect.zero;

  void _recomputeBounds() {
    var union = extra;
    for (var child = first; child != null; child = child.next) {
      union = _union(union, child.extent);
    }
    bounds = union;
  }

  bool _walkChildren(GlassForm form) {
    final layer = this.layer as ContainerLayer;
    var changed = false;
    var composed = composes;
    var byKind = savesByKind;
    var pictures = 0;
    var old = first;
    FormNode? last;
    for (
      var child = layer.firstChild;
      child != null;
      child = child.nextSibling
    ) {
      FormNode node;
      if (old != null && identical(old.layer, child)) {
        node = old;
        old = old.next;
      } else {
        final found = _ahead(old, child);
        if (found != null) {
          var gone = old!;
          while (!identical(gone, found)) {
            gone.removedFrom(form);
            changed = true;
            edited = true;
            gone = gone.next!;
          }
          node = found;
          old = found.next;
        } else {
          node = _nodeOf(child)..parent = this;
          if (node is! OutputNode) changed = true;
          edited = true;
        }
      }
      if (node.refreshIn(form, world)) changed = true;
      if (node.contentAt == form.frame) edited = true;
      if (node.holdsComposed) composed = true;
      switch (node) {
        case PictureNode(picture: _?):
          pictures++;
        case OpenNode():
          pictures += node.leaves;
          if (node._drawnByKind) byKind = true;
        default:
          break;
      }
      if (last == null) {
        first = node;
      } else {
        last.next = node;
      }
      last = node;
    }
    for (var gone = old; gone != null; gone = gone.next) {
      if (gone is! OutputNode) changed = true;
      edited = true;
      gone.removedFrom(form);
    }
    if (last == null) {
      first = null;
    } else {
      last.next = null;
    }
    _holdsComposed = composed;
    _drawnByKind = byKind;
    leaves = pictures;
    return changed;
  }

  // A list item that left: its next siblings are the same layers.
  static FormNode? _ahead(FormNode? from, Layer child) {
    var node = from?.next;
    for (var i = 0; node != null && i < 8; i++) {
      if (identical(node.layer, child)) return node;
      node = node.next;
    }
    return null;
  }
}

// Teaches the walk a layer type: this is the only place that switches on one.
FormNode _nodeOf(Layer layer) {
  switch (layer) {
    case GlassSlotLayer():
      return OutputNode(layer);
    case PictureLayer():
      return PictureNode(layer);
    // The scene holds the frame the texture shows under the glass: a video
    // whose bars move every frame stays whole across the glass's edge on the
    // iPhone 16 Pro, and a list of videos under glass takes 17 passes on the
    // Pixel 6a where reading it live took 50.
    case TextureLayer():
      return VolatileNode(layer, ReadLimit.sceneOnly);
    case PlatformViewLayer():
      return VolatileNode(layer, ReadLimit.liveOnly);
    case OpacitySeedLayer():
      return OwnNode(layer);
    case BackdropFilterLayer():
      return VolatileNode(layer, ReadLimit.liveOnly);
    case LiquidGlassBackdropFilterLayer():
      return SiteNode(layer);
    case GeometryTransformTrackingLayer():
      return SiteNode(layer);
    case TransformLayer():
      return TransformNode(layer);
    case FollowerLayer():
      return FollowerNode(layer);
    case OpacityLayer():
      return AlphaNode(layer);
    case ImageFilterLayer():
      return FilterNode(layer);
    case ThinOffsetLayer():
      return ShiftNode(layer);
    case OffsetLayer() when layer.runtimeType == OffsetLayer:
      return ShiftNode(layer);
    case ColorFilterLayer():
      return ColorNode(layer);
    case ShaderMaskLayer():
      return MaskNode(layer);
    case ClipRectLayer() ||
        ClipRRectLayer() ||
        ClipRSuperellipseLayer() ||
        ClipPathLayer() ||
        NativeClipLayer():
      return ClipNode(layer as ContainerLayer);
    case LeaderLayer():
      return ShiftNode(layer);
    case AnnotatedRegionLayer():
      return PlainNode(layer as ContainerLayer);
    case ContainerLayer() when layer.runtimeType == ContainerLayer:
      return PlainNode(layer);
    case ContainerLayer() when underlayEffectsOf(layer) != null:
      return EffectsNode(layer);
    case _:
      return VolatileNode(layer, ReadLimit.liveOnly);
  }
}

/// A container that adds nothing.
@internal
class PlainNode extends OpenNode {
  /// Creates the node.
  PlainNode(super.layer);

  @override
  bool updateWorld(FormWorld outside) => world.inherit(outside);
}

/// All one glass paints: what lies here moves back with its glass or lies over
/// it, as the plan decides from the glass's own facts.
@internal
final class OwnNode extends PlainNode {
  /// Creates the node.
  OwnNode(super.layer);

  @override
  bool refreshIn(GlassForm form, FormWorld outside) {
    final above = form._owner;
    form._owner = this;
    final changed = super.refreshIn(form, outside);
    form._owner = above;
    return changed;
  }
}

/// An offset: what most repaint boundaries are, and all a scroll changes.
@internal
class ShiftNode extends OpenNode {
  /// Creates the node.
  ShiftNode(super.layer);

  Offset get _offset => switch (layer) {
    OffsetLayer(:final offset) => offset,
    LeaderLayer(:final offset) => offset,
    _ => Offset.zero,
  };

  @override
  void enter(SceneOut out, Rect band) => out.at += _offset;

  Offset _placed = Offset.zero;

  @override
  bool updateWorld(FormWorld outside) {
    final offset = _offset;
    if (offset != _placed) {
      _placed = offset;
      parent?.edited = true;
    }
    return world.set(
      outside.base,
      outside.dx + offset.dx,
      outside.dy + offset.dy,
      outside.clip,
      outside.state,
      spread: outside.spread,
    );
  }
}

/// A site: where glass or a scroll edge draws. It has one [facts] for its life.
@internal
final class SiteNode extends ShiftNode {
  /// Creates the node.
  SiteNode(super.layer) : facts = SiteFacts(layer);

  /// What the plan reads of it.
  final SiteFacts facts;

  /// The site's layer.
  PlanSite get site => layer as PlanSite;

  Matrix4? _screen;
  Offset _screenAt = Offset.zero;
  int _screenStamp = -1;

  /// The transform from the coordinates [at] in this layer's to the screen's
  /// logical pixels, and whether what lies above can say it: a filter above
  /// moves things in ways no matrix tells. Allocates only when it changed.
  Matrix4? screenTransform(Offset at) {
    if (world.spread > 0) return null;
    final held = _screen;
    if (held != null && _screenStamp == world.stamp && _screenAt == at) {
      return held;
    }
    final next = world.base.clone()
      ..translateByDouble(world.dx + at.dx, world.dy + at.dy, 0, 1);
    _screen = next;
    _screenAt = at;
    _screenStamp = world.stamp;
    return next;
  }

  @override
  bool get composes => true;

  GlassForm? _form;
  int _seen = -1;

  /// Whether this frame's walk reached the site and found nothing changed
  /// around it: where it lies, and all that its parent holds, which is all
  /// that paints with it.
  bool get rests {
    final frame = _form?.frame;
    return frame == _seen &&
        changedAt != frame &&
        parent != null &&
        parent!.changedAt != frame;
  }

  @override
  bool refreshIn(GlassForm form, FormWorld outside) {
    _form = form;
    _seen = form.frame;
    facts.placeInWalk(
      order: form._next,
      index: form._sites.length,
      state: outside.state,
      clip: outside.clip,
    );
    form._sites.add(facts);
    form._siteNodes.add(this);
    site.formNode = this;
    final above = form._owner;
    form._owner = this;
    final changed = super.refreshIn(form, outside);
    form._owner = above;
    return changed;
  }
}
