import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Connects the content a [LiquidGlassAdaptiveBrightness] estimates its
/// brightness from to the [LiquidGlassBrightnessBackdrop] that paints it.
///
/// Create one per content plane, like a [BackdropKey], and pass it to both
/// widgets. The glass and its glyphs are never part of the sampled content, so
/// flipping them cannot feed back into the estimate.
class LiquidGlassBrightnessSource {
  RenderLiquidGlassBrightnessBackdrop? _backdrop;

  /// Whether a [LiquidGlassBrightnessBackdrop] currently paints this source.
  bool get isAttached => _backdrop?.attached ?? false;
}

/// Marks [child] as the content that [source] samples.
///
/// Wrap the content that scrolls beneath the glass, not the glass itself.
/// The child is painted into its own retained layer; sampling re-rasterizes
/// only the part of that layer beneath each [LiquidGlassAdaptiveBrightness],
/// at a few pixels of resolution, off the main render path.
class LiquidGlassBrightnessBackdrop extends SingleChildRenderObjectWidget {
  /// Creates a sampled backdrop for [source].
  const LiquidGlassBrightnessBackdrop({
    required this.source,
    required super.child,
    super.key,
  });

  /// The handle [LiquidGlassAdaptiveBrightness] widgets sample through.
  final LiquidGlassBrightnessSource source;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderLiquidGlassBrightnessBackdrop(source);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlassBrightnessBackdrop renderObject,
  ) {
    renderObject.source = source;
  }
}

/// Render object for [LiquidGlassBrightnessBackdrop].
@internal
class RenderLiquidGlassBrightnessBackdrop extends RenderProxyBox {
  /// Creates the render object for [source].
  RenderLiquidGlassBrightnessBackdrop(this._source);

  LiquidGlassBrightnessSource _source;

  /// The handle this backdrop registers with while attached.
  LiquidGlassBrightnessSource get source => _source;
  set source(LiquidGlassBrightnessSource value) {
    if (identical(value, _source)) return;
    if (identical(_source._backdrop, this)) _source._backdrop = null;
    _source = value;
    if (attached) _source._backdrop = this;
  }

  @override
  bool get isRepaintBoundary => true;

  /// The retained layer this backdrop's content was last painted into.
  OffsetLayer? get sampleLayer => layer as OffsetLayer?;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _source._backdrop = this;
  }

  @override
  void detach() {
    if (identical(_source._backdrop, this)) _source._backdrop = null;
    super.detach();
  }
}

/// Tuning for [LiquidGlassAdaptiveBrightness].
///
/// Luminance is Rec.709 luma of the gamma-encoded backdrop (the basis the glass
/// shader uses), averaged over the glass bounds and weighted by coverage.
@immutable
class LiquidGlassAdaptiveBrightnessSettings with Equatable {
  /// Creates adaptive brightness settings.
  const LiquidGlassAdaptiveBrightnessSettings({
    this.threshold = .5,
    this.hysteresis = .1,
    this.smoothing = const Duration(milliseconds: 120),
    this.interval = const Duration(milliseconds: 100),
    this.resolution = .125,
    this.maxSampleExtent = 32,
  }) : assert(threshold >= 0 && threshold <= 1, 'threshold must be in 0-1'),
       assert(hysteresis >= 0, 'hysteresis must not be negative'),
       assert(resolution > 0, 'resolution must be positive'),
       assert(maxSampleExtent > 0, 'maxSampleExtent must be positive');

  /// Smoothed luminance at which the backdrop counts as light.
  final double threshold;

  /// Width of the dead band around [threshold].
  ///
  /// A dark backdrop turns light above `threshold + hysteresis / 2` and a light
  /// one turns dark below `threshold - hysteresis / 2`, so content hovering at
  /// the threshold does not make glyphs flicker.
  final double hysteresis;

  /// Time constant of the exponential smoothing applied to samples.
  ///
  /// [Duration.zero] uses each sample as is.
  final Duration smoothing;

