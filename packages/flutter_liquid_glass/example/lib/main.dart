import 'package:flutter/material.dart';
import 'package:flutter_liquid_glass/flutter_liquid_glass.dart';
import 'package:springster/springster.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.yellow,
        body: RawSquircles(
          squircle1: Squircle(
            topLeft: Offset(100, 100),
            size: Size(100, 100),
            cornerRadius: 10,
          ),
          squircle2: Squircle(
            topLeft: Offset(200, 300),
            size: Size(100, 100),
            cornerRadius: 10,
          ),
          blend: 10,
        ),
      ),
    );
  }
}
