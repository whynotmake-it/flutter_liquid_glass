import 'package:apple_liquid_glass/src/motions/sheet_tuning.dart';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

/// A height a sheet rests at, after UISheetPresentationController.Detent.
///
/// A detent's value is the height of the sheet above the bottom safe
/// area; the sheet itself extends under it to the screen's edge. The
/// largest possible value, the "maximum", is the container height minus
/// the top and bottom safe areas, the room UIKit hands a custom detent's
/// resolver.
@immutable
class GlassSheetDetent {
  const GlassSheetDetent._(this._kind, this._value)
    : _resolver = null,
      _identifier = null;

  /// A detent whose value [resolver] computes from the maximum value, as
  /// UIKit's `.custom(identifier:resolver:)`; detents with the same
  /// `identifier` are the same detent (null compares the resolver).
  const GlassSheetDetent.custom(
    double Function(double maximum) resolver, {
    this._identifier,
  }) : _kind = _DetentKind.custom,
       _value = 0,
       _resolver = resolver;

  /// A detent [value] points tall, clamped to the maximum.
  const GlassSheetDetent.height(double value)
    : this._(_DetentKind.height, value);

  /// A detent at [fraction] of the maximum.
  const GlassSheetDetent.fraction(double fraction)
    : this._(_DetentKind.fraction, fraction);

  /// A detent as tall as the sheet's content (SwiftUI
  /// `presentationSizing(.fitted)`), up to the maximum.
  ///
  /// The sheet lays its content out with a loose height and rests it at
  /// the top; content that scrolls fills the maximum instead. Until the
  /// content has laid out once the detent is the maximum.
  static const fitted = GlassSheetDetent._(_DetentKind.fitted, 0);

  /// UIKit's medium detent: [SheetTuning.mediumFraction] of the
  /// maximum.
  static const medium = GlassSheetDetent._(
    _DetentKind.fraction,
    SheetTuning.mediumFraction,
  );

  /// UIKit's large detent: the whole maximum. A sheet at the large detent
  /// docks to the screen edges and turns opaque.
  static const large = GlassSheetDetent._(_DetentKind.large, 1);

  final _DetentKind _kind;
  final double _value;
  final double Function(double maximum)? _resolver;
  final Object? _identifier;

  /// Whether this detent follows the height of the sheet's content.
  bool get isFitted => _kind == _DetentKind.fitted;

  /// Whether this is the full-height detent that docks the sheet.
  bool get isLarge => _kind == _DetentKind.large;

  /// The detent's value for a [maximum] value; a [fitted] detent takes
  /// the content's [fittedHeight], the maximum while it is unknown.
  double resolve(double maximum, {double? fittedHeight}) => switch (_kind) {
    _DetentKind.large => maximum,
    _DetentKind.fraction => maximum * _value.clamp(0.0, 1.0),
    _DetentKind.height => _value.clamp(0.0, maximum),
    _DetentKind.custom => _resolver!(maximum).clamp(0.0, maximum),
    _DetentKind.fitted => (fittedHeight ?? maximum).clamp(0.0, maximum),
  };

  @override
  bool operator ==(Object other) =>
      other is GlassSheetDetent &&
      other._kind == _kind &&
      other._value == _value &&
      (_kind != _DetentKind.custom ||
          (_identifier == null
              ? other._identifier == null && other._resolver == _resolver
              : other._identifier == _identifier));

  @override
  int get hashCode => Object.hash(
    _kind,
    _value,
    _kind == _DetentKind.custom ? (_identifier ?? _resolver) : null,
  );

  @override
  String toString() => switch (_kind) {
    _DetentKind.large => 'GlassSheetDetent.large',
    _DetentKind.fraction => 'GlassSheetDetent.fraction($_value)',
    _DetentKind.height => 'GlassSheetDetent.height($_value)',
    _DetentKind.custom => 'GlassSheetDetent.custom(${_identifier ?? ''})',
    _DetentKind.fitted => 'GlassSheetDetent.fitted',
  };
}

enum _DetentKind { height, fraction, large, custom, fitted }
