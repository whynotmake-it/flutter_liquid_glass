import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/effects.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:liquid_glass_renderer/src/effects/stretch.dart';
import 'package:liquid_glass_renderer/widgets.dart';

/// The values each effect hands its render objects, frame by frame, through
/// scripted touches, held to `effect_motion.json`.
///
/// The fixture was recorded while the effects ran on the springs of the
/// package `motor`; the effects now run on the SDK's own spring simulation
/// and replay it. `RECORD_EFFECT_MOTION=1` rewrites the fixture.
///
/// A channel matches when every frame lies within 1e-3 of the channel's
/// range over the script: a thousandth of a glow's travel or of a stretch's
/// reach is far below a device pixel, so the feel is the same. The glow
/// replays exactly. The stretch differs by under 1e-4 of its range: one
/// axis that settles while the other still moves now rests on its target,
/// where `motor`'s shared clock kept it wandering within the spring's
/// tolerance (under 5e-4 px).
const _fixture = 'test/src/effect_motion.json';
const _tolerance = 1e-3;
const _frame = Duration(microseconds: 16667);

bool get _recording => Platform.environment['RECORD_EFFECT_MOTION'] == '1';

typedef _Channels = Map<String, List<double>>;

Widget _scene(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(alignment: Alignment.topLeft, child: child),
);

Future<_Channels> _glow(WidgetTester tester) async {
  await tester.pumpWidget(
    _scene(
      const FakeGlass(
        shape: LiquidRoundedRectangle(borderRadius: 0),
        child: GlassGlow(child: SizedBox(width: 200, height: 100)),
      ),
    ),
  );
  final channels = <String, List<double>>{
    'radius': [],
    'alpha': [],
    'dx': [],
    'dy': [],
  };
  Future<void> frames(int count) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(_frame);
      final glow = tester
          .element(find.byType(GlassGlow))
          .findAncestorRenderObjectOfType<RenderLiquidGlassContent>()!;
      channels['radius']!.add(glow.glowRadius);
      channels['alpha']!.add(glow.glowColor.a);
      channels['dx']!.add(glow.glowOffset.dx);
      channels['dy']!.add(glow.glowOffset.dy);
    }
  }

  final press = await tester.startGesture(const Offset(50, 50));
  await frames(10);
  for (var i = 0; i < 6; i++) {
    await press.moveBy(const Offset(12, 2));
    await frames(1);
  }
  await press.up();
  await frames(12);
  final again = await tester.startGesture(const Offset(150, 30));
  await frames(3);
  for (var i = 0; i < 4; i++) {
    await again.moveBy(const Offset(-6, 5));
    await frames(1);
  }
  await again.up();
  await frames(5);
  final tap = await tester.startGesture(const Offset(20, 80));
  await frames(2);
  await tap.up();
  await frames(120);
  return channels;
}

Future<_Channels> _stretch(WidgetTester tester) async {
  const childKey = Key('stretched');
  await tester.pumpWidget(
    _scene(
      const Padding(
        padding: EdgeInsets.all(100),
        child: LiquidStretch(
          child: SizedBox.square(key: childKey, dimension: 100),
        ),
      ),
    ),
  );
  final channels = <String, List<double>>{
    'scale': [],
    'stretchX': [],
    'stretchY': [],
  };
  final transform = find.descendant(
    of: find.byType(LiquidStretch),
    matching: find.byType(Transform),
  );
  Future<void> frames(int count) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(_frame);
      final stretch = tester.renderObject<RenderRawLiquidStretch>(
        find.byType(RawLiquidStretch),
      );
      final scale = tester.renderObject<RenderTransform>(transform);
      final matrix = Matrix4.identity();
      scale.applyPaintTransform(stretch, matrix);
      channels['scale']!.add(matrix.entry(0, 0));
      channels['stretchX']!.add(stretch.stretchPixels.dx);
      channels['stretchY']!.add(stretch.stretchPixels.dy);
    }
  }

  final center = tester.getCenter(find.byKey(childKey));
  final drag = await tester.startGesture(center);
  await frames(8);
  for (var i = 0; i < 10; i++) {
    await drag.moveBy(const Offset(5, 0));
    await frames(1);
  }
  for (var i = 0; i < 5; i++) {
    await drag.moveBy(const Offset(-8, 6));
    await frames(1);
  }
  await drag.up();
  await frames(6);
  final again = await tester.startGesture(center);
  await frames(4);
  for (var i = 0; i < 4; i++) {
    await again.moveBy(const Offset(3, -4));
    await frames(1);
  }
  await again.moveBy(const Offset(40, 30));
  await frames(3);
  await again.up();
  await frames(90);
  return channels;
}

void _hold(String effect, _Channels actual, Map<String, Object?> fixture) {
  final expected = fixture[effect]! as Map<String, Object?>;
  expect(actual.keys, unorderedEquals(expected.keys));
  for (final MapEntry(key: channel, value: values) in actual.entries) {
    final recorded = [
      for (final value in expected[channel]! as List<Object?>)
        (value! as num).toDouble(),
    ];
    expect(values, hasLength(recorded.length), reason: '$effect $channel');
    final range = recorded.reduce(math.max) - recorded.reduce(math.min);
    final allowed = _tolerance * (range == 0 ? 1 : range);
    for (var i = 0; i < values.length; i++) {
      expect(
        values[i],
        moreOrLessEquals(recorded[i], epsilon: allowed),
        reason: '$effect $channel at frame $i (range $range)',
      );
    }
  }
}

void main() {
  final recorded = <String, _Channels>{};
  final fixture = _recording
      ? const <String, Object?>{}
      : jsonDecode(File(_fixture).readAsStringSync()) as Map<String, Object?>;

  tearDownAll(() {
    if (_recording) {
      File(_fixture).writeAsStringSync(
        '${const JsonEncoder.withIndent(' ').convert(recorded)}\n',
      );
    }
  });

  testWidgets('the glow follows a press, a drag, a release and a press '
      'that interrupts it as recorded', (tester) async {
    final channels = await _glow(tester);
    if (_recording) {
      recorded['glow'] = channels;
    } else {
      _hold('glow', channels, fixture);
    }
  });

  testWidgets('the stretch follows a drag that turns, a release and a '
      'drag that interrupts it as recorded', (tester) async {
    final channels = await _stretch(tester);
    if (_recording) {
      recorded['stretch'] = channels;
    } else {
      _hold('stretch', channels, fixture);
    }
  });
}
