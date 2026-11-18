part of 'glass_form.dart';

/// One layer as the composer knows it.
@internal
sealed class FormNode {
  /// Creates the node of [layer].
  FormNode(this.layer);

  /// The layer.
  final Layer layer;

  /// Its place in paint order this frame.
  int order = 0;

  /// The container above.
  OpenNode? parent;

  /// The next sibling.
  FormNode? next;

  /// The frame it last changed.
  int changedAt = 0;

  /// The frame what a read adds for it last changed. A move of what holds it,
  /// which [changedAt] counts, changes none of that, and neither does a
  /// [ShiftNode]'s own offset, which counts for its parent.
  int contentAt = -1;

  /// The innermost container of what one site paints with its glass that
  /// holds it, itself if it is one.
  OpenNode? owner;

  /// What it covers on the screen.
  Rect get extent;

  /// Whether the frame's composing may change what lies here after the walk
  /// read it, so [extent] says nothing about it.
  bool get holdsComposed => false;

  /// Reads the layer; true when what it covers changed.
  bool refreshIn(GlassForm form, FormWorld world);

  /// Notes that this node left the tree.
  void removedFrom(GlassForm form) => form._logGone(extent);
}

/// A picture.
@internal
final class PictureNode extends FormNode {
  /// Creates the node.
  PictureNode(PictureLayer super.layer);

  /// What it drew last.
  ui.Picture? picture;

  /// Its canvas bounds.
  Rect local = Rect.zero;

  /// Where it lies on the screen.
  Rect screen = Rect.zero;

  int _seen = 0;

  @override
  Rect get extent => screen;

  @override
  bool refreshIn(GlassForm form, FormWorld world) {
    form._enter(this);
    final layer = this.layer as PictureLayer;
    final drawn = layer.picture;
    final bounds = layer.canvasBounds;
    if (identical(drawn, picture) &&
        (identical(bounds, local) || bounds == local) &&
        _seen == world.stamp) {
      return false;
    }
    final before = screen;
    if (!identical(drawn, picture)) contentAt = form.frame;
    picture = drawn;
    local = bounds;
    _seen = world.stamp;
    screen = drawn == null ? Rect.zero : world.reaching(bounds);
    changedAt = form.frame;
    form._log(order, _union(before, screen));
    return true;
  }
}

/// What the composer itself shows for a site, whose fate holds no layer of the
/// walk. The plan accounts for it through the site's own facts, so it says
/// nothing about what changed.
@internal
final class OutputNode extends FormNode {
  /// Creates the node.
  OutputNode(GlassSlotLayer super.layer);

  /// The site the slot shows.
  PlanSite? get site => (layer as GlassSlotLayer).site;

  @override
  Rect get extent => Rect.zero;

  @override
  bool get holdsComposed => true;

  @override
  void removedFrom(GlassForm form) {}

  @override
  bool refreshIn(GlassForm form, FormWorld world) {
    form._enter(this);
    return false;
  }
}

/// A kind of content the layer tree can't vouch for between frames: what a
/// read over it may be, what it reaches on the screen and how a person is
/// told it limits a read.
@internal
enum VolatileKind {
  /// A [TextureLayer]: the scene holds the frame it shows under the glass.
  texture(ReadLimit.sceneOnly, 'a texture'),

  /// A [PlatformViewLayer], which only the engine composites.
  platformView(ReadLimit.backdropOnly, 'a platform view'),

  /// A [BackdropFilterLayer], which reads what lies under it.
  backdropFilter(ReadLimit.backdropOnly, 'a backdrop filter'),

  /// A layer type the form does not know, which may draw anywhere.
  unregistered(ReadLimit.backdropOnly, null);

  const VolatileKind(this.limit, this._named);

  /// What it lets a read over it be.
  final ReadLimit limit;

  final String? _named;

  /// Why [layer] of this kind limits a read over it, for a person.
  String reasonFor(Layer layer) => switch (_named) {
    final named? => '$named lies under it',
    null =>
      '${layer.runtimeType} (unregistered) reaches its footprint -> '
          'LiquidGlassUnderlay.registerLayer',
  };
}

/// Content the layer tree can't vouch for between frames: its pixels change
/// with no layer changing. Logged every frame, so nothing holds over it.
@internal
final class VolatileNode extends FormNode {
  /// Creates the node.
  VolatileNode(super.layer, this.kind);

  /// What content it is.
  final VolatileKind kind;

  /// What it may reach on the screen.
  Rect screen = Rect.zero;

  @override
  Rect get extent => screen;

  @override
  bool refreshIn(GlassForm form, FormWorld world) {
    form._enter(this);
    final next = switch ((kind, layer)) {
      (VolatileKind.texture, TextureLayer(:final rect)) ||
      (
        VolatileKind.platformView,
        PlatformViewLayer(:final rect),
      ) => world.reaching(rect),
      (VolatileKind.backdropFilter, _) when world.spread == 0 =>
        world.clip ?? _everywhere,
      _ => _everywhere,
    };
    final changed = next != screen;
    if (changed) screen = next;
    changedAt = form.frame;
    contentAt = form.frame;
    if (form._volatileCount == form._volatile.length) {
      form._volatile.add(this);
    } else {
      form._volatile[form._volatileCount] = this;
    }
    form._volatileCount++;
    form.dirty.add(order, screen);
    return changed;
  }
}
