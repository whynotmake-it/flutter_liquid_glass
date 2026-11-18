part of 'plan.dart';

/// Measured numbers the policy trades on. Only joining across space and buying
/// an image read them; everything else is dominance and needs no number.
///
/// In GPU ms per frame on the Pixel 6a (3.50 beta). Sources are in-launch pairs
/// from the 2026-11-05 one-pass results. Some are inferred from those pairs;
/// the sensitivity gate holds the plan to at most two targets more or less when
/// any of them is three times off.
///
/// The prices sign the decisions those pairs measured; they do not predict
/// what a frame costs on any device. Only tests replace them, through
/// `debugGlassPrices`.
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

  static double _mpx(double logicalArea, double devicePixelRatio) =>
      logicalArea * devicePixelRatio * devicePixelRatio / 1e6;

  /// What one more pass costs a frame before its pixels: the pass on the GPU
  /// and its filter on the raster thread.
  double get passOverhead => passGpu + rasterWeight * passRaster;

  /// What copying [footprint] at [share] costs a frame on a screen of
  /// [devicePixelRatio].
  double copyCost(Rect footprint, int share, double devicePixelRatio) =>
      copyGpuPerMpx *
      _mpx(footprint.width * footprint.height, devicePixelRatio) /
      (share * share);

  /// What one pass over [footprint] at [share] costs a frame on a screen of
  /// [devicePixelRatio].
  double passCost(Rect footprint, int share, double devicePixelRatio) =>
      passOverhead + copyCost(footprint, share, devicePixelRatio);

  /// What one image costs, once.
  double get imageCost => imageGpu + rasterWeight * imageRaster;

  /// How many frames a read over [footprint] must hold still to pay for its
  /// image, which spares the frame its [targets].
  int rent(
    Rect footprint,
    int share, {
    required double devicePixelRatio,
    int targets = 1,
  }) => math.max(
    1,
    (imageCost /
            (passCost(footprint, share, devicePixelRatio) +
                (targets - 1) * passOverhead))
        .ceil(),
  );
}

/// Decisions a person made once, from the measured trades of how copies are
/// drawn to the bounds of a frame's plan. Only tests replace them, through
/// `debugGlassPolicy`.
final class PlanPolicy {
  /// Creates a policy.
  const PlanPolicy({
    this.maxTargets = 24,
    this.maxShapes = geometryMaxShapesPerDraw,
    this.shaderFrost = true,
    this.maxCopyShare = 2,
  });

  /// Shapes one shared atlas can hold.
  final int maxShapes;

  /// Targets a frame may issue before reads move to images. Counted as
  /// [GlassRead.targets] counts them: a frosted read is two or three.
  final int maxTargets;

  /// Whether a frost is drawn from an unblurred copy through a shader;
  /// without, the copy is blurred or filtered as the backdrop is. Glass
  /// picks its final shader by it, and fake glass and scroll edge bands
  /// their copies.
  ///
  /// NEAR, for glass: the final shader's 12 taps, turned over a 2 x 2 cell
  /// of pixels except in the tinted variants, are not Impeller's blur, and a
  /// thin hard edge under the frost shows a faint dither. Over the white
  /// bars of the host test they differ from the backdrop filter by at most 22
  /// channel levels over a half-size copy and 36 over a quarter-size one,
  /// where the blurred half-size copy differs by 4, and by 30 for glass
  /// scaled 1.2 over a quarter-size copy. In return a frosted copy takes no
  /// blur passes.
  ///
  /// NEAR, for a frost of a copy: the shader weighs every pixel of the copy
  /// the frost reaches (latticeTaps in copy_frost.dart), so a point under
  /// the frost stays one point. Over the colored rows and white lines of
  /// apple_liquid_glass's scroll edge frost host test, the bands differ from
  /// the copy filtered as the backdrop by at most 11 channel levels at a
  /// device pixel ratio of 2.625 and 6 at 3. Fake glass with 6 px of frost
  /// over the test font's white blocks, the hardest edges a frost meets,
  /// differs by at most 20 at 2.625 (13 for the filtered copy); at 3 the
  /// frost is too wide for the shader and the copy stays filtered. In return
  /// the copy takes no blur passes and, once the frost spans 3.6 device px,
  /// holds a quarter of the pixels or fewer; a change of the color matrix
  /// alone, as a band or a glass fades in, keeps it.
  final bool shaderFrost;

  /// How many device pixels along each side one pixel of a copy that
  /// Impeller blurs stands for at most; a copy the shader frosts takes its
  /// size from the frost.
  ///
  /// NEAR: a copy drawn at half size differs from the full one by at most 10
  /// channel levels on the Pixel 6a (5 in the scroll scene, 10 under the
  /// crowd of buttons), and by 4 in the host test of white text under 8 px
  /// of frost at dpr 1. In return the Pixel's rails spend 7 % less on a dot
  /// or the Liquid tab and 32 % less under the crowd. A quarter size differs
  /// by 15 on the Liquid tab and saves no more.
  final int maxCopyShare;

  /// This policy with the given decisions replaced.
  PlanPolicy copyWith({
    int? maxTargets,
    int? maxShapes,
    bool? shaderFrost,
    int? maxCopyShare,
  }) => PlanPolicy(
    maxTargets: maxTargets ?? this.maxTargets,
    maxShapes: maxShapes ?? this.maxShapes,
    shaderFrost: shaderFrost ?? this.shaderFrost,
    maxCopyShare: maxCopyShare ?? this.maxCopyShare,
  );
}

/// The most times a read's wait for an image doubles after holds that ended
/// before the image paid: at most 64 times its rent.
const int _maxWaitDoublings = 6;
