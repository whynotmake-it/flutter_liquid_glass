import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// Controls built from Flutter's own blocks that calibrate the checks: the
/// `good` ones meet every check, the `bad` ones break the rules on purpose,
/// so every check is seen to pass and to fail.
final List<Entry> references = [
  Entry(
    'reference.good.button',
    covers: const [],
    kind: Kind.pressable,
    build: (probe, {required enabled}) =>
        _GoodButton(enabled: enabled, onPressed: () => probe.add('pressed')),
  ),
  Entry(
    'reference.good.slider',
    covers: const [],
    kind: Kind.value,
    build: (probe, {required enabled}) => Held<double>(
      probe: probe,
      initial: 0.5,
      builder: (context, value, set) =>
          _GoodSlider(value: value, onChanged: enabled ? set : null),
    ),
  ),
  Entry(
    'reference.good.dialog',
    covers: const [],
    kind: Kind.overlay,
    marker: find.text(overlayText),
    inside: find.text('Inside'),
    build: (probe, {required enabled}) => Opener(
      show: (context) => _dialog(context, probe, overlayText, 'Inside'),
    ),
  ),
  Entry(
    'reference.good.contextMenu',
    covers: const [],
    kind: Kind.opener,
    openGesture: OpenGesture.longPress,
    contextMenu: true,
    marker: find.text('First item'),
    inside: find.text('First item'),
    build: (probe, {required enabled}) => _GoodContextMenu(
      enabled: enabled,
      open: (context) => _dialog(context, probe, 'Menu', 'First item'),
    ),
  ),
  Entry(
    'reference.good.grid',
    covers: const [],
    kind: Kind.grid,
    pages: true,
    build: (probe, {required enabled}) => Held<int>(
      probe: probe,
      initial: 5,
      builder: (context, value, set) =>
          _Grid(value: value, onChanged: enabled ? set : null),
    ),
  ),
  Entry(
    'reference.bad.grid',
    covers: const [],
    kind: Kind.grid,
    pages: true,
    fails: const {
      'semantics-role': '"Number 1" is not announced as a button',
      'key-activate': 'Space does not pick the focused item',
      'key-remap': 'a key the app maps to ActivateIntent does nothing',
      'key-arrows': 'Arrow Right changes the pick; it only moves the focus',
      'key-arrows-rtl': 'the items keep their order on screen in right-to-left',
      'key-home-end': 'Home does not move the focus to the first item',
      'key-arrows-edge':
          'Arrow Down past the last row stops at "Number 8" instead of '
          'turning the page',
    },
    build: (probe, {required enabled}) => Held<int>(
      probe: probe,
      initial: 5,
      builder: (context, value, set) =>
          _Grid(value: value, onChanged: enabled ? set : null, bad: true),
    ),
  ),
  Entry(
    'reference.bad.button',
    covers: const [],
    fails: const {
      'focus-disabled': 'Tab reaches 1 parts while disabled',
      'focus-indicator': 'keyboard focus draws nothing',
      'haptics-gesture-only': 'assistive activation plays the gesture feedback',
      'key-activate': 'Space does not activate it',
      'key-remap': 'a key the app maps to ActivateIntent does nothing',
      'mouse-cursor':
          'it declares no cursor; the cursor over it is '
          'SystemMouseCursor(basic)',
      'mouse-hover': 'hover draws nothing',
      'rtl-text-scale-2': 'A RenderFlex overflowed by 278 pixels on the right.',
      'semantics-disabled': 'nothing is announced as disabled',
      'semantics-label':
          'expected tappable node to have semantic label, but none was found',
      'semantics-role': '"" offers a tap but is not a button',
      'tap-target':
          'expected tap target size of at least Size(44.0, 44.0), but found '
          'Size(300.0, 20.0)',
      'zero-size': 'A RenderFlex overflowed by 288 pixels on the right.',
    },
    kind: Kind.pressable,
    build: (probe, {required enabled}) =>
        _BadButton(enabled: enabled, onPressed: () => probe.add('pressed')),
  ),
  Entry(
    'reference.bad.slider',
    covers: const [],
    fails: const {
      'key-activate':
          'Space changes it; a value control takes no Space or Enter',
      'focus-disabled': 'Tab reaches 1 parts while disabled',
      'focus-indicator': 'keyboard focus draws nothing',
      'key-arrows': 'Arrow Right does not step it forward',
      'key-arrows-rtl': 'Arrow Left does not step it forward',
      'key-home-end': 'Home does not reach the start',
      'mouse-cursor':
          'it declares no cursor; the cursor over it is '
          'SystemMouseCursor(basic)',
      'mouse-hover': 'hover draws nothing',
      'mouse-wheel': 'the wheel steps it, but it does not declare that',
      'semantics-actions': 'nothing offers increase',
      'semantics-disabled': 'nothing is announced as disabled',
      'semantics-label':
          'expected tappable node to have semantic label, but none was found',
      'semantics-role': 'no node has a value with increase and decrease',
      'tap-target':
          'expected tap target size of at least Size(44.0, 44.0), but found '
          'Size(300.0, 20.0)',
    },
    kind: Kind.value,
    build: (probe, {required enabled}) => Held<double>(
      probe: probe,
      initial: 0.5,
      builder: (context, value, set) =>
          _BadSlider(value: value, onChanged: enabled ? set : null),
    ),
  ),
  Entry(
    'reference.bad.contextMenu',
    covers: const [],
    fails: const {
      'focus-indicator': 'Tab reaches no part of it',
      'key-context-menu': 'Tab reaches no part of it',
      'mouse-cursor':
          'it declares no cursor; the cursor over it is '
          'SystemMouseCursor(basic)',
      'mouse-hover': 'hover draws nothing',
      'mouse-secondary-click':
          'a secondary click does not open its context menu',
      'semantics-disabled': 'nothing is announced as disabled',
      'tab-stops': 'Tab reaches no part of it',
    },
    kind: Kind.opener,
    openGesture: OpenGesture.longPress,
    contextMenu: true,
    marker: find.text('First item'),
    inside: find.text('First item'),
    build: (probe, {required enabled}) => Builder(
      builder: (context) => GestureDetector(
        onLongPress: enabled
            ? () => _dialog(context, probe, 'Menu', 'First item')
            : null,
        child: SizedBox(
          width: 120,
          height: 80,
          child: Center(
            child: Text(
              'Photo',
              style: TextStyle(fontSize: 17, color: _ink(context)),
            ),
          ),
        ),
      ),
    ),
  ),
  Entry(
    'reference.bad.overlay',
    covers: const [],
    fails: const {
      'contrast-dark':
          '"Overlay content": expected contrast ratio of at least 4.5 but '
          'found 1.32 for a font size of 17.0',
      'barrier-hides-behind':
          'assistive technology still reaches what is behind it',
      'barrier-label': 'no barrier is offered to assistive technology',
      'contrast-light':
          '"Overlay content": expected contrast ratio of at least 4.5 but '
          'found 1.36 for a font size of 17.0',
      'key-escape': 'Escape leaves it open',
      'key-remap-dismiss': 'a key the app maps to DismissIntent leaves it open',
      'no-leaks': 'leaks FocusNode',
      'overlay-focus-in': 'opening leaves focus outside',
      'overlay-focus-return': 'it could not be closed',
      'overlay-inert-closing':
          'Escape does not close it, so closing is not checked',
      'semantics-role': 'the overlay is not announced as a named route',
    },
    kind: Kind.overlay,
    marker: find.text(overlayText),
    inside: find.text('Inside'),
    build: (probe, {required enabled}) => Opener(
      show: (context) => Overlay.of(context).insert(
        OverlayEntry(
          builder: (context) => Positioned(
            key: ObjectKey(FocusNode()),
            left: 100,
            top: 300,
            child: Column(
              children: [
                Text(
                  overlayText,
                  style: TextStyle(fontSize: 17, color: _faint(context)),
                ),
                ProbeButton(
                  label: 'Inside',
                  onPressed: () => probe.add('inside'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
];

Future<void> _dialog(
  BuildContext context,
  Probe probe,
  String title,
  String inside,
) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Dismiss',
  pageBuilder: (context, animation, secondary) => AnimatedBuilder(
    animation: animation,
    builder: (context, child) => ExcludeSemantics(
      excluding: animation.status == AnimationStatus.reverse,
      child: child,
    ),
    child: Center(
      child: ColoredBox(
        color: MediaQuery.platformBrightnessOf(context) == Brightness.light
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF000000),
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          label: 'Dialog',
          explicitChildNodes: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 17, color: _ink(context)),
              ),
              ProbeButton(label: inside, onPressed: () => probe.add('inside')),
            ],
          ),
        ),
      ),
    ),
  ),
);

class _OpenMenuIntent extends Intent {
  const _OpenMenuIntent();
}

class _GoodContextMenu extends StatefulWidget {
  const _GoodContextMenu({required this.enabled, required this.open});

  final bool enabled;
  final void Function(BuildContext context) open;

  @override
  State<_GoodContextMenu> createState() => _GoodContextMenuState();
}

class _GoodContextMenuState extends State<_GoodContextMenu> {
  bool _focused = false;
  bool _hovered = false;

  void _open() => widget.open(context);

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final ink = _ink(context);
    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.contextMenu): _OpenMenuIntent(),
        SingleActivator(LogicalKeyboardKey.f10, shift: true): _OpenMenuIntent(),
      },
      actions: {
        _OpenMenuIntent: CallbackAction<_OpenMenuIntent>(
          onInvoke: (_) {
            _open();
            return null;
          },
        ),
      },
      child: Semantics(
        enabled: enabled,
        label: 'Reference photo',
        onLongPress: enabled ? _open : null,
        child: GestureDetector(
          excludeFromSemantics: true,
          onLongPress: enabled ? _open : null,
          onSecondaryTap: enabled ? _open : null,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _hovered
                    ? const Color(0x22808080)
                    : const Color(0x00000000),
                border: Border.all(
                  width: 2,
                  color: _focused ? const Color(0xFF0066CC) : ink.withAlpha(0),
                ),
              ),
              child: SizedBox(
                width: 120,
                height: 80,
                child: Center(
                  child: ExcludeSemantics(
                    child: Text(
                      'Photo',
                      style: TextStyle(fontSize: 17, color: ink),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _ink(BuildContext context) =>
    MediaQuery.platformBrightnessOf(context) == Brightness.light
    ? const Color(0xFF000000)
    : const Color(0xFFFFFFFF);

Color _faint(BuildContext context) =>
    MediaQuery.platformBrightnessOf(context) == Brightness.light
    ? const Color(0xFFDDDDDD)
    : const Color(0xFF222222);

class _GoodButton extends StatefulWidget {
  const _GoodButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<_GoodButton> createState() => _GoodButtonState();
}

class _GoodButtonState extends State<_GoodButton> {
  bool _focused = false;
  bool _hovered = false;

  void _tap() {
    HapticFeedback.selectionClick();
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final ink = _ink(context);
    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        enabled: enabled,
        label: 'Reference',
        onTap: enabled ? widget.onPressed : null,
        child: GestureDetector(
          excludeFromSemantics: true,
          onTap: enabled ? _tap : null,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _hovered
                    ? const Color(0x22808080)
                    : const Color(0x00000000),
                border: Border.all(
                  width: 2,
                  color: _focused ? const Color(0xFF0066CC) : ink.withAlpha(0),
                ),
              ),
              child: SizedBox(
                width: 120,
                height: 44,
                child: Center(
                  child: ExcludeSemantics(
                    child: Text(
                      'Reference',
                      style: TextStyle(fontSize: 17, color: ink),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepIntent extends Intent {
  const _StepIntent(this.by);

  final double by;
}

class _EdgeIntent extends Intent {
  const _EdgeIntent(this.to);

  final double to;
}

class _GoodSlider extends StatefulWidget {
  const _GoodSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double>? onChanged;

  @override
  State<_GoodSlider> createState() => _GoodSliderState();
}

class _GoodSliderState extends State<_GoodSlider> {
  bool _focused = false;
  bool _hovered = false;

  void _set(double value) => widget.onChanged?.call(value.clamp(0, 1));

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    final ink = _ink(context);
    final forward = Directionality.of(context) == TextDirection.ltr ? 1 : -1;
    final value = widget.value;
    String percent(double v) => '${(v.clamp(0, 1) * 100).round()}%';
    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): _StepIntent(
          0.1 * forward,
        ),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _StepIntent(
          -0.1 * forward,
        ),
        const SingleActivator(LogicalKeyboardKey.arrowUp): const _StepIntent(
          0.1,
        ),
        const SingleActivator(LogicalKeyboardKey.arrowDown): const _StepIntent(
          -0.1,
        ),
        const SingleActivator(LogicalKeyboardKey.home): const _EdgeIntent(0),
        const SingleActivator(LogicalKeyboardKey.end): const _EdgeIntent(1),
      },
      actions: {
        _StepIntent: CallbackAction<_StepIntent>(
          onInvoke: (intent) {
            _set(value + intent.by);
            return null;
          },
        ),
        _EdgeIntent: CallbackAction<_EdgeIntent>(
          onInvoke: (intent) {
            _set(intent.to);
            return null;
          },
        ),
      },
      child: Semantics(
        slider: true,
        enabled: enabled,
        label: 'Reference level',
        value: percent(value),
        increasedValue: percent(value + 0.1),
        decreasedValue: percent(value - 0.1),
        onIncrease: enabled ? () => _set(value + 0.1) : null,
        onDecrease: enabled ? () => _set(value - 0.1) : null,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            excludeFromSemantics: true,
            onTapUp: enabled
                ? (details) {
                    final x = details.localPosition.dx / 300;
                    _set(forward == 1 ? x : 1 - x);
                  }
                : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _hovered
                    ? const Color(0x22808080)
                    : const Color(0x00000000),
                border: Border.all(
                  width: 2,
                  color: _focused ? const Color(0xFF0066CC) : ink.withAlpha(0),
                ),
              ),
              child: SizedBox(
                width: 300,
                height: 44,
                child: Align(
                  alignment: AlignmentDirectional(value * 2 - 1, 0),
                  child: SizedBox.square(
                    dimension: 24,
                    child: ColoredBox(color: ink),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BadButton extends StatelessWidget {
  const _BadButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  void _tap() {
    HapticFeedback.heavyImpact();
    onPressed();
  }

  @override
  Widget build(BuildContext context) => Focus(
    child: Semantics(
      onTap: _tap,
      child: GestureDetector(
        excludeFromSemantics: true,
        onTap: _tap,
        child: SizedBox(
          width: 300,
          height: 20,
          child: Row(
            children: [
              ExcludeSemantics(
                child: Text(
                  'Bad control label',
                  style: TextStyle(fontSize: 17, color: _faint(context)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BadSlider extends StatelessWidget {
  const _BadSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          onChanged?.call(1);
          return null;
        },
      ),
    },
    child: Focus(
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            onChanged?.call((value + 0.1).clamp(0, 1));
          }
        },
        child: Semantics(
          value: '$value',
          onTap: () => onChanged?.call(1),
          child: GestureDetector(
            excludeFromSemantics: true,
            onTap: () => onChanged?.call(1),
            child: SizedBox(
              width: 300,
              height: 20,
              child: Align(
                alignment: AlignmentDirectional(value * 2 - 1, 0),
                child: SizedBox.square(
                  dimension: 20,
                  child: ColoredBox(color: _faint(context)),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _MoveIntent extends Intent {
  const _MoveIntent(this.direction);

  final TraversalDirection direction;
}

class _EndIntent extends Intent {
  const _EndIntent({required this.last});

  final bool last;
}

/// Numbers 1 to 27 in pages of three rows of three, one picked. The good
/// form follows Flutter's CalendarDatePicker; the bad one moves the pick
/// with the arrows as a radio group does, keeps its left-to-right order,
/// stops at its page's edge, has no Home and End, announces no buttons and
/// takes no Space or Enter.
class _Grid extends StatefulWidget {
  const _Grid({required this.value, required this.onChanged, this.bad = false});

  final int value;
  final ValueChanged<int>? onChanged;
  final bool bad;

  @override
  State<_Grid> createState() => _GridState();
}

class _GridState extends State<_Grid> {
  static const int _count = 27;
  static const double _pitch = 48;

  late int _focused = widget.value;
  bool _hasFocus = false;
  bool _highlight = false;
  bool _hovered = false;

  int get _page => (_focused - 1) ~/ 9;

  void _pick(int n) => widget.onChanged?.call(n);

  void _tap(int n) {
    HapticFeedback.selectionClick();
    _pick(n);
  }

  void _move(TraversalDirection direction) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final mirrored = rtl && !widget.bad;
    final step = switch (direction) {
      TraversalDirection.left => mirrored ? 1 : -1,
      TraversalDirection.right => mirrored ? -1 : 1,
      TraversalDirection.up => -3,
      TraversalDirection.down => 3,
    };
    final next = _focused + step;
    if (next < 1 || next > _count) return;
    if (widget.bad && (next - 1) ~/ 9 != _page) return;
    setState(() => _focused = next);
    if (widget.bad) _pick(next);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    final rtl = Directionality.of(context) == TextDirection.rtl && !widget.bad;
    final ink = _ink(context);
    final first = _page * 9 + 1;
    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowFocusHighlight: (value) => setState(() => _highlight = value),
      onFocusChange: (value) => setState(() {
        _hasFocus = value;
        if (value) _focused = widget.value;
      }),
      shortcuts: {
        for (final (key, direction) in const [
          (LogicalKeyboardKey.arrowLeft, TraversalDirection.left),
          (LogicalKeyboardKey.arrowRight, TraversalDirection.right),
          (LogicalKeyboardKey.arrowUp, TraversalDirection.up),
          (LogicalKeyboardKey.arrowDown, TraversalDirection.down),
        ])
          SingleActivator(key): _MoveIntent(direction),
        if (!widget.bad) ...{
          const SingleActivator(LogicalKeyboardKey.home): const _EndIntent(
            last: false,
          ),
          const SingleActivator(LogicalKeyboardKey.end): const _EndIntent(
            last: true,
          ),
        },
      },
      actions: {
        _MoveIntent: CallbackAction<_MoveIntent>(
          onInvoke: (intent) {
            _move(intent.direction);
            return null;
          },
        ),
        _EndIntent: CallbackAction<_EndIntent>(
          onInvoke: (intent) {
            setState(() => _focused = intent.last ? first + 8 : first);
            return null;
          },
        ),
        if (!widget.bad)
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _pick(_focused);
              return null;
            },
          ),
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: ColoredBox(
          color: _hovered ? const Color(0x22808080) : const Color(0x00000000),
          child: SizedBox(
            width: 3 * _pitch,
            height: 3 * _pitch,
            child: Stack(
              children: [
                for (var i = 0; i < 9; i++)
                  Positioned(
                    left: (rtl ? 2 - i % 3 : i % 3) * _pitch,
                    top: i ~/ 3 * _pitch,
                    width: 44,
                    height: 44,
                    child: _cell(first + i, enabled: enabled, ink: ink),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(int n, {required bool enabled, required Color ink}) {
    final focused = _hasFocus && n == _focused;
    return Semantics(
      container: true,
      button: !widget.bad,
      selected: n == widget.value,
      enabled: enabled,
      focused: focused,
      label: 'Number $n',
      onTap: enabled ? () => _pick(n) : null,
      child: GestureDetector(
        excludeFromSemantics: true,
        onTap: enabled ? () => _tap(n) : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              width: 2,
              color: focused && _highlight
                  ? const Color(0xFF0066CC)
                  : n == widget.value
                  ? ink
                  : ink.withAlpha(0),
            ),
          ),
          child: Center(
            child: ExcludeSemantics(
              child: Text('$n', style: TextStyle(fontSize: 17, color: ink)),
            ),
          ),
        ),
      ),
    );
  }
}
