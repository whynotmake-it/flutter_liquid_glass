import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer_example/pages/glint_ab_page.dart';

/// Run with `flutter run -t lib/glint_ab_main.dart` on an iOS 26+ device.
void main() {
  runApp(
    const CupertinoApp(
      debugShowCheckedModeBanner: false,
      home: GlintAbPage(),
    ),
  );
}
