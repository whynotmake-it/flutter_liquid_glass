import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/rendering.dart';

/// Shows the last [GlassFrameReport] over [child], in debug and profile
/// builds.
class LiquidGlassReportOverlay extends StatefulWidget {
  /// Shows the report over [child], at [alignment] inside [padding].
  const LiquidGlassReportOverlay({
    required this.child,
    this.alignment = Alignment.topCenter,
    this.padding = const EdgeInsets.all(8),
    super.key,
  });

  /// What the report lies over.
  final Widget child;

  /// Where the report sits in the box of [child].
  final Alignment alignment;

  /// The room between the report and the edges of the box, on top of what
  /// the view keeps clear (the status bar, the home indicator) where a
  /// `MediaQuery` above says it.
  final EdgeInsets padding;

  @override
  State<LiquidGlassReportOverlay> createState() =>
      _LiquidGlassReportOverlayState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('alignment', alignment))
      ..add(DiagnosticsProperty('padding', padding));
  }
}

class _LiquidGlassReportOverlayState extends State<LiquidGlassReportOverlay> {
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
    GlassFrameReports.addListener(_onReport);
  }

  @override
  void dispose() {
    GlassFrameReports.removeListener(_onReport);
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kReleaseMode) return widget.child;
    final keptClear = MediaQuery.maybeViewPaddingOf(context) ?? EdgeInsets.zero;
    return Stack(
      textDirection: TextDirection.ltr,
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: Padding(
              padding: widget.padding + keptClear,
              child: Align(
                alignment: widget.alignment,
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
          ),
        ),
      ],
    );
  }
}
