import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_entries.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The entries of an open menu and everything that is not in them: the
/// answers of deferred groups, the measured heights of free-form rows;
/// lays them out and runs their actions.
///
/// The shared menu host keeps one content model, so entries behave the
/// same in a menu button and a context menu.
@internal
class MenuContent {
  /// Creates the content; [onChanged] runs when it changes on its own (a
  /// deferred group answered, a free-form row measured), with whether the
  /// change should animate the menu's size.
  MenuContent({required this.onChanged});

  /// Called when the content changed outside a rebuild of the entries.
  final void Function({required bool animate}) onChanged;

  /// The entries, top to bottom.
  List<GlassMenuEntry> entries = const [];

  /// The order of the entries relative to the button.
  GlassMenuOrder order = GlassMenuOrder.automatic;

  /// Whether the menu is laid out right to left.
  bool rtl = false;

  /// The title of a loading row whose group gives none.
  String loadingLabel = '';

  /// The style row titles are measured in when they may wrap.
  TextStyle titleStyle = const TextStyle(fontSize: 17);

  /// The text scale row titles are measured at, the scale the rows draw at.
  GlassTextScale? textScale;

  /// The layout of the inside of the menu: what its lists are laid out
  /// with, its rows drawn with and its motion sized by.
  MenuMetrics metrics = MenuMetrics.standard;

  final Map<Object, List<GlassMenuEntry>> _cached = {};
  final Map<Object, List<GlassMenuEntry>> _session = {};
  final Set<Object> _loading = {};
  final Map<Object, double> _heights = {};
  int _sessionId = 0;
  bool _disposed = false;

  /// Starts a new opening: uncached deferred groups load again.
  void beginSession() {
    _sessionId++;
    _session.clear();
  }

  /// Stops reporting changes.
  void dispose() => _disposed = true;

  /// The root list, reversed for a menu that opens upward unless the
  /// order is fixed.
  MenuLayout root({required bool reversed}) => MenuLayout.build(
    menuSpecs(entries, loadingLabel: loadingLabel, resolve: _resolve),
    metrics: metrics,
    reversed: reversed && order != GlassMenuOrder.fixed,
    rtl: rtl,
    widgetHeight: _heightOf,
    titleLines: _lines,
  );

  /// The card of the submenu behind [target], or null.
  MenuLayout? submenu(MenuTarget target) {
    final entry = target.entry;
    if (entry is! GlassSubmenu) return null;
    return MenuLayout.build(
      menuSpecs(entry.children, loadingLabel: loadingLabel, resolve: _resolve),
      metrics: metrics,
      rtl: rtl,
      header: menuRowSpec(entry),
      singleSelection: entry.singleSelection,
      size: menuSpecSize(entry.elementSize),
      widgetHeight: _heightOf,
      titleLines: _lines,
    );
  }

  /// Runs the action behind [target].
  void activate(MenuTarget target) {
    final entry = target.entry;
    if (entry is GlassMenuItem) entry.onPressed?.call();
  }

  /// Tells the items behind [from] and [to] that the highlight moved.
  void highlight(MenuTarget? from, MenuTarget? to) {
    final left = from?.entry;
    final entered = to?.entry;
    if (identical(left, entered)) return;
    if (left is GlassMenuItem) left.onHighlightChanged?.call(false);
    if (entered is GlassMenuItem) entered.onHighlightChanged?.call(true);
  }

  /// Records the laid out height of the free-form row [key].
  void reportHeight(Object key, double height) {
    final known = _heights[key];
    if (known != null && (known - height).abs() < 0.5) return;
    _heights[key] = height;
    if (!_disposed) onChanged(animate: known != null);
  }

  double? _heightOf(Object key) => _heights[key];

  int _lines(String title, double width, int maxLines) {
    final lines = textScale!
        .measure(
          title,
          titleStyle,
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          maxLines: maxLines,
          maxWidth: width,
        )
        .lines;
    return lines < 1 ? 1 : lines;
  }

