import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

part 'package:apple_liquid_glass/src/widgets/navigation/page_route_card.dart';
part 'package:apple_liquid_glass/src/widgets/navigation/page_route_slide.dart';
part 'package:apple_liquid_glass/src/widgets/navigation/page_route_zoom.dart';

/// An iOS 27 page pushed onto a navigator: it slides in over the page
/// below, which moves aside and dims under it.
///
/// UIKit: `UINavigationController.pushViewController(_:animated:)`.
/// SwiftUI: `NavigationLink`. Flutter: `CupertinoPageRoute`.
///
/// Without a finger the page slides on a critically damped spring of
/// response 0.3, leaving its start at 8.77 widths a second; the page below
/// moves aside by the width less 0.7 of it and dims under black at 10
/// percent, both with the page's progress; while they move, both pages are
/// cards with the display's corners and the top one casts UIKit's light
/// shadow (read from UIKit, notes private; device recordings). A finger
/// that drags the page toward the trailing side pops it as UIKit's
/// interactive pop does, from the leading edge (9 percent of the width)
/// after 15 points, or from anywhere else after 30 points within UIKit's
/// funnel, so drags and scrolls of the page's own that claim the touch
/// first keep it: the page follows the finger, rubber bands past either
/// end, and on release pops or returns as UIKit predicts from the finger's
/// last speeds, on a spring of response 0.3 and damping 0.85. With Prefer
/// Cross-Fade Transitions, which iOS turns on with Reduce Motion, a push or
/// pop without a finger cross-fades over 0.5 s instead.
/// Back, Escape and a screen reader's dismiss pop it through the page's
/// `PopScope`s; a pop asked for while a finger holds the page waits for
/// the release, which then takes the page out. Android's predictive back
/// slides a sliding page with the gesture, as a finger's swipe does, pops
/// it on commit and returns it on cancel; a page whose `PopScope` refuses
/// Back does not take the gesture.
///
/// The pages of a navigator share one `GlassNavigationBar`, drawn right
/// above the topmost glass page and under every route pushed after it, so
/// alerts, sheets and menus cover it; its capsules stay while the pages
/// move and change into the next page's as UIKit's do. The page follows
/// the finger one to one; UIKit's settings carry a tracking spring whose
/// use is not confirmed on the device. A finger does not catch a page that
/// is already leaving, as UIKit's does: the navigator has popped it by
/// then.
///
/// With a [source], the page zooms out of it instead, as a UIKit page with
/// `preferredTransition = .zoom` does: it grows from the source's frame to the
/// screen, center and width on a critically damped spring of response 0.317 and
/// height on one of response 0.406, damping 0.925, while the source's look
/// crossfades into it and the page underneath dims 15 percent under the growing
/// card's shadow; popped, it shrinks back into the source on UIKit's zoom-out
/// spring (iPhone 16 Pro recordings, replayed). A drag down or toward the
/// trailing side shrinks the page under the finger after 13.5 points, and a
/// release past 132.5 points or at 1050 points a second pops it into the
/// source; short of that it returns. The source hides while the page shows.
/// Without an attached source the page slides.
///
/// To assistive technology the page is a route of its own, as a
/// `CupertinoPageRoute`'s page is, named by [title], which screen readers
/// announce as it opens.
class GlassPageRoute<T> extends PresentationPageRoute<T> {
  /// Creates a page [builder] builds, zooming out of [source] when given.
  GlassPageRoute({
    required this.builder,
    this.title,
    this.source,
    super.settings,
  }) : super(semanticsLabel: title);

  /// Builds the page.
  final WidgetBuilder builder;

  /// The page's name: what screen readers announce as it opens, and what
  /// the back button of a page above shows when this page's navigation bar
  /// has no text title (Flutter: `CupertinoPageRoute.title`).
  final String? title;

  /// The source the page zooms out of and back into, shown by a
  /// [GlassZoomSource], or null for a page that slides in.
  final MotionSource? source;

  // Fixed when the page is installed, so the page and the route agree on
  // its transition for its whole life.
  late final bool _zooms = source?.geometry != null;

  late final PageMotion _motion = _zooms
      ? ZoomPageMotion(page: _navigatorRect())
      : PageSlideMotion();
  late final MotionSelection<double> _progress = _motion.select(
    (m) => m.progress,
  );
  late final MotionSelection<bool> _fades = _motion.select((m) => m.fades);

  @override
  Presentation<T, Presented> get presentation => _presentation;

  late final Presentation<T, Presented> _presentation =
      Presentation<T, PageMotion>(
        motion: (_) => _motion,
        builder: (context, motion) => motion is ZoomPageMotion
            ? _Zoom(
                route: this,
                motion: motion,
                child: Builder(builder: builder),
              )
            : _Slide(
                route: this,
                motion: motion as PageSlideMotion,
                child: Builder(builder: builder),
              ),
        source: _zooms ? source : null,
        dismiss: DismissPolicy.modal,
      );

  // The motion time of the call that presented the page.
  double _presented = 0;

  // The page above this one, whose progress moves and dims this one.
  final _cover = ValueNotifier<GlassPageRoute<Object?>?>(null);
  GlassPageRoute<Object?>? _below;

