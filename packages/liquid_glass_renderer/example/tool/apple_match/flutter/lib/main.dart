import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'scene.dart';
import 'scene_view.dart';
import 'session.dart';

const _sceneBase64 = String.fromEnvironment('SCENE_B64');
const _configurationChannel = MethodChannel('apple_match/config');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  if (_sceneBase64.isEmpty) {
    throw StateError('SCENE_B64 is required');
  }
  final arguments =
      await _configurationChannel.invokeListMethod<String>('arguments') ??
      const [];
  final scene = MatchScene.fromBase64(_sceneBase64);
  // Mode selection is deterministic: the legacy capture driver always passes
  // `--probe`, while `flutter run` never forwards custom process arguments.
  // A launch without `--probe` therefore starts the persistent hot-reload
  // session, which reads candidates from the sandbox IPC file instead.
  final probe = _argument(arguments, '--probe');
  runApp(
    probe == null
        ? SessionApp(scene: scene)
        : MatchApp(
            scene: scene,
            probe: probe,
            settings: _decodeSettings(
              _argument(arguments, '--settings-b64') ?? '',
            ),
          ),
  );
}

String? _argument(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  return index >= 0 && index + 1 < arguments.length
      ? arguments[index + 1]
      : null;
}

Map<String, Object?> _decodeSettings(String value) {
  if (value.isEmpty) {
    return const {};
  }
  return jsonDecode(utf8.decode(base64Decode(value)))! as Map<String, Object?>;
}

class MatchApp extends StatelessWidget {
  const MatchApp({
    required this.scene,
    required this.probe,
    required this.settings,
    super.key,
  });

  final MatchScene scene;
  final String probe;
  final Map<String, Object?> settings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: MatchSceneView(scene: scene, probe: probe, settings: settings),
      ),
    );
  }
}
