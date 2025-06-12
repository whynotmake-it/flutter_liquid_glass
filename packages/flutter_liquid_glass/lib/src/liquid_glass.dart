import 'dart:ui' show Image, ImageFilter;
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_liquid_glass/src/liquid.dart';

import 'package:flutter_shaders/flutter_shaders.dart';

class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.blur = 10,
    this.thickness = 2,
    this.shape = const RoundedSuperellipseBorder(
      borderRadius: BorderRadiusGeometry.all(
        Radius.circular(40),
      ),
    ),
  });

  final Widget child;

  final OutlinedBorder shape;

  final double blur;

  final double thickness;

  @override
  Widget build(BuildContext context) {
    return ShaderBuilder(
      assetKey:
          'packages/flutter_liquid_glass/lib/assets/shaders/displacement.frag',
      (context, shader, child) => ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: child,
      ),
      child: Liquid(
        child: Container(
          decoration: ShapeDecoration(
            shape: shape,
            color: Colors.white,
          ),
          child: child,
        ),
      ),
    );
  }
}

class LiquidWrapper extends StatelessWidget {
  const LiquidWrapper({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderBuilder(
      (context, shader, child) => ImageFiltered(
        imageFilter: ImageFilter.shader(shader),
        child: child,
      ),
      assetKey:
          'packages/flutter_liquid_glass/lib/assets/shaders/displacement.frag',
      child: child,
    );
  }
}