  late final GlassPageBarLink _bar;
  bool _presenting = false;

  // The time of the finger's lift that committed a swipe's pop.
  double? _lifted;

  Rect _navigatorRect() {
    final box = navigator?.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  void install() {
    _bar = GlassBarHost.of(
      navigator!,
    ).attach(this, presence: _progress, title: title);
    super.install();
  }

  @override
  void didPresent() {
    super.didPresent();
    _presented = _motion.clock.now;
    _presenting = true;
  }

  // A zooming page shows the page underneath around its card.
  @override
  bool get opaque => !_zooms;

  // Another glass page below follows this page's progress itself, from the
  // push on; any other page below gets it from the navigator, which hands
  // it over once this page rests.
  @override
  DelegatedTransitionBuilder? get delegatedTransition => _zooms
      ? null
      : (context, animation, secondaryAnimation, allowSnapshotting, child) =>
            ModalRoute.of(context) is GlassPageRoute
            ? null
            : _Card(
                presence: _progress,
                fades: _fades,
                top: false,
                child: child,
              );

  @override
  void didChangePrevious(Route<Object?>? previousRoute) {
    super.didChangePrevious(previousRoute);
    _uncover();
    if (previousRoute is GlassPageRoute) {
      _below = previousRoute;
      // The page under a zoom stays where it is.
      if (!_zooms) previousRoute._cover.value = this;
    }
    final below = previousRoute is GlassPageRoute ? previousRoute._bar : null;
    if (_presenting) {
      _presenting = false;
      _bar.host.presented(
        _bar,
        below: below,
        current: isCurrent,
        animated: animation?.status == AnimationStatus.forward,
        time: _presented,
      );
    } else {
      _bar.host.previousChanged(
        _bar,
        below: below,
        time: _motion.clock.now,
      );
    }
  }

  @override
  void didChangeNext(Route<Object?>? nextRoute) {
    super.didChangeNext(nextRoute);
    _bar.host.coveredChanged(
      _bar,
      covered: nextRoute is PageRoute && nextRoute is! GlassPageRoute,
    );
  }

  @override
  void didPopNext(Route<Object?> nextRoute) {
    super.didPopNext(nextRoute);
    if (nextRoute is! GlassPageRoute) _bar.host.revealed(_bar);
  }

  @override
  void beginInteraction() {
    super.beginInteraction();
    _bar.host.swipeStarted(_bar);
  }

  @override
  void endInteraction() {
    super.endInteraction();
    _bar.host.swipeEnded(_bar);
  }

  void _uncover() {
    final below = _below;
    if (below != null && identical(below._cover.value, this)) {
      below._cover.value = null;
    }
    _below = null;
  }

  @override
  void didFinish(T? result) {
    _uncover();
    _bar.host.finished(_bar);
    super.didFinish(result);
  }

  @override
  void dispose() {
    _uncover();
    _bar.host.detach(_bar);
    _cover.dispose();
    super.dispose();
  }

  @override
  Widget buildContent(BuildContext context) =>
      GlassBarSlot(link: _bar, child: super.buildContent(context));

  @override
  bool leave(DismissTrigger trigger) {
    final lifted = trigger == DismissTrigger.interaction ? _lifted : null;
    _lifted = null;
    _bar.host.leaving(_bar, time: lifted ?? _motion.clock.now);
    return super.leave(trigger);
  }

  // Starts the push's transition from the time it counts from, read at
  // the page's first frame: the clock runs the start at that frame's time
  // in the next frame, before the motion steps.
  VoidCallback _startAfterFirstFrame() {
    final clock = _motion.clock;
    return clock.schedule(clock.now, (firstFrame) {
      if (!_motion.isShown) return;
      _motion.start(
        PageMotion.transitionOrigin(
          call: _presented,
          firstFrame: firstFrame,
          framePeriod: clock.framePeriod,
        ),
      );
    });
  }
}

// What each zoom source shows, which its page draws while the source's look
// crossfades into the page.
final _looks = Expando<Widget>('GlassZoomSource.look');

/// The widget a [GlassPageRoute] with a [source] grows out of when it is
/// pushed and lands in when it is popped.
///
/// UIKit: the `sourceViewProvider` of `.zoom`. SwiftUI:
/// `matchedTransitionSource(id:in:)`.
///
/// The source hides from the frame its page is pushed in until the page
/// has gone, as UIKit hides a zoom transition's source view, and stays
/// tappable meanwhile; the zoom draws [child] while it crossfades into the
/// page.
class GlassZoomSource extends StatelessWidget {
  /// Marks [child] as the [source] of a page.
  const GlassZoomSource({
    required this.source,
    required this.child,
    this.borderRadius = 0,
    super.key,
  });

  /// The source the page is pushed with.
  final MotionSource source;

  /// The radius of the source's corners, which the zoom's corners turn
  /// from into the display's.
  final double borderRadius;

  /// The widget the page grows out of and lands in; the zoom draws it
  /// while it crossfades into the page.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    _looks[source] = child;
    return MotionSourceBox(
      source: source,
      radius: BorderRadius.all(Radius.circular(borderRadius)),
      child: child,
    );
  }
}
