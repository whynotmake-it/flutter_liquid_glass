import 'dart:async';

import 'package:liquid_glass_renderer/widgets.dart';

/// Loads full glass once, outside any test's fake clock: a load a layer
/// starts inside one never settles there, and a later test awaiting it
/// would wait forever.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await precacheLiquidGlass();
  await testMain();
}
