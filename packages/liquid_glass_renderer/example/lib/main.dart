import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/basic_app.dart';

void main() {
  LgrLogs.initAllLogs();
  runApp(CupertinoApp(home: BasicApp()));
}

final settingsNotifier = ValueNotifier<LiquidGlassSettings>(
  LiquidGlassSettings(
    thickness: 20,
    lightAngle: 0.5 * pi,
    blend: 50,
    chromaticAberration: 1,
  ),
);

final cornerRadiusNotifier = ValueNotifier<double>(100);

final glassColorNotifier = ValueNotifier<Color>(
  const Color.fromARGB(0, 255, 255, 255),
);
