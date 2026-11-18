import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A listenable that never notifies and holds no state: the frames of a part
/// that moves only with its surroundings, or the states of one that takes no
/// input.
const ValueListenable<Set<WidgetState>> still = _Still();

final class _Still implements ValueListenable<Set<WidgetState>> {
  const _Still();

  @override
  Set<WidgetState> get value => const {};

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
