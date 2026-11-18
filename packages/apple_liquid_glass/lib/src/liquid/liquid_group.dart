part of 'liquid.dart';

class _LiquidGroup extends StatefulWidget {
  const _LiquidGroup({
    required this.fake,
    required this.child,
    this.blend,
    this.glass,
    this.body,
    this.lens,
  });

  final bool fake;
  final double? blend;

  /// The glass of a lone surface or lens, or null for a group.
  final Glass? glass;

  /// The frame of a lone surface, whose outline's field the layer shades,
  /// or null.
  final ValueListenable<GlassFrame>? body;

  /// The lone lens or knob whose lift sets the layer's optics, or null.
  final GlassSurfaceDetails? lens;

  final Widget child;

  @override
  State<_LiquidGroup> createState() => _LiquidGroupState();
}

class _LiquidGroupState extends State<_LiquidGroup> {
  final _layer = ValueNotifier(
    const LiquidGlassLayerFrame(settings: LiquidGlassSettings()),
  );
  // A member that leaves with its group writes nothing to the layer.
  bool _active = true;
  final _clearMembers = <Object, bool>{};
  LiquidGlassSettings _base = const LiquidGlassSettings();
  late LiquidGlassAppearance _appearance;
  late GlassTraits _traits;

  ValueListenable<GlassFrame>? get _lens => widget.lens?.frame;

  @override
  void initState() {
    super.initState();
    teachLiquidUnderlay();
    _lens?.addListener(_writeFrame);
    widget.body?.addListener(_writeFrame);
  }

  @override
  void didUpdateWidget(_LiquidGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lens?.frame != _lens) {
      oldWidget.lens?.frame.removeListener(_writeFrame);
      _lens?.addListener(_writeFrame);
    }
    if (oldWidget.body != widget.body) {
      oldWidget.body?.removeListener(_writeFrame);
      widget.body?.addListener(_writeFrame);
    }
  }

  LiquidGlassSettings get _settings {
    final lens = widget.lens;
    if (lens == null) return _base;
    final frame = lens.frame.value;
    final rect = frame.rect;
    return _lensSettings(
      _base,
      frame.lift,
      lens: lens.lens,
      height: rect == null
          ? null
          : math.min(rect.width * frame.scaleX, rect.height * frame.scaleY),
    );
  }

  void _writeFrame() => _layer.value = LiquidGlassLayerFrame(
    settings: _settings,
    field: widget.body?.value.outline?.field,
    defaultAppearance: _appearance,
  );

  // UIKit shades each member with its own glass; one layer has one set of
  // settings, so a group is clear glass only when all its members are.
  bool get _clear {
    final glass = widget.glass;
    if (glass != null) return glass.isClear;
    return _clearMembers.isNotEmpty && !_clearMembers.containsValue(false);
  }

  void _chooseGlass() {
    final material = LiquidGlassRenderer.materialOf(
      _clear ? const Glass.clear() : const Glass.regular(),
      _traits.brightness,
      sliderPosition: _traits.glassTintAmount,
    );
    _base = material.settings;
    _appearance = material.appearance;
  }

  /// Records the glass of [member], or that it left when [glass] is null.
  ///
  /// The layer takes new settings in the same frame, so a member that
  /// joins while the framework builds paints with them; the scope its
  /// blend group and shapes read follows a frame later: a live layer's
  /// scope moves only when the layer builds, and a member reports while
  /// the framework builds or finalizes the tree, when its group cannot
  /// be marked to build.
  void reportGlass(Object member, Glass? glass) {
    final wasClear = _clear;
    if (glass == null) {
      _clearMembers.remove(member);
    } else {
      _clearMembers[member] = glass.isClear;
    }
    if (!_active || _clear == wasClear) return;
    _chooseGlass();
    _writeFrame();
    _runAfterBuild(this, () => setState(() {}));
  }

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void deactivate() {
    _active = false;
    super.deactivate();
  }

  @override
  void dispose() {
    _lens?.removeListener(_writeFrame);
    widget.body?.removeListener(_writeFrame);
    _layer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _traits = GlassTraits.of(context);
    _chooseGlass();
    _writeFrame();
    final blend = widget.blend;
    final child = widget.child;
    final solid = widget.lens == null
        ? GlassSolidBackdrop.colorOf(context)
        : null;
    return LiquidGlassLayer.live(
      frame: _layer,
      fake: widget.fake,
      backdrop: solid == null
          ? const LiquidGlassBackdrop.read()
          : LiquidGlassBackdrop.solid(solid),
      child: _LiquidGroupScope(
        group: this,
        child: blend == null
            ? child
            : LiquidGlassBlendGroup(blend: blend, child: child),
      ),
    );
  }
}

