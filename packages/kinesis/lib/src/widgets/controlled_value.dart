import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// The state of a control whose app owns the value it shows, as a switch's
/// app owns whether it is on.
///
/// The user changes what the control's motion shows. The control tells the
/// app ([tellApp]), and the app answers by rebuilding the control with the
/// new value, or does not. In the build after it a motion the app did not
/// follow returns to the widget's value ([followWidget]): a controlled
/// control never shows a value its app does not hold.
///
/// A motion may raise its event while the framework builds or lays out,
/// such as when an update cancels a drag. The app then hears it in the
/// clock's coming publish phase, where it may rebuild.
///
/// The state writes [buildControl], not [build].
mixin ControlledValue<T extends StatefulWidget> on State<T> {
  bool _told = false;

  /// The clock the control's motion runs on.
  @protected
  MotionClock get valueClock;

  /// Whether the user still leads the value, in a drag or the glide after
  /// it: the motion does not return while they do. A control that answers
  /// true calls [returnUnlessFollowed] when they stop.
  @protected
  bool get userLeads => false;

  /// Puts the motion at the value the widget carries, unless it is there.
  @protected
  void followWidget();

  /// Runs [tell], which calls the app with what the user chose, where the
  /// app may rebuild, then returns the motion to the widget's value in the
  /// build that follows unless the app followed.
  @protected
  void tellApp(VoidCallback tell) => outsideBuild(() {
    tell();
    if (mounted) setState(() => _told = true);
  });

  /// Returns the motion to the widget's value in the coming build unless
  /// the app followed, without telling the app anything.
  @protected
  void returnUnlessFollowed() => tellApp(() {});

  /// Runs [callback] now, or in the clock's coming publish phase when the
  /// framework is building, laying out or painting, where a rebuild is not
  /// allowed; not at all once the state is gone.
  @protected
  void outsideBuild(VoidCallback callback) {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      callback();
      return;
    }
    valueClock.schedulePublish(() {
      if (mounted) callback();
    });
  }

  /// Builds the control.
  @protected
  Widget buildControl(BuildContext context);

  @override
  @nonVirtual
  Widget build(BuildContext context) {
    if (_told && !userLeads) {
      _told = false;
      followWidget();
    }
    return buildControl(context);
  }
}
