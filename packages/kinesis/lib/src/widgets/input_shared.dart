import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:meta/meta.dart';

/// Marks the input hosts below a host whose interactions contend with the
/// controls inside it ([Interaction.contendsWithControls]): their touches
/// start [PointerDownInput.contested].
@internal
final class ContestScope extends InheritedWidget {
  /// Marks [child] as [contested] or not.
  const ContestScope({
    required this.contested,
    required super.child,
    super.key,
  });

  /// Whether a host around contends with the controls below.
  final bool contested;

  /// Whether a host around [context] contends with the controls below it;
  /// [listen] makes [context] depend on it.
  static bool of(BuildContext context, {bool listen = true}) =>
      (listen
              ? context.dependOnInheritedWidgetOfExactType<ContestScope>()
              : context.getInheritedWidgetOfExactType<ContestScope>())
          ?.contested ??
      false;

  @override
  bool updateShouldNotify(ContestScope oldWidget) =>
      contested != oldWidget.contested;
}

/// The cursor [given] resolves to in [states]; by default the adaptive
/// click cursor when the host [clickable] (it activates or adjusts), the
/// cursor of what lies below otherwise.
@internal
MouseCursor resolveCursor(
  MouseCursor? given, {
  required bool clickable,
  required Set<WidgetState> states,
}) => WidgetStateProperty.resolveAs<MouseCursor>(
  given ??
      (clickable
          ? WidgetStateMouseCursor.adaptiveClickable
          : MouseCursor.defer),
  states,
);

ActivationSource? _dispatching;

/// Whether no input host is handling a keyboard or accessibility input
/// now: haptics play only outside one.
@internal
bool get gestureInput =>
    _dispatching == null || _dispatching == ActivationSource.pointer;

/// Runs [body], which hands [input] to an input host's interactions, with
/// the input's source known to [gestureInput].
@internal
void dispatchInput(InteractionInput input, VoidCallback body) {
  final source = switch (input) {
    ActivateInput(:final source) ||
    AdjustInput(:final source) ||
    ContextMenuInput(:final source) => source,
    _ => ActivationSource.pointer,
  };
  final outer = _dispatching;
  _dispatching = source;
  try {
    body();
  } finally {
    _dispatching = outer;
  }
}
