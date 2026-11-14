import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/composer.dart';

/// Shows the last [GlassFrameReport] over [child], in debug and profile
/// builds.
class GlassPlanOverlay extends StatefulWidget {
  /// Shows the report over [child].
  const GlassPlanOverlay({required this.child, super.key});

  /// What the report lies over.
  final Widget child;

  @override
  State<GlassPlanOverlay> createState() => _GlassPlanOverlayState();
}

class _GlassPlanOverlayState extends State<GlassPlanOverlay> {
  // The overlay's own text changes the frame after it, and a report twice a
  // second is as fast as anyone reads it.
  static const _every = 30;

  final _text = ValueNotifier('');
  var _frames = 0;

  void _onReport(GlassFrameReport report) {
    if (_frames++ % _every == 0) _text.value = '$report';
  }

  @override
  void initState() {
    super.initState();
    GlassFrameReport.addListener(_onReport);
  }

  @override
  void dispose() {
    GlassFrameReport.removeListener(_onReport);
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kReleaseMode) return widget.child;
    return Stack(
      textDirection: TextDirection.ltr,
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned(
          left: 8,
          right: 8,
          top: 56,
          child: IgnorePointer(
            child: RepaintBoundary(
              child: ValueListenableBuilder(
                valueListenable: _text,
                builder: (context, text, _) => text.isEmpty
                    ? const SizedBox.shrink()
                    : ColoredBox(
                        color: const Color(0xCC000000),
                        child: Text(
                          text,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 9,
                            fontFamily: 'monospace',
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
}
