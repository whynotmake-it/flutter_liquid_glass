import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

const Set<WidgetState> _inputStates = {
  WidgetState.pressed,
  WidgetState.hovered,
  WidgetState.focused,
  WidgetState.dragged,
};

/// The states a control shows: what it says of itself ([said]), disabled
/// when it is not [enabled], and the [live] states input keeps while it is.
///
/// A disabled control shows no live state but focus under directional
/// navigation (a TV remote), whose focus can rest on it.
@internal
Set<WidgetState> shownStates({
  required Set<WidgetState> said,
  required bool enabled,
  required Set<WidgetState> live,
  bool? focusShows,
  NavigationMode? navigation,
}) {
  assert(
    said.every((s) => s != WidgetState.disabled && !_inputStates.contains(s)),
    'A control says neither disabled, which is its enabled, nor a state '
    'input keeps: $said',
  );
  final focused = focusShows ?? live.contains(WidgetState.focused);
  return {
    ...said,
    if (!enabled) WidgetState.disabled,
    if (enabled)
      for (final state in live)
        if (state != WidgetState.focused && _inputStates.contains(state)) state,
    if (focused && (enabled || navigation == NavigationMode.directional))
      WidgetState.focused,
  };
}

/// Writes [states] to [controller] when they differ from its value.
@internal
void publishStates(
  WidgetStatesController controller,
  Set<WidgetState> states,
) {
  if (!setEquals(controller.value, states)) controller.value = states;
}

/// Holds a control's [WidgetState] set in one [WidgetStatesController]: the
/// one the control's widget gives ([givenStates]) or one of the state's
/// own. A change of the states rebuilds the control.
///
/// The control says what it is: [enabled], [saidStates] and [focusShows].
/// It hands the same to its `InputRegion` with [widgetStates], and the
/// region publishes them there with the live states input keeps (pressed,
/// hovered, focused, dragged), so the controller is an output: what an app
/// writes to a given one is written over. Before the first build, after
/// every widget update and on [restate] the control publishes what the
/// region will, so it builds with its states.
mixin ControlStates<T extends StatefulWidget> on State<T> {
  WidgetStatesController? _own;
  WidgetStatesController? _listened;
  NavigationMode? _navigation;

  /// The controller the widget gives, or null for one of the state's own.
  WidgetStatesController? get givenStates;

  /// Whether the control takes input now.
  bool get enabled;

  /// What the control says of itself, such as selected: never disabled,
  /// which is [enabled], nor a state input keeps.
  Set<WidgetState> get saidStates => const {};

  /// Whether the focused state shows, for a control whose focus is not its
  /// region's; null leaves it to the region.
  bool? get focusShows => null;

  /// The control's states.
  WidgetStatesController get widgetStates =>
      givenStates ?? (_own ??= WidgetStatesController());

  /// Publishes what the control says now; call it when [enabled],
  /// [saidStates] or [focusShows] change outside a widget update.
  ///
  /// A control whose input comes from many parts instead of one region
  /// gathers their states input keeps and publishes them as [live]; by
  /// default the ones published last stay.
  @protected
  void restate({Set<WidgetState>? live}) =>
      _publish(live ?? widgetStates.value);

  void _publish(Set<WidgetState> live) => publishStates(
    widgetStates,
    shownStates(
      said: saidStates,
      enabled: enabled,
      live: live,
      focusShows: focusShows,
      navigation: _navigation,
    ),
  );

  void _listen() {
    final now = widgetStates;
    if (identical(now, _listened)) return;
    _listened?.removeListener(_changed);
    now.addListener(_changed);
    _listened = now;
  }

  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    _publish(const {});
    _listen();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final navigation = MediaQuery.maybeNavigationModeOf(context);
    if (navigation == _navigation) return;
    _navigation = navigation;
    restate();
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    final live = (_listened ?? widgetStates).value;
    _listen();
    _publish(live);
  }

  @override
  void dispose() {
    _listened?.removeListener(_changed);
    _own?.dispose();
    super.dispose();
  }
}
