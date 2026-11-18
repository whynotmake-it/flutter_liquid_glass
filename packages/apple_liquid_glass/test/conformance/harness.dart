import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The root every entry is built under. The package's root widget is
/// changing shape; this is the one place to adapt.
Widget glassRoot(Brightness brightness, Widget child) => GlassScope(
  renderer: const FlatGlassRenderer(),
  data: GlassThemeData(brightness: brightness),
  child: child,
);

/// What a registry entry is, which decides the checks that apply to it.
enum Kind {
  /// Activates on tap, Space and Enter: a button.
  pressable,

  /// Flips between two states on activation: a switch.
  toggle,

  /// Holds a value between ends, stepped by arrows and assistive increase
  /// and decrease: a slider, a stepper, a page control.
  value,

  /// Selects one of several items: a segmented control, a tab bar.
  selection,

  /// Picks one of many items laid out in rows, as Flutter's
  /// `CalendarDatePicker` picks a day: the arrows move the focus an item
  /// along the reading order and a row up or down, mirrored in
  /// right-to-left, without picking; Space and Enter pick the focused
  /// item; the items are one Tab stop, entered at the picked one.
  grid,

  /// Takes text.
  textInput,

  /// A control whose activation presents an overlay: a menu button.
  opener,

  /// An overlay presented by a function such as `showGlassAlert`.
  overlay,

  /// Adds actions to a child, as swipe actions do.
  actions,
}

/// Records what a subject did, so a check can compare two ways of doing it.
final class Probe {
  /// Callbacks the subject ran, in order.
  final List<String> events = [];

  /// The subject's current value or selected index, for value and selection
  /// entries.
  Object? value;

  /// The states a raw core last handed its builder.
  Set<WidgetState>? states;

  /// Records [event].
  void add(String event) => events.add(event);
}

/// One public interactive widget under the conformance checks.
final class Entry {
  /// An entry named [id] standing for the public names in [covers].
  const Entry(
    this.id, {
    required this.covers,
    required this.kind,
    required this.build,
    this.canDisable = true,
    this.focusStops = 1,
    this.marker,
    this.inside,
    this.dismissible = true,
    this.contextMenu = false,
    this.wheel = false,
    this.openGesture = OpenGesture.tap,
    this.part,
    this.header,
    this.mirrors = true,
    this.look = Look.own,
    this.glassRoutes = false,
    this.pages = false,
    this.exempt = const {},
    this.fails = const {},
  });

  /// The stable name used in `known_failures.txt`.
  final String id;

  /// The public API names this entry holds to the bar.
  final List<String> covers;

  /// What the entry is.
  final Kind kind;

  /// Builds the subject in its smallest sensible form.
  final Widget Function(Probe probe, {required bool enabled}) build;

  /// Whether the subject has a disabled form.
  final bool canDisable;

  /// How many Tab stops the subject should take when enabled.
  final int focusStops;

  /// Finds content that is on screen only while the overlay is presented.
  final Finder? marker;

  /// Finds a tappable part inside the overlay that adds `inside` to the
  /// probe.
  final Finder? inside;

  /// Whether a tap outside the overlay closes it, so its barrier needs a
  /// label.
  final bool dismissible;

  /// Whether a secondary click should open a context menu.
  final bool contextMenu;

  /// Whether the subject declares that the mouse wheel steps it.
  final bool wheel;

  /// The gesture that presents an opener's overlay.
  final OpenGesture openGesture;

  /// Finds the part a pointer check aims at, when that is not the middle of
  /// the subject.
  final Finder? part;

  /// The label of a node that should be announced as a header.
  final String? header;

  /// Whether the arrow keys swap in right-to-left; false where the control
  /// keeps its left-to-right layout on purpose.
  final bool mirrors;

  /// Who draws the subject: the control, or the app's builder.
  final Look look;

  /// Whether the app's home page is a glass page route too, as a glass
  /// page needs one below it to show a back button.
  final bool glassRoutes;

  /// Whether an arrow past a grid's edge turns to the neighbouring page of
  /// items and moves the focus there, as a calendar turns its month.
  final bool pages;

