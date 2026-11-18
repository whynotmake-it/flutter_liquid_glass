part of 'sheet.dart';

class _SheetScrollController extends ScrollController {
  _SheetScrollController(this.sheet);

  final _SheetViewState sheet;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SheetScrollPosition(
    sheet: sheet,
    physics: physics.applyTo(const AlwaysScrollableScrollPhysics()),
    context: context,
    oldPosition: oldPosition,
  );
}

/// A scroll position that hands its drags to the sheet: a drag down on
/// content at its top moves the sheet, and a drag up expands it first when
/// it may; the content scrolls once the sheet has nowhere to go.
class _SheetScrollPosition extends ScrollPositionWithSingleContext {
  _SheetScrollPosition({
    required this.sheet,
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  final _SheetViewState sheet;
  bool _owns = false;

  @override
  void applyUserOffset(double delta) {
    if (_owns && delta < 0 && !sheet._canExpand) {
      _owns = false;
      sheet._release(sheet._stamp, 0);
      super.applyUserOffset(delta);
      return;
    }
    final atTop = pixels <= minScrollExtent;
    if (_owns ||
        (delta > 0 && atTop) ||
        (delta < 0 && sheet._spec.scrollingExpandsSheet && sheet._canExpand)) {
      _owns = true;
      sheet._scrollDragBy(delta);
      if (!sheet._scrollDragging) _owns = false;
      return;
    }
    super.applyUserOffset(delta);
  }

  @override
  void goBallistic(double velocity) {
    if (_owns) {
      _owns = false;
      sheet._release(sheet._stamp, -velocity);
      super.goBallistic(0);
      return;
    }
    super.goBallistic(velocity);
  }

  @override
  void dispose() {
    if (_owns) sheet._release(sheet._stamp, 0);
    super.dispose();
  }
}

/// Which ways the detents can step from the one the sheet rests at.
final class _DetentRange implements ValueListenable<AdjustRange> {
  _DetentRange(this.sheet);

  final _SheetViewState sheet;

  @override
  AdjustRange get value {
    final motion = sheet.widget.motion;
    final at = motion.indexOfDetent(sheet._detent.value);
    return AdjustRange(
      canIncrease: at >= 0 && at + 1 < motion.heights.length,
      canDecrease: at > 0,
    );
  }

  @override
  void addListener(VoidCallback listener) {
    sheet._detent.addListener(listener);
    sheet._laidOut.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    sheet._detent.removeListener(listener);
    sheet._laidOut.removeListener(listener);
  }
}

/// The value commands of the keyboard and screen readers on the grabber;
/// no finger reaches it: a finger there is the sheet's drag and tap.
final class _DetentStep extends Interaction {
  _DetentStep(this.step);

  final void Function(double t, ValueCommand command) step;

  @override
  bool get adjusts => true;

  @override
  bool get takesPointers => false;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is AdjustInput) step(input.time, input.command);
    return InteractionUpdate.none;
  }
}

/// Tells screen readers the detent the sheet rests at, and the ones a step
/// up and down reach, as the grabber's value. It reads them when semantics
/// are gathered, so the frame whose resolve phase lays the sheet out
/// already tells them.
class _DetentValue extends SingleChildRenderObjectWidget {
  const _DetentValue({required this.state, required super.child});

  final _SheetViewState state;

  @override
  _RenderDetentValue createRenderObject(BuildContext context) =>
      _RenderDetentValue(
        state,
        GlassLocalizations.of(context),
        Directionality.of(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderDetentValue renderObject,
  ) {
    renderObject.update(
      GlassLocalizations.of(context),
      Directionality.of(context),
    );
  }
}

class _RenderDetentValue extends RenderProxyBox {
  _RenderDetentValue(this._state, this._strings, this._textDirection);

  // The view's own notifiers, which live as long as the view.
  final _SheetViewState _state;
  late final Listenable _changes = Listenable.merge([
    _state._detent,
    _state._laidOut,
  ]);

  GlassLocalizations _strings;
  TextDirection _textDirection;

  void update(GlassLocalizations strings, TextDirection textDirection) {
    if (identical(strings, _strings) && textDirection == _textDirection) {
      return;
    }
    _strings = strings;
    _textDirection = textDirection;
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _changes.addListener(markNeedsSemanticsUpdate);
  }

  @override
  void detach() {
    _changes.removeListener(markNeedsSemanticsUpdate);
    super.detach();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.textDirection = _textDirection;
    final motion = _state.widget.motion;
    final detent = _state._detent.value;
    final at = motion.indexOfDetent(detent);
    if (at < 0) return;
    String name(int i) => _state._detentName(_strings, motion.detentAt(i));
    config.value = _state._detentName(_strings, detent);
    if (at + 1 < motion.heights.length) config.increasedValue = name(at + 1);
    if (at > 0) config.decreasedValue = name(at - 1);
  }
}
