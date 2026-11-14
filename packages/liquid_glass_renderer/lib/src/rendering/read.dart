import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_frost.dart'
    show InPlaceFrost, frostInPlace;
import 'package:liquid_glass_renderer/src/rendering/copy_haze.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_read.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_blur.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_form.dart';
import 'package:liquid_glass_renderer/src/rendering/running_under_flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/scene_out.dart';

/// A layer the frame's plan decides for.
///
/// The view's composer asks each site for its facts, compiles the plan and
/// tells each its fate, in paint order, before the scene is built.
@internal
abstract interface class PlanSite {
  /// Where this frame's walk of the layers found the site.
  SiteNode? formNode;

  /// What the site asks of this frame: a new value each frame, which the
  /// form keeps only where it differs from the last.
  SiteAsk ask();

  /// This frame's [fate], before any read of the frame is drawn. A site that
  /// draws no read of its own takes its place here.
  void beginFate(SiteFate fate);

  /// Draws [read], which this site leads, from [pixels].
  void show(GlassRead read, ReadPixels pixels);

  /// Adds the read this site leads to [out], inside a copy of what lies under
  /// glass over it.
  void addOutput(SceneOut out, ReadCopy outer);

  /// Whether this frame's read draws what the site's layer holds, so a replay
  /// leaves it out.
  bool get drawsOwnChildren;

  /// Whether a replay meets the site's output where it meets the site, rather
  /// than at a [GlassSlotLayer] further on.
  bool get outputsInPlace;

  /// The frame's plan is drawn: what held for the frame lets go.
  void endFrame();
}

/// Where the pixels of a read its lead draws lie this frame.
@internal
sealed class ReadPixels {
  const ReadPixels();
}

/// The read's copy, laid out over its layer in the frame's scene: a layer
/// that replays what lies under the lead when the scene is added.
@internal
final class InScene extends ReadPixels {
  /// Creates the pixels.
  const InScene(this.corner);

  /// The copy's layer.
  final CornerRead corner;
}

/// An image of the read's copy.
@internal
final class OnPage extends ReadPixels {
  /// Creates the pixels.
  const OnPage(this.page);

  /// Where the read's copy lies in its image.
  final PageCopy page;
}

/// The live backdrop.
@internal
final class LiveBackdrop extends ReadPixels {
  /// Creates the pixels.
  const LiveBackdrop(this.group);

  /// The key the read shares one copy of the backdrop under, if it does.
  final BackdropKey? group;
}

/// Glass that draws other sites of its read in its own filter.
@internal
abstract interface class ReadPainter {
  /// The filter that draws [read] over [corner].
  ui.ImageFilter readFilter(GlassRead read, CornerRead corner);

  /// Equal while [recordPage] draws the same for [read] over [page].
  Object pageKey(GlassRead read, PageCopy page);

  /// Records [read] over [page], in the coordinates [screenToCanvas] takes the
  /// screen's device pixels to.
  ui.Picture recordPage(GlassRead read, PageCopy page, Matrix4 screenToCanvas);
}

/// The role of glass whose [painter] draws the read it is the first glass of.
///
/// Equal while the same painter's origin stays in place on the screen, so a
/// resting glass asks the same.
@internal
final class PainterRole extends GlassSiteRole {
  /// Creates the role of [painter] whose transform puts its origin at
  /// [originOnScreen] this frame.
  const PainterRole(this.painter, {required this.originOnScreen});

  /// What draws the read.
  final ReadPainter painter;

  /// Where the glass's transform puts its origin on the screen this frame, in
  /// logical pixels.
  final Offset originOnScreen;

  @override
  bool operator ==(Object other) =>
      other is PainterRole &&
      identical(other.painter, painter) &&
      other.originOnScreen == originOnScreen;

  @override
  int get hashCode => Object.hash(identityHashCode(painter), originOnScreen);
}

/// Where a site's fate shows in the layer tree: the walk does not go in, and
/// what is in here says nothing to the plan.
@internal
class GlassSlotLayer extends ContainerLayer {
  /// The site the slot shows.
  PlanSite? site;
}

