import 'dart:ui' as ui;

import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

/// The float index of the uniform [name] of [shader]'s program.
int uniformAt(ui.FragmentShader shader, String name) =>
    shader.getUniformFloat(name).shaderIndex;

/// Writes [floats] into the uniform [name] of [shader].
void putUniform(ui.FragmentShader shader, String name, List<double> floats) =>
    putFloats(shader, uniformAt(shader, name), floats);

/// Writes [floats] into [shader] from float [at] on, and returns the float
/// after them.
int putFloats(ui.FragmentShader shader, int at, List<double> floats) {
  for (var i = 0; i < floats.length; i++) {
    shader.setFloat(at + i, floats[i]);
  }
  return at + floats.length;
}

/// Writes every lane of [lanes] from [values] into [shader], a block of whole
/// vec4s from float [at] on, and returns the float after the block.
int putLanes<L extends UniformLane>(
  ui.FragmentShader shader,
  int at,
  List<L> lanes,
  Map<L, List<double>> values,
) => putFloats(shader, at, laneBlock(lanes, values));

/// The quad a shader-filled draw of [local] covers on [canvas]: [local]
/// grown to whole device pixels, or [local] where the canvas turns it.
///
/// Works around an Impeller/Metal coverage bug on macOS: a shader-filled draw
/// whose quad edge lands on a half-integer device pixel quantizes its alpha
/// ramp to whole pixels near that edge, so the analytic silhouette
/// stair-steps. The shader places the shape by `FlutterFragCoord`, so a
/// larger quad changes nothing visible. The snap is taken at paint;
/// compositor-only motion of a retained layer can move the quad back onto a
/// half pixel until the next repaint.
ui.Rect shaderQuad(ui.Rect local, ui.Canvas canvas) =>
    onWholeDevicePixels(
      local,
      Matrix4.fromFloat64List(canvas.getTransform()),
    ) ??
    local;
