import 'dart:ffi';
import 'dart:io';

const _monotonicRaw = 4;
const _uptimeRaw = 8;

final int Function(int)? _clockNanoseconds = Platform.isIOS || Platform.isMacOS
    ? DynamicLibrary.process()
          .lookupFunction<Uint64 Function(Uint32), int Function(int)>(
            'clock_gettime_nsec_np',
          )
    : null;

/// How far the engine's frame clock runs ahead of pointer time stamps.
///
/// On iOS and macOS pointer time stamps count CLOCK_UPTIME_RAW, which
/// stops while the device sleeps, and frames CLOCK_MONOTONIC_RAW, which
/// does not: the offset is the sleep so far. Elsewhere both count the same
/// clock.
Duration pointerClockOffset() {
  final read = _clockNanoseconds;
  if (read == null) return Duration.zero;
  final monotonic = read(_monotonicRaw);
  final uptime = read(_uptimeRaw);
  return Duration(microseconds: (monotonic - uptime) ~/ 1000);
}
