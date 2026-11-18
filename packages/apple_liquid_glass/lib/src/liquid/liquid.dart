import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/liquid/lens_content.dart';
import 'package:apple_liquid_glass/src/liquid/lens_shadows.dart';
import 'package:apple_liquid_glass/src/liquid/scroll_edge.dart';
import 'package:apple_liquid_glass/src/liquid/underlay_layers.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/widgets.dart';

part 'package:apple_liquid_glass/src/liquid/liquid_group.dart';

/// The liquid renderer: every surface is liquid glass, and the members of
/// a group share one glass layer.
///
/// A lone body whose [GlassFrame.outline] has a field is shaded from that
/// field in a layer of its own, which casts its shadow by the field's edge;
/// an outlined body in a group or without a field draws flat.
/// The renderer chooses from the frame the surface builds with, not per
/// frame.
///
/// A surface outside a group draws as a group of one, and a track as a
/// plain fill, as iOS draws one. A lens or knob is an opaque platter at
/// rest and gets a glass layer of its own over the platter only while it
/// is lifted.
///
/// Layers use the fitted iOS 27 settings: clear for clear glass (a group
/// only when all its members are clear), regular in the ambient brightness
/// ([GlassTraits.brightness]) otherwise, both at the Liquid Glass slider's
/// position ([GlassTraits.glassTintAmount]).
///
/// Under Reduce Transparency the surfaces draw flat, an unmeasured
/// stand-in for iOS's frosted glass.
///
/// A body whose control is focused from the keyboard draws Flutter's
/// Cupertino focus ring outside its shape, and a hovered one a pressed
/// body's wash at half strength over it ([GlassSurfaceDetails.states]),
/// both plain painting over the glass that costs it no pass.
///
/// Until full glass has loaded, and where it does not, the layers draw fake
/// glass, as [FakeGlassRenderer] does.
base class LiquidGlassRenderer extends GlassRenderer {
  /// Creates the liquid renderer.
  const LiquidGlassRenderer();

  /// Whether every layer draws fake glass.
  @internal
  bool get fake => false;

  @override
  Widget buildSurface(BuildContext context, GlassSurfaceDetails details) =>
      buildHighlights(context, details, _body(context, details));

  Widget _body(BuildContext context, GlassSurfaceDetails details) {
    if (GlassTraits.of(context).reduceTransparency ||
        details.role == GlassRole.track) {
      return FlatGlassRenderer.flatSurface(context, details);
    }
    if (details.role == GlassRole.lens) {
      return _LiquidLens(details: details, fake: fake);
    }
    final grouped = _LiquidGroupScope.maybeOf(context) != null;
    if (details.frame.value.outline case final outline?
        when grouped || !outline.hasField) {
      return FlatGlassRenderer.flatSurface(context, details);
    }
    if (grouped) return _LiquidSurface(details: details);
    return _LiquidGroup(
      fake: fake,
      glass: details.glass,
      body: details.frame,
      child: _LiquidSurface(details: details),
    );
  }

  @override
  Widget buildScrollEdge(
    BuildContext context,
    GlassScrollEdgeDetails details,
  ) => GlassTraits.of(context).reduceTransparency
      ? super.buildScrollEdge(context, details)
      : ScrollEdge(details: details);

  @override
  Widget buildGroup(BuildContext context, GlassGroupDetails details) {
    if (GlassTraits.of(context).reduceTransparency) return details.child;
    return _LiquidGroup(
      fake: fake,
      blend: details.merge.spacing,
      child: details.child,
    );
  }

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  /// The iOS 27 material of [glass] in [brightness], at the Liquid Glass
  /// slider position [sliderPosition].
  @internal
  static LiquidGlassMaterial materialOf(
    Glass glass,
    Brightness brightness, {
    double sliderPosition = 0,
  }) => glass.isClear
      ? LiquidGlassMaterial.ios27Clear(
          sliderPosition: sliderPosition,
          tint: glass.tint,
        )
      : LiquidGlassMaterial.ios27Regular(
          brightness: brightness,
          sliderPosition: sliderPosition,
          tint: glass.tint,
        );

  /// The shadows a body of [role] made of [material] casts.
  ///
  /// Regular glass casts the shadow iOS 27 gives glass of its size, and
  /// clear glass casts none, as on iOS. The glass of a lifted lens casts no
  /// drop shadow either (read from UIKit on iOS 27.2; notes private): its
  /// shadows are the ring and inner shadow drawn over it
  /// ([LensShadowLaw]).
  @internal
  static List<LiquidGlassShadow> shadowsOf(
    GlassRole role,
    LiquidGlassMaterial material,
  ) => switch (role) {
    GlassRole.control || GlassRole.panel || GlassRole.bar => material.shadows,
    GlassRole.lens || GlassRole.track => const [],
  };
}

