import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:layer_rules/layer_rules.dart';

const _rules = LayerRules(
  package: 'liquid_glass_renderer',
  libraries: {
    'painting': {},
    'plan': {'painting'},
    'rendering': {'painting', 'plan'},
    'widgets': {'painting', 'plan', 'rendering'},
  },
  sourceOnly: {'plan'},
  umbrella: 'liquid_glass_renderer',
  umbrellaLibraries: {'painting', 'widgets'},
  otherLibrariesThroughSource: true,
  packages: {
    'flutter',
    'flutter_gpu',
    'vector_math',
    'meta',
  },
  forbidden: {
    everyLibrary: [
      'package:material_ui/material_ui.dart',
      'package:cupertino_ui/cupertino_ui.dart',
      'package:logging/',
    ],
  },
  bans: [
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
      'addPostFrameCallback',
      r'\baddPostFrameCallback\b',
      reason:
          'The end of a frame is for what a frame leaves behind: '
          'disposal, a report, a flag reset. Glass that shows a value a '
          'frame late is a defect, so each use says why it is not one on '
          'the line above it.',
      allowedWith: 'After the frame:',
    ),
    Ban(
      'AnimationController',
      r'\bAnimationController\b',
      reason:
          'The renderer animates nothing: motion belongs to the widget '
          'libraries on top, which drive glass through its live frames.',
    ),
    Ban(
      'Ticker',
      r'\b(?:Single)?Ticker(?:Provider(?:StateMixin)?)?\b|\bcreateTicker\b',
      reason:
          'The renderer animates nothing: motion belongs to the widget '
          'libraries on top, which drive glass through its live frames.',
    ),
    Ban(
      'dynamic',
      r'\bdynamic\b',
      reason: 'Object? keeps the type checker on, where dynamic turns it off.',
    ),
    Ban(
      'SingleChildScrollView',
      r'\bSingleChildScrollView\b',
      reason:
          'A SingleChildScrollView lays out and paints its whole child, '
          'however little of it shows; a sliver builds what shows.',
    ),
    Ban(
      'backdrop-read',
      r'toImageSync\(|pushBackdropFilter\(|(?<![\w.])(?:BackdropFilterLayer|'
          'BackdropFilter|BackdropKey|BackdropGroup|'
          r'OpacitySeedLayer|GlassCopies)\(',
      reason:
          'Glass reads its backdrop, or takes a copy of the screen, only '
          "through the frame's composer, which plans every read. The "
          'warm-up draws its own detached layer tree that is never part '
          "of a frame, the shading's one image is the empty pixel bound "
          'where a draw has no image of its own, the consolidated fake '
          'glass layer shares one capture among its own reads, bent '
          'content draws a picture of what lies over a shape, which the '
          'caller paints and which holds nothing of the screen, and a '
          "fake field body's node image holds the field's samples.",
      allowedIn: {
        'lib/src/plan/',
        'lib/src/rendering/backdrop_filter_layer.dart',
        'lib/src/rendering/backdrop_rig.dart',
        'lib/src/rendering/bent_content.dart',
        'lib/src/rendering/consolidated_fake_glass_layer.dart',
        'lib/src/rendering/copy_frost.dart',
        'lib/src/rendering/copy_read.dart',
        'lib/src/rendering/fake_glass_field_image.dart',
        'lib/src/rendering/glass_form.dart',
        'lib/src/rendering/glass_form_open.dart',
        'lib/src/rendering/glass_composer.dart',
        'lib/src/rendering/glass_composition_probe.dart',
        'lib/src/rendering/read.dart',
        'lib/src/rendering/scene_out.dart',
        'lib/src/rendering/shading.dart',
        'lib/src/rendering/warm_up.dart',
      },
    ),
    Ban(
      'copy-grid',
      r'\.cover\(|\.outTo\(|\.pixelsOn\(|'
          r'devicePixelRatio\s*/\s*share|/\s*share\b.*\bpixels\b',
      reason:
          "A copy's grid is its read's geometry's to decide and its "
          "place's to lay out: readers take the boxes and texels they "
          'give, round nothing to pixels of their own and carry no ratio '
          "between a copy's pixels and the screen's.",
      allowedIn: {
        'lib/src/plan/copy_place.dart',
        'lib/src/plan/impeller.dart',
        'lib/src/plan/read_layout.dart',
        'lib/src/painting/view_pixels.dart',
      },
    ),
    Ban(
      'pixel-rounding',
      r'(?:devicePixelRatio|\bdpr\b)[^;\n]*\.(?:floor|ceil|round)(?:ToDouble)?\(|'
          r'\.(?:floor|ceil|round)(?:ToDouble)?\(\)[^;\n]*/\s*'
          r'(?:devicePixelRatio|dpr)\b|'
          r'\.(?:floor|ceil|round)(?:ToDouble)?\(\)\s*-\s*[\w.]+\)\s*/',
      reason:
          "Rounding a length to device pixels is ViewPixels's: a rect "
          'rounded twice, or by two rules, lands a pixel off the one '
          'beside it. That holds whatever the ratio is called: a value '
          'rounded where a transform puts it and mapped back is rounded '
          'to pixels.',
      allowedIn: {
        'lib/src/plan/impeller.dart',
        'lib/src/painting/impeller_blur.dart',
        'lib/src/painting/view_pixels.dart',
      },
    ),
    Ban(
      'overlaps',
      r'\.overlaps\(',
      reason:
          "Whether two rects reach each other is rects.dart's: an empty "
          'rect, clipped away or drawing nothing, meets nothing wherever '
          'it lies.',
      allowedIn: {'lib/src/plan/rects.dart'},
    ),
    Ban(
      'read-member-index',
      r'\bmembers\[\d',
      reason:
          "Which member of a read is its band's painter, and which are "
          "glass, is the read's to say (GlassRead.bandPainter, "
          'glassMembers).',
      allowedIn: {'lib/src/plan/plan_result.dart'},
    ),
    Ban(
      'visibility-threshold',
      r'\.visibility\s*(?:>|<=)\s*0\b',
      reason:
          'Whether glass shows is one answer (DrawnAppearance.shows), and '
          'whether a layer draws a shape another (FrameShapes.drawn).',
      bannedIn: {'lib/src/'},
    ),
    Ban(
      'ancestor-walk',
      r'\bvisitAncestorElements\b',
      reason:
          'Where glass draws, beside its siblings or in a layer of its '
          "own under another glass, is the nearest GlassHost's answer, "
          'not an ancestor walk.',
      bannedIn: {'lib/src/widgets/'},
    ),
    Ban(
      'uniform-write',
      r'\.(?:setFloat|getUniformFloat)\(',
      reason:
          "A fragment shader's uniforms are found and written in one "
          'file, by name or by a lane table.',
      allowedIn: {'lib/src/rendering/shader_uniforms.dart'},
    ),
    Ban(
      'geometry-settings',
      r'\bLiquidGlassSettings\b',
      reason:
          'Geometry hears of settings only through what they ask of it, '
          "the layer's GeometryNeed: a frost or a tint redraws no geometry, "
          'and a rising bevel only each step of its reach.',
      bannedIn: {
        'lib/src/rendering/flutter_gpu_geometry_renderer.dart',
        'lib/src/rendering/flutter_gpu_geometry_renderer_native.dart',
        'lib/src/rendering/flutter_gpu_geometry_renderer_native_pages.dart',
        'lib/src/rendering/flutter_gpu_geometry_renderer_native_quads.dart',
        'lib/src/rendering/flutter_gpu_geometry_renderer_native_resources.dart',
        'lib/src/rendering/flutter_gpu_geometry_renderer_web.dart',
        'lib/src/rendering/geometry_render_link.dart',
        'lib/src/rendering/geometry_tiling.dart',
        'lib/src/rendering/geometry_tiling_atlas.dart',
        'lib/src/rendering/geometry_tiling_bounds.dart',
        'lib/src/rendering/geometry_tiling_groups.dart',
        'lib/src/rendering/geometry_tiling_values.dart',
        'lib/src/rendering/group_atlas.dart',
        'lib/src/rendering/liquid_glass.dart',
        'lib/src/rendering/liquid_glass_blend_group.dart',
        'lib/src/rendering/render_liquid_glass_geometry.dart',
        'lib/src/rendering/shape_set.dart',
        'lib/src/rendering/tiling_drift.dart',
      },
    ),
    Ban(
      'shader-constant',
      r'(?<![\d.])(?:0\.2126|0\.7152|0\.0722|0\.258819|0\.965926)(?!\d)',
      reason:
          'A number Dart and the shaders share is written once, in the '
          "table the shaders' constants are generated from.",
      allowedIn: {'lib/src/painting/shader_constants.dart'},
    ),
    Ban(
      'copy-frost',
      r'\bfrostInPlace\(',
      reason:
          'A copy comes to hold a frost only where its layers are made: a '
          "read's corner in the frame and a page in an image. Every "
          'reader takes what the copy holds from there.',
      allowedIn: {
        'lib/src/rendering/copy_frost.dart',
        'lib/src/rendering/copy_read.dart',
        'lib/src/rendering/read.dart',
      },
    ),
    Ban(
      'shadow-blur',
      r'\bBlurStyle\.|\bMaskFilter\.blur\(',
      reason:
          'Glass casts its shadows by one law '
          '(LiquidGlassSilhouette.paintShadows): one fade, one reach, one '
          'cut. A blur anywhere else is a second law.',
      allowedIn: {'lib/src/painting/liquid_glass_shadow.dart'},
    ),
    Ban(
      'shape-switch',
      r'^\s*(?:case\s+)?(?:final\s+)?Liquid(?:RoundedSuperellipse|RoundedRectangle|Oval)\b[^;\n]*=>'
          r'|\b(?:is|case)\s+(?:final\s+)?Liquid(?:RoundedSuperellipse|RoundedRectangle|Oval)\b',
      reason:
          'What a shape is to the shaders is answered by its drawn '
          'values, and a fill by LiquidShape.paintInterior; only the clip '
          "picks Flutter's clip widget for each shape.",
      allowedIn: {
        'lib/src/painting/liquid_shape.dart',
        'lib/src/rendering/drawn_values.dart',
        'lib/src/widgets/optimized_clip.dart',
      },
    ),
    Ban(
      'full-glass',
      r'\bisShaderFilterSupported\b|\bkIsWeb\b',
      reason:
          'Whether full glass draws is one state for the process '
          '(FullGlass), and whether the engine draws shader filters one '
          'fact beside it; a layer or a read that asked the engine itself '
          'would answer a third way.',
      allowedIn: {'lib/src/rendering/full_glass.dart'},
    ),
    Ban(
      'blur-reach',
      r'[sS]igma\s*\*\s*[34](?:\.0*)?\b|\b[34](?:\.0*)?\s*\*\s*\w*[sS]igma\b'
          r'|\b_?blurReach\b',
      reason:
          "How far a blur reads past what it covers is Impeller's "
          '(ImpellerBlur.reach) where Impeller blurs, at the pixel ratio a '
          "backdrop filter layer finds in its view, and the shader's taps' "
          '(CopyNeed.reachAt) where a shader frosts.',
      allowedIn: {'lib/src/painting/impeller_blur.dart'},
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
