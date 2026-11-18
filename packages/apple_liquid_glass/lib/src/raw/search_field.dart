import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';

/// Builds a search field from [details]; it runs when the field builds,
/// such as when its states change, never on a frame of its motion.
typedef GlassSearchFieldBuilder = Widget Function(
  BuildContext context,
  GlassSearchFieldDetails details,
);

/// What a [GlassSearchFieldBuilder] builds a search field from.
final class GlassSearchFieldDetails {
  const GlassSearchFieldDetails._(
    this._text, {
    required this.frame,
    required this.states,
    required this.controller,
    required this.clear,
    this.statesListenable,
  });

  /// The frame of the field's glass as a touch lifts it; under a
  /// navigation bar's large title its opacity follows the glass's presence,
  /// and the field's text and glyphs stay.
  final MotionSelection<GlassFrame> frame;

  /// The states the field is in: focused, pressed, hovered, disabled.
  final Set<WidgetState> states;

  /// The field's states as they change: a look hands it to the
  /// `GlassSurface` of its glass, whose renderer then draws the hover
  /// response (and a focus ring, unless the look turns it off).
  final ValueListenable<Set<WidgetState>>? statesListenable;

  /// The field's text; a look listens to it to show a placeholder or a
  /// clear button.
  final TextEditingController controller;

  /// Clears the text and reports it, or null while the field is disabled.
  final VoidCallback? clear;

  final Widget Function(
    TextStyle style,
    Color cursor,
    Color backgroundCursor,
  )
  _text;

  /// The editable text with its gestures and semantics, drawn in [style]
  /// with a [cursorColor] cursor; [backgroundCursorColor] colors the
  /// cursor's resting ghost while a force press moves it
  /// (`EditableText.backgroundCursorColor`).
  Widget text({
    required TextStyle style,
    required Color cursorColor,
    required Color backgroundCursorColor,
  }) => _text(style, cursorColor, backgroundCursorColor);
}

/// A search field with the measured lift of iOS 27's `UISearchTextField`
/// and no look of its own: [builder] decides how it looks and places the
/// editable text it gets from [GlassSearchFieldDetails.text].
///
/// UIKit: `UISearchTextField`. SwiftUI: the field of `searchable`. Flutter:
/// `CupertinoSearchTextField`.
///
/// It is 48 points tall. A touch lifts it 0.05 s later on the glass
/// button's lift, without stretching (fitted, search passport), and a tap
/// focuses it. Text follows the text scale up to
/// [maxTextScale]. The keyboard offers no suggestions, as
/// UIKit's search field does not. On iOS a long press shows the system
/// edit menu; other platforms show none.
class RawGlassSearchField extends StatefulWidget {
  /// Creates a search field.
  const RawGlassSearchField({
    required this.builder,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.autofocus = false,
    this.semanticLabel,
    this.statesController,
    super.key,
  });

  /// Builds the field's look.
  final GlassSearchFieldBuilder builder;

  /// The text, or null for the field's own.
  final TextEditingController? controller;

  /// The field's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Called with the text as the user edits it or clears it.
  final ValueChanged<String>? onChanged;

  /// Called with the text when the user submits it from the keyboard.
  final ValueChanged<String>? onSubmitted;

  /// Whether the field takes input.
  final bool enabled;

  /// Whether the field takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the field; the localized "Search" when
  /// null.
  final String? semanticLabel;

  /// Where the field publishes its states, or null for its own: focused
  /// while its text has the focus, pressed, hovered and disabled. The field
  /// is its only writer: what else writes to it is written over.
  final WidgetStatesController? statesController;

  /// The height of the field when its host sets none, in points (search
  /// passport).
  static const double height = SearchBarGeometry.fieldHeight;

  /// The largest text scale the text follows, not measured.
  static const double maxTextScale = 1.5;

  @override
  State<RawGlassSearchField> createState() => _RawGlassSearchFieldState();
}

/// What a bar that hosts search fields tells the [RawGlassSearchField]s
/// below it.
///
/// A navigation bar that stacks a field under its large title sets the
/// field's [height] and how present its glass is ([glass]), so the field
/// draws over the plain fill the bar puts under it; a toolbar that hosts
/// a field and its close button sets [ends], which the fields below hear
/// when the search ends outside them. A field reads the values it needs
/// and ignores the rest; without a host it is [RawGlassSearchField.height]
/// tall and draws its own glass.
class GlassSearchFieldHost extends InheritedWidget {
  /// Tells the search fields below the values of the bar that hosts them.
  const GlassSearchFieldHost({
    required super.child,
    this.height,
    this.glass,
    this.ends,
    super.key,
  });

  /// The height of the fields, or null for [RawGlassSearchField.height].
  final double? height;

  /// How present the fields' glass is, 0 to 1, or null when it is not the
  /// host's to dim: a field that finds a value here draws over the host's
  /// plain fill instead of a glass of its own.
  final MotionValue<double>? glass;

  /// Notifies when a search ends outside the fields, such as at the tap on
  /// the host's close button, or null.
  final Listenable? ends;

  /// The host around [context], or null.
  static GlassSearchFieldHost? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassSearchFieldHost>();

  @override
  bool updateShouldNotify(GlassSearchFieldHost oldWidget) =>
      height != oldWidget.height ||
      glass != oldWidget.glass ||
      ends != oldWidget.ends;
}

