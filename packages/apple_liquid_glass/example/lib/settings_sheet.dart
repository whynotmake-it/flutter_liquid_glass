import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/app.dart';
import 'package:apple_liquid_glass_example/perf/device_check.dart';
import 'package:apple_liquid_glass_example/settings.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

Future<void> showGallerySettings(BuildContext context) => showGlassSheet<void>(
  context,
  detents: const [GlassSheetDetent.medium, GlassSheetDetent.large],
  showDragHandle: true,
  semanticLabel: 'Settings',
  builder: (context) => const _SettingsSheet(),
);

enum _Appearance {
  system('Auto', null),
  light('Light', Brightness.light),
  dark('Dark', Brightness.dark);

  const _Appearance(this.title, this.brightness);

  final String title;
  final Brightness? brightness;
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context) {
    final settings = GallerySettingsScope.of(context).value;
    void update(GallerySettings Function(GallerySettings s) change) =>
        GallerySettingsScope.update(context, change);
    return ListView(
      controller: GlassSheet.scrollControllerOf(context),
      padding: const EdgeInsets.only(top: 24, bottom: 40),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: GlassDefaultTextStyle(
            role: GlassTextRole.title2,
            child: Text(
              'Settings',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        GlassListSection(
          header: const Text('Renderer'),
          footer: const Text(
            'Every surface redraws with the new renderer at once, mid-press '
            'too. Liquid refracts, Fake only blurs, Flat reads no backdrop.',
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: GlassSegmentedControl<GalleryRenderer>(
                segments: [
                  for (final renderer in GalleryRenderer.values)
                    GlassSegment(value: renderer, label: Text(renderer.title)),
                ],
                groupValue: settings.renderer,
                onChanged: (renderer) =>
                    update((s) => s.copyWith(renderer: renderer)),
              ),
            ),
          ],
        ),
        GlassListSection(
          header: const Text('Appearance'),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: GlassSegmentedControl<_Appearance>(
                segments: [
                  for (final appearance in _Appearance.values)
                    GlassSegment(
                      value: appearance,
                      label: Text(appearance.title),
                    ),
                ],
                groupValue: _Appearance.values.firstWhere(
                  (a) => a.brightness == settings.brightness,
                ),
                onChanged: (appearance) => update(
                  (s) => s.copyWith(brightness: () => appearance.brightness),
                ),
              ),
            ),
            GlassListRow(
              title: const Text('Accent'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final accent in GalleryAccent.values)
                    _Swatch(
                      accent: accent,
                      selected: accent == settings.accent,
                      onTap: () => update((s) => s.copyWith(accent: accent)),
                    ),
                ],
              ),
            ),
          ],
        ),
        GlassListSection(
          header: const Text('Liquid Glass'),
          footer: Text(
            settings.glassTint == null
                ? 'Follows the slider in Settings, Appearance, on iOS 27.'
                : 'Set here: the system slider no longer applies.',
          ),
          children: [
            GlassListRow(
              child: Row(
                children: [
                  const Text('Clear'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassSlider(
                      value: GlassTraits.of(context).glassTintAmount,
                      semanticLabel: 'Glass',
                      onChanged: (value) =>
                          update((s) => s.copyWith(glassTint: () => value)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('Tinted'),
                ],
              ),
            ),
            if (settings.glassTint != null)
              GlassListRow(
                title: const Text('Follow System'),
                onPressed: () =>
                    update((s) => s.copyWith(glassTint: () => null)),
              ),
          ],
        ),
        GlassListSection(
          header: const Text('Accessibility'),
          footer: const Text(
            'The same traits the apple_liquid_glass_accessibility plugin '
            'reads from the system settings.',
          ),
          children: [
            _Toggle(
              icon: CupertinoIcons.circle_lefthalf_fill,
              color: GlassColors.systemGray,
              title: 'Reduce Transparency',
              value: settings.reduceTransparency,
              onChanged: (on) =>
                  update((s) => s.copyWith(reduceTransparency: on)),
            ),
            _Toggle(
              icon: CupertinoIcons.square_on_square,
              color: GlassColors.systemBlue,
              title: 'Show Borders',
              value: settings.showBorders,
              onChanged: (on) => update((s) => s.copyWith(showBorders: on)),
            ),
            _Toggle(
              icon: CupertinoIcons.arrow_right_arrow_left,
              color: GlassColors.systemGreen,
              title: 'Prefer Cross-Fade',
              value: settings.crossFade,
              onChanged: (on) => update((s) => s.copyWith(crossFade: on)),
            ),
          ],
        ),
        GlassListSection(
          header: const Text('Performance'),
          footer: const Text(
            'The frame meter shows frames a second and the time a frame '
            'takes on each thread, over everything. Device check measures '
            'how this phone draws glass and makes a report to send.',
          ),
          children: [
            _Toggle(
              icon: CupertinoIcons.speedometer,
              color: GlassColors.systemGreen,
              title: 'Frame meter',
              value: settings.frameMeter,
              onChanged: (on) => update((s) => s.copyWith(frameMeter: on)),
            ),
            GlassListRow(
              title: const Text('Device check'),
              onPressed: () => runDeviceCheck(
                leave: () => runApp(GalleryApp(settings: settings)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color color;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => GlassListRow(
    leading: SettingsIcon(icon: icon, color: color),
    title: Text(title),
    trailing: GlassSwitch(value: value, onChanged: onChanged),
    onPressed: () => onChanged(!value),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final GalleryAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = GlassDynamicColor.resolve(accent.color, context);
    return GestureDetector(
      onTap: onTap,
      child: Semantics(
        button: true,
        selected: selected,
        label: accent.title,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 26,
            height: 26,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? color : const Color(0x00000000),
                width: 2,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}
