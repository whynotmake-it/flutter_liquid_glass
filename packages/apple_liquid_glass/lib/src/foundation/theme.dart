import 'package:apple_liquid_glass/src/foundation/colors.dart';
import 'package:apple_liquid_glass/src/foundation/glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The app's overrides of the iOS semantic colors.
///
/// Flutter: `ColorScheme`, as overrides: a null field keeps the native
/// color, and an app-wide color never replaces a look a control has of its
/// own (a prominent button's label stays white).
@immutable
final class GlassColorScheme {
  /// Creates a scheme; every field defaults to the native color.
  const GlassColorScheme({
    this.surfaces = const {},
    this.label,
    this.tertiaryLabel,
  });

  /// The fill of flat surfaces per role; glass keeps its own material and
  /// takes a color only as its tint.
  final Map<GlassRole, Color> surfaces;

  /// Primary text, in place of [GlassColors.label].
  final Color? label;

  /// Tertiary text and disabled labels, in place of
  /// [GlassColors.tertiaryLabel].
  final Color? tertiaryLabel;

  /// This scheme with the non-null fields of [other] over it.
  GlassColorScheme merge(GlassColorScheme? other) {
    if (other == null) return this;
    return GlassColorScheme(
      surfaces: {...surfaces, ...other.surfaces},
      label: other.label ?? label,
      tertiaryLabel: other.tertiaryLabel ?? tertiaryLabel,
    );
  }

