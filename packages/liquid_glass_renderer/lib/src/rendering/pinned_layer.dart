import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:meta/meta.dart';

/// Filter layers that start at a corner of their own and keep their size
/// whatever they hold: the layers a filter reads by fragments counted from
/// the layer's corner, as glass reads a copy and a frost or a haze runs over
/// it. The only code that pins a layer so.
///
/// Impeller sizes a layer by what is drawn in it. A pinned layer's first
/// draw is a clear over all of it, which Impeller takes as the clear colour
/// of the layer's pass, so it draws nothing. It is one draw: a scene
/// recorded with an R-tree, as macOS records it, sizes a layer by those
/// draws of a picture that meet the clip alone, so a pin of a pixel at two
/// corners would lose the one past the clip and shrink to what it holds.
///
/// A clip still cuts a pinned layer as [ImpellerLayers.keepsWhole] tells.
abstract final class PinnedLayers {
  /// Pushes a layer filtered by [filter] onto [builder] that starts at
  /// [origin] and is [size] large, in the coordinates [builder] draws in.
  /// Pop it as any layer.
  static void push(
    ui.SceneBuilder builder,
    ui.ImageFilter filter,
    Offset origin,
    Size size,
  ) {
    builder
      ..pushImageFilter(filter)
      ..addPicture(origin, pinOf(size));
  }

  static final _pins = <Size, ui.Picture>{};
  static final _made = Expando<bool>();

  /// The picture that pins a layer of [size]: the layer cleared whole.
  /// Chrome keeps its few sizes across frames.
  @visibleForTesting
  static ui.Picture pinOf(Size size) {
    if (_pins[size] case final held?) return held;
    if (_pins.length >= 32) {
      for (final picture in _pins.values) {
        picture.dispose();
      }
      _pins.clear();
    }
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Offset.zero & size,
      Paint()..blendMode = BlendMode.clear,
    );
    final pin = recorder.endRecording();
    _made[pin] = true;
    return _pins[size] = pin;
  }

  /// Whether [picture] pins a layer.
  @visibleForTesting
  static bool isPin(ui.Picture picture) => _made[picture] ?? false;
}
