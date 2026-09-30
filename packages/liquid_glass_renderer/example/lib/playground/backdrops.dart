import 'package:flutter/cupertino.dart';

/// Backdrops for judging glass: photographs for color and tone, plus
/// high-contrast type and a grid that make refraction easy to read.
enum Backdrop {
  coast('Coast', 'assets/backdrops/coast.webp'),
  city('Night', 'assets/backdrops/city.webp'),
  bloom('Bloom', 'assets/backdrops/bloom.webp'),
  type('Type', null),
  grid('Grid', null);

  const Backdrop(this.label, this.asset);

  final String label;

  /// The photograph for this backdrop, or `null` for painted backdrops.
  final String? asset;

  static Iterable<String> get photoAssets =>
      values.map((backdrop) => backdrop.asset).nonNulls;
}

/// Paints [backdrop] edge to edge.
class BackdropView extends StatelessWidget {
  const BackdropView({required this.backdrop, super.key});

  final Backdrop backdrop;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: switch (backdrop) {
        Backdrop.type => const _TypeBackdrop(),
        Backdrop.grid => const _GridBackdrop(),
        _ => Image.asset(
          backdrop.asset!,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      },
    );
  }
}

/// A small preview of [backdrop] for the picker.
class BackdropThumbnail extends StatelessWidget {
  const BackdropThumbnail({required this.backdrop, super.key});

  final Backdrop backdrop;

  @override
  Widget build(BuildContext context) {
    final asset = backdrop.asset;
    if (asset != null) {
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        cacheWidth: 160,
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: 360,
        height: 480,
        child: BackdropView(backdrop: backdrop),
      ),
    );
  }
}

class _TypeBackdrop extends StatelessWidget {
  const _TypeBackdrop();

  static const _ink = Color(0xFF111111);
  static const _accent = Color(0xFFE5402F);

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFF7F5F0),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(
            width: 700,
            height: 1400,
            child: Padding(
              padding: EdgeInsets.fromLTRB(28, 56, 28, 0),
              child: DefaultTextStyle(
                style: TextStyle(
                  color: _ink,
                  fontSize: 15,
                  height: 1.45,
                  letterSpacing: -0.1,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ISSUE 27 — OPTICS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: _accent,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Light, bent\nbeautifully.',
                      style: TextStyle(
                        fontSize: 64,
                        height: 0.98,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -2.4,
                      ),
                    ),
                    SizedBox(height: 18),
                    _Rule(),
                    SizedBox(height: 14),
                    SizedBox(
                      width: 640,
                      child: Text(_body),
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Aa Bb Cc 0123456789',
                      style: TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w300,
                        letterSpacing: -1,
                      ),
                    ),
                    SizedBox(height: 16),
                    _Rule(),
                    SizedBox(height: 14),
                    SizedBox(
                      width: 640,
                      child: Text(
                        _body,
                        style: TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ),
                    SizedBox(height: 22),
                    Text(
                      'Refraction.',
                      style: TextStyle(
                        fontSize: 88,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -3.5,
                      ),
                    ),
                    SizedBox(height: 16),
                    SizedBox(width: 640, child: Text(_body)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _body =
      'Glass is a flat face with a rounded bevel. Only the bevel refracts: '
      'straight lines bend as they reach the rim, text stays crisp through '
      'the middle, and a thin glint traces the edge where light catches it. '
      'Drag a shape across these lines to see how far inside the silhouette '
      'the backdrop is sampled, and how shapes merge when they meet.';
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 640,
      height: 2,
      child: ColoredBox(color: _TypeBackdrop._ink),
    );
  }
}

class _GridBackdrop extends StatelessWidget {
  const _GridBackdrop();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _GridPainter(), child: SizedBox.expand());
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  static const _cell = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );

    final bands = [
      const Color(0xFFFF3B30),
      const Color(0xFFFF9500),
      const Color(0xFFFFCC00),
      const Color(0xFF34C759),
      const Color(0xFF007AFF),
      const Color(0xFFAF52DE),
    ];
    const bandHeight = _cell * 2;
    final bandTop = (size.height * 0.62 / _cell).floorToDouble() * _cell;
    for (var i = 0; i < bands.length; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, bandTop + i * bandHeight, size.width, bandHeight),
        Paint()..color = bands[i],
      );
    }

    final minor = Paint()
      ..color = const Color(0x33000000)
      ..strokeWidth = 1;
    final major = Paint()
      ..color = const Color(0xFF000000)
      ..strokeWidth = 2;
    var index = 0;
    for (var x = 0.0; x <= size.width; x += _cell, index++) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        index % 4 == 0 ? major : minor,
      );
    }
    index = 0;
    for (var y = 0.0; y <= size.height; y += _cell, index++) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        index % 4 == 0 ? major : minor,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}