/// A read as a layer of the scene.
///
/// While nothing under its band and nothing of its filter changed, it stays out
/// of the scene's rebuild: the engine layer it made holds.
@internal
final class ReadLayer extends ContainerLayer {
  ui.TransformEngineLayer? Function(ui.SceneBuilder builder)? _add;

  /// What the read keeps of the frame between the scenes it is added to.
  final held = HeldLayers();

  /// Shows what [add] adds, which returns the engine layer around it. Unless
  /// [changed], the engine layer of the last frame stands for it.
  void show(
    ui.TransformEngineLayer? Function(ui.SceneBuilder builder) add, {
    required bool changed,
  }) {
    _add = add;
    if (changed) markNeedsAddToScene();
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    engineLayer = _add?.call(builder);
    held.built();
  }

  @override
  void dispose() {
    held.dispose();
    super.dispose();
  }
}

/// Whether glass reads copies of what lies under it, for a test: true or
/// false decides, null goes back to the default.
///
/// An app's glass reads copies wherever Impeller renders. Under
/// `flutter test` it reads none unless a test sets this to true, so a test
/// that checks what an app draws turns it on.
bool? debugGlassCopies;

/// Whether glass reads copies of what lies under it ([debugGlassCopies]).
@internal
abstract final class GlassCopies {
  static final bool _defaultEnabled =
      !kIsWeb &&
      ui.ImageFilter.isShaderFilterSupported &&
      !runningUnderFlutterTest;

  /// Whether glass layers keep copies of what lies under them.
  static bool get enabled => debugGlassCopies ?? _defaultEnabled;

  /// How many images were drawn.
  @visibleForTesting
  static int debugImagesDrawn = 0;

  /// How many filtered layers the pages were drawn in.
  @visibleForTesting
  static int debugBlurLayers = 0;
}

// Content clipped away reaches no band, even where its empty rect lies across
// one.
bool _meets(Rect bounds, Rect band) => !bounds.isEmpty && bounds.overlaps(band);

/// What lies under one read of a frame, drawn again from the frame's own
/// layers: the layer tree before the read's lead, in a band of the screen.
///
/// Glass in the band that the plan says lies under the read adds its own read
/// in here, so a read holding glass takes one more target per glass it holds.
/// The read's filter reads it: Impeller renders it into a target of its render
/// target cache, ahead of the frame's pass in the frame's one submission, and
/// draws the filter's output straight into the pass. The text in the copy is
/// the frame's own, sharing its glyph atlas and its text shadow cache, which an
/// image drawn between frames empties.
@internal
final class ReadCopy {
  /// The copy of [read], replayed from the layers of the frame a form
  /// lowered, under the frame's plan.
  ReadCopy(this.read, this._plan, this._form);

  /// The read this copy is for.
  final GlassRead read;

  final GlassPlan _plan;
  final GlassForm _form;

  /// Where the copy of [held], whose glass this copy holds, lies inside this
  /// one, or null where none of it does.
  CornerRead? cornerOf(GlassRead held) {
    final geometry = held.geometry;
    final cut = geometry.heldIn(read.geometry).intersect(geometry.layer);
    final band = read.geometry.band;
    return cut.isEmpty
        ? null
        : CornerRead(
            ReadCopy(held, _plan, _form),
            cut,
            read.geometry.lattice.share,
            geometry.clip?.intersect(band) ?? band,
          );
  }

  /// Adds the copy at [origin], its pixels holding [lattice]'s share of the
  /// device pixels of the layer it is drawn in. What holds between scenes is
  /// kept in [held], the layers of the reader [builder]'s part of the scene
  /// belongs to.
  void addTo(
    ui.SceneBuilder builder,
    Lattice lattice,
    Offset origin,
    Rect within,
    HeldLayers held,
  ) {
    builder.pushClipRect(
      rectIn(lattice, origin, within),
      clipBehavior: Clip.hardEdge,
    );
    _replay(builder, lattice, read.geometry.band, origin, held);
    builder.pop();
  }