class _RawGlassSearchFieldState extends State<RawGlassSearchField>
    with ControlStates<RawGlassSearchField>
    implements TextSelectionGestureDetectorBuilderDelegate {
  final GlassPress _press = GlassPress.search(
    size: const Size(346, RawGlassSearchField.height),
  );
  late final _lift = _press.select(
    (p) => p.isAtRest
        ? const GlassFrame()
        : GlassFrame(scaleX: p.scaleX, scaleY: p.scaleY),
  );
  late final _LiftInput _input = _LiftInput(this);
  late final List<Interaction> _interactions = [_input];
  final _regionFocus = FocusNode(skipTraversal: true);
  late final TextSelectionGestureDetectorBuilder _gestures =
      TextSelectionGestureDetectorBuilder(delegate: this);
  final _editable = GlobalKey<EditableTextState>();
  TextEditingController? _ownController;
  FocusNode? _ownFocus;

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());

  FocusNode get _focus =>
      widget.focusNode ??
      (_ownFocus ??= FocusNode(debugLabel: 'GlassSearchField'));

  @override
  GlobalKey<EditableTextState> get editableTextKey => _editable;

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => widget.enabled && _focus.hasFocus;

  @override
  WidgetStatesController? get givenStates => widget.statesController;

  @override
  bool get enabled => widget.enabled;

  @override
  bool get focusShows => _focus.hasFocus;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(RawGlassSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final focus = oldWidget.focusNode ?? _ownFocus;
    if (!identical(focus, _focus)) {
      focus?.removeListener(_focusChanged);
      _focus.addListener(_focusChanged);
    }
    if (!widget.enabled && _focus.hasFocus) _focus.unfocus();
  }

  @override
  void dispose() {
    _ends?.removeListener(_ended);
    _focus.removeListener(_focusChanged);
    _regionFocus.dispose();
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  Listenable? _ends;
  MotionValue<double>? _fadedGlass;
  late MotionSelection<GlassFrame> _faded;

  MotionSelection<GlassFrame> _fadedBy(MotionValue<double> glass) {
    if (identical(glass, _fadedGlass)) return _faded;
    _fadedGlass = glass;
    return _faded = MotionSelection(() {
      final frame = _lift.value;
      return frame.copyWith(
        opacity: frame.opacity * glass.value.clamp(0.0, 1.0),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ends = GlassSearchFieldHost.maybeOf(context)?.ends;
    if (identical(ends, _ends)) return;
    _ends?.removeListener(_ended);
    _ends = ends;
    ends?.addListener(_ended);
  }

  void _ended() {
    if (_controller.text.isNotEmpty) _clear();
    _focus.unfocus();
  }

  void _focusChanged() {
    restate();
    if (_focus.hasFocus) _press.pointerCancel(_press.clock.now);
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
  }

  Widget _text(TextStyle style, Color cursor, Color backgroundCursor) {
    final editable = EditableText(
      key: _editable,
      controller: _controller,
      focusNode: _focus,
      readOnly: !widget.enabled,
      autofocus: widget.autofocus,
      style: style,
      textScaler: GlassTextScale.of(
        context,
        max: RawGlassSearchField.maxTextScale,
      ).scaler,
      cursorColor: cursor,
      backgroundCursorColor: backgroundCursor,
      selectionColor: cursor.withValues(alpha: 0.25),
      textInputAction: TextInputAction.search,
      keyboardAppearance: GlassTraits.of(context).brightness,
      textCapitalization: TextCapitalization.sentences,
      // UIKit's search field offers no suggestions. iOS's engine ties
      // spell checking, and with it the prediction bar, to this flag.
      autocorrect: false,
      enableSuggestions: false,
      rendererIgnoresPointer: true,
      contextMenuBuilder: SystemContextMenu.isSupported(context)
          ? (context, state) =>
                SystemContextMenu.editableText(editableTextState: state)
          : null,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
    );
    return Semantics(
      label: widget.semanticLabel ?? GlassLocalizations.of(context).searchLabel,
      child: widget.enabled
          ? _gestures.buildGestureDetector(
              behavior: HitTestBehavior.translucent,
              child: editable,
            )
          : IgnorePointer(child: ExcludeFocus(child: editable)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final host = GlassSearchFieldHost.maybeOf(context);
    final stacked = host?.glass;
    final field = InputRegion(
      interactions: _interactions,
      enabled: enabled,
      focusShows: focusShows,
      statesController: widgetStates,
      focusNode: _regionFocus,
      mouseCursor: widget.enabled
          ? SystemMouseCursors.text
          : SystemMouseCursors.basic,
      child: SizedBox(
        height: host?.height ?? RawGlassSearchField.height,
        child: widget.builder(
          context,
          GlassSearchFieldDetails._(
            _text,
            frame: stacked == null ? _lift : _fadedBy(stacked),
            states: {...widgetStates.value},
            statesListenable: widgetStates,
            controller: _controller,
            clear: widget.enabled ? _clear : null,
          ),
        ),
      ),
    );
    return MotionScope(motion: _press, child: field);
  }
}

/// Follows a touch on the field to lift it, and focuses the field on a
/// tap; it never holds the touch, so the text's own gestures and a scroll
/// still take it.
final class _LiftInput extends Interaction {
  _LiftInput(this._owner) : super(role: InteractionRole.content);

  final _RawGlassSearchFieldState _owner;
  int? _pointer;
  late final _unclaimingTap = TapInteraction(
    onTap: (t) => _owner._focus.requestFocus(),
  );

  @override
  bool get pressed => _pointer != null;

  @override
  bool accepts(PointerDownInput down) =>
      super.accepts(down) && !_owner._focus.hasFocus;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput() when _pointer == null && accepts(input):
        _pointer = input.pointer;
        _unclaimingTap.handle(input);
        _owner._press.down(input);
      case PointerMoveInput() when input.pointer == _pointer:
        _unclaimingTap.handle(input);
        _owner._press.move(input);
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        _owner._press.up(input);
        _unclaimingTap.handle(input);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        _unclaimingTap.handle(input);
        _owner._press.cancel(input);
      default:
    }
    return InteractionUpdate.none;
  }
}
