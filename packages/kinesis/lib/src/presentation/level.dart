import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/src/presentation/route.dart';

/// Where a presentation goes.
///
/// UIKit: the presenting view controller. Flutter: the navigator of
/// `Navigator.of(context, rootNavigator: ...)`.
enum PresentationLevel {
  /// The outermost navigator in the same view, inside the nearest
  /// [PresentationContext]: over every bar and tab of the app, as UIKit
  /// presents menus, alerts, popovers and sheets.
  window,

  /// The nearest navigator: a page among the pages of its stack.
  page,
}

/// Marks a subtree that presentations from inside it stay within, such as
/// an embedded device frame or a split view's column: a window
/// presentation goes to the outermost navigator inside the context, so the
/// context holds a [Navigator] of its own.
///
/// UIKit: `definesPresentationContext`.
class PresentationContext extends InheritedWidget {
  /// Bounds the presentations from inside [child].
  const PresentationContext({required super.child, super.key});

  @override
  bool updateShouldNotify(PresentationContext oldWidget) => false;
}

/// The navigator a presentation from [context] at [level] is pushed on, or
/// null when there is none.
@internal
NavigatorState? presentationNavigatorOf(
  BuildContext context, {
  PresentationLevel level = PresentationLevel.window,
}) {
  final nearest = Navigator.maybeOf(context);
  if (nearest == null || level == PresentationLevel.page) return nearest;
  final view = View.maybeOf(context);
  final bound = context
      .getElementForInheritedWidgetOfExactType<PresentationContext>();
  var found = nearest;
  while (true) {
    final outer = found.context.findAncestorStateOfType<NavigatorState>();
    if (outer == null) return found;
    if (View.maybeOf(outer.context) != view) return found;
    final outerBound = outer.context
        .getElementForInheritedWidgetOfExactType<PresentationContext>();
    if (bound != null && outerBound != bound) return found;
    found = outer;
  }
}

/// Presents [route] from [context] at [level] and completes with its
/// result.
///
/// The content carries the themes around [context], so a presentation
/// looks like the place it was shown from.
Future<T?> showPresentation<T>(
  BuildContext context,
  PresentationRoute<T> route, {
  PresentationLevel level = PresentationLevel.window,
}) {
  final navigator = presentationNavigatorOf(context, level: level);
  if (navigator == null) {
    throw FlutterError('showPresentation found no Navigator above $context.');
  }
  route.presentFrom(context, navigator);
  return navigator.push(route);
}