/// The liquid renderer on fake glass: every surface blurred and lit, with
/// no refraction. Cheaper than real glass, and the glass a platform without
/// shader filters, such as the web, can draw.
final class FakeGlassRenderer extends LiquidGlassRenderer {
  /// Creates the fake glass renderer.
  const FakeGlassRenderer();

  @override
  bool get fake => true;
}

// The tint [frame] gives a body whose glass has [own], crossing from it
// (or from none: an untinted iOS material is one with a transparent tint)
// by the frame's amount, or null where the frame keeps the glass's look.
Color? _tintOf(GlassFrame frame, Color? own) {
  final tint = frame.tint;
  final amount = frame.tintAmount.clamp(0.0, 1.0);
  if (tint == null || amount == 0) return null;
  if (amount == 1) return tint;
  return Color.lerp(own ?? tint.withValues(alpha: 0), tint, amount);
}

/// The settings of [lens] lifted by [lift], its glass [height] across its
/// short side, or null where its frame names no rect.
///
/// Read from UIKit's lifted lenses on iOS 27.2 (tab bar 114 x 70,
/// segmented control 110 x 44, switch 58 x 38.3, slider 57.3 x 37; notes
/// private). The glass of a lifted lens bends its edge toward the middle by
/// 0.15 of its height over 0.1 of it, a small lens (a knob or thumb) by 0.3
/// over 0.18. A large lens parts the colors over its glass by seven reads,
/// the farthest 1 / 19 of its height from its place, along the way
/// [LiquidGlassSettings.aberration] describes, fading over 0.2 of the
/// height from the edge; a small one parts none. Under the glass the lens
/// pulls in its surroundings by its [GlassLens.pull]. Its rim is lit as at
/// rest. Bend, pull and parting grow with the lift. The glass shades
/// nothing itself: the shadow regular glass carries inside its rim is off,
/// and the lens's own shadows are drawn over it ([LensShadowLaw]).
///
/// The parting's reach is in points like every length here, 3.68 on the
/// tab bar's lens. Around that lens's rounded end a host capture puts red
/// and blue on the sides of the bar's edge the iPhone 16 Pro references
/// do: 30 degrees from the top blue lies 3.0 points deeper than red (the
/// phone: 2.3), 120 degrees from it red lies 2.3 deeper (the phone: 2.4).
///
/// NEAR: a read beside a point takes the glass for a capsule of the lens,
/// and past its edge reads what lies under the lens's layer, where UIKit
/// reads the screen beside the lens.
///
/// At rest UIKit's lens configuration bends what is behind a small lens by
/// 50 and blurs it by 6, and a large lens rests clear. Neither mixes a wide
/// blur into what it shows. A lens without a height keeps the bevel of the
/// glass it rests as.
///
/// What a large lens selects lies over this glass, bent by a law of its
/// own and parted as the glass is ([LensContentLaw]).
LiquidGlassSettings _lensSettings(
  LiquidGlassSettings base,
  double lift, {
  required GlassLens lens,
  required double? height,
}) {
  final l = lift.clamp(0.0, 1.0);
  final small = lens.small;
  final settings = base.copyWith(
    frost: LiquidGlassFrost.sigma(small ? 6 * (1 - l) : 0),
    haze: const LiquidGlassHaze.none(),
    dispersion: 0,
    bevelShadowStrength: 0,
    backdropPull: lens.pull * l,
    backdropPullDepth: lens.pullHeight,
  );
  if (height == null) {
    return small ? settings.copyWith(refractionAmount: 50 * (1 - l)) : settings;
  }
  final lifted = (small ? 0.3 : 0.15) * height;
  final bevel = (small ? 0.18 : 0.1) * height;
  return settings.copyWith(
    refractionAmount: small ? 50 + (lifted - 50) * l : lifted * l,
    refractionHeight: small
        ? base.refractionHeight + (bevel - base.refractionHeight) * l
        : bevel,
    aberration: small ? 0 : LensContentLaw.parting(height, lift: l),
    aberrationDepth: LensContentLaw.partingDepth(height),
  );
}

