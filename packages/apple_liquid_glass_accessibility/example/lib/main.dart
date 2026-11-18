import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_accessibility/apple_liquid_glass_accessibility.dart';
import 'package:flutter/widgets.dart';

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) => WidgetsApp(
    color: const Color(0xFF007AFF),
    builder: (context, _) => const GlassPlatformTraits(
      child: GlassTheme(data: GlassThemeData(), child: _Settings()),
    ),
  );
}

class _Settings extends StatelessWidget {
  const _Settings();

  @override
  Widget build(BuildContext context) {
    final traits = GlassTraits.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF9500), Color(0xFFAF52DE), Color(0xFF007AFF)],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (name, value) in [
                ('Reduce Motion', traits.reduceMotion),
                ('Reduce Transparency', traits.reduceTransparency),
                ('Show Borders', traits.showBorders),
                ('Prefer Cross-Fade Transitions', traits.prefersCrossFade),
                (
                  'Reduced Resource Usage',
                  traits.prefersReducedResourceUsage,
                ),
              ])
                Text(
                  '$name: ${value ? 'on' : 'off'}',
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 17,
                    height: 1.6,
                  ),
                ),
              const Spacer(),
              Center(
                child: GlassButton(
                  onPressed: () {},
                  child: const Text('Glass'),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
