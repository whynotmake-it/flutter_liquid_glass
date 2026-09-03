import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'scene.dart';
import 'scene_view.dart';

/// File names used for the host-driven file IPC channel.
///
/// Both live directly in the app sandbox's temporary directory, which on the
/// iOS simulator is host-visible at
/// `xcrun simctl get_app_container <udid> <bundle> data`/tmp.
const kCandidateFileName = 'apple_match_candidate.json';
const kStatusFileName = 'apple_match_status.json';

/// Stdout sentinels parsed by the host runner. The status file remains the
/// source of truth; these lines exist for log inspection and path discovery.
const kReadySentinel = 'APPLE_MATCH_SESSION_READY';
const kSettledSentinel = 'APPLE_MATCH_SETTLED';

/// One deterministic capture request written by the host runner.
///
/// The runner atomically replaces the candidate file and then triggers a hot
/// reload; [SessionAppState.reassemble] re-reads the file and applies the
/// candidate to the persistent render subtree.
class CandidateSpec {
  const CandidateSpec({
    required this.candidateId,
    required this.probe,
    required this.settings,
    required this.serial,
    required this.settleFrames,
  });

  factory CandidateSpec.fromJson(Map<String, Object?> json) {
    final candidateId = json['candidateId'] as String?;
    final probe = json['probe'] as String?;
    if (candidateId == null || candidateId.isEmpty) {
      throw const FormatException('candidateId is required');
    }
    if (probe == null || probe.isEmpty) {
      throw const FormatException('probe is required');
    }
    return CandidateSpec(
      candidateId: candidateId,
      probe: probe,
      settings:
          (json['settings'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{},
      serial: (json['serial'] as num?)?.toInt() ?? 0,
      settleFrames: (json['settleFrames'] as num?)?.toInt() ?? 4,
    );
  }

  /// Reads and parses [file], returning null when it is absent or invalid.
  ///
  /// The runner writes the file atomically (write-then-rename), so a parse
  /// failure means corruption worth reporting rather than a partial read.
  static CandidateSpec? tryRead(File file) {
    try {
      if (!file.existsSync()) {
        return null;
      }
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      return CandidateSpec.fromJson(decoded);
    } on Object {
      return null;
    }
  }

  final String candidateId;
  final String probe;
  final Map<String, Object?> settings;

  /// Runner-controlled monotonically increasing id, echoed in the status file
  /// so the host can distinguish a fresh settle from a stale one.
  final int serial;
  final int settleFrames;

  /// Identity of the applied scene.
  String get key => '$candidateId|$probe';

  /// Identity of the request used only by settle supersession checks.
  String get resetKey => '$key|$serial';
}

/// Persistent capture session driven by hot reload.
///
/// Instead of relaunching the process per candidate, the app stays resident,
/// re-reads [kCandidateFileName] on every hot reload, renders the requested
/// probe/settings through the persistent render subtree, waits
/// [CandidateSpec.settleFrames] frames, and finally records a settled status
/// the host polls before screenshotting.
class SessionApp extends StatefulWidget {
  const SessionApp({
    required this.scene,
    this.candidateFile,
    this.statusFile,
    this.sceneBuilder,
    super.key,
  });

  final MatchScene scene;

  /// Overrides for the sandbox IPC files; used by widget tests.
  final File? candidateFile;
  final File? statusFile;

  /// Test seam replacing the real glass view (which needs Impeller/GPU).
  final Widget Function(BuildContext context, CandidateSpec spec)? sceneBuilder;

  @override
  State<SessionApp> createState() => SessionAppState();
}

class SessionAppState extends State<SessionApp> {
  CandidateSpec? _spec;
  late final File _candidateFile =
      widget.candidateFile ??
      File('${Directory.systemTemp.path}/$kCandidateFileName');
  late final File _statusFile =
      widget.statusFile ??
      File('${Directory.systemTemp.path}/$kStatusFileName');

  @override
  void initState() {
    super.initState();
    _writeStatus(const <String, Object?>{'state': 'waiting'});
    debugPrint(
      '$kReadySentinel ${jsonEncode(<String, Object?>{'candidatePath': _candidateFile.path, 'statusPath': _statusFile.path, 'shaderFiltersSupported': ui.ImageFilter.isShaderFilterSupported})}',
    );
    final initial = CandidateSpec.tryRead(_candidateFile);
    if (initial != null) {
      _apply(initial, trigger: 'launch');
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    reloadFromDisk(trigger: 'hotReload');
  }

  /// Re-reads the candidate file and applies it. Called on hot reload; also
  /// directly callable from tests.
  void reloadFromDisk({String trigger = 'hotReload'}) {
    final spec = CandidateSpec.tryRead(_candidateFile);
    if (spec == null) {
      _writeStatus(<String, Object?>{
        'state': 'error',
        'error': 'candidate-file-unreadable',
        'candidatePath': _candidateFile.path,
      });
      return;
    }
    _apply(spec, trigger: trigger);
  }

  void _apply(CandidateSpec spec, {required String trigger}) {
    if (!mounted) {
      return;
    }
    setState(() => _spec = spec);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scheduleSettle(spec, trigger);
  }

  void _scheduleSettle(CandidateSpec spec, String trigger) {
    var remaining = spec.settleFrames;
    void step(Duration _) {
      if (!mounted || _spec?.resetKey != spec.resetKey) {
        return; // superseded by a newer candidate
      }
      if (remaining > 0) {
        remaining -= 1;
        // Force another frame even though the scene is otherwise static.
        SchedulerBinding.instance.scheduleFrame();
        WidgetsBinding.instance.addPostFrameCallback(step);
        return;
      }
      final payload = <String, Object?>{
        'state': 'settled',
        'candidateId': spec.candidateId,
        'probe': spec.probe,
        'serial': spec.serial,
        'trigger': trigger,
        'resetMode': 'persistent',
        'settleFrames': spec.settleFrames,
      };
      _writeStatus(payload);
      debugPrint('$kSettledSentinel ${jsonEncode(payload)}');
    }

    WidgetsBinding.instance.addPostFrameCallback(step);
  }

  void _writeStatus(Map<String, Object?> payload) {
    try {
      final tmp = File('${_statusFile.path}.tmp');
      tmp.writeAsStringSync(jsonEncode(payload));
      tmp.renameSync(_statusFile.path);
    } on Object {
      // The host also watches stdout; a missing status file surfaces as a
      // runner-side timeout rather than an app crash.
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: widget.scene.appearance == 'dark'
          ? ThemeMode.dark
          : ThemeMode.light,
      darkTheme: ThemeData.dark(),
      home: Scaffold(
        body: spec == null
            ? const ColoredBox(color: Color(0xFF000000))
            : KeyedSubtree(
                // Keep the glass render objects resident. Re-keying this
                // subtree for every probe repeatedly allocates GPU geometry
                // textures and eventually drops the simulator connection.
                // Normal widget updates invalidate settings and shape safely.
                key: const ValueKey('persistent-capture-tree'),
                child: (widget.sceneBuilder ?? _defaultSceneBuilder)(
                  context,
                  spec,
                ),
              ),
      ),
    );
  }

  Widget _defaultSceneBuilder(BuildContext context, CandidateSpec spec) {
    return MatchSceneView(
      scene: widget.scene,
      probe: spec.probe,
      settings: spec.settings,
    );
  }
}
