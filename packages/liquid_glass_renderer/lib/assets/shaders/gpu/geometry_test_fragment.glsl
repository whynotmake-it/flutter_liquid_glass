// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Test-only. The minimal fragment shader that the Flutter GPU smoke tests
// (test/src/flutter_gpu_shader_test.dart, flutter_gpu_render_test.dart) use
// to check bundle loading and render-pipeline execution. The renderer never
// binds it.

in vec2 vTexCoord;
out vec4 fragColor;

void main() {
  fragColor = vec4(vTexCoord, 0.0, 1.0);
}
