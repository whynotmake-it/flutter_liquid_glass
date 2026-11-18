import 'package:flutter/foundation.dart';

/// The kind of GPU full glass draws on, for code that picks between glass and
/// a cheaper look itself, such as a widget library's adaptive quality.
enum LiquidGlassDeviceClass {
  /// Vulkan, Metal on a Mac or an Apple GPU from the A13, or OpenGL ES on
  /// a desktop.
  capable,

  /// Impeller's OpenGL ES fallback on an Android device without a usable
  /// Vulkan driver. Full glass costs more frame time there than on Vulkan,
  /// and such devices usually have little to spare.
  gles,

  /// An Apple GPU before the A13.
  appleBeforeA13,
}

/// Whether full liquid glass draws in this process, as `liquidGlassSupport`
/// says it: [LiquidGlassSupport.pending] until full glass has loaded, then
/// [LiquidGlassSupport.available] with the GPU it draws on, or
/// [LiquidGlassSupport.unavailable] with the reason.
///
/// Glass layers draw fake glass by themselves wherever full glass is not
/// available; this is for code that wants to know before it builds them,
/// for example to choose an opaque look on a weak GPU.
@immutable
sealed class LiquidGlassSupport {
  const LiquidGlassSupport._();

  /// Full glass has not loaded: it does not draw yet, and still may.
  const factory LiquidGlassSupport.pending() = LiquidGlassPendingSupport._;

  /// Every full-glass program and the Flutter GPU geometry bundle loaded, so
  /// glass layers draw full glass, on a GPU of [deviceClass].
  const factory LiquidGlassSupport.available({
    required LiquidGlassDeviceClass deviceClass,
  }) = LiquidGlassAvailableSupport._;

  /// Full glass does not draw in this process, for [reason]: the engine has
  /// no shader filters (Skia, the web), or a program or the geometry bundle
  /// did not load.
  const factory LiquidGlassSupport.unavailable(String reason) =
      LiquidGlassUnavailableSupport._;
}

/// The [LiquidGlassSupport] before full glass has loaded
/// ([LiquidGlassSupport.pending]).
final class LiquidGlassPendingSupport extends LiquidGlassSupport {
  const LiquidGlassPendingSupport._() : super._();

  @override
  bool operator ==(Object other) => other is LiquidGlassPendingSupport;

  @override
  int get hashCode => (LiquidGlassPendingSupport).hashCode;

  @override
  String toString() => 'LiquidGlassSupport.pending()';
}

/// The [LiquidGlassSupport] of a process that draws full glass
/// ([LiquidGlassSupport.available]).
final class LiquidGlassAvailableSupport extends LiquidGlassSupport {
  const LiquidGlassAvailableSupport._({required this.deviceClass}) : super._();

  /// The kind of GPU full glass draws on.
  final LiquidGlassDeviceClass deviceClass;

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassAvailableSupport && other.deviceClass == deviceClass;

  @override
  int get hashCode => deviceClass.hashCode;

  @override
  String toString() =>
      'LiquidGlassSupport.available(deviceClass: ${deviceClass.name})';
}

/// The [LiquidGlassSupport] of a process that draws no full glass
/// ([LiquidGlassSupport.unavailable]).
final class LiquidGlassUnavailableSupport extends LiquidGlassSupport {
  const LiquidGlassUnavailableSupport._(this.reason) : super._();

  /// Why full glass does not draw.
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassUnavailableSupport && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'LiquidGlassSupport.unavailable($reason)';
}
