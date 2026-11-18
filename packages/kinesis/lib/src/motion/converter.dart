import 'dart:ui' show Color, Offset, Radius, Rect, Size;

import 'package:kinesis/src/motion/rest.dart';

/// Maps a value of type [T] to the doubles a spring moves and back.
///
/// Every component moves on the same spring. [restDistance] is how far a
/// component may still swing from its target before the swing is
/// invisible.
abstract class MotionConverter<T> {
  /// Creates a converter.
  const MotionConverter();

  /// A plain double, at rest within 0.1: a tenth of a logical pixel for a
  /// length. An opacity or a fraction gives `MotionValue` its own
  /// `restDistance`.
  static const MotionConverter<double> single = _SingleConverter();

  /// An [Offset] as dx and dy, at rest within 0.1 logical pixels.
  static const MotionConverter<Offset> offset = _OffsetConverter();

  /// A [Size] as width and height, at rest within 0.1 logical pixels.
  static const MotionConverter<Size> size = _SizeConverter();

  /// A [Rect] as its left, top, right and bottom edges, at rest within 0.1
  /// logical pixels.
  static const MotionConverter<Rect> rect = _RectConverter();

  /// A [Radius] as x and y, at rest within 0.1 logical pixels.
  static const MotionConverter<Radius> radius = _RadiusConverter();

  /// An sRGB [Color] as its alpha, red, green and blue channels, each
  /// clamped to 0..1 on the way back, at rest within 0.002 (half an 8-bit
  /// step).
  static const MotionConverter<Color> color = _ColorConverter();

  /// The built-in converter for [T]; throws for a type without one.
  static MotionConverter<T> of<T>() {
    final MotionConverter<Object?> converter = switch (T) {
      const (double) => single,
      const (Offset) => offset,
      const (Size) => size,
      const (Rect) => rect,
      const (Radius) => radius,
      const (Color) => color,
      _ => throw ArgumentError(
        'No built-in MotionConverter for $T; pass a converter.',
      ),
    };
    return converter as MotionConverter<T>;
  }

  /// The number of components a value has.
  int get dimensions;

  /// The swing of one component below which it counts as at rest.
  double get restDistance;

  /// Writes the components of [value] into [out], starting at index 0.
  void write(T value, List<double> out);

  /// Reads a value from the components in [values].
  T read(List<double> values);
}

abstract class _LengthConverter<T> extends MotionConverter<T> {
  const _LengthConverter();

  @override
  double get restDistance => MotionRest.length;
}

class _SingleConverter extends _LengthConverter<double> {
  const _SingleConverter();

  @override
  int get dimensions => 1;

  @override
  void write(double value, List<double> out) => out[0] = value;

  @override
  double read(List<double> values) => values[0];
}

class _OffsetConverter extends _LengthConverter<Offset> {
  const _OffsetConverter();

  @override
  int get dimensions => 2;

  @override
  void write(Offset value, List<double> out) {
    out[0] = value.dx;
    out[1] = value.dy;
  }

  @override
  Offset read(List<double> values) => Offset(values[0], values[1]);
}

class _SizeConverter extends _LengthConverter<Size> {
  const _SizeConverter();

  @override
  int get dimensions => 2;

  @override
  void write(Size value, List<double> out) {
    out[0] = value.width;
    out[1] = value.height;
  }

  @override
  Size read(List<double> values) => Size(values[0], values[1]);
}

class _RectConverter extends _LengthConverter<Rect> {
  const _RectConverter();

  @override
  int get dimensions => 4;

  @override
  void write(Rect value, List<double> out) {
    out[0] = value.left;
    out[1] = value.top;
    out[2] = value.right;
    out[3] = value.bottom;
  }

  @override
  Rect read(List<double> values) =>
      Rect.fromLTRB(values[0], values[1], values[2], values[3]);
}

class _RadiusConverter extends _LengthConverter<Radius> {
  const _RadiusConverter();

  @override
  int get dimensions => 2;

  @override
  void write(Radius value, List<double> out) {
    out[0] = value.x;
    out[1] = value.y;
  }

  @override
  Radius read(List<double> values) => Radius.elliptical(values[0], values[1]);
}

class _ColorConverter extends MotionConverter<Color> {
  const _ColorConverter();

  @override
  int get dimensions => 4;

  @override
  double get restDistance => MotionRest.opacity;

  @override
  void write(Color value, List<double> out) {
    out[0] = value.a;
    out[1] = value.r;
    out[2] = value.g;
    out[3] = value.b;
  }

  @override
  Color read(List<double> values) => Color.from(
    alpha: values[0].clamp(0, 1),
    red: values[1].clamp(0, 1),
    green: values[2].clamp(0, 1),
    blue: values[3].clamp(0, 1),
  );
}
