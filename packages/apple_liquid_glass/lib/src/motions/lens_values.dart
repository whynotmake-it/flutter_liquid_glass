import 'package:apple_liquid_glass/src/motions/lens_motion.dart';

/// A slot the lens can rest in: its center and width along the track.
typedef LensSlot = ({double center, double width});

/// What a [LensMotion] tells its host.
sealed class LensEvent {
  const LensEvent();
}

/// The selection changed to [index].
final class LensSelected extends LensEvent {
  /// Creates the event.
  const LensSelected(this.index);

  /// The selected slot.
  final int index;
}
