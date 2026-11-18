/// The menu fusion worker: a background isolate where the platform has
/// isolates, a stub that never runs on the web.
library;

export 'package:apple_liquid_glass/src/motions/menu_fusion_worker_stub.dart'
    if (dart.library.io) 'package:apple_liquid_glass/src/motions/menu_fusion_worker_io.dart';
