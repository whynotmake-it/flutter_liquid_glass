# Transform tracking: analysis and what shipped

## Why tracking exists

The glass layer renders all registered shapes in one consolidated, retained
pass (the alternative — a backdrop pass per shape — costs a readback per
shape). The layer positions each shape's matte from transforms read at its
own paint(). Flutter only calls paint() when markNeedsPaint propagates
through repaint boundaries, but shapes can move via boundary offset updates,
layer-property updates, and scroll without that — so an independent
notification is required, or mattes stay stale forever.

## Mechanism

GeometryTransformTrackingLayer is a lightweight sentinel layer whose
updateSubtreeNeedsAddToScene hook diffs transforms before the scene is built.
Flutter traverses that method unconditionally on every built scene — no forced
dirtiness is needed for the poll to run. Detected changes mark only the
affected branches dirty (layer property setters call markNeedsAddToScene),
which preserves same-frame updates for uniform translation and retained
geometry refresh while leaving idle frames fully retained.

GPU command buffers are flushed at the end of the same hook, after refresh —
not in addToScene, which retained ancestors can bypass.

## Limitation (issue 2, documented not fixed)

pollRelativeTransforms uses getTransformTo: layout offsets plus
applyPaintTransform overrides. Transforms an ancestor applies inside paint()
via PaintingContext.pushTransform are invisible to it — the child moves, the
glass does not. Acceptable in practice; fixing it means reading composited
transforms from the layer tree (e.g. marker layers at each shape's paint
position), a separate project. Render objects that transform in paint should
override applyPaintTransform instead — then the tracking sees them.

## Alternatives considered

- Layer.addCompositionCallback: fires on every composite incl. retained, but
  post-recording with a no-mutation contract — every update lands a frame
  late. Observer only.
- Per-shape passes: correct-by-construction, abandoned for consolidation.
- Upstream: a "composited transform changed" notification would make the
  sentinel unnecessary; not needed for the retention win shipped here.