  /// The rect the copy fills at [origin] on [lattice], inside [within].
  Rect rectIn(Lattice lattice, Offset origin, Rect within) {
    final band = read.geometry.band;
    final pixels = lattice.pixels;
    return (origin & Size(band.width * pixels, band.height * pixels)).intersect(
      within,
    );
  }

  // Adds the glass of [site] if this copy holds its read.
  void _addHeld(PlanSite site, SceneOut out) {
    final facts = site.formNode?.facts;
    if (facts == null || facts.index >= _plan.fates.length) return;
    final fate = _plan.fates[facts.index];
    if (fate is LeadFate && read.holds.contains(fate.read)) {
      site.addOutput(out, this);
    }
  }

  void _replay(
    ui.SceneBuilder builder,
    Lattice lattice,
    Rect rect,
    Offset at,
    HeldLayers held,
  ) {
    final out = SceneOut(
      builder,
      lattice.deviceToCopy(rect, at),
      held,
      flat: read.flat,
    );
    final top = _form.top;
    if (top is OpenNode) _Replay(out, this, rect).from(top);
    out.finish();
  }
}

// Adds what lies before a read's lead in a rect of the screen. Stops at the
// lead: past it, nothing of the frame lies under the glass.
final class _Replay {
  _Replay(this.out, this.copy, this.band) : stop = copy.read.lead.order;

  final SceneOut out;
  final ReadCopy copy;
  final Rect band;
  final int stop;

  void from(OpenNode top) {
    out.mark();
    top.enter(out, band);
    children(top);
    out.leave();
  }

  // False once the replay reached the lead.
  bool children(OpenNode node) {
    final read = copy.read;
    final parts = read.members.length > 1 && read.geometry.room == null
        ? read.members
        : null;
    for (var child = node.first; child != null; child = child.next) {
      if (child.order >= stop) return false;
      switch (child) {
        case PictureNode(:final screen):
          final layer = child.layer as PictureLayer;
          // Glass moved its shadows into its slot this frame.
          if (!identical(layer.parent, node.layer)) continue;
          if (layer.picture == null || !_meets(screen, band)) continue;
          if (parts != null && !parts.any((m) => _meets(screen, m.ask.reads))) {
            continue;
          }
          if (!kReleaseMode) GlassWork.replayed++;
          out.picture(layer.picture!);
        case OutputNode(:final site?):
          copy._addHeld(site, out);
        case OutputNode():
          break;
        case VolatileNode(
          layer: final TextureLayer texture,
          limit: ReadLimit.sceneOnly,
          :final screen,
        ):
          if (_meets(screen, band)) out.texture(texture);
        case VolatileNode():
          break;
        case final SiteNode site:
          if (!site.holdsComposed &&
              site.end <= stop &&
              !_meets(site.bounds, band)) {
            continue;
          }
          out.mark();
          site.enter(out, band);
          if (site.site.outputsInPlace) copy._addHeld(site.site, out);
          final through = site.site.drawsOwnChildren
              ? site.end <= stop
              : children(site);
          out.leave();
          if (!through) return false;
        case final OpenNode open:
          if (!open.holdsComposed &&
              open.end <= stop &&
              !_meets(open.bounds, band)) {
            continue;
          }
          if (_addHeld(open, parts)) continue;
          out.mark();
          open.enter(out, band);
          final through = children(open);
          out.leave();
          if (!through) return false;
      }
    }
    return true;
  }

  // Adds [open] as one layer the reader keeps between scenes, while it holds
  // no glass and nothing in it changed: a scroll moves rows, not what lies in
  // them. False where it has to be walked.
  bool _addHeld(OpenNode open, List<SiteFacts>? parts) {
    final layers = out.held;
    if (open.holdsComposed ||
        open.drawnByKind ||
        open.contentAt == copy._form.frame ||
        layers.holds(open) ||
        open.end - open.order < _heldLayers) {
      return false;
    }
    if (parts != null && !parts.any((m) => _meets(open.bounds, m.ask.reads))) {
      return true;
    }
    final moves = open is ShiftNode;
    out.mark();
    if (moves) open.enter(out, band);
    out.settle();
    final builder = out.builder;
    if (layers.take(open, open.contentAt) case final held?) {
      builder.addRetained(held);
    } else {
      layers.keep(open, open.contentAt, builder.pushOffset(0, 0));
      final inner = SceneOut(builder, null, layers);
      if (!moves) open.enter(inner, Rect.largest);
      _addWhole(open, inner);
      inner.finish();
      builder.pop();
    }
    out.leave();
    return true;
  }