  /// Minimum time between two samples.
  ///
  /// Samples are only taken on frames that were actually drawn (plus one
  /// trailing sample after the last one), so an idle screen costs nothing.
  final Duration interval;

  /// Sample pixels per logical pixel of the sampled region.
  final double resolution;

  /// Upper bound for the sample image's width and height in pixels.
  final int maxSampleExtent;

  @override
  List<Object?> get props => [
    threshold,
    hysteresis,
    smoothing,
    interval,
    resolution,
    maxSampleExtent,
  ];
}

/// The brightness estimate of the content behind a
/// [LiquidGlassAdaptiveBrightness].
@immutable
class LiquidGlassBackdropBrightness with Equatable {
  /// Creates a brightness estimate.
  const LiquidGlassBackdropBrightness({
    required this.luminance,
    required this.brightness,
    this.hasSample = true,
  });

  /// The estimate before the first sample has arrived.
  const LiquidGlassBackdropBrightness.unknown(this.brightness)
    : luminance = brightness == Brightness.light ? 1 : 0,
      hasSample = false;

  /// Smoothed backdrop luminance in 0-1.
  final double luminance;

  /// Whether the backdrop is light or dark, after hysteresis.
  ///
  /// Glyphs should use the opposite brightness: dark glyphs and light glass
  /// over a light backdrop.
  final Brightness brightness;

  /// Whether [luminance] comes from a sample rather than the fallback.
  final bool hasSample;

  @override
  List<Object?> get props => [luminance, brightness, hasSample];
}

/// Smoothing and hysteresis applied to raw luminance samples.
@internal
class BackdropBrightnessFilter {
  /// Creates a filter that starts out at [initial].
  BackdropBrightnessFilter({
    required this.settings,
    required Brightness initial,
  }) : _value = LiquidGlassBackdropBrightness.unknown(initial);

  /// The settings used for the next [add].
  LiquidGlassAdaptiveBrightnessSettings settings;

  LiquidGlassBackdropBrightness _value;

  /// The current estimate.
  LiquidGlassBackdropBrightness get value => _value;

  Duration? _lastSampleTime;

  /// Adds a raw [luminance] sample taken at [time] and returns the estimate.
  LiquidGlassBackdropBrightness add(double luminance, Duration time) {
    final raw = luminance.clamp(0.0, 1.0);
    final last = _lastSampleTime;
    _lastSampleTime = time;
    final double smoothed;
    if (!_value.hasSample ||
        last == null ||
        settings.smoothing <= Duration.zero) {
      smoothed = raw;
    } else {
      final dt = (time - last).inMicroseconds.clamp(0, 1 << 31);
      final alpha = 1 - math.exp(-dt / settings.smoothing.inMicroseconds);
      smoothed = _value.luminance + (raw - _value.luminance) * alpha;
    }

    final half = settings.hysteresis / 2;
    final Brightness brightness;
    if (!_value.hasSample) {
      brightness = smoothed >= settings.threshold
          ? Brightness.light
          : Brightness.dark;
    } else if (_value.brightness == Brightness.dark) {
      brightness = smoothed > settings.threshold + half
          ? Brightness.light
          : Brightness.dark;
    } else {
      brightness = smoothed < settings.threshold - half
          ? Brightness.dark
          : Brightness.light;
    }
    return _value = LiquidGlassBackdropBrightness(
      luminance: smoothed,
      brightness: brightness,
    );
  }
}

/// Coverage-weighted Rec.709 luma of premultiplied RGBA8 [pixels], or `null`
/// when nothing is covered.
@internal
double? averageLuminance(ByteData pixels) {
  var luma = 0.0;
  var coverage = 0.0;
  final bytes = pixels.buffer.asUint8List(
    pixels.offsetInBytes,
    pixels.lengthInBytes,
  );
  for (var i = 0; i + 3 < bytes.length; i += 4) {
    luma += .2126 * bytes[i] + .7152 * bytes[i + 1] + .0722 * bytes[i + 2];
    coverage += bytes[i + 3];
  }
  if (coverage < 1) return null;
  return luma / coverage;
}