  /// The checks this control fails on purpose, each with the reviewed
  /// reason: a deviation that matches a measured iOS value, or a rule that
  /// does not fit the control.
  final Map<String, Exemption> exempt;

  /// For a `reference.bad.*` control: the checks it breaks on purpose,
  /// each with the reason the check must give, so every check is seen to
  /// catch what it is for.
  final Map<String, String> fails;

  /// Whether the subject presents an overlay.
  bool get presents => kind == Kind.overlay || kind == Kind.opener;

  /// Whether the subject runs a callback when activated.
  bool get activates =>
      kind == Kind.pressable ||
      kind == Kind.toggle ||
      kind == Kind.opener ||
      kind == Kind.grid;
}

/// A reviewed deviation: a check an entry fails, and why that is right.
final class Exemption {
  /// The check reports [observed]; [because] says why the control is right.
  const Exemption(this.observed, {required this.because});

  /// What the check reports, as the suite records a failure.
  final String observed;

  /// Why the deviation is right, with its source, in words a reviewer can
  /// check: a measurement on iOS, a system colour, a rule that does not
  /// apply.
  final String because;
}

/// Who draws a subject.
enum Look {
  /// The control draws its default look; checks compare what it paints.
  own,

  /// A raw core: the app's builder draws, so checks read the states the
  /// core hands the builder, and skip the look's contrast.
  builder,
}

/// How an opener presents its overlay.
enum OpenGesture {
  /// A primary tap.
  tap,

  /// A long press.
  longPress,
}

