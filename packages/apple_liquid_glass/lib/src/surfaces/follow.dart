import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// A render object that hears listenables, such as the frames of a moving
/// glass body or the states of its control, while it is attached, and
/// stops hearing them when it detaches.
///
/// It names them in [followed]. A setter that replaces one of them makes
/// the change inside [refollow], which moves the subscriptions to the new
/// listenables while the render object is attached.
mixin ListenableFollower on RenderObject {
  /// The listenables this render object hears, each with the callback it
  /// runs when that listenable changes.
  @protected
  List<(Listenable, VoidCallback)> get followed;

  /// Runs [change], which replaces listenables [followed] names, and moves
  /// the subscriptions from the old ones to the new ones while attached.
  @protected
  void refollow(VoidCallback change) {
    if (!attached) {
      change();
      return;
    }
    _unfollow();
    change();
    _follow();
  }

  void _follow() {
    for (final (listenable, listener) in followed) {
      listenable.addListener(listener);
    }
  }

  void _unfollow() {
    for (final (listenable, listener) in followed) {
      listenable.removeListener(listener);
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _follow();
  }

  @override
  void detach() {
    _unfollow();
    super.detach();
  }
}
