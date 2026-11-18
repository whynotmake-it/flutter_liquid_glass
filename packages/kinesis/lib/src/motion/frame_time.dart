import 'package:kinesis/src/motion/frame_grid.dart';
import 'package:meta/meta.dart';

/// The time the binding's frame clock gives its frames and input events,
/// from the time stamps the scheduler and the input deliver.
///
/// A frame's time is its frame time stamp (so `timeDilation` and test pumps
/// apply), put on the display's frame grid ([FrameGrid]). While the clock
/// dozes or sleeps, the wait counts where the frame time stamps follow the
/// engine clock, as on a device: input stamped and changes made meanwhile
/// get the time an uninterrupted clock would give them, and so does the
/// frame that ends the wait, so a finger held still keeps its time. Under a
/// test's fake frame clock, which the engine clock does not follow, the time
/// stands still while the clock sleeps.
///
/// Input events are stamped at their own time stamp, moved onto the frame
/// clock by the pointer clock offset: UIKit's measured delays count from
/// the touch's time stamp. While the clock runs or dozes, an event's time is
/// the latest frame's time plus the time from that frame's time stamp to
/// the event's, usually a frame or two in the past. Events that arrive
/// before its first frame, or while it sleeps under a fake frame clock,
/// keep their spacing, measured by their own time stamps and slowed by
/// `timeDilation`, and the first frame after the wake continues from the
/// latest of them, so the clock never runs backwards. An event whose time
/// stamp does not land within [maxEventAge] before the engine clock is
/// taken as happening one frame after its delivery. When the frame time
/// stamps and the engine clock disagree by more than [maxFrameLead] (a
/// test's fake frame clock), an event gets the latest frame's time while
/// the clock runs, and the first frame after a wake continues from the
/// latest stamp itself.
///
/// It reads no scheduler: the stamps arrive as arguments, the engine clock,
/// the pointer clock offset, `timeDilation` and the frame rate through the
/// functions it is given.
@internal
final class FrameTime {
  /// Creates the time map of a clock that reads the engine clock with
  /// `engineNow`, the pointer clock offset with `pointerClockOffset` (null
  /// where the platform gives no usable time stamps), `timeDilation` with
  /// `dilation` and its frame rate with `frameRate`.
  FrameTime({
    required this._engineNow,
    required this._pointerClockOffset,
    required this._dilation,
    required this._frameRate,
  });

  /// The largest distance, in seconds, between a frame's time stamp and
  /// the engine clock at its callback for which the two count as one.
  static const double maxFrameLead = 0.05;

  /// The oldest an event's time stamp may be at its delivery, in seconds,
  /// for [stamp] to trust it.
  static const double maxEventAge = 0.25;

  final Duration Function() _engineNow;
  final Duration? Function() _pointerClockOffset;
  final double Function() _dilation;
  final double Function() _frameRate;

  final FrameGrid _grid = FrameGrid();
  double _base = 0;
  double _time = 0;
  double _tickTime = 0;
  bool _ticking = false;
  Duration? _advanced;
  Duration? _tickStamp;
  bool _stampsAgree = false;
  Duration? _stampFrom;
  double _stampTime = 0;
  Duration? _wakeFrom;
  double _wakeTime = 0;
  Duration? _dozeStamp;
  Duration? _dozeSystemStamp;
  double _dozeTime = 0;

  /// The time of the latest frame, or of the latest input stamped while
  /// the clock sleeps, in seconds.
  double get time => _time;

  /// The display's frame period in seconds, or null before steady frames.
  double? get period => _grid.period;

  /// Whether the clock dozes or sleeps where the frame time stamps follow
  /// the engine clock, so that [read] counts the wait.
  @visibleForTesting
  bool get dozing =>
      _dozeSystemStamp != null && _dozeStamp != null && _stampsAgree;

  /// The frame stamp the clock's frames count from, or null before its
  /// first frame; a clock that starts inside a frame sets it to that frame's
  /// stamp, so its next frame already moves by a frame.
  Duration? origin;

