part of 'plan.dart';

/// Measured numbers the policy trades on. Only joining across space and buying
/// an image read them; everything else is dominance and needs no number.
///
/// In GPU ms per frame on the Pixel 6a (3.50 beta). Sources are in-launch pairs
/// from the 2026-11-05 one-pass results. Some are inferred from those pairs;
/// the sensitivity gate holds the plan to at most two targets more or less when
/// any of them is three times off.
final class PlanPrices {
  /// Creates a price table.
  const PlanPrices({
    this.rasterWeight = 0.3,
    this.passGpu = 0.04,
    this.passRaster = 0.27,
    this.copyGpuPerMpx = 0.35,
    this.deadGpuPerMpx = 0.15,
    this.imageGpu = 0.3,
    this.imageRaster = 2,
    this.pixelsPerLogical = 2.625,
  });

  /// GPU ms one raster ms is worth. At 0.3 the model signs the kept and
  /// rejected group verdicts of 2026-11-05 as they were decided; rails alone
  /// say nearer 0.1, but frame time comes first.
  final double rasterWeight;

  /// One offscreen pass with its pixels unchanged.
  final double passGpu;

  /// One filter on the raster thread: 12 buttons merged saved 0.24-0.31 each.
  final double passRaster;

  /// Copy pixels; about 0.3-0.4 per Mpx at full size, blur included.
  final double copyGpuPerMpx;

  /// Quad pixels nothing draws in: the 0.4 of a screen per filter that
  /// grouping shipped with, at 0.17 per pass.
  final double deadGpuPerMpx;

  /// One image drawn in a frame, its target and submit.
  final double imageGpu;

  /// One image drawn in a frame on the raster thread, inferred from snapshot
  /// shares of 20-46 %.
  final double imageRaster;

  /// Device pixels per logical pixel the areas are priced at.
  final double pixelsPerLogical;

  double _mpx(double logicalArea) =>
      logicalArea * pixelsPerLogical * pixelsPerLogical / 1e6;

  /// What one pass over [band] at [share] costs a frame.
  double passCost(Rect band, int share) =>
      passGpu +
      rasterWeight * passRaster +
      copyGpuPerMpx * _mpx(band.width * band.height) / (share * share);

  /// What one image costs, once.
  double get imageCost => imageGpu + rasterWeight * imageRaster;

  /// How many frames a read over [band] must hold still to pay for its image,
  /// which spares the frame its [targets].
  int rent(Rect band, int share, {int targets = 1}) => math.max(
    1,
    (imageCost /
            (passCost(band, share) +
                (targets - 1) * (passGpu + rasterWeight * passRaster)))
        .ceil(),
  );
}

/// Decisions a person made once.
final class PlanPolicy {
  /// Creates a policy.
  const PlanPolicy({
    this.maxTargets = 24,
    this.maxShapes = geometryMaxShapesPerDraw,
    this.bands = true,
    this.copies = true,
    this.dropsFrost = true,
  });

  /// Whether a band under glass that frosts as wide stays out of what the
  /// glass reads, the glass adding its frost to its own.
  final bool dropsFrost;

  /// Whether a read may come from anything but the live backdrop.
  final bool copies;

  /// Whether glass may draw a scroll edge under it in its own filter.
  final bool bands;

  /// Shapes one shared matte can hold.
  final int maxShapes;

  /// Targets a frame may issue before reads move to images. Counted as
  /// [GlassRead.targets] counts them: a frosted read is two or three.
  final int maxTargets;
}