/// Signature for [LiquidGlassAdaptiveBrightness.builder].
typedef LiquidGlassAdaptiveBrightnessBuilder = Widget Function(
  BuildContext context,
  LiquidGlassBackdropBrightness brightness,
  Widget? child,
);

/// Estimates the brightness of the content behind its bounds so glyphs and
/// glass can flip between light and dark, like iOS toolbars and tab bars.
///
/// Experimental: this API may change without a major version bump.
///
/// The estimate comes from [source]: the region of the
/// [LiquidGlassBrightnessBackdrop] beneath this widget is rasterized into an
/// image of at most [LiquidGlassAdaptiveBrightnessSettings.maxSampleExtent]
/// pixels per side and read back asynchronously. Nothing is added to the glass
/// shader, and neither the UI nor the raster thread waits for the GPU; results
/// arrive a frame or two after the content moved.
///
/// Each instance samples its own bounds, so wrap every element that should
/// flip independently (a tab bar and a floating button, for example).
class LiquidGlassAdaptiveBrightness extends StatefulWidget {
  /// Creates an adaptive brightness estimate for this widget's bounds.
  const LiquidGlassAdaptiveBrightness({
    required this.source,
    this.builder,
    this.child,
    this.settings = const LiquidGlassAdaptiveBrightnessSettings(),
    this.initialBrightness,
    this.onChanged,
    super.key,
  }) : assert(
         builder != null || child != null,
         'Provide a builder, a child, or both.',
       );

  /// The content to estimate brightness from.
  final LiquidGlassBrightnessSource source;

  /// Builds the subtree for the current estimate.
  ///
  /// Only called when [LiquidGlassBackdropBrightness.brightness] changes or
  /// luminance moves noticeably. Descendants can also read the estimate with
  /// [LiquidGlassAdaptiveBrightness.of].
  final LiquidGlassAdaptiveBrightnessBuilder? builder;

  /// Passed to [builder], or shown as is without one.
  final Widget? child;

  /// Thresholds, smoothing and sampling cost.
  final LiquidGlassAdaptiveBrightnessSettings settings;

  /// Assumed backdrop brightness before the first sample. Defaults to the
  /// opposite of the platform brightness, where default glyphs are legible.
  final Brightness? initialBrightness;

  /// Called whenever the estimate changes.
  final ValueChanged<LiquidGlassBackdropBrightness>? onChanged;

  /// The nearest estimate above [context], or `null` if there is none.
  static LiquidGlassBackdropBrightness? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_InheritedBackdropBrightness>()
      ?.value;

  /// The nearest estimate above [context].
  static LiquidGlassBackdropBrightness of(BuildContext context) {
    final value = maybeOf(context);
    assert(value != null, 'No LiquidGlassAdaptiveBrightness above $context.');
    return value!;
  }

  @override
  State<LiquidGlassAdaptiveBrightness> createState() =>
      _LiquidGlassAdaptiveBrightnessState();
}

