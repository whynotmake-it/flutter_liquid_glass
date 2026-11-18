import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A glass knob of the app's own: a `Motion` that follows one finger on a
/// rubber band and springs home with the release's velocity.
///
/// Every command takes the input's stamp, so the knob is a pure function
/// of the inputs it hears: [Replay] feeds the same inputs to a fresh knob
/// and reads it at any time. Not measured: the band and the springs are
/// chosen by eye.
final class KnobMotion extends Motion implements PointerFollower {
  /// How far the knob travels before the band resists.
  static const reach = 44.0;

  static const _band = RubberBand(-reach, reach, dimension: 4 * reach);

  late final offset = own(MotionValue(Offset.zero));
  late final press = own(MotionValue<double>(0));
  Offset _start = Offset.zero;
  Offset _from = Offset.zero;

  @override
  void down(PointerDownInput input) {
    final t = input.time;
    advance(t);
    final shown = offset.valueAt(t);
    _start = input.position;
    _from = Offset(_band.unshow(shown.dx), _band.unshow(shown.dy));
    offset.snap(t, shown);
    press.retarget(t, 1, spring: Spring.snappy);
  }

  @override
  void move(PointerMoveInput input) {
    final t = input.time;
    advance(t);
    final raw = _from + input.position - _start;
    offset.snap(t, Offset(_band.show(raw.dx), _band.show(raw.dy)));
  }

  @override
  void up(PointerUpInput input) => _home(input.time, input.velocity);

  @override
  void cancel(PointerCancelInput input) => _home(input.time, Offset.zero);

  @override
  void hover(PointerHoverInput input) {}

  void _home(double t, Offset velocity) {
    advance(t);
    offset.setVelocity(t, velocity);
    offset.retarget(t, Offset.zero, spring: Spring.bouncy);
    press.retarget(t, 0, spring: Spring.smooth);
  }

  /// Puts the knob at [t] where [other] stands at its own time, without
  /// velocity.
  void show(double t, KnobMotion other) {
    advance(t);
    offset.snap(t, other.offset.valueAt(other.now));
    press.snap(t, other.press.valueAt(other.now));
  }

  /// The knob's body in a box of [size].
  GlassFrame frameIn(Size size) {
    final pressed = press.valueAt(now);
    return GlassFrame(
      rect: (Offset.zero & size).shift(offset.valueAt(now)),
      scaleX: 1 + 0.2 * pressed,
      scaleY: 1 + 0.2 * pressed,
    );
  }
}

/// Forwards each stamped input of a touch to [knob] and keeps those of the
/// last touch.
final class KnobRecording extends ChangeNotifier implements PointerFollower {
  /// Records for and feeds [knob].
  KnobRecording(this.knob);

  /// The knob the inputs go to.
  final KnobMotion knob;

  /// The inputs of the last touch, in order.
  final List<InteractionInput> inputs = [];

  /// The time of the first input.
  double get start => inputs.isEmpty ? 0 : inputs.first.time;

  /// How long the touch lasted, plus time for the knob to settle.
  double get duration => inputs.isEmpty ? 0 : inputs.last.time - start + 1.2;

  /// Feeds [inputs] up to [t] to a fresh knob and reads it at [t].
  KnobMotion replay(double t) {
    final copy = KnobMotion();
    for (final input in inputs) {
      if (input.time > t) break;
      switch (input) {
        case PointerDownInput():
          copy.down(input);
        case PointerMoveInput():
          copy.move(input);
        case PointerUpInput():
          copy.up(input);
        case PointerCancelInput():
          copy.cancel(input);
        default:
      }
    }
    copy.advance(t);
    return copy;
  }

  @override
  void down(PointerDownInput input) {
    inputs.clear();
    inputs.add(input);
    knob.down(input);
  }

  @override
  void move(PointerMoveInput input) {
    inputs.add(input);
    knob.move(input);
  }

  @override
  void up(PointerUpInput input) {
    inputs.add(input);
    knob.up(input);
    notifyListeners();
  }

  @override
  void cancel(PointerCancelInput input) {
    inputs.add(input);
    knob.cancel(input);
    notifyListeners();
  }

  @override
  void hover(PointerHoverInput input) {}
}

/// The app's own control next to two package controls with an app look:
/// the knob, a `RawGlassSwitch` whose knob the app draws, and
/// `GlassButton`s styled with `styleFrom` and with a builder.
class OwnControlSection extends StatefulWidget {
  const OwnControlSection({required this.recording, super.key});

  final KnobRecording recording;

  @override
  State<OwnControlSection> createState() => _OwnControlSectionState();
}

class _OwnControlSectionState extends State<OwnControlSection> {
  static const _knob = Size.square(56);
  static const _orange = Color(0xFFFF9500);

  late final _frame = widget.recording.knob.select((k) => k.frameIn(_knob));
  late final List<Interaction> _interactions = [
    FollowInteraction(widget.recording),
  ];
  var _night = false;
  var _presses = 0;