  List<GlassMenuEntry>? _resolve(GlassMenuDeferred deferred) {
    final key = deferred.cacheKey;
    final answer = deferred.cache ? _cached[key] : _session[key];
    if (answer != null) return answer;
    final session = _sessionId;
    final loading = deferred.cache ? key : (key, session);
    if (_loading.contains(loading)) return null;
    _loading.add(loading);
    void store(List<GlassMenuEntry> entries) {
      _loading.remove(loading);
      if (deferred.cache) {
        _cached[key] = entries;
      } else if (session == _sessionId) {
        _session[key] = entries;
      } else {
        return;
      }
      if (!_disposed) onChanged(animate: true);
    }

    Future<List<GlassMenuEntry>>.sync(deferred.load).then(
      store,
      onError: (Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'apple_liquid_glass',
            context: ErrorDescription('while loading a deferred menu group'),
          ),
        );
        store(const []);
      },
    );
    return null;
  }
}

/// The specs the menu's layout reads of [entries]: hidden entries left
/// out, a deferred group spliced in as [resolve] answers it, or a loading
/// row while it answers null.
@internal
List<MenuSpec> menuSpecs(
  List<GlassMenuEntry> entries, {
  required String loadingLabel,
  List<GlassMenuEntry>? Function(GlassMenuDeferred deferred)? resolve,
}) => [
  for (final entry in entries)
    ...switch (entry) {
      GlassMenuItem(:final hidden) ||
      GlassSubmenu(:final hidden) when hidden => const <MenuSpec>[],
      GlassMenuItem() || GlassSubmenu() => [menuRowSpec(entry)],
      GlassMenuWidget(:final height, :final id) => [
        MenuWidgetSpec(height: height, key: id, entry: entry),
      ],
      GlassMenuDivider() => [MenuDividerSpec(entry: entry)],
      GlassMenuDeferred(:final loadingTitle) => switch (resolve?.call(entry)) {
        final answer? => menuSpecs(
          answer,
          loadingLabel: loadingLabel,
          resolve: resolve,
        ),
        null => [MenuLoadingSpec(loadingTitle ?? loadingLabel, entry: entry)],
      },
      GlassMenuSection() => [
        MenuSectionSpec(
          children: menuSpecs(
            entry.children,
            loadingLabel: loadingLabel,
            resolve: resolve,
          ),
          title: entry.title,
          singleSelection: entry.singleSelection,
          size: entry.palette
              ? MenuSpecSize.palette
              : menuSpecSize(entry.elementSize),
          maxTitleLines: entry.maxTitleLines,
          entry: entry,
        ),
      ],
    },
];

/// The spec of an item or a submenu.
@internal
MenuRowSpec menuRowSpec(GlassMenuEntry entry) => switch (entry) {
  GlassSubmenu() => MenuRowSpec(
    title: entry.title,
    subtitle: entry.subtitle,
    hasIcon: entry.icon != null,
    enabled: entry.enabled,
    submenu: true,
    entry: entry,
  ),
  GlassMenuItem() => MenuRowSpec(
    title: entry.title,
    subtitle: entry.subtitle,
    hasIcon:
        entry.icon != null &&
        entry.iconVisibility != GlassMenuIconVisibility.hidden,
    enabled: entry.enabled,
    keepsOpen: entry.keepsMenuOpen,
    marked: entry.state != GlassMenuItemState.off,
    entry: entry,
  ),
  _ => MenuRowSpec(title: '', enabled: false, entry: entry),
};

/// How the layout places entries of [size].
@internal
MenuSpecSize menuSpecSize(GlassMenuElementSize size) => switch (size) {
  GlassMenuElementSize.small => MenuSpecSize.small,
  GlassMenuElementSize.medium => MenuSpecSize.medium,
  GlassMenuElementSize.large ||
  GlassMenuElementSize.automatic => MenuSpecSize.rows,
};
