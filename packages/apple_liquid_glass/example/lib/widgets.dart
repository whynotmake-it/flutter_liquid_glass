import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/settings_sheet.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

/// The rounded square icon of an iOS Settings row.
class SettingsIcon extends StatelessWidget {
  const SettingsIcon({required this.icon, required this.color, super.key});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      color: GlassDynamicColor.resolve(color, context),
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(8)),
    ),
    child: SizedBox.square(
      dimension: 30,
      child: Icon(icon, size: 18, color: const Color(0xFFFFFFFF)),
    ),
  );
}

/// The settings item of a page's navigation bar.
GlassBarItem settingsItem(BuildContext context) => GlassBarItem(
  icon: const Icon(CupertinoIcons.gear),
  semanticLabel: 'Settings',
  onPressed: () => showGallerySettings(context),
);

/// Text that stays legible on a photo.
class PhotoText extends StatelessWidget {
  const PhotoText(this.text, {this.size = 15, this.weight, super.key});

  final String text;
  final double size;
  final FontWeight? weight;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(
      color: const Color(0xFFFFFFFF),
      fontSize: size,
      fontWeight: weight,
      letterSpacing: size > 24 ? -0.6 : -0.2,
      shadows: const [Shadow(color: Color(0x66000000), blurRadius: 12)],
    ),
  );
}