class _LiquidGroupScope extends InheritedWidget {
  const _LiquidGroupScope({required this.group, required super.child});

  const _LiquidGroupScope.outside({required super.child}) : group = null;

  final _LiquidGroupState? group;

  static _LiquidGroupState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LiquidGroupScope>()?.group;

  @override
  bool updateShouldNotify(_LiquidGroupScope oldWidget) =>
      group != oldWidget.group;
}

class _LiquidLens extends StatefulWidget {
  const _LiquidLens({required this.details, required this.fake});

  final GlassSurfaceDetails details;
  final bool fake;

  @override
  State<_LiquidLens> createState() => _LiquidLensState();
}

class _LiquidLensState extends State<_LiquidLens> {
  late _Lifted _lifted = _Lifted(widget.details.frame);

  @override
  void didUpdateWidget(_LiquidLens oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.details.frame != widget.details.frame) {
      _lifted = _Lifted(widget.details.frame);
    }
  }

  final _content = LensContentBend();
  ValueNotifier<GlassLensContent?>? _report;

  @override
  void initState() {
    super.initState();
    liquidGlassSupport.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  void _writeContent() => _report?.value =
      widget.fake ||
          liquidGlassSupport.value is! LiquidGlassAvailableSupport ||
          widget.details.lens.small
      ? null
      : _content;

  void _withdraw() {
    final report = _report;
    if (report != null && identical(report.value, _content)) {
      report.value = null;
    }
  }

  @override
  void dispose() {
    liquidGlassSupport.removeListener(_rebuild);
    _withdraw();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final details = widget.details;
    if (!identical(_report, details.lensContent)) {
      _withdraw();
      _report = details.lensContent;
    }
    _content.devicePixelRatio = GlassTraits.of(context).viewPixelRatio;
    _writeContent();
    return Stack(
      fit: StackFit.passthrough,
      children: [
        FlatGlassRenderer.flatSurface(context, details, underGlass: true),
        // The lifted layer stays built and is painted only while the lens
        // is lifted, so it shows in the frame the lift crosses its rest.
        Positioned.fill(
          child: MotionVisibility(
            visible: _lifted,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _LiquidGroup(
                  fake: widget.fake,
                  glass: details.glass,
                  lens: details,
                  child: _LiquidSurface(
                    details: GlassSurfaceDetails(
                      role: details.role,
                      lens: details.lens,
                      glass: details.glass,
                      frame: details.frame,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                LensShadows(
                  frame: details.frame,
                  small: details.lens.small,
                  brightness: GlassTraits.of(context).brightness,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Whether a lens's frame lifts it above its rest.
final class _Lifted implements ValueListenable<bool> {
  _Lifted(this.frame);

  final ValueListenable<GlassFrame> frame;

  @override
  bool get value => frame.value.lift > GlassFrame.restingLift;

  @override
  void addListener(VoidCallback listener) => frame.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => frame.removeListener(listener);
}

/// Runs [callback] now, or after the frame while the framework builds or
/// finalizes the tree, if [state] is still mounted then: a callback may
/// rebuild ancestors, and a cancel from a widget's own update or dispose
/// arrives in those phases.
void _runAfterBuild(State<StatefulWidget> state, VoidCallback callback) {
  if (SchedulerBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks) {
    // After the frame: a callback may rebuild ancestors, which the build
    // and finalize phases it arrives in do not allow.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (state.mounted) callback();
    });
    return;
  }
  callback();
}
