import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer_example/playground/inspector/grouped_list.dart';
import 'package:liquid_glass_renderer_example/playground/inspector/inspector.dart';
import 'package:liquid_glass_renderer_example/playground/playground_state.dart';
import 'package:liquid_glass_renderer_example/playground/stage.dart';
import 'package:stupid_simple_sheet/stupid_simple_sheet.dart';

/// Window width from which the sheet floats beside the stage instead of
/// rising across it.
const wideBreakpoint = 760.0;

/// The inspector in a sheet that floats below the stage's top controls.
///
/// Like a non-modal iOS sheet it has no barrier, so the stage stays visible
/// and interactive while the glass is tuned. It holds no glass, and the route
/// only exists while the sheet is open, so a closed sheet costs nothing.
/// Scrolling the inspector past its top drags the sheet down.
class SettingsSheetRoute extends StupidSimpleSheetRoute<void> {
  /// Opens at half height on phones, where it can be pulled up to full
  /// height, and at full height on [wide] windows.
  SettingsSheetRoute({required PlaygroundState state, required bool wide})
    : super(
        barrierColor: null,
        snappingConfig: wide
            ? SheetSnappingConfig.full
            : const SheetSnappingConfig([0.5, 1], initialSnap: 0.5),
        child: _SettingsSheet(state: state),
      );

  @override
  Widget buildModalBarrier() => const SizedBox.shrink();
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.state});

  final PlaygroundState state;

  static const _wideWidth = 380.0;
  static const _wideInset = 16.0;
  static const _phoneInset = 8.0;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= wideBreakpoint;
        final inset = wide ? _wideInset : _phoneInset;
        final bottom = wide ? padding.bottom + inset : inset;
        final sheet = _Panel(
          grabber: !wide,
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: true,
            child: Inspector(
              state: state,
              padding: EdgeInsets.only(
                top: wide ? 0 : _Grabber.extent,
                bottom: math.max(0, padding.bottom - bottom),
              ),
            ),
          ),
        );
        return Padding(
          padding: EdgeInsets.fromLTRB(
            padding.left + inset,
            padding.top + Stage.topControlsExtent,
            padding.right + inset,
            bottom,
          ),
          child: wide
              ? Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(width: _wideWidth, child: sheet),
                )
              : sheet,
        );
      },
    );
  }
}

/// The sheet's surface: opaque grouped background with [panelRadius] on all
/// corners, which the inspector's cards and buttons are concentric with.
class _Panel extends StatelessWidget {
  const _Panel({required this.grabber, required this.child});

  final bool grabber;
  final Widget child;

  static const _radius = BorderRadius.all(Radius.circular(panelRadius));

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: const ShapeDecoration(
          shape: RoundedSuperellipseBorder(borderRadius: _radius),
          shadows: [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 32,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRSuperellipse(
          borderRadius: _radius,
          child: ColoredBox(
            color: CupertinoColors.systemGroupedBackground.resolveFrom(context),
            child: grabber
                ? Stack(
                    children: [
                      child,
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _Grabber(),
                      ),
                    ],
                  )
                : child,
          ),
        ),
      ),
    );
  }
}

/// The iOS sheet grabber, shown when the sheet can be resized.
class _Grabber extends StatelessWidget {
  const _Grabber();

  static const extent = 10.0;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Center(
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              shape: const StadiumBorder(),
            ),
            child: const SizedBox(width: 36, height: 5),
          ),
        ),
      ),
    );
  }
}