  /// The scheme between [a] and [b] at [t].
  static GlassColorScheme? lerp(
    GlassColorScheme? a,
    GlassColorScheme? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    return GlassColorScheme(
      surfaces: {
        for (final role in {...a.surfaces.keys, ...b.surfaces.keys})
          if (GlassDynamicColor.lerp(a.surfaces[role], b.surfaces[role], t)
              case final color?)
            role: color,
      },
      label: GlassDynamicColor.lerp(a.label, b.label, t),
      tertiaryLabel: GlassDynamicColor.lerp(
        a.tertiaryLabel,
        b.tertiaryLabel,
        t,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassColorScheme &&
      mapEquals(other.surfaces, surfaces) &&
      other.label == label &&
      other.tertiaryLabel == tertiaryLabel;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(surfaces.entries.map((e) => (e.key, e.value))),
    label,
    tertiaryLabel,
  );
}

/// The look of one component, kept in a [GlassThemeData] under its [type].
///
/// Flutter: `ThemeExtension`. Each component's style class extends it, so
/// the theme holds a style it knows nothing about, finds it by type, layers
/// a nested theme's over the enclosing one with [merge] and moves between
/// two themes with [lerp]. A widget that reads one style through
/// [GlassTheme.styleOf] rebuilds only when that style changes.
@immutable
abstract class GlassStyle<T extends Object> {
  /// Creates a style.
  const GlassStyle();

  /// The key the theme keeps this style under: [T], unless a component
  /// keeps two looks of one style class apart.
  Object get type => T;

  /// This style over [other]: what this style leaves null comes from
  /// [other].
  T merge(T? other);

  /// The style between this one and [other] at [t].
  T lerp(T other, double t);

  /// [value] in every state, or null when [value] is null.
  ///
  /// Flutter: `ButtonStyleButton.allOrNull`. A style author's `styleFrom`
  /// uses it to turn a plain value into the state property a style field
  /// holds.
  static WidgetStateProperty<T?>? allOrNull<T>(T? value) =>
      value == null ? null : WidgetStatePropertyAll<T?>(value);

  /// [first] over [second], state by state: a state [first] resolves to
  /// null takes [second]'s value.
  ///
  /// A style's `merge` uses it for every state property field, so that a
  /// nested theme layers over the enclosing one the way the package's own
  /// styles do. A null side yields the other.
  static WidgetStateProperty<T?>? mergeStates<T>(
    WidgetStateProperty<T?>? first,
    WidgetStateProperty<T?>? second,
  ) {
    if (first == null) return second;
    if (second == null) return first;
    return _MergedStates<T>(first, second);
  }

  /// The lerp of a state-colour field at [t]: the colours of each state
  /// interpolate as dynamic colours, and a null end jumps at the middle.
  static WidgetStateProperty<Color?>? Function(
    WidgetStateProperty<Color?>?,
    WidgetStateProperty<Color?>?,
  )
  lerpStateColors(double t) =>
      (from, to) => WidgetStateProperty.lerp<Color?>(
        from,
        to,
        t,
        lerpNullable(GlassDynamicColor.lerp),
      );

  /// [lerp] with a null end jumping to the other end at the middle.
  ///
  /// In a style a null value falls through to what lies under it, so it
  /// does not fade; a style's `lerp` wraps each field's own lerp with it.
  static T? Function(T?, T?, double) lerpNullable<T>(
    T? Function(T?, T?, double) lerp,
  ) =>
      (a, b, t) => a == null || b == null ? (t < 0.5 ? a : b) : lerp(a, b, t);
}

@immutable
final class _MergedStates<T> implements WidgetStateProperty<T?> {
  const _MergedStates(this.first, this.second);

  final WidgetStateProperty<T?> first;
  final WidgetStateProperty<T?> second;

  @override
  T? resolve(Set<WidgetState> states) =>
      first.resolve(states) ?? second.resolve(states);

  @override
  bool operator ==(Object other) =>
      other is _MergedStates<T> &&
      other.first == first &&
      other.second == second;

  @override
  int get hashCode => Object.hash(first, second);
}

/// The look of the glass widgets below a [GlassTheme].
///
/// Every field is an override: null keeps the enclosing theme's value, and
/// at the root the native one. A nested theme merges into the enclosing
/// one field by field, and style by style.
///
/// The theme names no component: the look of each one is a [GlassStyle] in
/// [styles], which the component looks up by type.
@immutable
class GlassThemeData {
  /// Creates a theme.
  const GlassThemeData({
    this.brightness,
    this.primaryColor,
    this.fontFamily,
    this.colorScheme,
    this.styles = const [],
  });

  /// The theme between [a] and [b] at [t]: colors and styles interpolate;
  /// brightness and font take [b]'s at once, and a style only one of the
  /// two has switches at the middle.
  factory GlassThemeData.lerp(
    GlassThemeData a,
    GlassThemeData b,
    double t,
  ) {
    if (identical(a, b) || t == 0) return a;
    if (t == 1) return b;
    final from = {for (final style in a.styles) style.type: style};
    final to = {for (final style in b.styles) style.type: style};
    return GlassThemeData(
      brightness: b.brightness,
      primaryColor: GlassDynamicColor.lerp(a.primaryColor, b.primaryColor, t),
      fontFamily: b.fontFamily,
      colorScheme: GlassColorScheme.lerp(a.colorScheme, b.colorScheme, t),
      styles: [
        for (final type in {...from.keys, ...to.keys})
          if (switch ((from[type], to[type])) {
                (final a?, final b?) => a.lerp(b, t) as GlassStyle<Object>,
                (final a, final b) => t < 0.5 ? a : b,
              }
              case final style?)
            style,
      ],
    );
  }

  /// Light or dark, or null to follow the platform.
  final Brightness? brightness;

  /// The accent, UIKit's `tintColor`; [GlassColors.systemBlue] when null.
  final Color? primaryColor;

  /// The font of every label, or null for the system font.
  final String? fontFamily;

  /// The app's semantic colors.
  final GlassColorScheme? colorScheme;

  /// The looks of the components, one per [GlassStyle.type]; of two with
  /// one type, the later wins.
  final List<GlassStyle<Object>> styles;

  /// The style in [styles] kept under [type], or under [T] without one;
  /// null when there is none.
  ///
  /// Flutter: `ThemeData.extension`.
  T? style<T extends GlassStyle<Object>>([Object? type]) {
    final key = type ?? T;
    for (final style in styles.reversed) {
      if (style.type == key) return style as T;
    }
    return null;
  }

  /// This theme with the non-null fields of [other] over it; schemes merge
  /// too, and each of [other]'s styles merges over this theme's of its
  /// type.
  GlassThemeData merge(GlassThemeData? other) {
    if (other == null) return this;
    return GlassThemeData(
      brightness: other.brightness ?? brightness,
      primaryColor: other.primaryColor ?? primaryColor,
      fontFamily: other.fontFamily ?? fontFamily,
      colorScheme: colorScheme?.merge(other.colorScheme) ?? other.colorScheme,
      styles: _mergeStyles(styles, other.styles),
    );
  }

  static List<GlassStyle<Object>> _mergeStyles(
    List<GlassStyle<Object>> under,
    List<GlassStyle<Object>> over,
  ) {
    if (over.isEmpty) return under;
    if (under.isEmpty) return over;
    final byType = {for (final style in under) style.type: style};
    for (final style in over) {
      byType[style.type] =
          style.merge(byType[style.type]) as GlassStyle<Object>;
    }
    return List.unmodifiable(byType.values);
  }

  @override
  bool operator ==(Object other) =>
      other is GlassThemeData &&
      other.brightness == brightness &&
      other.primaryColor == primaryColor &&
      other.fontFamily == fontFamily &&
      other.colorScheme == colorScheme &&
      listEquals(other.styles, styles);

  @override
  int get hashCode => Object.hash(
    brightness,
    primaryColor,
    fontFamily,
    colorScheme,
    Object.hashAll(styles),
  );
}

/// Sets the look of the glass widgets below it.
///
/// Flutter: `CupertinoTheme`, except that a nested theme merges into the
/// enclosing one instead of replacing it.
///
/// A widget that reads one part of the theme ([brightnessOf],
/// [primaryColorOf], [fontFamilyOf], [colorSchemeOf], or one style with
/// [styleOf]) rebuilds only when that part changes.
///
/// It only provides: an app's root is a `GlassScope`, which also animates
/// a theme change and sets the renderer and the frame rate; a
/// [GlassTheme] gives a subtree a theme of its own.
class GlassTheme extends StatelessWidget {
  /// Applies [data] to [child].
  const GlassTheme({required this.data, required this.child, super.key});

  /// The theme.
  final GlassThemeData data;

  /// The subtree the theme applies to.
  final Widget child;

  /// The merged theme at [context], or an empty one.
  static GlassThemeData of(BuildContext context) =>
      maybeOf(context) ?? const GlassThemeData();

  /// The merged theme at [context], or null without a theme above.
  static GlassThemeData? maybeOf(BuildContext context) =>
      InheritedModel.inheritFrom<_GlassThemeScope>(context)?.data;

  static GlassThemeData? _of(BuildContext context, Object aspect) =>
      InheritedModel.inheritFrom<_GlassThemeScope>(
        context,
        aspect: aspect,
      )?.data;

  /// The theme's brightness at [context], or null to follow the platform.
  static Brightness? brightnessOf(BuildContext context) =>
      _of(context, _GlassThemeAspect.brightness)?.brightness;

  /// The theme's accent at [context], or null for the native one.
  static Color? primaryColorOf(BuildContext context) =>
      _of(context, _GlassThemeAspect.primaryColor)?.primaryColor;

  /// The theme's font at [context], or null for the system font.
  static String? fontFamilyOf(BuildContext context) =>
      _of(context, _GlassThemeAspect.fontFamily)?.fontFamily;

  /// The theme's color scheme at [context], or null without one.
  static GlassColorScheme? colorSchemeOf(BuildContext context) =>
      _of(context, _GlassThemeAspect.colorScheme)?.colorScheme;

  /// The scheme's label at [context], or [GlassColors.label].
  @internal
  static Color labelColorOf(BuildContext context) =>
      colorSchemeOf(context)?.label ?? GlassColors.label;

  /// The scheme's tertiary label at [context], or
  /// [GlassColors.tertiaryLabel].
  @internal
  static Color tertiaryLabelColorOf(BuildContext context) =>
      colorSchemeOf(context)?.tertiaryLabel ?? GlassColors.tertiaryLabel;

  /// The theme's style kept under [type], or under [T] without one, at
  /// [context]; null when the theme has none.
  ///
  /// The widget at [context] rebuilds when that style changes, and not when
  /// another one does.
  static T? styleOf<T extends GlassStyle<Object>>(
    BuildContext context, [
    Object? type,
  ]) {
    final key = type ?? T;
    return _of(context, key)?.style<T>(key);
  }

  @override
  Widget build(BuildContext context) => _GlassThemeScope(
    data: maybeOf(context)?.merge(data) ?? data,
    child: child,
  );
}

enum _GlassThemeAspect { brightness, primaryColor, fontFamily, colorScheme }

class _GlassThemeScope extends InheritedModel<Object> {
  const _GlassThemeScope({required this.data, required super.child});

  final GlassThemeData data;

  @override
  bool updateShouldNotify(_GlassThemeScope oldWidget) => data != oldWidget.data;

  @override
  bool updateShouldNotifyDependent(
    _GlassThemeScope oldWidget,
    Set<Object> dependencies,
  ) {
    final old = oldWidget.data;
    return dependencies.any(
      (aspect) => switch (aspect) {
        _GlassThemeAspect.brightness => data.brightness != old.brightness,
        _GlassThemeAspect.primaryColor => data.primaryColor != old.primaryColor,
        _GlassThemeAspect.fontFamily => data.fontFamily != old.fontFamily,
        _GlassThemeAspect.colorScheme => data.colorScheme != old.colorScheme,
        _ =>
          data.style<GlassStyle<Object>>(aspect) !=
              old.style<GlassStyle<Object>>(aspect),
      },
    );
  }
}
