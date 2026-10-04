import 'dart:async';

import 'package:impeller_model/impeller_model.dart';

// Only the tests in this folder record frames for impeller_model.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ImpellerModelBinding.ensureInitialized();
  await testMain();
}
