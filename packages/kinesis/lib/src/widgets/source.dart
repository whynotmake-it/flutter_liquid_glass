import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// The identity of what a presentation grows out of, held like a
/// `LayerLink`: a [MotionSourceBox] or a zone of an `InputZones` host
/// (`InputZonesController.sourceOf`) shows it, a presentation leases it.
///
/// While a lease is held the box paints nothing, from the frame the
/// presentation commits, and stays hit-testable, as UIKit hides a zoom
/// transition's source view; a control that paints its zones itself paints
/// a zone whose source [isHidden] the same way.
final class MotionSource {
  /// Creates a source.
  MotionSource({this.debugLabel});

  /// A name for debugging.
  final String? debugLabel;

  SourceView? _view;
  int _leases = 0;

  /// Whether a presentation holds the source.
  bool get isHidden => _leases > 0;

  /// Where the source is now, or null when nothing laid out shows it.
  SourceGeometry? get geometry => _view?.sourceGeometry;

  /// Lets [view] show the source, in place of any other, or ends that for
  /// [view] when [shown] is false, if it still shows the source.
  @internal
  void showIn(SourceView view, {bool shown = true}) {
    if (shown) {
      _view = view;
    } else if (identical(_view, view)) {
      _view = null;
    }
  }

  /// Hides the source until the returned callback releases it; later
  /// calls of the callback do nothing.
  @internal
  VoidCallback lease() {
    _leases++;
    _view?.sourceHiddenChanged();
    var held = true;
    return () {
      if (!held) return;
      held = false;
      _leases--;
      _view?.sourceHiddenChanged();
    };
  }

  @override
  String toString() => 'MotionSource(${debugLabel ?? ''})';
}

/// Shows [source] around [child]: it reports where the source is and paints
/// nothing while a presentation leases it.
class MotionSourceBox extends SingleChildRenderObjectWidget {
  /// Shows [source] with [radius] corners around [child].
  const MotionSourceBox({
    required this.source,
    this.radius = BorderRadius.zero,
    super.child,
    super.key,
  });

  /// The source shown.
  final MotionSource source;

  /// The source's corners.
  final BorderRadius radius;

  @override
  RenderMotionSourceBox createRenderObject(BuildContext context) =>
      RenderMotionSourceBox(source: source, radius: radius);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMotionSourceBox renderObject,
  ) {
    renderObject.source = source;
    renderObject.radius = radius;
  }
}

/// What shows a [MotionSource]: where it is, and how it learns that a
/// presentation hid or showed it.
@internal
abstract interface class SourceView {
  /// Where the source is now, in global coordinates, or null when it is
  /// not shown.
  SourceGeometry? get sourceGeometry;

  /// The source's [MotionSource.isHidden] may have changed.
  void sourceHiddenChanged();
}

/// The render object of a [MotionSourceBox].
@internal
class RenderMotionSourceBox extends RenderProxyBox implements SourceView {
  /// Creates the box of [source].
  RenderMotionSourceBox({
    required this._source,
    required this.radius,
  });

  MotionSource _source;

  /// The source's corners.
  BorderRadius radius;

  /// The source shown.
  MotionSource get source => _source;
  set source(MotionSource value) {
    if (identical(value, _source)) return;
    if (attached) _source.showIn(this, shown: false);
    _source = value;
    if (attached) value.showIn(this);
    markNeedsPaint();
  }

  @override
  SourceGeometry? get sourceGeometry {
    if (!attached || !hasSize) return null;
    return SourceGeometry(
      rect: MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size),
      radius: radius,
    );
  }

  @override
  void sourceHiddenChanged() => markNeedsPaint();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _source.showIn(this);
  }

  @override
  void detach() {
    _source.showIn(this, shown: false);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_source.isHidden) return;
    super.paint(context, offset);
  }
}
