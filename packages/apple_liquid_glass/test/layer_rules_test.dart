import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:layer_rules/layer_rules.dart';

const _material = 'package:material_ui/material_ui.dart';
const _cupertino = 'package:cupertino_ui/cupertino_ui.dart';
const _widgets = 'package:flutter/widgets.dart';
const _rendering = 'package:flutter/rendering.dart';

/// The glass renderer's values: its shapes, fields and looks, which draw
/// nothing.
const _glassValues = 'package:liquid_glass_renderer/painting.dart';

/// The glass renderer past its values.
const _glassDrawing = [
  'package:liquid_glass_renderer/liquid_glass_renderer.dart',
  'package:liquid_glass_renderer/rendering.dart',
  'package:liquid_glass_renderer/widgets.dart',
  'package:liquid_glass_renderer/src/',
];
const _kinesis = 'package:kinesis/kinesis.dart';
const _kinesisWidgets = 'package:kinesis/widgets.dart';
const _kinesisPresentation = 'package:kinesis/presentation.dart';
const _kinesisTesting = 'package:kinesis/testing.dart';
const _kinesisSrc = 'package:kinesis/src/';

/// Below widgets, a library reaches kinesis no higher than its widgets: the
/// umbrella of kinesis brings its presentations too.
const _belowPresentation = [_kinesis, _kinesisPresentation];

