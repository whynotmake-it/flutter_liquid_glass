part of 'date_picker.dart';

/// The look of a [GlassDatePicker], a [GlassTimePicker] and of the compact
/// picker's labels and wheels; a null field leaves it to the theme's style,
/// then the default, which follows the brightness and Increase Contrast.
@immutable
class GlassDatePickerStyle extends GlassStyle<GlassDatePickerStyle> {
  /// Creates a style.
  const GlassDatePickerStyle({
    this.accentColor,
    this.labelColor,
    this.labelFillColor,
    this.weekdayColor,
    this.todayFillColor,
    this.selectedDayTextColor,
    this.wheelBandColor,
    this.focusColor,
    this.hoverColor,
    this.titleTextStyle,
    this.weekdayTextStyle,
    this.dayTextStyle,
    this.selectedDayTextStyle,
    this.labelTextStyle,
    this.wheelTextStyle,
  });

  /// [style] over the theme's style over the measured defaults at
  /// [context], with every color but [focusColor] and [hoverColor] and
  /// every text style set.
  ///
  /// The defaults follow the ambient brightness and Increase Contrast; an
  /// accent without a [todayFillColor] of its own lends the today fill its
  /// color at the default's opacity. Dynamic colors resolve at [context];
  /// the text styles are merged, and each part resolves its own with
  /// [GlassTextScale.resolve] at the scale it draws at.
  factory GlassDatePickerStyle.resolve(
    BuildContext context,
    GlassDatePickerStyle? style,
  ) {
    final traits = GlassTraits.of(context);
    final night = traits.brightness == Brightness.dark;
    final table = traits.highContrast
        ? (night ? _darkHighContrast : _lightHighContrast)
        : (night ? _dark : _light);
    final look = (style ?? const GlassDatePickerStyle()).merge(
      maybeOf(context),
    );
    Color? resolved(Color? color) =>
        GlassDynamicColor.maybeResolve(color, context);
    final accent = resolved(
      look.accentColor ?? GlassTheme.primaryColorOf(context),
    );
    final labelColor = resolved(look.labelColor) ?? table.labelColor!;
    final weekdayColor = resolved(look.weekdayColor) ?? table.weekdayColor!;
    return GlassDatePickerStyle(
      labelFillColor: resolved(look.labelFillColor) ?? table.labelFillColor,
      labelColor: labelColor,
      accentColor: accent ?? table.accentColor,
      weekdayColor: weekdayColor,
      todayFillColor:
          resolved(look.todayFillColor) ??
          accent?.withValues(alpha: table.todayFillColor!.a) ??
          table.todayFillColor,
      selectedDayTextColor:
          resolved(look.selectedDayTextColor) ?? table.selectedDayTextColor,
      wheelBandColor: resolved(look.wheelBandColor) ?? table.wheelBandColor,
      focusColor: resolved(look.focusColor),
      hoverColor: resolved(look.hoverColor),
      titleTextStyle: _title.merge(look.titleTextStyle),
      weekdayTextStyle: _weekday
          .copyWith(color: weekdayColor)
          .merge(look.weekdayTextStyle),
      dayTextStyle: _day.merge(look.dayTextStyle),
      selectedDayTextStyle: _daySelected.merge(look.selectedDayTextStyle),
      labelTextStyle: _compact.merge(look.labelTextStyle),
      wheelTextStyle: TextStyle(
        fontSize: _WheelGeometry.fontSize,
        color: labelColor,
      ).merge(look.wheelTextStyle),
    );
  }

  /// The theme's [GlassDatePickerStyle] at [context], or null without one: the
  /// look between a widget's own style and its defaults.
  static GlassDatePickerStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassDatePickerStyle>(context);

  /// The colors a resolved look's parts show the keyboard focus and the
  /// pointer over them in at [context].
  @internal
  GlassHighlightLook highlightsAt(BuildContext context) =>
      GlassHighlightLook.of(
        context,
        focusColor: focusColor,
        hoverColor: hoverColor,
        base: accentColor,
      );

  /// The accent: the text of an open label, the month title's chevron,
  /// today's number and, when today is the chosen day, its disc; the
  /// theme's primary color, then systemBlue, by default.
  final Color? accentColor;