class _LiquidGlassAdaptiveBrightnessState
    extends State<LiquidGlassAdaptiveBrightness> {
  static const _minimumLuminanceChange = .02;

  BackdropBrightnessFilter? _filter;
  LiquidGlassBackdropBrightness? _published;
  bool _frameHookArmed = false;
  bool _sampling = false;
  bool _pendingTrailingSample = false;
  Timer? _trailingTimer;
  Duration? _lastSampleStart;
  final _clock = Stopwatch()..start();

  BackdropBrightnessFilter get _brightnessFilter =>
      _filter ??= BackdropBrightnessFilter(
        settings: widget.settings,
        initial:
            widget.initialBrightness ??
            switch (MediaQuery.platformBrightnessOf(context)) {
              Brightness.light => Brightness.dark,
              Brightness.dark => Brightness.light,
            },
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _published ??= _brightnessFilter.value;
    _armFrameHook();
  }

  @override
  void didUpdateWidget(covariant LiquidGlassAdaptiveBrightness oldWidget) {
    super.didUpdateWidget(oldWidget);
    _brightnessFilter.settings = widget.settings;
    if (!identical(oldWidget.source, widget.source)) _armFrameHook();
  }

  @override
  void dispose() {
    _trailingTimer?.cancel();
    super.dispose();
  }

  // Post-frame callbacks only run for frames that were drawn and do not
  // schedule frames themselves, so a static screen stops sampling.
  void _armFrameHook() {
    if (_frameHookArmed) return;
    _frameHookArmed = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _frameHookArmed = false;
      if (!mounted) return;
      _armFrameHook();
      _maybeSample();
    }, debugLabel: 'LiquidGlassAdaptiveBrightness.sample');
  }

  void _maybeSample() {
    final now = _clock.elapsed;
    final last = _lastSampleStart;
    if (_sampling) {
      // The completing sample schedules the trailing one.
      _pendingTrailingSample = true;
      return;
    }
    if (last != null && now - last < widget.settings.interval) {
      _pendingTrailingSample = true;
      _scheduleTrailingSample(widget.settings.interval - (now - last));
      return;
    }
    unawaited(_sample(now));
  }

  void _scheduleTrailingSample(Duration delay) {
    if (_trailingTimer?.isActive ?? false) return;
    _trailingTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!mounted || !_pendingTrailingSample) return;
      _maybeSample();
    });
  }

  Future<void> _sample(Duration start) async {
    final region = _sampleRegion();
    if (region == null) return;
    final (layer, rect) = region;
    final settings = widget.settings;
    final pixelRatio = math.min(
      settings.resolution,
      math.min(
        settings.maxSampleExtent / rect.width,
        settings.maxSampleExtent / rect.height,
      ),
    );

    _sampling = true;
    _pendingTrailingSample = false;
    _lastSampleStart = start;
    ui.Image? image;
    try {
      image = layer.toImageSync(rect, pixelRatio: pixelRatio);
      final pixels = await image.toByteData();
      if (!mounted || pixels == null) return;
      final luminance = averageLuminance(pixels);
      if (luminance == null) return;
      _publish(_brightnessFilter.add(luminance, _clock.elapsed));
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'liquid_glass_adaptive_brightness',
          context: ErrorDescription('while sampling backdrop brightness'),
        ),
      );
    } finally {
      image?.dispose();
      _sampling = false;
    }
    if (mounted && _pendingTrailingSample) {
      _scheduleTrailingSample(
        settings.interval - (_clock.elapsed - start),
      );
    }
  }

  (OffsetLayer, Rect)? _sampleRegion() {
    final backdrop = widget.source._backdrop;
    final box = context.findRenderObject();
    if (backdrop == null ||
        !backdrop.attached ||
        !backdrop.hasSize ||
        box is! RenderBox ||
        !box.attached ||
        !box.hasSize) {
      return null;
    }
    final layer = backdrop.sampleLayer;
    if (layer == null || !layer.attached) return null;
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(backdrop),
      Offset.zero & box.size,
    ).intersect(Offset.zero & backdrop.size);
    if (rect.isEmpty) return null;
    return (layer, rect);
  }

  void _publish(LiquidGlassBackdropBrightness value) {
    final published = _published;
    if (published != null &&
        published.hasSample &&
        published.brightness == value.brightness &&
        (published.luminance - value.luminance).abs() <
            _minimumLuminanceChange) {
      return;
    }
    setState(() => _published = value);
    widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final value = _published ?? _brightnessFilter.value;
    return _InheritedBackdropBrightness(
      value: value,
      child:
          widget.builder?.call(context, value, widget.child) ?? widget.child!,
    );
  }
}

class _InheritedBackdropBrightness extends InheritedWidget {
  const _InheritedBackdropBrightness({
    required this.value,
    required super.child,
  });

  final LiquidGlassBackdropBrightness value;

  @override
  bool updateShouldNotify(_InheritedBackdropBrightness oldWidget) =>
      value != oldWidget.value;
}