/// Finds the `Semantics` widget labelled [label].
Finder semanticsWidget(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

/// Finds the subject of the current test.
final Finder subject = find.byKey(subjectKey);

/// Finds the home page the subject sits on.
final Finder home = find.byKey(homeKey);

/// The key of the subject's root.
const Key subjectKey = ValueKey<String>('conformance subject');

/// The key of the home page.
const Key homeKey = ValueKey<String>('conformance home');

const _screenKey = ValueKey<String>('conformance screen');

/// The label of the overlay entries' opener.
const String openerLabel = 'Open';

/// The label of the content behind an overlay.
const String behindLabel = 'Behind content';

/// The text inside an overlay entry's content.
const String overlayText = 'Overlay content';

/// The phone the checks run on.
const Size phone = Size(402, 874);

/// Sets the test view to [phone].
void usePhone(WidgetTester tester) {
  tester.view.physicalSize = phone * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Builds [entry] on the conformance root.
Widget app(
  Entry entry,
  Probe probe, {
  bool enabled = true,
  Brightness brightness = Brightness.light,
  TextDirection direction = TextDirection.ltr,
  double textScale = 1,
  Map<ShortcutActivator, Intent>? shortcuts,
  Size? box,
}) {
  final background = brightness == Brightness.light
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF000000);
  final body = KeyedSubtree(
    key: subjectKey,
    child: entry.build(probe, enabled: enabled),
  );
  return RepaintBoundary(
    key: _screenKey,
    child: WidgetsApp(
      color: const Color(0xFF000000),
      shortcuts: shortcuts,
      pageRouteBuilder: entry.glassRoutes
          ? <T>(settings, builder) =>
                GlassPageRoute<T>(builder: builder, settings: settings)
          : <T>(settings, builder) => PageRouteBuilder<T>(
              settings: settings,
              pageBuilder: (context, animation, secondary) => builder(context),
            ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          platformBrightness: brightness,
        ),
        child: Directionality(
          textDirection: direction,
          child: glassRoot(brightness, child!),
        ),
      ),
      home: ColoredBox(
        key: homeKey,
        color: background,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: Semantics(
                label: behindLabel,
                container: true,
                child: const SizedBox(width: 4, height: 4),
              ),
            ),
            Positioned.fill(
              child: Center(
                child: box == null
                    ? body
                    : SizedBox.fromSize(size: box, child: body),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Pumps [frames] frames of 16 ms.
Future<void> settle(WidgetTester tester, [int frames = 60]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Pumps [entry] at phone size and lets it settle.
Future<Probe> pumpEntry(
  WidgetTester tester,
  Entry entry, {
  bool enabled = true,
  Brightness brightness = Brightness.light,
  TextDirection direction = TextDirection.ltr,
  double textScale = 1,
  Map<ShortcutActivator, Intent>? shortcuts,
}) async {
  usePhone(tester);
  final probe = Probe();
  await tester.pumpWidget(
    app(
      entry,
      probe,
      enabled: enabled,
      brightness: brightness,
      direction: direction,
      textScale: textScale,
      shortcuts: shortcuts,
    ),
  );
  await settle(tester);
  return probe;
}

/// Whether [finder] finds an ancestor of, or the element of, [context].
bool isInside(BuildContext? context, Finder finder) {
  if (context == null) return false;
  final roots = finder.evaluate().toSet();
  if (roots.isEmpty) return false;
  if (roots.contains(context)) return true;
  var found = false;
  context.visitAncestorElements((element) {
    if (roots.contains(element)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// Whether [node] belongs to the subject: its context is under the
/// subject, or outside the home page and not one of its ancestors, as the
/// bars a page scaffold hosts above the page are.
bool ownsFocus(FocusNode node) {
  final context = node.context;
  if (context == null) return false;
  if (isInside(context, subject)) return true;
  if (isInside(context, home)) return false;
  final homes = home.evaluate();
  if (homes.isEmpty) return false;
  return !isInside(homes.first, find.byElementPredicate((e) => e == context));
}

/// Presses Tab up to [limit] times and returns the distinct focus nodes of
/// the subject it reached, in order.
Future<List<FocusNode>> tabStops(WidgetTester tester, {int limit = 24}) async {
  final reached = <FocusNode>[];
  final seen = <FocusNode>{};
  for (var i = 0; i < limit; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final node = FocusManager.instance.primaryFocus;
    if (node == null) continue;
    if (!seen.add(node)) {
      if (reached.isNotEmpty && node == reached.first) break;
      continue;
    }
    if (ownsFocus(node)) reached.add(node);
  }
  return reached;
}

/// Every node of the semantics tree, root first.
List<SemanticsNode> semanticsNodes(WidgetTester tester) {
  final root =
      tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode;
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    nodes.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  if (root != null) visit(root);
  return nodes;
}

/// The rectangle of [node] in logical pixels of the screen.
Rect globalRect(WidgetTester tester, SemanticsNode node) {
  var rect = node.rect;
  SemanticsNode? current = node;
  while (current != null) {
    final transform = current.transform;
    if (transform != null) rect = MatrixUtils.transformRect(transform, rect);
    current = current.parent;
  }
  final ratio = tester.view.devicePixelRatio;
  return Rect.fromLTRB(
    rect.left / ratio,
    rect.top / ratio,
    rect.right / ratio,
    rect.bottom / ratio,
  );
}

/// Whether [node] takes a tap from assistive technology.
bool isTappable(SemanticsNode node) {
  final data = node.getSemanticsData();
  return data.hasAction(SemanticsAction.tap) &&
      !data.flagsCollection.isHidden &&
      data.label != openerLabel;
}

/// The nodes of the subject's semantics, without the harness's own nodes.
List<SemanticsNode> subjectNodes(WidgetTester tester) => [
  for (final node in semanticsNodes(tester))
    if (!node.isInvisible &&
        node.label != openerLabel &&
        node.label != behindLabel &&
        !node.isMergedIntoParent)
      node,
];

/// Opens the overlay of [entry] and lets it settle, or fails.
Future<void> present(WidgetTester tester, Entry entry, Probe probe) async {
  if (entry.kind == Kind.overlay) {
    Focus.of(tester.element(find.text(openerLabel))).requestFocus();
    await tester.pump();
    await tester.tap(find.text(openerLabel));
  } else if (entry.openGesture == OpenGesture.longPress) {
    await hold(tester, tester.getCenter((entry.part ?? subject).first));
  } else {
    await tester.tap(entry.part ?? subject, warnIfMissed: false);
  }
  await settle(tester, 90);
  if (entry.marker != null && entry.marker!.evaluate().isEmpty) {
    throw TestFailure('the overlay did not open');
  }
}

/// Holds a finger at [at] long enough for a context menu, frame by frame.
Future<void> hold(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(at);
  await settle(tester);
  await gesture.up();
}

/// Closes a presented overlay: Escape, then the entry's own way out.
Future<void> close(WidgetTester tester, Entry entry) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await settle(tester, 90);
  if (entry.marker != null && entry.marker!.evaluate().isNotEmpty) {
    await tester.tapAt(const Offset(8, 860));
    await settle(tester, 90);
  }
}

/// A raw RGBA image of the whole screen at one pixel per logical pixel.
Future<Uint8List> screenshot(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_screenKey),
  );
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData();
    image.dispose();
    return data!.buffer.asUint8List();
  });
  return bytes!;
}

/// Whether two screenshots differ.
bool differs(Uint8List a, Uint8List b) {
  if (a.length != b.length) return true;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return true;
  }
  return false;
}

/// Counts haptics and system sounds the platform is asked to play.
final class FeedbackLog {
  /// Starts counting on [tester]'s platform channel.
  FeedbackLog(this.tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate' ||
            call.method == 'SystemSound.play') {
          count++;
        }
        return null;
      },
    );
  }

  /// The tester whose channel is mocked.
  final WidgetTester tester;

  /// How many feedback calls were made.
  int count = 0;

  /// Stops counting.
  void dispose() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null);
}