  // All that [node] holds, wherever it lies now: the next frames' reads keep it
  // as it moves into them.
  void _addWhole(OpenNode node, SceneOut out) {
    for (var child = node.first; child != null; child = child.next) {
      switch (child) {
        case PictureNode(:final picture?):
          if (!kReleaseMode) GlassWork.replayed++;
          out.picture(picture);
        case final OpenNode open:
          out.mark();
          open.enter(out, Rect.largest);
          _addWhole(open, out);
          out.leave();
        default:
          break;
      }
    }
  }
}

// Fewer layers than this add no fewer calls to a scene held than walked: an
// offset and its picture take as many as an offset and a held layer.
const _heldLayers = 3;

/// Where a read's page lies in an image: [rect] of the screen, in logical
/// pixels. Glass reads it as [glassSampling] says, a surface paints the part
/// [readOf] gives.
@internal
final class PageCopy {
  PageCopy._(this.image, this.geometry, this.offset, this._held);

  /// The image, shared with other pages of its frame.
  final ui.Image image;

  /// Where the read's pixels lay when the page was drawn.
  final ReadGeometry geometry;

  /// Where the page lies in [image], in its pixels.
  final Offset offset;

  // The frost drawn into the page, in logical pixels: 0 where it holds none.
  final double _held;

  /// The screen rect the page holds, in logical pixels.
  Rect get rect => geometry.imageRect!;

  /// Where the page lies in [image].
  @visibleForTesting
  Offset get debugOffset => offset;

  /// Equal while the page lies at the same place on the same grid.
  Object get placement => (offset, geometry.lattice);

  /// What [glassSampling] stands for by the frost [sigma] of a band.
  double frostOf(double sigma) => geometry.lattice.residual(sigma);

  /// What [glassSampling] stands for by the frost drawn into the page: 0
  /// where it holds none.
  double get heldFrost => geometry.lattice.residual(geometry.frostFor(_held));

  /// The sigma, in device pixels, the taps still frost the page by for
  /// Impeller's blur by [frost] (logical pixels): none where the page holds
  /// that frost.
  double frostLeft(double frost) => tapFrost(
    frost,
    held: _held,
    residual: (frost) => geometry.lattice.residual(geometry.frostFor(frost)),
  );

  // Where the shader's fragment zero lies on the screen, in device pixels.
  Offset get _origin {
    final lattice = geometry.lattice;
    return rect.topLeft * lattice.devicePixelRatio -
        offset * lattice.share.toDouble();
  }

  /// How the final shader reads the page, painted in the screen's device
  /// pixels, to frost it for Impeller's blur by [frost] (see
  /// [GlassSampling.frost]).
  GlassSampling glassSampling(double frost) {
    final lattice = geometry.lattice;
    final share = lattice.share;
    return GlassSampling(
      origin: _origin,
      reduced: share > 1 ? 1 : 0,
      frost: frostLeft(frost),
      image: image,
      size: Size(
        image.width * share.toDouble(),
        image.height * share.toDouble(),
      ),
    );
  }

  /// The part [shown] (screen logical pixels, inside [rect]) of the page.
  PagePart readOf(Rect shown) => PagePart(this, shown);

  /// The rect [drawn] (screen logical pixels) covers in the fragments
  /// [glassSampling] gives.
  Rect fragmentsOf(Rect drawn) {
    final dpr = geometry.lattice.devicePixelRatio;
    final cut = drawn.intersect(rect);
    return cut.scaled(dpr).shift(-_origin);
  }

  void _dispose() => image.dispose();
}

// One read's page in a frame's images.
final class _Tile {
  _Tile(this.copy, this.page)
    : _pixels = copy.read.geometry.lattice.pixelsOf(
        copy.read.geometry.imageRect!,
      );

