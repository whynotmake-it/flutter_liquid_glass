/// The clock's scheduled actions, ordered by the time they come due.
///
/// [runDue] hands each action the time it was scheduled for, so a late
/// frame still applies every action at its own time. Actions with equal
/// times run in the order they were inserted.
class MotionTimeline {
  final List<(double, void Function(double))> _events = [];

  /// Whether no action is pending.
  bool get isEmpty => _events.isEmpty;

  /// The time the earliest pending action comes due, or null when none is
  /// pending.
  double? get nextDue => _events.isEmpty ? null : _events.first.$1;

  /// Schedules [action] for time [t], after every action already scheduled
  /// for [t] or earlier.
  void insert(double t, void Function(double t) action) {
    var i = _events.length;
    while (i > 0 && _events[i - 1].$1 > t) {
      i--;
    }
    _events.insert(i, (t, action));
  }

  /// Runs every action due by [t] in order, each at its own time; actions
  /// that come due while the run is in progress run in the same call.
  void runDue(double t) {
    while (_events.isNotEmpty && _events.first.$1 <= t) {
      final (at, action) = _events.removeAt(0);
      action(at);
    }
  }

  /// Drops every pending run of [action].
  void remove(void Function(double t) action) =>
      _events.removeWhere((event) => identical(event.$2, action));
}
