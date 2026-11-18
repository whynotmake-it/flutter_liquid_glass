import 'dart:math' as math;

import 'package:flutter/widgets.dart';

enum Wallpaper {
  aurora('Aurora'),
  alpine('Alpine'),
  bloom('Bloom'),
  coast('Coast'),
  city('City'),
  dunes('Dunes');

  const Wallpaper(this.title);

  final String title;

  ImageProvider get image => AssetImage('assets/backdrops/$name.webp');
}

/// A wallpaper that drifts and breathes slowly while [drifts], so the glass
/// over it has something moving to bend.
class DriftingWallpaper extends StatefulWidget {
  const DriftingWallpaper({
    required this.wallpaper,
    this.drifts = true,
    super.key,
  });

  final Wallpaper wallpaper;
  final bool drifts;

  @override
  State<DriftingWallpaper> createState() => _DriftingWallpaperState();
}

class _DriftingWallpaperState extends State<DriftingWallpaper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  );

  @override
  void initState() {
    super.initState();
    if (widget.drifts) _drift.repeat();
  }

  @override
  void didUpdateWidget(DriftingWallpaper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.drifts && !_drift.isAnimating) {
      _drift.repeat();
    } else if (!widget.drifts) {
      _drift.stop();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 700),
      child: AnimatedBuilder(
        key: ValueKey(widget.wallpaper),
        animation: _drift,
        builder: (context, child) {
          final a = _drift.value * 2 * math.pi;
          final transform = Matrix4.translationValues(
            math.sin(a) * 24,
            math.cos(a * 2) * 16,
            0,
          );
          transform.scaleByDouble(
            1.14 + math.sin(a) * 0.04,
            1.14 + math.sin(a) * 0.04,
            1,
            1,
          );
          return Transform(
            transform: transform,
            alignment: Alignment.center,
            child: child,
          );
        },
        child: Image(
          image: widget.wallpaper.image,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      ),
    ),
  );
}
