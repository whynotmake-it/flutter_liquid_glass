import 'package:apple_liquid_glass/src/motions/sheet_motion.dart';
import 'package:apple_liquid_glass/src/motions/sheet_tuning.dart';

/// What a [SheetMotion] tells its host.
sealed class SheetEvent {
  const SheetEvent();
}

/// A settle picked detent [index]; [byUser] when a drag or a grabber tap
/// picked it, not the app.
final class SheetDetentChanged extends SheetEvent {
  /// Creates the event.
  const SheetDetentChanged(this.index, {required this.byUser});

  /// The detent index, in the motion's ascending order.
  final int index;

  /// Whether the user picked the detent.
  final bool byUser;
}

/// A released drag dismisses the sheet.
final class SheetDismissed extends SheetEvent {
  /// Creates the event.
  const SheetDismissed();
}

/// A released drag pulled a sheet that is not dismissible further than
/// [SheetTuning.dismissAttemptShare] of [SheetTuning.refusedPullExtent];
/// the sheet returns to its smallest detent.
final class SheetDismissRefused extends SheetEvent {
  /// Creates the event.
  const SheetDismissRefused();
}