  /// A frame stamped [frameStamp] by the scheduler and [systemStamp] by the
  /// engine; a second call with the same frame stamp changes nothing.
  void advance(Duration frameStamp, Duration systemStamp) {
    final start = origin ??= frameStamp;
    if (frameStamp == _advanced) return;
    _advanced = frameStamp;
    final seconds = (frameStamp - start).inMicroseconds / 1e6;
    _stampsAgree =
        ((systemStamp - _engineNow()).inMicroseconds / 1e6).abs() <
        maxFrameLead;
    _tickStamp = systemStamp;
    if (_wakeFrom case final from?) {
      _wakeFrom = null;
      final lag = (systemStamp - from).inMicroseconds / 1e6;
      if (_stampsAgree && lag > 0 && lag < 1) {
        final woken = _wakeTime + lag / _dilation();
        if (_base + seconds < woken) _base = woken - seconds;
      }
    }
    if (_dozeStamp case final dozed?) {
      final micros =
          (_dozeTime * 1e6).round() + (frameStamp - dozed).inMicroseconds;
      _base = micros / 1e6 - seconds;
      _dozeStamp = null;
      _dozeSystemStamp = null;
    }
    if (_base + seconds < _time) _base = _time - seconds;
    _tickTime = _base + seconds;
    final snapped = _grid.snap(_tickTime);
    _time = snapped >= _time ? snapped : _tickTime;
    _ticking = true;
    _stampFrom = null;
  }

  /// The time a change made now gets outside the clock's own frames: in a
  /// frame stamped [frameStamp] that the clock sits out, or between frames
  /// when [frameStamp] is null.
  double read({Duration? frameStamp}) {
    final dozed = _dozeSystemStamp;
    final dozedFrame = _dozeStamp;
    if (dozed != null && dozedFrame != null && _stampsAgree) {
      // In a frame the clock sits out, a change made now shows in that frame,
      // so it takes that frame's time; the clock's next frame counts on from
      // it.
      final t = frameStamp == null
          ? _dozeTime +
                (_engineNow() - dozed).inMicroseconds / 1e6 / _dilation()
          : _dozeTime + (frameStamp - dozedFrame).inMicroseconds / 1e6;
      if (t > _time) return t;
    }
    return _time;
  }

  Duration _occurred(Duration timeStamp, Duration now) {
    final offset = _pointerClockOffset();
    if (offset != null) {
      final at = timeStamp + offset;
      final age = (now - at).inMicroseconds / 1e6;
      if (age >= 0 && age < maxEventAge) return at;
    }
    return now + Duration(microseconds: (1e6 / _frameRate()).round());
  }

  /// The time of an input event whose time stamp is [timeStamp].
  double stamp(Duration timeStamp) {
    final now = _engineNow();
    if (_ticking) {
      final tick = _tickStamp;
      if (!_stampsAgree || tick == null) return _time;
      final since = (_occurred(timeStamp, now) - tick).inMicroseconds / 1e6;
      if (since < -maxEventAge) return _time;
      return _tickTime + since / _dilation();
    }
    _wakeFrom = _occurred(timeStamp, now);
    final from = _stampFrom;
    if (from == null) {
      _stampFrom = timeStamp;
      _stampTime = _time;
      _wakeTime = _time;
      return _time;
    }
    final elapsed = (timeStamp - from).inMicroseconds / 1e6;
    if (elapsed > 0) {
      final t = _stampTime + elapsed / _dilation();
      if (t > _time) _time = t;
    }
    _wakeTime = _time;
    return _time;
  }

  /// The clock dozes on a timer after its latest frame.
  void dozed() {
    _dozeStamp = _advanced;
    _dozeSystemStamp = _tickStamp;
    _dozeTime = _time;
  }

  /// The clock asks for no more frames; it stops instead of dozing under a
  /// fake frame clock.
  void sleep() {
    final frame = _advanced;
    if (!_stampsAgree || !_ticking || (_dozeStamp == null && frame == null)) {
      stop();
      return;
    }
    _advanced = null;
    // Sleep counts as a doze without a timer: a finger held still while
    // nothing moves keeps its time.
    if (_dozeStamp == null) {
      _dozeStamp = frame;
      _dozeSystemStamp = _tickStamp;
      _dozeTime = _time;
    }
  }

  /// The clock stops: the wait until its next frame does not count.
  void stop() {
    _advanced = null;
    _dozeStamp = null;
    _dozeSystemStamp = null;
    _base = _time;
    _ticking = false;
    origin = null;
  }
}
