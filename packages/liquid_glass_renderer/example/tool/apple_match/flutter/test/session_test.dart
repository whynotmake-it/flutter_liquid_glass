import 'dart:convert';
import 'dart:io';

import 'package:apple_match_flutter/scene.dart';
import 'package:apple_match_flutter/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MatchScene testScene() {
  return MatchScene(
    width: 100,
    height: 100,
    scale: 1,
    shapeRect: const Rect.fromLTWH(10, 10, 50, 20),
    cornerRadius: 10,
    probes: const {
      'A': {'kind': 'solid', 'color': '#000000'},
      'B': {'kind': 'solid', 'color': '#FFFFFF'},
      'C': {'kind': 'solid', 'color': '#101010'},
      'D': {'kind': 'solid', 'color': '#F0F0F0'},
    },
  );
}

Map<String, Object?> candidateJson({
  required String id,
  required String probe,
  required int serial,
  int settleFrames = 2,
  Map<String, Object?> settings = const {'blur': 6.0},
}) {
  return {
    'candidateId': id,
    'probe': probe,
    'serial': serial,
    'settleFrames': settleFrames,
    'settings': settings,
  };
}

void writeCandidate(File file, Map<String, Object?> json) {
  file.writeAsStringSync(jsonEncode(json));
}

Map<String, Object?> readStatus(File file) =>
    jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