/// The appearance of the glass of [lens], [visibility] of the way from its
/// resting platter to glass.
///
/// Read from UIKit's lifted lenses on iOS 27.2 (notes private). The face of
/// a selection changes no color. The face of a knob or thumb lifts black to
/// a tenth of white and leaves white where it is, `0.1 + 0.9 * c` for every
/// channel: a tenth of white lies over what the lens shows, under its
/// shadows and its rim light. On the iPhone 16 Pro references a held slider
/// thumb over a black page shows 25 of 255.
LiquidGlassAppearance _lensAppearance(GlassLens lens, double visibility) =>
    lens.small
    ? LiquidGlassAppearance(tint: _smallLensFace, visibility: visibility)
    : LiquidGlassAppearance(visibility: visibility);

const _smallLensFace = Color.from(alpha: 0.1, red: 1, green: 1, blue: 1);

class _LiquidSurface extends StatefulWidget {
  const _LiquidSurface({required this.details});

  final GlassSurfaceDetails details;

  @override
  State<_LiquidSurface> createState() => _LiquidSurfaceState();
}

class _LiquidSurfaceState extends State<_LiquidSurface> {
  late final _shape = ValueNotifier(_shapeFrame);
  late LiquidGlassMaterial _material;
  late Brightness _brightness;
  _LiquidGroupState? _group;

  ValueListenable<GlassFrame> get _source => widget.details.frame;

  LiquidGlassShapeFrame get _shapeFrame {
    final frame = _source.value;
    final role = widget.details.role;
    final tint = _tintOf(frame, widget.details.glass.tint);
    final appearance = role == GlassRole.lens
        ? _lensAppearance(
            widget.details.lens,
            GlassFrame.glassnessAt(frame.lift),
          )
        : tint == null
        ? _material.appearance
        : LiquidGlassRenderer.materialOf(
            widget.details.glass.isClear
                ? Glass.clear(tint: tint)
                : Glass.regular(tint: tint),
            _brightness,
          ).appearance;
    return LiquidGlassShapeFrame(
      shape: frame.shape,
      appearance: frame.opacity >= 1
          ? appearance
          : appearance.copyWith(
              visibility: appearance.visibility * frame.opacity.clamp(0.0, 1.0),
            ),
      shadows: LiquidGlassRenderer.shadowsOf(role, _material),
      rect: frame.bodyRect,
      scaleX: frame.scaleX,
      scaleY: frame.scaleY,
      glow: switch (frame.glow) {
        final glow? => LiquidGlassGlow(
          center: glow.center,
          radius: glow.radius,
          gain: glow.gainOn(widget.details.glass, _brightness),
          wash: glow.wash,
        ),
        null => null,
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _source.addListener(_onFrame);
  }

  @override
  void didUpdateWidget(_LiquidSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.details.frame != _source) {
      oldWidget.details.frame.removeListener(_onFrame);
      _source.addListener(_onFrame);
    }
  }

  @override
  void dispose() {
    _source.removeListener(_onFrame);
    _group?.reportGlass(this, null);
    _shape.dispose();
    super.dispose();
  }

  void _onFrame() => _shape.value = _shapeFrame;

  @override
  Widget build(BuildContext context) {
    final group = _LiquidGroupScope.maybeOf(context)!;
    if (!identical(group, _group)) {
      _group?.reportGlass(this, null);
      _group = group;
    }
    group.reportGlass(this, widget.details.glass);
    _brightness = GlassTraits.of(context).brightness;
    _material = LiquidGlassRenderer.materialOf(
      widget.details.glass,
      _brightness,
    );
    _shape.value = _shapeFrame;
    return LiquidGlass.live(
      frame: _shape,
      child: _LiquidGroupScope.outside(child: widget.details.child),
    );
  }
}
