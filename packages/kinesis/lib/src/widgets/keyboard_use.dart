import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Whether the keyboard is what the person uses now: a key went down since
/// the last pointer did.
///
/// A focused control shows its focus by it, and a presentation hands its
/// focus to its first control by it, so a click that focuses lights no ring
/// and a menu opened by the mouse lights no row.
/// `FocusManager.highlightMode` cannot say this on a desktop: there it is
/// traditional until a finger touches the screen, mouse or not.
///
/// A shortcut is not use of the keyboard to move around: a key pressed with
/// Control, Alt or Meta held, and a modifier on its own, change nothing.
///
/// An app that sets `FocusManager.highlightStrategy` decides instead: always
/// traditional means always in use, always touch never.
abstract final class KeyboardUse {
  static final _KeyboardUse _tracker = _KeyboardUse();

  /// Whether the keyboard is in use.
  static bool get inUse => switch (FocusManager.instance.highlightStrategy) {
    .alwaysTraditional => true,
    .alwaysTouch => false,
    .automatic =>
      _tracker.keyCameLast &&
          FocusManager.instance.highlightMode == FocusHighlightMode.traditional,
  };

  /// Tells its listeners when a key or a pointer changes [inUse]. A change
  /// of `FocusManager.highlightMode` changes it too, and is heard from the
  /// focus manager's own listeners.
  ///
  /// Keys and pointers are followed while it has a listener, which every
  /// input region and zone host is; with none, the keyboard is not in use.
  static Listenable get changes => _tracker;
}

final class _KeyboardUse extends ChangeNotifier {
  @override
  void addListener(VoidCallback listener) {
    if (!hasListeners) {
      HardwareKeyboard.instance.addHandler(_key);
      GestureBinding.instance.pointerRouter.addGlobalRoute(_pointer);
    }
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (hasListeners) return;
    HardwareKeyboard.instance.removeHandler(_key);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointer);
    keyCameLast = false;
  }

  static final _aloneSaysNothing = {
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.fn,
  };

  bool keyCameLast = false;

  bool _key(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event is KeyDownEvent &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed &&
        !_aloneSaysNothing.contains(event.logicalKey)) {
      _set(true);
    }
    return false;
  }

  void _pointer(PointerEvent event) {
    if (event is PointerDownEvent) _set(false);
  }

  void _set(bool value) {
    if (keyCameLast == value) return;
    keyCameLast = value;
    notifyListeners();
  }
}