void main() {
  group('CandidateSpec', () {
    test('parses a full candidate document', () {
      final spec = CandidateSpec.fromJson(
        candidateJson(id: 'c1', probe: 'B', serial: 7),
      );
      expect(spec.candidateId, 'c1');
      expect(spec.probe, 'B');
      expect(spec.serial, 7);
      expect(spec.settleFrames, 2);
      expect(spec.settings, {'blur': 6.0});
    });

    test('applies defaults for serial and settleFrames', () {
      final spec = CandidateSpec.fromJson({'candidateId': 'c1', 'probe': 'A'});
      expect(spec.serial, 0);
      expect(spec.settleFrames, 4);
      expect(spec.settings, isEmpty);
    });

    test('rejects missing candidateId or probe', () {
      expect(
        () => CandidateSpec.fromJson({'probe': 'A'}),
        throwsFormatException,
      );
      expect(
        () => CandidateSpec.fromJson({'candidateId': 'c1'}),
        throwsFormatException,
      );
    });

    test('tryRead returns null for missing or invalid files', () {
      final dir = Directory.systemTemp.createTempSync('apple_match_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/candidate.json');
      expect(CandidateSpec.tryRead(file), isNull);
      file.writeAsStringSync('{not json');
      expect(CandidateSpec.tryRead(file), isNull);
      file.writeAsStringSync('["a"]');
      expect(CandidateSpec.tryRead(file), isNull);
    });

    test('resetKey changes with serial for identical settings', () {
      final first = CandidateSpec.fromJson(
        candidateJson(id: 'c1', probe: 'A', serial: 1),
      );
      final retry = CandidateSpec.fromJson(
        candidateJson(id: 'c1', probe: 'A', serial: 2),
      );
      expect(first.key, retry.key);
      expect(first.resetKey, isNot(retry.resetKey));
    });
  });

  group('SessionApp', () {
    late Directory dir;
    late File candidateFile;
    late File statusFile;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('apple_match_session_test');
      candidateFile = File('${dir.path}/candidate.json');
      statusFile = File('${dir.path}/status.json');
    });

    tearDown(() {
      dir.deleteSync(recursive: true);
    });

    Widget buildApp() {
      return SessionApp(
        scene: testScene(),
        candidateFile: candidateFile,
        statusFile: statusFile,
        sceneBuilder: (context, spec) =>
            ColoredBox(color: spec.probe == 'A' ? Colors.black : Colors.white),
      );
    }

    Future<void> pumpUntilSettled(
      WidgetTester tester, {
      required int serial,
      int maxPumps = 12,
    }) async {
      for (var i = 0; i < maxPumps; i++) {
        await tester.pump();
        final status = readStatus(statusFile);
        if (status['state'] == 'settled' && status['serial'] == serial) {
          return;
        }
      }
      fail('session did not settle serial $serial within $maxPumps frames');
    }

    testWidgets('waits deterministically when no candidate exists', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();
      expect(readStatus(statusFile)['state'], 'waiting');
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColoredBox && widget.color == const Color(0xFF000000),
        ),
        findsOneWidget,
      );
    });

    testWidgets('applies candidate present at launch and settles', (
      tester,
    ) async {
      writeCandidate(
        candidateFile,
        candidateJson(id: 'c0', probe: 'A', serial: 1),
      );
      await tester.pumpWidget(buildApp());
      await pumpUntilSettled(tester, serial: 1);
      final status = readStatus(statusFile);
      expect(status['candidateId'], 'c0');
      expect(status['probe'], 'A');
      expect(status['trigger'], 'launch');
      expect(status['resetMode'], 'persistent');
    });

    testWidgets('does not settle before settleFrames have rendered', (
      tester,
    ) async {
      writeCandidate(
        candidateFile,
        candidateJson(id: 'c0', probe: 'A', serial: 1, settleFrames: 3),
      );
      await tester.pumpWidget(buildApp());
      // The launch frame plus two extra frames are fewer than settleFrames.
      await tester.pump();
      await tester.pump();
      expect(readStatus(statusFile)['state'], isNot('settled'));
      await pumpUntilSettled(tester, serial: 1);
    });

    testWidgets('hot reload updates the persistent render subtree', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      writeCandidate(
        candidateFile,
        candidateJson(id: 'c1', probe: 'A', serial: 1),
      );
      tester.state<SessionAppState>(find.byType(SessionApp)).reloadFromDisk();
      await pumpUntilSettled(tester, serial: 1);
      const persistentKey = ValueKey('persistent-capture-tree');
      expect(find.byKey(persistentKey), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is ColoredBox && widget.color == Colors.black,
        ),
        findsOneWidget,
      );
      expect(readStatus(statusFile)['trigger'], 'hotReload');

      // A new candidate updates the same subtree instead of repeatedly
      // allocating GPU geometry and filter resources.
      writeCandidate(
        candidateFile,
        candidateJson(
          id: 'c2',
          probe: 'B',
          serial: 2,
          settings: const {'blur': 12.0},
        ),
      );
      tester.state<SessionAppState>(find.byType(SessionApp)).reloadFromDisk();
      await pumpUntilSettled(tester, serial: 2);
      expect(find.byKey(persistentKey), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is ColoredBox && widget.color == Colors.white,
        ),
        findsOneWidget,
      );
      final status = readStatus(statusFile);
      expect(status['serial'], 2);
      expect(status['probe'], 'B');
    });

    testWidgets('a superseded candidate never reports settled', (tester) async {
      await tester.pumpWidget(buildApp());
      final state = tester.state<SessionAppState>(find.byType(SessionApp));
      writeCandidate(
        candidateFile,
        candidateJson(id: 'c1', probe: 'A', serial: 1, settleFrames: 6),
      );
      state.reloadFromDisk();
      await tester.pump();
      writeCandidate(
        candidateFile,
        candidateJson(id: 'c2', probe: 'A', serial: 2, settleFrames: 2),
      );
      state.reloadFromDisk();
      await pumpUntilSettled(tester, serial: 2);
      expect(readStatus(statusFile)['candidateId'], 'c2');
    });

    testWidgets('reports an error status for an unreadable candidate', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      candidateFile.writeAsStringSync('{broken');
      tester.state<SessionAppState>(find.byType(SessionApp)).reloadFromDisk();
      await tester.pump();
      final status = readStatus(statusFile);
      expect(status['state'], 'error');
      expect(status['error'], 'candidate-file-unreadable');
    });
  });
}
