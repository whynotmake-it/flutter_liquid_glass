import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Shows, while [shown], how the app is drawing over [child]: frames a
/// second, and the mean time of a frame on the UI thread and on the raster
/// thread over the last half second. It is plain paint, so what it adds to
/// a frame is a line of text.
class FrameMeter extends StatefulWidget {
  const FrameMeter({required this.shown, required this.child, super.key});

  final bool shown;
  final Widget child;

  @override
  State<FrameMeter> createState() => _FrameMeterState();
}

class _FrameMeterState extends State<FrameMeter> {
  final _text = ValueNotifier('');
  final _frames = <FrameTiming>[];
  var _listening = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(FrameMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    if (_listening) SchedulerBinding.instance.removeTimingsCallback(_timed);
    _text.dispose();
    super.dispose();
  }

  void _sync() {
    if (widget.shown == _listening) return;
    _listening = widget.shown;
    if (_listening) {
      SchedulerBinding.instance.addTimingsCallback(_timed);
    } else {
      SchedulerBinding.instance.removeTimingsCallback(_timed);
      _frames.clear();
      _text.value = '';
    }
  }

  void _timed(List<FrameTiming> timings) {
    _frames.addAll(timings);
    final last = _frames.last.timestampInMicroseconds(FramePhase.rasterFinish);
    _frames.removeWhere(
      (frame) =>
          last - frame.timestampInMicroseconds(FramePhase.rasterFinish) >
          500000,
    );
    if (_frames.length < 2) return;
    final span =
        last - _frames.first.timestampInMicroseconds(FramePhase.rasterFinish);
    var ui = 0;
    var raster = 0;
    for (final frame in _frames) {
      ui += frame.buildDuration.inMicroseconds;
      raster += frame.rasterDuration.inMicroseconds;
    }
    final count = _frames.length;
    _text.value =
        '${((count - 1) * 1e6 / span).round()} fps   '
        'UI ${(ui / count / 1000).toStringAsFixed(1)}   '
        'raster ${(raster / count / 1000).toStringAsFixed(1)} ms';
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      if (widget.shown)
        IgnorePointer(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: ValueListenableBuilder(
                valueListenable: _text,
                builder: (context, text, _) => DecoratedBox(
                  decoration: const ShapeDecoration(
                    color: Color(0xCC000000),
                    shape: StadiumBorder(),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    child: Text(
                      text,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        color: Color(0xFF7CFC9A),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
