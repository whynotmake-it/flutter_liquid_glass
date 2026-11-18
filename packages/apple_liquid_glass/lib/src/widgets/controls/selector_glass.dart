import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// The glass of a selector, the segmented control's and the tab bar's: its
/// body as [role] tinted [background], and, while an item is selected,
/// UIKit's lifted lens ([GlassLens.lifted]) tinted [thumb], both resolved
/// in the selector's states.
///
/// On the iPhone 16 Pro references the lifted lens shows a segmented
/// track's edges 0.8125 of its height apart, and with the bend of its glass
/// a swollen tab bar's 0.890 (0.886 on the liquid renderer).
@internal
class SelectorGlass extends StatelessWidget {
  /// The glass of the selector [details] describes.
  const SelectorGlass({
    required this.details,
    required this.role,
    required this.background,
    required this.thumb,
    super.key,
  });

  /// The selector.
  final GlassSelectorDetails details;

  /// The role of the selector's body: a track or a bar.
  final GlassRole role;

  /// The body's tint, or null for none.
  final WidgetStateProperty<Color?>? background;

  /// The lens's tint, or null for none.
  final WidgetStateProperty<Color?>? thumb;

  @override
  Widget build(BuildContext context) {
    Glass glass(WidgetStateProperty<Color?>? tint) =>
        Glass.regular(tint: tint?.resolve(details.states));

    return Stack(
      children: [
        Positioned.fill(
          child: GlassSurface.live(
            role: role,
            glass: glass(background),
            frame: details.body,
            child: const SizedBox.expand(),
          ),
        ),
        details.items(
          lens: details.selectedIndex == null
              ? null
              : GlassSurface.live(
                  role: GlassRole.lens,
                  lens: const GlassLens.lifted(),
                  lensContent: details.lensContent,
                  glass: glass(thumb),
                  frame: details.lens,
                  child: const SizedBox.expand(),
                ),
        ),
      ],
    );
  }
}
