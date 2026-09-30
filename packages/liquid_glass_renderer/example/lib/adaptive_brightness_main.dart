import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer_example/pages/adaptive_brightness_page.dart';

/// Run with `flutter run -t lib/adaptive_brightness_main.dart`.
void main() {
  runApp(
    const CupertinoApp(
      debugShowCheckedModeBanner: false,
      home: AdaptiveBrightnessPage(),
    ),
  );
}