  /// The text of a compact label, the month title, a day, the month
  /// chevrons, the wheels' rows and the disc behind the chosen day when it
  /// is not today; label by default.
  final Color? labelColor;

  /// The fill of a compact label; tertiarySystemFill by default.
  final Color? labelFillColor;

  /// The weekday initials; secondaryLabel by default.
  final Color? weekdayColor;

  /// The fill behind today when it is not selected; the accent at the
  /// default's opacity by default.
  final Color? todayFillColor;

  /// The chosen day's number on its [labelColor] disc; the opposite of
  /// label by default.
  final Color? selectedDayTextColor;

  /// The band behind the wheels' selected row; tertiarySystemFill by
  /// default.
  final Color? wheelBandColor;

  /// The keyboard focus ring of a part; by default the ring Flutter's
  /// Cupertino controls derive from the accent.
  final Color? focusColor;

  /// What a part adds under the pointer; by default the wash of a glass
  /// body.
  final Color? hoverColor;

  /// The month title, over the default 17 points, semibold.
  final TextStyle? titleTextStyle;

  /// The weekday initials, over the default 13 points, semibold, in
  /// [weekdayColor].
  final TextStyle? weekdayTextStyle;

  /// A day's number, over the default 20 points. The calendar draws it in
  /// the color the day's state gives.
  final TextStyle? dayTextStyle;

  /// The chosen day's number, over the default 20 points, semibold.
  final TextStyle? selectedDayTextStyle;

  /// A compact label, over the default 17 points. The label draws it in
  /// [labelColor], or the accent while it is open.
  final TextStyle? labelTextStyle;

  /// A row of a wheel, over the default 21 points in [labelColor].
  final TextStyle? wheelTextStyle;

  /// This style over [other].
  @override
  GlassDatePickerStyle merge(GlassDatePickerStyle? other) {
    if (other == null) return this;
    return GlassDatePickerStyle(
      accentColor: accentColor ?? other.accentColor,
      labelColor: labelColor ?? other.labelColor,
      labelFillColor: labelFillColor ?? other.labelFillColor,
      weekdayColor: weekdayColor ?? other.weekdayColor,
      todayFillColor: todayFillColor ?? other.todayFillColor,
      selectedDayTextColor: selectedDayTextColor ?? other.selectedDayTextColor,
      wheelBandColor: wheelBandColor ?? other.wheelBandColor,
      focusColor: focusColor ?? other.focusColor,
      hoverColor: hoverColor ?? other.hoverColor,
      titleTextStyle:
          other.titleTextStyle?.merge(titleTextStyle) ?? titleTextStyle,
      weekdayTextStyle:
          other.weekdayTextStyle?.merge(weekdayTextStyle) ?? weekdayTextStyle,
      dayTextStyle: other.dayTextStyle?.merge(dayTextStyle) ?? dayTextStyle,
      selectedDayTextStyle:
          other.selectedDayTextStyle?.merge(selectedDayTextStyle) ??
          selectedDayTextStyle,
      labelTextStyle:
          other.labelTextStyle?.merge(labelTextStyle) ?? labelTextStyle,
      wheelTextStyle:
          other.wheelTextStyle?.merge(wheelTextStyle) ?? wheelTextStyle,
    );
  }