  @override
  Widget build(BuildContext context) => GlassListSection(
    header: const Text('Your own control'),
    footer: const Text(
      'Drag the knob: it is a Motion of the app with FollowInteraction and '
      "GlassSurface.live. The app draws the switch's knob and styles the "
      'buttons.',
    ),
    children: [
      ClipRect(
        child: SizedBox(
          height: 200,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image(image: Wallpaper.aurora.image, fit: BoxFit.cover),
              Center(
                child: MotionScope(
                  motion: widget.recording.knob,
                  child: InputRegion(
                    interactions: _interactions,
                    semantics: const SemanticsProperties(label: 'Knob'),
                    child: SizedBox.fromSize(
                      size: _knob,
                      child: GlassSurface.live(
                        frame: _frame,
                        glass: const Glass.clear(),
                        child: const Icon(
                          CupertinoIcons.move,
                          color: Color(0xFFFFFFFF),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      GlassListRow(
        title: const Text('Night'),
        trailing: RawGlassSwitch(
          value: _night,
          semanticLabel: 'Night',
          onChanged: (on) => setState(() => _night = on),
          builder: (context, details) => Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: GlassDynamicColor.resolve(
                    GlassColors.systemGray4,
                    context,
                  ),
                  shape: const StadiumBorder(),
                ),
              ),
              MotionTransition(
                opacity: details.progress,
                child: const DecoratedBox(
                  decoration: ShapeDecoration(
                    color: Color(0xFF3A3A8C),
                    shape: StadiumBorder(),
                  ),
                ),
              ),
              GlassSurface.live(
                frame: details.thumb,
                glass: const Glass.regular(tint: _orange),
                child: Icon(
                  _night ? CupertinoIcons.moon_fill : CupertinoIcons.sun_max,
                  size: 16,
                  color: const Color(0xFFFFFFFF),
                ),
              ),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            GlassButton(
              onPressed: () => setState(() => _presses++),
              style: GlassButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: const Color(0xFFFFFFFF),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text('Pressed $_presses'),
            ),
            GlassButton(
              onPressed: () => setState(() => _presses = 0),
              style: GlassButtonStyle(
                builder: (context, details) => GlassSurface.live(
                  frame: details.body,
                  glass: const Glass.regular(tint: Color(0xFFAF52DE)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 11,
                    ),
                    child: details.label,
                  ),
                ),
              ),
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    ],
  );
}

/// The last touch on the knob, replayed on a fresh copy of its motion at a
/// tenth of its speed, or scrubbed by hand.
class Replay extends StatefulWidget {
  const Replay({required this.recording, super.key});

  final KnobRecording recording;

  @override
  State<Replay> createState() => _ReplayState();
}

class _ReplayState extends State<Replay> with SingleTickerProviderStateMixin {
  static const _knob = Size.square(56);
  static const _speed = 0.1;

  final _shown = KnobMotion();
  late final _frame = _shown.select((k) => k.frameIn(_knob));
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  var _progress = 0.0;

  @override
  void initState() {
    super.initState();
    widget.recording.addListener(_recorded);
  }

  @override
  void dispose() {
    widget.recording.removeListener(_recorded);
    _ticker.dispose();
    super.dispose();
  }

  void _recorded() {
    _ticker.stop();
    _scrub(0);
  }

  void _scrub(double progress) {
    final recording = widget.recording;
    final t = recording.start + progress * recording.duration;
    _shown.show(MotionClock.instance.now, recording.replay(t));
    setState(() => _progress = progress);
  }

  void _play() {
    if (_ticker.isActive) {
      _ticker.stop();
      setState(() {});
      return;
    }
    _last = Duration.zero;
    if (_progress >= 1) _scrub(0);
    _ticker.start();
    setState(() {});
  }

  void _tick(Duration elapsed) {
    final step = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final duration = widget.recording.duration;
    if (duration <= 0) return;
    final next = (_progress + step * _speed / duration).clamp(0.0, 1.0);
    _scrub(next);
    if (next >= 1) {
      _ticker.stop();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final recorded = widget.recording.inputs.isNotEmpty;
    return GlassListSection(
      header: const Text('Slow replay'),
      footer: Text(
        recorded
            ? '${widget.recording.inputs.length} stamped inputs from your '
                  'last touch, fed to a fresh knob. A motion is a function '
                  'of its stamped inputs, so it reads the same at any time.'
            : 'Drag the knob above, then replay the touch here.',
      ),
      children: [
        ClipRect(
          child: SizedBox(
            height: 160,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image(image: Wallpaper.aurora.image, fit: BoxFit.cover),
                Center(
                  child: SizedBox.fromSize(
                    size: _knob,
                    child: GlassSurface.live(
                      frame: _frame,
                      glass: const Glass.clear(),
                      child: const Icon(
                        CupertinoIcons.move,
                        color: Color(0xFFFFFFFF),
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  left: 16,
                  top: 12,
                  child: PhotoText('0.1x', weight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        GlassListRow(
          child: Row(
            children: [
              GlassButton(
                onPressed: recorded ? _play : null,
                semanticLabel: _ticker.isActive ? 'Pause' : 'Play',
                child: Icon(
                  _ticker.isActive
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GlassSlider(
                  value: _progress,
                  semanticLabel: 'Time',
                  onChanged: recorded
                      ? (progress) {
                          _ticker.stop();
                          _scrub(progress);
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
