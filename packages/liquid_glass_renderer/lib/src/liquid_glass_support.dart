import 'package:flutter/foundation.dart';

/// The kind of GPU full glass runs on, for code that picks between glass and
/// a cheaper look itself, such as a widget library's adaptive quality.
enum LiquidGlassDeviceClass {
  /// Not known: full glass did not load (for example Flutter GPU is not
  /// enabled).
  unknown,

  /// Vulkan, Metal on a Mac or an Apple GPU from the A13, or OpenGL ES on
  /// a desktop.
  capable,

  /// Impeller's OpenGL ES fallback on an Android device without a usable
  /// Vulkan driver. Full glass costs more frame time there than on Vulkan,
  /// and such devices usually have little to spare.
  gles,

  /// An Apple GPU before the A13.
  appleBeforeA13,

  /// No shader filters: Skia or the web.
  noShaderFilters,
}

/// Whether full liquid glass draws on this device, and on what GPU, as
/// `LiquidGlass.precache` found it.
///
/// Glass layers fall back to fake glass by themselves; this is for code that
/// wants to know before it builds them, for example to choose an opaque look
/// on a weak GPU.
@immutable
final class LiquidGlassSupport {
  /// Creates the result of loading full glass.
  const LiquidGlassSupport({
    required this.deviceClass,
    this.unavailableReason,
  });

  /// Whether every full-glass program and the Flutter GPU geometry bundle
  /// loaded, so glass layers can draw full glass.
  bool get available => unavailableReason == null;

  /// The class of the GPU full glass runs on, or, when full glass is
  /// unavailable, [LiquidGlassDeviceClass.noShaderFilters] or
  /// [LiquidGlassDeviceClass.unknown].
  final LiquidGlassDeviceClass deviceClass;

  /// Why full glass is unavailable, when it is.
  final String? unavailableReason;

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassSupport &&
      other.deviceClass == deviceClass &&
      other.unavailableReason == unavailableReason;

  @override
  int get hashCode => Object.hash(deviceClass, unavailableReason);

  @override
  String toString() =>
      'LiquidGlassSupport(available: $available, deviceClass: '
      '${deviceClass.name}'
      '${unavailableReason == null ? '' : ', $unavailableReason'})';
}