/// foundation < motions < surfaces < liquid < raw < widgets, each importing
/// only what its row names. The measured laws stay below widgets and
/// rendering so they replay a recording without a screen; only liquid draws
/// with the glass renderer, and nothing but the umbrella imports liquid, so
/// no other library picks a renderer for the app; a core knows no surface.
/// Every library takes the renderer's values ([_glassValues]): a body's
/// shape and field are the renderer's, and foundation lays a body out as
/// live glass does.
const _rules = LayerRules(
  package: 'apple_liquid_glass',
  libraries: {
    'foundation': {},
    'motions': {'foundation'},
    'surfaces': {'foundation', 'motions'},
    'liquid': {'foundation', 'surfaces'},
    'raw': {'foundation', 'motions'},
    'widgets': {'foundation', 'motions', 'surfaces', 'raw'},
  },
  umbrella: 'apple_liquid_glass',
  umbrellaReexports: {_kinesis, _glassValues},
  packages: {'flutter', 'meta', 'kinesis', 'liquid_glass_renderer'},
  forbidden: {
    everyLibrary: [_material, _cupertino, _kinesisSrc],
    'foundation': [..._belowPresentation, _kinesisTesting, ..._glassDrawing],
    'motions': [
      _widgets,
      _rendering,
      _kinesisWidgets,
      ..._belowPresentation,
      _kinesisTesting,
      ..._glassDrawing,
    ],
    'surfaces': [..._belowPresentation, _kinesisTesting, ..._glassDrawing],
    'liquid': [..._belowPresentation, _kinesisTesting],
    'raw': [..._belowPresentation, _kinesisTesting, ..._glassDrawing],
    'widgets': [_kinesisTesting, ..._glassDrawing],
  },
  bans: [
    Ban(
      'GestureDetector',
      r'\b(?:Raw)?GestureDetector\b',
      reason: "Input goes through kinesis's InputRegion.",
    ),
    Ban(
      'Listener',
      r'\bListener\s*\(',
      reason: "Input goes through kinesis's InputRegion.",
    ),
    Ban(
      'CallbackShortcuts',
      r'\bCallbackShortcuts\b',
      reason: "Keys reach a control through kinesis's InputRegion.",
    ),
    Ban(
      'pointer-route',
      r'\bGestureBinding\b|\bpointerRouter\b',
      reason:
          "A touch with no region under it comes through kinesis's "
          'InputCapture.',
    ),
    Ban(
      'key-handler',
      r'\bonKey(?:Event)?\s*:|\bHardwareKeyboard\b|\bKeyboardListener\b|'
          r'\bShortcuts\s*\(',
      reason: "Keys reach a control through kinesis's InputRegion.",
    ),
    Ban(
      'AnimationController',
      r'\bAnimationController\b',
      reason:
          "Motion runs on kinesis's clock and reaches the screen without "
          'a rebuild.',
    ),
    Ban(
      'Ticker',
      r'\bTicker\b|\bcreateTicker\b',
      reason:
          "Motion runs on kinesis's clock and reaches the screen without "
          'a rebuild.',
    ),
    Ban(
      'addPostFrameCallback',
      r'\baddPostFrameCallback\b',
      reason:
          'A value shown after the frame is a frame late, so each use '
          'says on the line above it why it is not one: disposal, a '
          'report, a flag reset.',
      allowedWith: 'After the frame:',
    ),
    Ban(
      'MotionClock.instance',
      r'\bMotionClock\.instance\b',
      reason:
          'A motion runs on the clock of its place (MotionClockScope.of, '
          'Motion.clock), so a subtree replays on a clock of its own.',
    ),
    Ban(
      'ValueListenableBuilder',
      r'\bValueListenableBuilder\b',
      reason:
          'Motion reaches the screen without a rebuild: a render object '
          'listens to the value it draws.',
    ),
    Ban(
      'pixel-ratio',
      r'[dD]evicePixelRatioOf\b|'
          r'\bView\.(?:maybeOf|of)\([^)]*\)\??\.devicePixelRatio\b',
      reason:
          'Apple reads the pixel ratio of the view it draws into in one '
          'place (GlassTraits.viewPixelRatio).',
      allowedIn: {'lib/src/foundation/traits.dart'},
    ),
    Ban(
      'blur-reach',
      r'\bImpellerBlur\b',
      reason:
          'How far a blur reaches, and when a band blurs at half '
          "resolution, is the renderer's.",
    ),
    Ban(
      'frost-sentinel',
      r'1e5\b',
      reason:
          'A scroll edge band says hard or soft '
          '(LiquidGlassFrostBand.hard, .soft); the renderer keeps what no '
          'dissolve is.',
    ),
    Ban(
      'shader-filters',
      r'\bisShaderFilterSupported\b|\bkIsWeb\b',
      reason:
          "Whether full glass draws is the renderer's to know: liquid "
          'builds one tree in every state and reads liquidGlassSupport '
          'where it must.',
      bannedIn: {'lib/src/liquid/'},
    ),
    Ban(
      'reducedMotion',
      r'\breducedMotion\b',
      reason: 'Reduce Motion reaches a motion through Motion.traits.',
    ),
    Ban(
      'engine-layer',
      r'\b(?:ImageFilter|BackdropFilter|ColorFilter|ShaderMask)Layer\b|'
          r'\bpush(?:ImageFilter|BackdropFilter|ColorFilter|ShaderMask)\b',
      reason:
          'A layer the frame composer does not know is drawn past it; the '
          "renderer's own layers are its business. The selector blurs the "
          'items that dissolve as its bar collapses in its own paint, '
          'with either renderer.',
      allowedIn: {'lib/src/liquid/', 'lib/src/raw/selector_render.dart'},
    ),
    Ban(
      'press-reach',
      r'\breleaseSlop\b|\.inflate\([^)]*[sS]lop|'
          r'\bmax\([^)]*\bglassMinimumTargetExtent\b',
      reason:
          "Where a press counts is its region's reach (glassTargetReach, "
          'glassButtonReach), applied by kinesis and by the laws that '
          'hold the same reach.',
    ),
    Ban(
      'touch-slop',
      r'\bkTouchSlop\b|\bkPanSlop\b',
      reason:
          "Whether a touch is a tap or a drag is the gesture's or its "
          "law's, in kinesis.",
    ),
    Ban(
      'state-write',
      r'\bwriteStates\b|\.update\(\s*WidgetState\.|'
          r'\.update\([^,()]+,\s*WidgetState\.|\.statesOf\(',
      reason:
          'A control says its states (ControlStates: enabled, saidStates, '
          'focusShows; InputZone.states) and its region or zone publishes '
          'them with the ones input keeps; nothing else writes a state.',
    ),
    Ban(
      'haptic-play',
      r'\.play\(\)',
      reason:
          'A haptic plays with the input that causes it, through '
          'InputRegion.',
    ),
    Ban(
      'HapticFeedback',
      r'\bHapticFeedback\.',
      reason:
          'A haptic plays with the input that causes it, through '
          'InputRegion.',
    ),
    Ban(
      'ignore',
      r'//\s*ignore:',
      reason: 'A lint is fixed in the code, never silenced.',
      code: false,
    ),
    Ban(
      'ignore_for_file',
      r'//\s*ignore_for_file:',
      reason: 'A lint is fixed in the code, never silenced.',
      code: false,
    ),
    Ban(
      'dynamic',
      r'\bdynamic\b',
      reason: 'Object? keeps the type checker on, where dynamic turns it off.',
    ),
    Ban(
      'spring',
      r'\bSpring(?:\.\w+|\()',
      reason:
          "A measured spring lives with its law; the app's own choice of "
          'a spring is a parameter of its scope.',
      allowedIn: {'lib/src/motions/', 'lib/src/liquid/scope.dart'},
    ),
    Ban(
      'law-outside-motions',
      r'\bextends\s+Motion(?:Loop)?\b',
      reason:
          'A law lives in motions, where it replays a recording without a '
          'screen; a host tells it what happened and reads its values.',
      allowedIn: {'lib/src/motions/'},
    ),
    Ban(
      'SingleChildScrollView',
      r'\bSingleChildScrollView\b',
      reason:
          'A SingleChildScrollView lays out and paints its whole child, '
          'however little of it shows; a sliver builds what shows.',
    ),
    Ban(
      'radius-clamp',
      r'\bmin\([^;]*?\bshortestSide\s*/\s*2\b',
      reason:
          'A corner radius is drawn as Flutter scales it '
          '(glassCornerRadii); one clamped to half the short side on its '
          "own draws a pair's corners wrong.",
      allowedIn: {'lib/src/motions/'},
    ),
    Ban(
      'shadow-blur',
      r'\bBlurStyle\.|\bMaskFilter\.blur\(',
      reason:
          'Glass casts its shadows as the renderer does '
          '(LiquidGlassSilhouette.paintShadows); only a page, which is no '
          'glass, blurs a shadow of its own.',
      allowedIn: {
        'lib/src/widgets/navigation/page_route_card.dart',
        'lib/src/widgets/navigation/page_route_zoom.dart',
      },
    ),
    Ban(
      'superellipse-draw',
      r'\b(?:drawRSuperellipse|toRSuperellipse)\b',
      reason:
          'A body fills through its shape (LiquidShape.paintInterior), '
          'and its corners are fitted as Flutter fits them in '
          'glassCornerRadii alone.',
      allowedIn: {'lib/src/foundation/body.dart'},
    ),
    Ban(
      'text-scale',
      r'\btextScalerOf\b|\.textScaler\b|\bTextScaler\b|'
          r'\bwith(?:Clamped|No)TextScaling\b|\bmaxScaleFactor\b|'
          r'\bTextPainter\(',
      reason: 'Text is resolved, measured and drawn at one GlassTextScale.',
      allowedIn: {'lib/src/foundation/typography.dart'},
    ),
  ],
);

void main() {
  final report = checkLayers(Directory.current, _rules);

  test('every lib/src folder is one library behind one library file', () {
    expect(report.structure, isEmpty);
  });

  test('imports and bans break the rules only as test/rules/debt.txt '
      'lists', () {
    final failure = holdDebt(
      File('test/rules/debt.txt'),
      report.violations,
      update: updateDebtRequested,
    );
    if (failure != null) fail(failure);
  });
}
