import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/widgets/controls/button.dart';
import 'package:apple_liquid_glass/src/widgets/controls/search_glyphs.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// What one bar's search does that the others' do not: how its measured
/// motion answers the search's events. A [SearchHost] calls it, and the bar
/// lays the host's parts out from that motion.
@internal
abstract mixin class SearchLaw {
  /// Whether the field rises with the keyboard: the host then hears the
  /// keyboard's inset, and holds it from the search's end until [returned].
  bool get followsKeyboard => true;

  /// Whether the field's losing the focus ends the search, as in a tab
  /// bar. Elsewhere only the close button and Escape end it, and a tap
  /// elsewhere leaves the search active, as in UIKit.
  bool get blurEnds => false;

  /// Whether the motion has come back to rest after an end, telling its
  /// listeners when that changes; null when nothing waits for it.
  ValueListenable<bool>? get returned => null;

  /// The field took the focus at [t], with the keyboard [keyboard] high
  /// (0 before it starts to rise).
  void begin(double t, {required double keyboard});

  /// The search ended at [t].
  void end(double t);

  /// The keyboard stands above the bottom at [t].
  void keyboardRose(double t) {}
}

/// What a [SearchHost] hands its bar to lay out.
@internal
final class SearchParts {
  const SearchParts._({
    required this.field,
    required this.close,
    required this.keyboard,
    required this.held,
  });

  /// The field, heard for its focus and ended by the host.
  final Widget field;

  /// The close button, which ends the search; it takes touches and the
  /// focus only while the search is active, from the field's focus to its
  /// end. The bar moves and fades it.
  final Widget close;

  /// How high the keyboard stands, as the field's layout follows it: held
  /// from the search's end until the motion has returned, so nothing
  /// follows the keyboard down.
  final ValueListenable<double> keyboard;

  /// Whether [keyboard] is held for a return.
  final ValueListenable<bool> held;
}

/// The one host of a bar's search: the navigation bar's stacked search,
/// the toolbar's bottom search and the tab bar's search tab.
///
/// It hears the field's focus and starts the search on it, ends the search
/// from its close button and from Escape (the field clears its text and
/// lets the focus go), and follows the keyboard's inset without building:
/// [builder] runs when the search starts or ends, never on a frame of the
/// motion or of the keyboard. What differs between the bars is [law] and
/// the layout [builder] makes of the [SearchParts]: where the field sits
/// at rest, what it grows out of and its measured motion.
@internal
class SearchHost extends StatefulWidget {
  /// Hosts [field]'s search under [law].
  const SearchHost({
    required this.law,
    required this.field,
    required this.builder,
    this.closeLabel,
    this.closeColor,
    this.fieldHeight,
    this.fieldGlass,
    super.key,
  });

  /// The height of the field, or null for its own.
  final double? fieldHeight;

  /// How present the field's glass is when the bar draws a fill under it.
  final MotionValue<double>? fieldGlass;

  /// What the bar's motion does on the search's events.
  final SearchLaw law;

  /// The search field.
  final Widget field;

  /// Lays the parts out.
  final Widget Function(BuildContext context, SearchParts parts) builder;

  /// What assistive technology reads for the close button; the localized
  /// "Close" when null.
  final String? closeLabel;

  /// The color of the close button's cross; the label color when null.
  final Color? closeColor;

  @override
  State<SearchHost> createState() => _SearchHostState();
}

class _SearchHostState extends State<SearchHost> {
  late final MotionClock _clock;
  final _ends = _SearchEndSignal();
  final _keyboard = ValueNotifier<double>(0);
  final _held = ValueNotifier<bool>(false);
  late final _endAction = _EndSearch(this);
  ValueListenable<bool>? _returned;
  double _inset = 0;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _clock = MotionClockScope.of(context);
    _follow();
  }

  @override
  void didUpdateWidget(SearchHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.law.returned, widget.law.returned)) _follow();
  }

  @override
  void dispose() {
    _returned?.removeListener(_release);
    _ends.dispose();
    _keyboard.dispose();
    _held.dispose();
    super.dispose();
  }

  void _follow() {
    _returned?.removeListener(_release);
    _returned = widget.law.returned;
    _returned?.addListener(_release);
  }

  void _release() {
    if (_active || !_held.value || !(_returned?.value ?? true)) return;
    _held.value = false;
    _keyboard.value = _inset;
  }

  void _insetChanged(double inset) {
    _inset = inset;
    if (!_held.value) _keyboard.value = inset;
    if (inset > 0) widget.law.keyboardRose(_clock.now);
  }

  void _focusChanged(bool focused) {
    if (focused && !_active) {
      setState(() => _active = true);
      _endAction.changed();
      _held.value = false;
      _keyboard.value = _inset;
      widget.law.begin(_clock.now, keyboard: _inset);
    } else if (!focused && _active && widget.law.blurEnds) {
      _finish();
    }
  }

  void _finish() {
    setState(() => _active = false);
    _endAction.changed();
    if (widget.law.followsKeyboard) _held.value = true;
    widget.law.end(_clock.now);
    _release();
  }

  void _end() {
    if (_active && !widget.law.blurEnds) _finish();
    _ends.end();
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    final glyph = GlassDynamicColor.resolve(
      widget.closeColor ?? GlassTheme.labelColorOf(context),
      context,
    );
    final parts = SearchParts._(
      field: GlassSearchFieldHost(
        ends: _ends,
        height: widget.fieldHeight,
        glass: widget.fieldGlass,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: _focusChanged,
          child: widget.field,
        ),
      ),
      close: IgnorePointer(
        ignoring: !active,
        child: ExcludeFocus(
          excluding: !active,
          child: GlassButton(
            onPressed: _end,
            semanticLabel:
                widget.closeLabel ??
                GlassLocalizations.of(context).closeButtonLabel,
            child: GlassCloseIcon(color: glyph),
          ),
        ),
      ),
      keyboard: _keyboard,
      held: _held,
    );
    final laidOut = Actions(
      actions: {DismissIntent: _endAction},
      child: widget.builder(context, parts),
    );
    if (!widget.law.followsKeyboard) return laidOut;
    return _KeyboardInset(onChanged: _insetChanged, child: laidOut);
  }
}

/// Escape ends an active search; otherwise it goes on to the route.
final class _EndSearch extends Action<DismissIntent> {
  _EndSearch(this._host);

  final _SearchHostState _host;

  void changed() => notifyActionListeners();

  @override
  bool isEnabled(DismissIntent intent) => _host._active;

  @override
  void invoke(DismissIntent intent) => _host._end();
}

/// Hears the keyboard's inset for its host without building the host.
class _KeyboardInset extends StatefulWidget {
  const _KeyboardInset({required this.onChanged, required this.child});

  final ValueChanged<double> onChanged;
  final Widget child;

  @override
  State<_KeyboardInset> createState() => _KeyboardInsetState();
}

class _KeyboardInsetState extends State<_KeyboardInset> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.onChanged(MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// [Rect.lerp] of [a] and [b] at [t] that keeps a width or height both
/// share exactly: the origin moves as [Rect.lerp] moves it, but a side
/// that does not change keeps its length to the bit, so what the box holds
/// is not laid out again for rounding.
@internal
Rect lerpRect(Rect a, Rect b, double t) {
  final at = Rect.lerp(a, b, t)!;
  return Rect.fromLTWH(
    at.left,
    at.top,
    a.width == b.width ? a.width : at.width,
    a.height == b.height ? a.height : at.height,
  );
}

/// The signal a search's close button fires through [end] when the search
/// ends.
class _SearchEndSignal extends ChangeNotifier {
  void end() => notifyListeners();
}
