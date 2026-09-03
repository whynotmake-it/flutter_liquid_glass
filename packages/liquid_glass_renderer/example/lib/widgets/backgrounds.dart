import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer_example/state.dart';

/// Backdrops rendered behind all glass. Each is cheap to paint so the glass
/// refraction stays the star of the show.
class WallPaper extends StatefulWidget {
  const WallPaper({super.key});

  @override
  State<WallPaper> createState() => _WallPaperState();
}

class _WallPaperState extends State<WallPaper> {
  bool _reportedLoaded = false;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/wallpaper.webp',
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (!_reportedLoaded && (frame != null || wasSynchronouslyLoaded)) {
          _reportedLoaded = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) backgroundRevisionNotifier.value++;
          });
        }
        return child;
      },
    );
  }
}

class Grid extends StatelessWidget {
  const Grid({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFCEC5B4), Color(0xFFF2F0EA)],
        ),
      ),
      child: GridPaper(
        color: const Color(0xFF0F0B0A).withValues(alpha: 0.2),
      ),
    );
  }
}

/// A solid backdrop used for legibility checks.
class SolidBackdrop extends StatelessWidget {
  const SolidBackdrop({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: color);
  }
}