  final ReadCopy copy;
  final PageFilter page;
  final (int, int) _pixels;

  ReadGeometry get geometry => copy.read.geometry;
  Lattice get lattice => geometry.lattice;
  Rect get rect => geometry.imageRect!;

  int get width => _pixels.$1;
  int get height => _pixels.$2;

  // Where the page lies in the image, in its pixels.
  Offset offset = Offset.zero;

  Rect get bounds => offset & Size(width.toDouble(), height.toDouble());

  bool get filtered => page.key != null;

  // Whether the page is filtered in the image's layer of pages rather than as
  // a backdrop of its own.
  bool get layered => switch (page.blur) {
    (final x, final y) =>
      max(x, y) * lattice.pixels <= _Pages._maxImageBlurSigma,
    null => false,
  };

  // What frosts the page in a layer of its own, and the frost it then holds;
  // for an unfiltered page alone.
  late final InPlaceFrost inPlace = frostInPlace(geometry.bakedIn(1), () {
    final size = Size(width.toDouble(), height.toDouble());
    return FrostSampling(
      size: size,
      bounds: Rect.fromLTRB(0.5, 0.5, size.width - 0.5, size.height - 0.5),
      frost:
          lattice.residual(geometry.frostFor(geometry.bakedIn(1))) /
          lattice.share,
      scale: 1,
      shown: Offset.zero & size,
    );
  });

  // What mixes the page's haze into it in layers of its own; for an
  // unfiltered page alone.
  late final CopyHaze? haze = switch (geometry.haze) {
    final haze? => CopyHaze.of(
      haze,
      copy: bounds.size,
      rect: Offset.zero & bounds.size,
      pixels: lattice.pixels,
    ),
    null => null,
  };
}

// The pages of a frame's reads, one image for all that can share one: every
// image drawn on its own costs the raster thread a render pass, a texture and a
// command buffer, and the GPU driver a submission.
final class _Pages {
  // Gap between pages, in device pixels: sampling between pixels at a page's
  // edge reads no neighbour.
  static const int _gap = 2;
  static const int _rowWidth = 2048;
  static const int _maxHeight = 4096;

  // Impeller downsamples an image filter's blur on a grid of its own and a
  // backdrop filter's on the target's: past this sigma in a page's pixels
  // the two part by up to 15 levels at some sizes (host parity), so a page
  // blurred more is blurred as a backdrop filter.
  static const double _maxImageBlurSigma = 14;

  // The pages' blurs, held across frames: dart:ui converts each new filter
  // to a native one again. Glass asks for few distinct blurs, so the held
  // ones are dropped all at once when that grows past a handful.
  static final _blurs = <(double, double), ui.ImageFilter>{};

  static ui.ImageFilter _blur(double sigmaX, double sigmaY) {
    final key = (sigmaX, sigmaY);
    if (_blurs[key] case final held?) return held;
    if (_blurs.length >= 16) _blurs.clear();
    if (!kReleaseMode) GlassWork.filters++;
    return _blurs[key] = ui.ImageFilter.blur(
      sigmaX: sigmaX,
      sigmaY: sigmaY,
      tileMode: glassBlurTileMode,
    );
  }

  final _held = Map<Object, PageCopy>.identity();

  // What the images keep of the frame between the scenes they are drawn from.
  final _layers = HeldLayers();

  PageCopy? held(GlassRead read) => _held[read.lead.id];

  // Draws [tiles], which hold no glass one of them reads from an image not yet
  // drawn.
  void draw(List<_Tile> tiles) {
    final runs = <Object?, List<_Tile>>{};
    for (final tile in tiles) {
      runs
          .putIfAbsent(
            !tile.filtered ? null : (tile.page.key, tile.lattice, tile.layered),
            () => [],
          )
          .add(tile);
    }
    _pack(runs.values.toList());
  }