  /// The style between this one and [other] at [t].
  @override
  GlassDatePickerStyle lerp(GlassDatePickerStyle other, double t) {
    if (identical(this, other)) return this;
    final color = GlassStyle.lerpNullable(GlassDynamicColor.lerp);
    final text = GlassStyle.lerpNullable(TextStyle.lerp);
    return GlassDatePickerStyle(
      accentColor: color(accentColor, other.accentColor, t),
      labelColor: color(labelColor, other.labelColor, t),
      labelFillColor: color(labelFillColor, other.labelFillColor, t),
      weekdayColor: color(weekdayColor, other.weekdayColor, t),
      todayFillColor: color(todayFillColor, other.todayFillColor, t),
      selectedDayTextColor: color(
        selectedDayTextColor,
        other.selectedDayTextColor,
        t,
      ),
      wheelBandColor: color(wheelBandColor, other.wheelBandColor, t),
      focusColor: color(focusColor, other.focusColor, t),
      hoverColor: color(hoverColor, other.hoverColor, t),
      titleTextStyle: text(titleTextStyle, other.titleTextStyle, t),
      weekdayTextStyle: text(weekdayTextStyle, other.weekdayTextStyle, t),
      dayTextStyle: text(dayTextStyle, other.dayTextStyle, t),
      selectedDayTextStyle: text(
        selectedDayTextStyle,
        other.selectedDayTextStyle,
        t,
      ),
      labelTextStyle: text(labelTextStyle, other.labelTextStyle, t),
      wheelTextStyle: text(wheelTextStyle, other.wheelTextStyle, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassDatePickerStyle &&
      other.accentColor == accentColor &&
      other.labelColor == labelColor &&
      other.labelFillColor == labelFillColor &&
      other.weekdayColor == weekdayColor &&
      other.todayFillColor == todayFillColor &&
      other.selectedDayTextColor == selectedDayTextColor &&
      other.wheelBandColor == wheelBandColor &&
      other.focusColor == focusColor &&
      other.hoverColor == hoverColor &&
      other.titleTextStyle == titleTextStyle &&
      other.weekdayTextStyle == weekdayTextStyle &&
      other.dayTextStyle == dayTextStyle &&
      other.selectedDayTextStyle == selectedDayTextStyle &&
      other.labelTextStyle == labelTextStyle &&
      other.wheelTextStyle == wheelTextStyle;

  @override
  int get hashCode => Object.hash(
    accentColor,
    labelColor,
    labelFillColor,
    weekdayColor,
    todayFillColor,
    selectedDayTextColor,
    wheelBandColor,
    focusColor,
    hoverColor,
    titleTextStyle,
    weekdayTextStyle,
    dayTextStyle,
    selectedDayTextStyle,
    labelTextStyle,
    wheelTextStyle,
  );

  // UIKit's fonts for the date picker.
  static const _title = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
  static const _weekday = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 15.67 / 13,
  );
  static const _day = TextStyle(fontSize: 20, height: 1.2);
  static const _daySelected = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
  static const _compact = TextStyle(fontSize: 17, height: 20.33 / 17);

  static const _light = GlassDatePickerStyle(
    labelFillColor: Color(0x1F767680),
    labelColor: Color(0xFF000000),
    accentColor: Color(0xFF0088FF),
    weekdayColor: Color(0x993C3C43),
    todayFillColor: Color(0x1F0088FF),
    selectedDayTextColor: Color(0xFFFFFFFF),
    wheelBandColor: Color(0x1F767680),
  );

  static const _dark = GlassDatePickerStyle(
    labelFillColor: Color(0x3D767680),
    labelColor: Color(0xFFFFFFFF),
    accentColor: Color(0xFF0091FF),
    weekdayColor: Color(0x99EBEBF5),
    todayFillColor: Color(0x330091FF),
    selectedDayTextColor: Color(0xFF000000),
    wheelBandColor: Color(0x3D767680),
  );

  // Increase Contrast: the label fill and the wheel band (tertiarySystemFill)
  // turn from 12 to 20 percent and the accent takes systemBlue's
  // increased-contrast variant, the today fill following it at its own
  // opacity (read from UIKit's color tables, notes private; the weekday
  // color keeps its standard secondaryLabel value, not measured under
  // Increase Contrast).
  static const _lightHighContrast = GlassDatePickerStyle(
    labelFillColor: Color(0x33767680),
    labelColor: Color(0xFF000000),
    accentColor: Color(0xFF1E6EF4),
    weekdayColor: Color(0x993C3C43),
    todayFillColor: Color(0x1F1E6EF4),
    selectedDayTextColor: Color(0xFFFFFFFF),
    wheelBandColor: Color(0x33767680),
  );

  // Increase Contrast, dark: the fills turn from 24 to 32 percent and the
  // accent takes its increased-contrast variant (read from UIKit's color
  // tables, notes private).
  static const _darkHighContrast = GlassDatePickerStyle(
    labelFillColor: Color(0x52767680),
    labelColor: Color(0xFFFFFFFF),
    accentColor: Color(0xFF5CB8FF),
    weekdayColor: Color(0x99EBEBF5),
    todayFillColor: Color(0x335CB8FF),
    selectedDayTextColor: Color(0xFF000000),
    wheelBandColor: Color(0x52767680),
  );
}
