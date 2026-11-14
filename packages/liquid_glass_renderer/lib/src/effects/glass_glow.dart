import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:liquid_glass_renderer/src/effects/effect_springs.dart';
import 'package:liquid_glass_renderer/src/effects/glass_drag_builder.dart';

/// {@template glass_glow}
/// Lights the glass this widget sits in under a finger: a soft light
/// follows the touch while it lasts and fades when it ends.
///
/// Place it inside the child of a `LiquidGlass` or a `FakeGlass`; it drives
/// the light of the nearest one above it (see [RenderLiquidGlassContent]),
/// and does nothing outside glass. Glass without a [GlassGlow] pays nothing
/// for the light: its motion lives here.
/// {@endtemplate}
class GlassGlow extends StatefulWidget {
  /// {@macro glass_glow}
  const GlassGlow({
    required this.child,
    this.glowColor = const Color(0x3DFFFFFF),
    this.glowRadius = 1,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.gestureMode = GestureMode.listener,
    super.key,
  });

  /// The radius of the glow effect relative to the glass's shortest side.
  ///
  /// A value of 0.8 means the glow radius will be 80% of the shortest
  /// dimension (width or height) of the glass.
  ///
  /// Defaults to 1.
  final double glowRadius;

  /// The color of the glow effect.
  ///
  /// The glow will have this colors opacity at the center, and will fade out
  /// to fully transparent at the edge of the glow.
  final Color glowColor;

  /// The hit test behavior of the internal gesture handler.
  ///
  /// Defaults to [HitTestBehavior.opaque].
  final HitTestBehavior hitTestBehavior;

  /// {@macro gesture_mode}
  ///
  /// Defaults to [GestureMode.listener].
  final GestureMode gestureMode;

  /// The child that will be painted above the glow effect.
  final Widget child;

  @override
  State<GlassGlow> createState() => _GlassGlowState();
}

/// The glow that last took each glass's light, so two glows in one glass
/// never write it in the same frame.
final _owners = Expando<_GlassGlowState>('GlassGlow owner');

class _GlassGlowState extends State<GlassGlow> with TickerProviderStateMixin {
  late final _x = AnimationController.unbounded(vsync: this);
  late final _y = AnimationController.unbounded(vsync: this);
  late final _alpha = AnimationController.unbounded(vsync: this);
  late final _radius = AnimationController.unbounded(value: 10, vsync: this);
  late final _motion = Listenable.merge([_x, _y, _alpha, _radius]);

  static final _offsetSpring = smoothSpring(const Duration(seconds: 1));

  RenderLiquidGlassContent? _glass;
  bool _dragging = false;
  double _baseRadius = 0;
  Color _baseColor = const Color.fromARGB(0, 0, 0, 0);

  @override
  void initState() {
    super.initState();
    _motion.addListener(_write);
  }

  @override
  void dispose() {
    _motion.removeListener(_write);
    // The light would otherwise stay where the last frame left it.
    if (_glass case final glass? when identical(_owners[glass], this)) {
      _owners[glass] = null;
      if (glass.attached) glass.glowColor = const Color(0x00000000);
    }
    _x.dispose();
    _y.dispose();
    _alpha.dispose();
    _radius.dispose();
    super.dispose();
  }

  void _write() {
    final glass = _glass;
    if (glass == null || !identical(_owners[glass], this)) return;
    glass
      ..glowRadius = _baseRadius * _radius.value
      ..glowColor = _baseColor.withValues(alpha: _baseColor.a * _alpha.value)
      ..glowOffset = Offset(_x.value, _y.value);
  }

  void _beginTouch(Offset offset) {
    if (!mounted) return;
    final glass = context
        .findAncestorRenderObjectOfType<RenderLiquidGlassContent>();
    if (glass == null) return;
    _glass = glass;
    _owners[glass] = this;
    _baseRadius = widget.glowRadius;
    _baseColor = widget.glowColor;

    if (!_dragging) {
      _dragging = true;
      springTo(_radius, interactiveSpring, 1, from: 0);
      springTo(_alpha, interactiveSpring, 1, from: 0);
    }

    _moveTouch(offset);
  }

  void _moveTouch(Offset offset) {
    if (!mounted || _glass == null) return;
    _x.value = offset.dx;
    _y.value = offset.dy;
    _write();
  }

  void _removeTouch() {
    if (!_dragging) return;
    _dragging = false;
    springTo(_x, _offsetSpring, 0);
    springTo(_y, _offsetSpring, 0);
    springTo(_radius, smoothSpring(), 10);
    springTo(_alpha, smoothSpring(), 0);
  }

  @override
  Widget build(BuildContext context) => switch (widget.gestureMode) {
    GestureMode.listener => Listener(
      behavior: widget.hitTestBehavior,
      onPointerDown: (event) => _beginTouch(event.localPosition),
      onPointerMove: (event) => _moveTouch(event.localPosition),
      onPointerUp: (_) => _removeTouch(),
      onPointerCancel: (_) => _removeTouch(),
      child: widget.child,
    ),
    GestureMode.gestureDetector => GestureDetector(
      behavior: widget.hitTestBehavior,
      onPanStart: (details) => _beginTouch(details.localPosition),
      onPanUpdate: (details) => _moveTouch(details.localPosition),
      onPanEnd: (_) => _removeTouch(),
      onPanCancel: _removeTouch,
      child: widget.child,
    ),
  };
}
