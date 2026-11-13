/// The plan of a frame of glass: which copies of the screen its glass reads,
/// at what size and frost, which geometry it takes, and how many passes that
/// costs.
///
/// Every decision about copies, frost, geometry and passes is made in the
/// plan and only there. The plan is a pure function of what the frame's
/// glass answered about itself, so it is checked without a GPU or a layer
/// tree. `GlassFrameReport` tells an app what a frame's glass took, for
/// budgets held in tests and for tuning; `debugDumpGlassPlan` prints it.
/// `LiquidGlassBackdropFrost` says how a backdrop filter is frosted and
/// `FrostBandPaint` what a scroll edge paints over its frost.
///
/// For a renderer, `compilePlan` takes a `PlanScenery` (the frame's sites,
/// each a `SiteFacts` holding the `SiteAsk` its glass made) with the
/// `PlanLedger` kept between frames, the `PlanPrices` and the `PlanPolicy`,
/// and returns the `GlassPlan`: a `SiteFate` for every site and the frame's
/// `GlassRead`s, each with the `ReadGeometry` of its copy on a `Lattice`.
/// `GlassWork` counts what the renderer did beyond the plan for the frame's
/// report.
///
/// For those who develop the renderer, and for an app that holds its glass
/// to a budget.
///
/// It creates no engine layer and touches no shader or texture: the
/// rendering library carries the plan out.
library;

export 'src/composer/backdrop_frost.dart' show LiquidGlassBackdropFrost;
export 'src/composer/band_look.dart' show BandLook, FrostBandPaint;
export 'src/composer/copy_tuning.dart' show GlassCopyTuning;
export 'src/composer/frame_report.dart'
    show
        GlassFrameReport,
        GlassReadReport,
        GlassReadSource,
        GlassWork,
        debugDumpGlassPlan;
export 'src/composer/geometry.dart'
    show
        CopyNeed,
        FrostLattice,
        HazeStrip,
        ImpellerLayers,
        Lattice,
        ReadGeometry,
        ceilPixels,
        frostLatticeOf;
export 'src/composer/geometry_renderer_limits.dart'
    show geometryMaxShapesPerDraw;
export 'src/composer/plan.dart' show PlanPolicy, PlanPrices, compilePlan;
export 'src/composer/plan_ledger.dart'
    show PlanLedger, PlanLedgerEdits, ReadMemo;
export 'src/composer/plan_result.dart'
    show
        FollowFate,
        GlassPlan,
        GlassRead,
        HiddenFate,
        ImageRead,
        LeadFate,
        LiveRead,
        ReadSource,
        SceneRead,
        SiteFate;
export 'src/composer/plan_scenery.dart'
    show DirtyLog, NoJoin, PageFilter, PlanScenery, ReadLimit, StateChain;
export 'src/composer/plan_site.dart'
    show
        BandSiteRole,
        ComputedShape,
        FilterLook,
        GeometryKind,
        GlassBody,
        GlassSiteRole,
        OwnAtlas,
        SharedAtlas,
        SiteAsk,
        SiteFacts,
        SiteRole,
        geometryKindOf;
