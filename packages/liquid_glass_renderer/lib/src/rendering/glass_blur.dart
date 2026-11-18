import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// What a glass's frost blur reads past the backdrop's edge.
@internal
const glassBlurTileMode = TileMode.mirror;

/// A filter that leaves what it filters as it is.
@internal
const ui.ImageFilter identityColorFilter = ui.ColorFilter.matrix(<double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0, //
]);
