import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_programs.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';
import 'package:liquid_glass_renderer/src/rendering/warm_up.dart';

/// Whether full glass draws in this process: loading ([FullGlassPending]),
/// ready to draw ([FullGlassReady]), or not drawn ([FullGlassUnavailable]).
@internal
sealed class FullGlass {
  const FullGlass._();

  /// Whether the engine draws shader filters: Impeller does, Skia and the
  /// web do not.
  static final bool shaderFilters =
      !kIsWeb && ui.ImageFilter.isShaderFilterSupported;

  static final FullGlass _first = shaderFilters
      ? const FullGlassPending._()
      : const FullGlassUnavailable._(
          'Impeller shader filters are unavailable.',
        );

  static final ValueNotifier<FullGlass> _state = ValueNotifier(_first);

  /// The state of full glass in this process.
  static ValueListenable<FullGlass> get state => _state;

  static Future<FullGlass>? _loading;
  static bool _loadScheduled = false;

  static FullGlass? _found;

  static int _overrideGeneration = 0;

  static bool _overriddenSince(int generation) =>
      generation != _overrideGeneration;

  /// Loads the fake glass programs everywhere and, where the engine draws
  /// shader filters, every full-glass program and the Flutter GPU geometry
  /// bundle, then settles [state].
  static Future<FullGlass> load() => _loading ??= _load();

  /// Starts [load] after the frame being drawn, unless it started: loading
  /// creates the engine's GPU context, which a first frame need not wait
  /// for.
  static void loadAfterFrame() {
    if (_loading != null || _loadScheduled) return;
    _loadScheduled = true;
    // After the frame: the layers it shows draw fake glass until the load
    // settles, which is no glass a frame late.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _loadScheduled = false;
      unawaited(load());
    });
  }

  /// Loads full glass ([load]), with [warmUp] draws each of its pipelines
  /// once offscreen, and says what it found.
  static Future<LiquidGlassSupport> precache({bool warmUp = false}) async {
    final glass = await load();
    if (warmUp && glass is FullGlassReady) {
      await (_warmUp ??= _guard(() async {
        final renderer = glass.geometryRenderer();
        try {
          await warmLiquidGlassPipelines(renderer);
        } finally {
          renderer.dispose();
        }
      }));
    }
    return glass.support;
  }

  static Future<void>? _warmUp;

  static Future<FullGlass> _load() async {
    final generation = _overrideGeneration;
    final finals = FinalShaderVariant.assetKeys;
    GeometryBundle? bundle;
    await Future.wait<void>([
      GlassShaderPrograms.precacheShaders([
        ...ShaderKeys.fakeLayerAssets,
        ShaderKeys.bentContent,
      ]),
      if (shaderFilters) ...[
        GlassShaderPrograms.precacheShaders([
          ...finals,
          ShaderKeys.backdropFrost,
          ShaderKeys.backdropFrostAxis,
          ShaderKeys.backdropFrostSquare,
          ShaderKeys.backdropHazeStrip,
          ShaderKeys.backdropHazeMix,
        ]),
        _guard(() async {
          bundle = await GeometryBundle.load(
            ShaderKeys.gpuGeometryShaderBundle,
          );
        }),
      ],
    ]);
    final programs = finals.map(GlassShaderPrograms.cached).nonNulls.toList();
    final FullGlass found;
    if (!shaderFilters) {
      found = _first;
    } else if (bundle case final bundle?
        when programs.length == finals.length) {
      found = FullGlassReady._(programs, bundle);
    } else {
      found = const FullGlassUnavailable._(
        'A full-glass program or the Flutter GPU geometry bundle did not '
        'load; the error was reported through FlutterError.',
      );
    }
    _found = found;
    if (!_overriddenSince(generation)) _state.value = found;
    return found;
  }

  /// Makes [state] say [support] for a test, as if loading full glass had
  /// found it. Only a load makes full glass ready, so an available [support]
  /// throws.
  static void debugOverride(LiquidGlassSupport? support) {
    final forced = switch (support) {
      LiquidGlassAvailableSupport() => throw ArgumentError.value(
        support,
        'support',
        'Only a load makes full glass ready.',
      ),
      LiquidGlassPendingSupport() => const FullGlassPending._(),
      LiquidGlassUnavailableSupport(:final reason) => FullGlassUnavailable._(
        reason,
      ),
      null => _found,
    };
    _overrideGeneration++;
    _loading = forced == null || forced is FullGlassPending
        ? null
        : Future.value(forced);
    _state.value = forced ?? _first;
  }

  /// What this state says about the device.
  LiquidGlassSupport get support;
}

/// Full glass is loading: layers draw fake glass meanwhile.
@internal
final class FullGlassPending extends FullGlass {
  const FullGlassPending._() : super._();

  @override
  LiquidGlassSupport get support => const LiquidGlassSupport.pending();
}

/// Full glass draws: every final program and the geometry bundle loaded.
@internal
final class FullGlassReady extends FullGlass {
  FullGlassReady._(this._programs, this._bundle)
    : support = LiquidGlassSupport.available(
        deviceClass: _bundle.deviceClass,
      ),
      super._();

  final List<ui.FragmentProgram> _programs;

  final GeometryBundle _bundle;

  @override
  final LiquidGlassSupport support;

  /// New final shaders, one per `FinalShaderVariant.all`, which the caller
  /// disposes.
  List<ui.FragmentShader> finalShaders() => [
    for (final program in _programs) program.fragmentShader(),
  ];

  /// A new geometry renderer, which the caller disposes.
  FlutterGpuGeometryRenderer geometryRenderer() =>
      FlutterGpuGeometryRenderer(_bundle);
}

/// Full glass does not draw, for [reason]: layers draw fake glass.
@internal
final class FullGlassUnavailable extends FullGlass {
  const FullGlassUnavailable._(this.reason) : super._();

  /// Why full glass does not draw.
  final String reason;

  @override
  LiquidGlassSupport get support => LiquidGlassSupport.unavailable(reason);
}

Future<void> _guard(Future<void> Function() load) async {
  try {
    await load();
  } on Object catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'liquid_glass_renderer',
        context: ErrorDescription('while loading liquid glass shaders'),
      ),
    );
  }
}
