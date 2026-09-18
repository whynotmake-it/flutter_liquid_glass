// Geometry matte renderer, selected per platform.
//
// `flutter_gpu` depends on `dart:ffi`, which does not exist on the web, so the
// web build gets a stub with the same surface. Real glass is never requested
// there: `ImageFilter.isShaderFilterSupported` is false on the web, and the
// layer takes the fake-glass path before touching the geometry renderer.
export 'flutter_gpu_geometry_renderer_native.dart'
    if (dart.library.js_interop) 'flutter_gpu_geometry_renderer_web.dart';
