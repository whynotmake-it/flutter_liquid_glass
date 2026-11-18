// `flutter_gpu` depends on `dart:ffi`, which does not exist on the web, so the
// web build gets a stub with the same surface.
export 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer_native.dart'
    if (dart.library.js_interop) 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer_web.dart';