/// A first line of [error] fit for a known-failures reason.
String reasonOf(Object error) {
  var text = error is TestFailure ? (error.message ?? '') : '$error';
  text = text.replaceAll(RegExp(r'#\d+'), '');
  text = text.replaceAll(RegExp(r'Rect\.fromLTRB\([^)]*\)'), 'Rect');
  final lines = text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty);
  var line = lines.isEmpty ? '${error.runtimeType}' : lines.first;
  line = line.replaceAll(RegExp(r'\s+'), ' ');
  return line.length > 110 ? '${line.substring(0, 107)}...' : line;
}

/// A reference button: Flutter's own building blocks, used as the overlay
/// opener and as content inside overlays.
class ProbeButton extends StatelessWidget {
  /// A button labelled [label] that runs [onPressed].
  const ProbeButton({required this.label, required this.onPressed, super.key});

  /// The text and semantic label.
  final String label;

  /// Runs on activation.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FocusableActionDetector(
    actions: {
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          onPressed();
          return null;
        },
      ),
    },
    mouseCursor: SystemMouseCursors.click,
    child: Semantics(
      button: true,
      label: label,
      onTap: onPressed,
      child: GestureDetector(
        excludeFromSemantics: true,
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: 120,
          height: 44,
          child: Center(
            child: ExcludeSemantics(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 17,
                  color:
                      MediaQuery.platformBrightnessOf(context) ==
                          Brightness.light
                      ? const Color(0xFF0040DD)
                      : const Color(0xFF66AAFF),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// An opener that presents an overlay through [show].
class Opener extends StatelessWidget {
  /// An opener that calls [show] with its context.
  const Opener({required this.show, super.key});

  /// Presents the overlay.
  final void Function(BuildContext context) show;

  @override
  Widget build(BuildContext context) => Align(
    alignment: const Alignment(0, -0.8),
    child: ProbeButton(label: openerLabel, onPressed: () => show(context)),
  );
}

/// Holds a value for a controlled subject and mirrors it into a probe.
class Held<T> extends StatefulWidget {
  /// Holds [initial] and builds with [builder].
  const Held({
    required this.probe,
    required this.initial,
    required this.builder,
    super.key,
  });

  /// The probe the value is mirrored into.
  final Probe probe;

  /// The first value.
  final T initial;

  /// Builds the subject from the value and a setter.
  final Widget Function(BuildContext context, T value, ValueSetter<T> set)
  builder;

  @override
  State<Held<T>> createState() => _HeldState<T>();
}

class _HeldState<T> extends State<Held<T>> {
  late T _value = widget.initial;

  @override
  void initState() {
    super.initState();
    widget.probe.value = _value;
  }

  void _set(T value) {
    widget.probe.value = value;
    widget.probe.add('value $value');
    setState(() => _value = value);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value, _set);
}
