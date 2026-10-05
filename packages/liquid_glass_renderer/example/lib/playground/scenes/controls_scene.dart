import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/bottom_bar/ios_bottom_bar.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/control_glass.dart';
import 'package:liquid_glass_renderer_example/playground/sheet_avoidance.dart';
import 'package:motor/motor.dart';

/// Everyday controls: navigation buttons at the top and a bottom bar. Every
/// shape samples the one shared backdrop capture.
class ControlsScene extends StatelessWidget {
  const ControlsScene({required this.fake, super.key});

  /// Whether the stage renders fake glass, which the bottom bar's loupe
  /// layer has to match.
  final ValueListenable<bool> fake;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
            topControlsSide,
            topControlsTop,
            topControlsSide + topControlSize + topControlsSpacing,
            0,
          ),
          child: _TopControls(),
        ),
        const Spacer(),
        AvoidSheet(
          alignment: Alignment.bottomCenter,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  bottomBarSide,
                  0,
                  bottomBarSide,
                  bottomBarGap(bottomInset),
                ),
                child: _BottomBar(fake: fake),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Distance of the bottom bar from the sides of the stage, as on iOS 27.
const bottomBarSide = 20.0;

/// Distance of the bottom bar from the bottom of the screen, for a home
/// indicator inset of [bottomInset].
///
/// The iOS 27 tab bar reaches 13.5 pt into the 34 pt home indicator inset
/// of an iPhone 17 Pro, ending 20.5 pt above the screen's edge.
double bottomBarGap(double bottomInset) => math.max(bottomInset - 13.5, 20);

/// Distance of the row of glass buttons along the top of the stage from the
/// top of the stage's safe area. iOS 27 centers its 44 pt toolbar buttons
/// 22 pt below it.
const topControlsTop = 0.0;

/// Distance of the row of glass buttons along the top of the stage from the
/// sides of the stage's safe area.
const topControlsSide = 16.0;

/// Height of the glass buttons along the top of the stage, as on iOS 27.
const topControlSize = 44.0;

/// Gap between neighboring glass buttons along the top of the stage.
const topControlsSpacing = 8.0;

/// The back button, a visibility toggle and the share/more capsule. The
/// toggle springs the capsule's [LiquidGlassVisibility] between 0 and 1, to
/// show every glass factor fading together.
class _TopControls extends StatefulWidget {
  const _TopControls();

  @override
  State<_TopControls> createState() => _TopControlsState();
}

class _TopControlsState extends State<_TopControls> {
  var _visible = true;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const CircleButton(icon: CupertinoIcons.chevron_left),
        const SizedBox(width: topControlsSpacing),
        CircleButton(
          icon: _visible ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
          semanticLabel: _visible ? 'Hide capsule' : 'Show capsule',
          onPressed: () => setState(() => _visible = !_visible),
        ),
        const Spacer(),
        SingleMotionBuilder(
          motion: const CupertinoMotion.smooth(
            duration: Duration(milliseconds: 600),
          ),
          value: _visible ? 1 : 0,
          builder: (context, visibility, child) =>
              LiquidGlassVisibility(visibility: visibility, child: child!),
          child: const _ButtonCapsule(
            icons: [CupertinoIcons.square_arrow_up, CupertinoIcons.ellipsis],
          ),
        ),
      ],
    );
  }
}

/// The mini player, tab bar and search button, adapting to the backdrop as
/// one group.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.fake});

  final ValueListenable<bool> fake;

  static const _tabs = [
    BottomBarTab(icon: CupertinoIcons.house_fill, label: 'Home'),
    BottomBarTab(icon: CupertinoIcons.square_grid_2x2_fill, label: 'New'),
    BottomBarTab(
      icon: CupertinoIcons.dot_radiowaves_left_right,
      label: 'Radio',
    ),
    BottomBarTab(icon: CupertinoIcons.music_albums_fill, label: 'Library'),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: fake,
      builder: (context, fake, _) => IosBottomBar(
        tabs: _tabs,
        accessory: const NowPlayingAccessory(),
        fake: fake,
      ),
    );
  }
}

class CircleButton extends StatelessWidget {
  const CircleButton({
    required this.icon,
    this.size = topControlSize,
    this.onPressed,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final double size;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final glass = ControlGlass(
      shape: const LiquidOval(),
      child: SizedBox.square(
        dimension: size,
        child: Icon(icon, semanticLabel: semanticLabel),
      ),
    );
    if (onPressed == null) return glass;
    return Semantics(
      button: true,
      child: GestureDetector(onTap: onPressed, child: glass),
    );
  }
}

class _ButtonCapsule extends StatelessWidget {
  const _ButtonCapsule({required this.icons});

  final List<IconData> icons;

  @override
  Widget build(BuildContext context) {
    return ControlGlass(
      shape: const LiquidRoundedSuperellipse(borderRadius: 24),
      child: SizedBox(
        height: topControlSize,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final icon in icons) SizedBox(width: 45, child: Icon(icon)),
            ],
          ),
        ),
      ),
    );
  }
}
