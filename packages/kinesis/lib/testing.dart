/// What only tests and replays need: `ManualMotionClock`, a clock that
/// moves only when told to.
///
/// For tests of motion, of widgets that move, and for apps that drive time
/// themselves. It does not import `flutter_test`.
library;

export 'src/motion/clock.dart' show ManualMotionClock;
