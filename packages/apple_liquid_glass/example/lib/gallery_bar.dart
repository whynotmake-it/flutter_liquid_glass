import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/settings.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

/// The items at the trailing end of every page's navigation bar, the same
/// two in the same places: the renderer, which draws the whole app in glass
/// or flat, and the settings.
List<GlassBarEntry> galleryItems(BuildContext context) {
  final flat =
      GallerySettingsScope.of(context).value.renderer == GalleryRenderer.flat;
  return [
    GlassBarItem(
      icon: Icon(flat ? CupertinoIcons.square : CupertinoIcons.drop_fill),
      semanticLabel: flat ? 'Draw in glass' : 'Draw flat',
      onPressed: () => GallerySettingsScope.update(
        context,
        (settings) => settings.copyWith(
          renderer: flat ? GalleryRenderer.liquid : GalleryRenderer.flat,
        ),
      ),
    ),
    settingsItem(context),
  ];
}