  // Every run starts a row of its own, so that the rect around a run's
  // pages holds no other page.
  void _pack(List<List<_Tile>> runs) {
    final batch = [for (final run in runs) ...run];
    final starts = Set<_Tile>.identity();
    for (final run in runs) {
      starts.add(run.first);
    }
    var start = 0;
    while (start < batch.length) {
      final tiles = <_Tile>[];
      var x = 0;
      var y = 0;
      var row = 0;
      var width = 0;
      for (final tile in batch.skip(start)) {
        final limit = tile.width > _rowWidth ? tile.width : _rowWidth;
        if (x > 0 && (x + tile.width > limit || starts.contains(tile))) {
          x = 0;
          y += row + _gap;
          row = 0;
        }
        if (tiles.isNotEmpty && y + tile.height > _maxHeight) break;
        tile.offset = Offset(x.toDouble(), y.toDouble());
        tiles.add(tile);
        x += tile.width + _gap;
        if (x - _gap > width) width = x - _gap;
        if (tile.height > row) row = tile.height;
      }
      start += tiles.length;
      _draw(tiles, width, y + row);
    }
  }

  // From the screen's logical pixels to [tile]'s place in the image.
  static Matrix4 _toAtlas(_Tile tile) {
    final pixels = tile.lattice.pixels;
    return Matrix4.translationValues(
      tile.offset.dx - tile.rect.left * pixels,
      tile.offset.dy - tile.rect.top * pixels,
      0,
    )..scaleByDouble(pixels, pixels, 1, 1);
  }

  void _draw(List<_Tile> tiles, int width, int height) {
    if (!kReleaseMode) GlassWork.images++;
    GlassCopies.debugImagesDrawn++;
    final b = ui.SceneBuilder();
    void add(_Tile tile, Rect within) {
      b.pushClipRect(within, clipBehavior: Clip.hardEdge);
      tile.copy._replay(b, tile.lattice, tile.rect, tile.offset, _layers);
      b.pop();
    }

    final isolated = <_Tile>[];
    // Pages under one blur share one filtered layer: the filter reads the
    // pages alone, so no backdrop is copied for it, and the layer is
    // clipped to the rows of the pages' run, which hold no other page.
    final layered = <(Object?, Lattice), List<_Tile>>{};
    for (final tile in tiles) {
      if (!tile.filtered) {
        final filter = tile.inPlace.filter;
        final haze = tile.haze;
        if (filter == null && haze == null) {
          add(tile, tile.bounds);
        } else {
          final size = tile.bounds.size;
          b.pushOffset(tile.offset.dx, tile.offset.dy);
          // The strip of a haze lies under its page, where the next row's
          // pages may: the haze draws nothing there.
          haze?.push(b, Offset.zero);
          filter?.push(b, Offset.zero, size);
          b.pushClipRect(Offset.zero & size, clipBehavior: Clip.hardEdge);
          tile.copy._replay(b, tile.lattice, tile.rect, Offset.zero, _layers);
          b.pop();
          filter?.pop(b);
          haze?.pop(b);
          b.pop();
        }
      } else if (tile.layered) {
        layered.putIfAbsent((tile.page.key, tile.lattice), () => []).add(tile);
      } else {
        isolated.add(tile);
      }
    }
    for (final group in layered.values) {
      GlassCopies.debugBlurLayers++;
      final first = group.first;
      var bounds = first.bounds;
      for (final tile in group.skip(1)) {
        bounds = bounds.expandToInclude(tile.bounds);
      }
      b
        ..pushClipRect(bounds, clipBehavior: Clip.hardEdge)
        // Impeller takes an image filter's sigmas in the pixels it draws
        // into, whatever the canvas scale: here the pages' own.
        ..pushImageFilter(
          _blur(
            first.page.blur!.$1 * first.lattice.pixels,
            first.page.blur!.$2 * first.lattice.pixels,
          ),
        );
      for (final tile in group) {
        add(tile, tile.bounds);
      }
      b
        ..pop()
        ..pop();
    }
    // A page's own filter stands under the view's scale, as the backdrop
    // filter it replaces does. In a layer around its page it reads that layer
    // alone; drawn straight into the image, Impeller blurs the whole image.
    for (final tile in isolated) {
      final page = tile.page;
      final filter = page.filter ?? _blur(page.blur!.$1, page.blur!.$2);
      b.pushClipRect(tile.bounds, clipBehavior: Clip.antiAliasWithSaveLayer);
      add(tile, tile.bounds);
      b
        ..pushTransform(_toAtlas(tile).storage)
        ..pushClipRect(
          page.clip?.intersect(tile.rect) ?? tile.rect,
          clipBehavior: Clip.hardEdge,
        )
        ..pushBackdropFilter(filter, blendMode: page.blendMode)
        ..pop()
        ..pop()
        ..pop()
        ..pop();
    }
    // The last row's hazes keep their strips under it.
    var rows = height;
    for (final tile in tiles) {
      if (tile.filtered) continue;
      if (tile.haze case final haze?) {
        rows = max(rows, (tile.offset.dy + haze.size.height).ceil());
      }
    }
    final scene = b.build();
    final image = scene.toImageSync(width, rows);
    scene.dispose();
    for (final tile in tiles) {
      final id = tile.copy.read.lead.id;
      _held[id]?._dispose();
      _held[id] = PageCopy._(
        image.clone(),
        tile.geometry,
        tile.offset,
        tile.filtered ? 0 : tile.inPlace.sigma,
      );
    }
    image.dispose();
  }

