/// Everything that appears above the screen: the presentation engine
/// (`Presentation`) and its three shells (`PresentationRoute`,
/// `PresentationPageRoute`, `PresentationPortal`). What an overlay grows
/// out of is a `MotionSource` from `package:kinesis/widgets.dart`.
///
/// For the author of any overlay: a menu, a sheet, an alert or a panel of
/// one's own.
///
/// It promises, in every shell unless said otherwise:
///
/// - focus: it moves in at the open, Tab stays inside a modal presentation
///   (a page keeps its navigator's rule), and it goes back to the opener
///   however the presentation goes;
/// - dismissal: Escape as a `DismissIntent` an app can remap, the Back
///   button, and Android's predictive back driving a route whose motion is
///   `PredictiveBack`; for an anchored presentation that asks, a scroll
///   around its anchor and a tap outside;
/// - screen readers: the presentation is a route of its own, named and
///   given a role by the presenter; a route's barrier hides the screen
///   behind it, and a barrier the presenter labels offers the dismissal
///   after the content;
/// - from the start of its leave it is inert: no touches, no focus, no
///   semantics.
///
/// It never knows how an overlay looks or which spring it moves on.
library;

export 'src/presentation/level.dart'
    show PresentationContext, PresentationLevel, showPresentation;
export 'src/presentation/portal.dart'
    show PresentationPortal, PresentationPortalController;
export 'src/presentation/presentation.dart'
    show Presentation, PresentationEnvironment, PresentationHandle;
export 'src/presentation/route.dart'
    show PresentationPageRoute, PresentationRoute;