  // Lets go of the pages of leads [keep] does not name.
  void retain(Set<Object> keep) {
    _held.removeWhere((id, page) {
      if (keep.contains(id)) return false;
      page._dispose();
      return true;
    });
  }

  /// The frame's images are drawn.
  void drawn() => _layers.built();

  void dispose() {
    retain(const {});
    _layers.dispose();
  }
}

/// Draws a frame's [GlassPlan]: every route of the frame is a value in there.
@internal
final class GlassEmit {
  final _pages = _Pages();

  // Keys of the view's live groups, the same ones every frame, so a plan that
  // holds adds nothing to the scene again.
  final _liveKeys = <BackdropKey>[];

  BackdropKey? _liveKeyOf(GlassRead read) {
    final group = read.liveGroup;
    if (group == null) return null;
    while (_liveKeys.length <= group) {
      _liveKeys.add(BackdropKey());
    }
    return _liveKeys[group];
  }

  /// Tells each site of [form] its fate and draws what the reads need before
  /// the scene is built, deepest last, so what a page holds is drawn by then.
  ///
  /// [again] shows a plan an earlier frame emitted: the images it bought are
  /// drawn already.
  void emit(GlassPlan plan, GlassForm form, {required bool again}) {
    final reads = plan.reads;
    var deepest = 0;
    final keep = Set<Object>.identity();
    for (final read in reads) {
      if (read.source is ImageRead) keep.add(read.lead.id);
      deepest = max(deepest, read.level);
    }
    _pages.retain(keep);
    for (var i = 0; i < plan.fates.length; i++) {
      form.siteNodes[i].site.beginFate(plan.fates[i]);
    }
    // What the pages hold reads the mattes paint and the fates wrote: all
    // of them are placed by now, so one pass draws them, ahead of the
    // images below and of the scene.
    FlutterGpuGeometryRenderer.flush();
    for (var level = 0; level <= deepest; level++) {
      final tiles = <_Tile>[];
      for (final read in reads) {
        if (read.level != level) continue;
        if (read.source case ImageRead(:final held)) {
          if ((held || again) && _pages.held(read) != null) continue;
          tiles.add(
            _Tile(
              ReadCopy(read, plan, form),
              read.lead.ask.look.page ?? PageFilter.none,
            ),
          );
        }
      }
      if (tiles.isNotEmpty) _pages.draw(tiles);
      for (final read in reads) {
        if (read.level != level) continue;
        form.siteNodes[read.lead.index].site.show(read, switch (read.source) {
          SceneRead() => InScene(
            CornerRead.inFrame(ReadCopy(read, plan, form)),
          ),
          ImageRead() => OnPage(_pages.held(read)!),
          LiveRead() => LiveBackdrop(_liveKeyOf(read)),
        });
      }
    }
    _pages.drawn();
  }

  /// Lets go of what the frame's reads hold.
  void dispose() => _pages.dispose();
}
