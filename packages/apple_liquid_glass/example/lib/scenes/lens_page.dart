import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/gallery_bar.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

enum _Outline { circle, capsule, squircle }

/// A lens to drag over a page of text and a photo, to see what glass does
/// to what lies under it: the bend at its rim, the frost of regular glass,
/// a tint. The bar below changes its outline, size and glass, and adds a
/// second lens, which fuses with the first where they come close.
class LensPage extends StatefulWidget {
  const LensPage({super.key});

  @override
  State<LensPage> createState() => _LensPageState();
}

class _LensPageState extends State<LensPage> {
  static const _tints = <Color?>[
    null,
    Color(0x660A84FF),
    Color(0x66FF375F),
    Color(0x66FFD60A),
    Color(0x6630D158),
  ];

  // Where each lens's center lies, as a share of the page.
  final _centers = [
    ValueNotifier(const Alignment(-0.25, -0.35)),
    ValueNotifier(const Alignment(0.4, 0.1)),
  ];
  var _outline = _Outline.circle;
  var _size = 150.0;
  var _tint = 0;
  var _clear = true;
  var _two = false;

  @override
  void dispose() {
    for (final center in _centers) {
      center.dispose();
    }
    super.dispose();
  }

  Size get _lensSize => switch (_outline) {
    _Outline.capsule => Size(_size * 1.5, _size * 0.62),
    _ => Size.square(_size),
  };

  LiquidShape get _shape => switch (_outline) {
    _Outline.circle => const LiquidOval(),
    _Outline.capsule => LiquidRoundedSuperellipse.capsule,
    _Outline.squircle => LiquidRoundedSuperellipse(radius: _size * 0.28),
  };

  @override
  Widget build(BuildContext context) => GlassPageScaffold(
    backgroundColor: GlassColors.systemBackground,
    navigationBar: GlassNavigationBar(
      title: const Text('Lens'),
      previousPageTitle: 'Surface',
      backButtonDisplayMode: GlassBackButtonDisplayMode.minimal,
      trailing: galleryItems(context),
    ),
    child: Builder(
      builder: (context) {
        final padding = MediaQuery.paddingOf(context);
        return Padding(
          padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    fit: StackFit.expand,
                    children: [
                      const _Article(),
                      // One group draws both lenses, so they read the page
                      // once and fuse where they meet.
                      GlassGroup(
                        merge: const GlassMerge.spacing(28),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            for (final center
                                in _two ? _centers : [_centers[0]])
                              _Lens(
                                center: center,
                                area: constraints.biggest,
                                size: _lensSize,
                                shape: _shape,
                                glass: _clear
                                    ? Glass.clear(tint: _tints[_tint])
                                    : Glass.regular(tint: _tints[_tint]),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _bar(),
            ],
          ),
        );
      },
    ),
  );

  Widget _bar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: Column(
      children: [
        GlassSegmentedControl<_Outline>(
          segments: const [
            GlassSegment(value: _Outline.circle, label: Text('Circle')),
            GlassSegment(value: _Outline.capsule, label: Text('Capsule')),
            GlassSegment(value: _Outline.squircle, label: Text('Squircle')),
          ],
          groupValue: _outline,
          onChanged: (outline) => setState(() => _outline = outline),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(CupertinoIcons.circle, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: GlassSlider(
                value: _size,
                min: 90,
                max: 230,
                semanticLabel: 'Size',
                onChanged: (size) => setState(() => _size = size),
              ),
            ),
            const SizedBox(width: 10),
            const Icon(CupertinoIcons.circle, size: 26),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final (index, tint) in _tints.indexed)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _Swatch(
                  color: tint,
                  selected: index == _tint,
                  onPressed: () => setState(() => _tint = index),
                ),
              ),
            const Spacer(),
            GlassButton(
              onPressed: () => setState(() => _clear = !_clear),
              semanticLabel: _clear ? 'Clear glass' : 'Regular glass',
              child: Icon(
                _clear ? CupertinoIcons.drop : CupertinoIcons.drop_fill,
              ),
            ),
            const SizedBox(width: 10),
            GlassButton(
              onPressed: () => setState(() => _two = !_two),
              semanticLabel: _two ? 'Remove the second lens' : 'Add a lens',
              child: Icon(_two ? CupertinoIcons.minus : CupertinoIcons.plus),
            ),
          ],
        ),
      ],
    ),
  );
}

/// One lens: a glass body the finger drags about the page.
class _Lens extends StatelessWidget {
  const _Lens({
    required this.center,
    required this.area,
    required this.size,
    required this.shape,
    required this.glass,
  });

  final ValueNotifier<Alignment> center;
  final Size area;
  final Size size;
  final LiquidShape shape;
  final Glass glass;

  void _drag(DragUpdateDetails details) {
    final reach = Size(
      (area.width - size.width) / 2,
      (area.height - size.height) / 2,
    );
    if (reach.width <= 0 || reach.height <= 0) return;
    center.value = Alignment(
      (center.value.x + details.delta.dx / reach.width).clamp(-1, 1),
      (center.value.y + details.delta.dy / reach.height).clamp(-1, 1),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: center,
    builder: (context, at, child) => Align(alignment: at, child: child),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: _drag,
      child: SizedBox.fromSize(
        size: size,
        child: GlassSurface(
          shape: shape,
          glass: glass,
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onPressed,
  });

  final Color? color;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = GlassDynamicColor.resolve(GlassColors.label, context);
    return Semantics(
      button: true,
      selected: selected,
      label: color == null ? 'No tint' : 'Tint',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color?.withValues(alpha: 1),
            border: Border.all(
              color: label.withValues(alpha: selected ? 1 : 0.25),
              width: selected ? 2.5 : 1,
            ),
          ),
          child: color == null
              ? Icon(CupertinoIcons.nosign, size: 16, color: label)
              : null,
        ),
      ),
    );
  }
}

/// Something worth bending: lines of text at several sizes and a photo.
class _Article extends StatelessWidget {
  const _Article();

  @override
  Widget build(BuildContext context) {
    final label = GlassDynamicColor.resolve(GlassColors.label, context);
    final secondary = GlassDynamicColor.resolve(
      GlassColors.secondaryLabel,
      context,
    );
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        maxHeight: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What glass does',
                style: TextStyle(
                  color: label,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Drag the lens. Glass keeps what lies under it and bends it '
                'at the rim: a line that crosses the edge turns toward the '
                'middle, as it does through the edge of a real lens.',
                style: TextStyle(color: label, fontSize: 17, height: 1.35),
              ),
              const SizedBox(height: 14),
              ClipRSuperellipse(
                borderRadius: BorderRadius.circular(18),
                child: Image(
                  image: Wallpaper.bloom.image,
                  height: 190,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Clear glass passes the page through. Regular glass frosts '
                'it, so a label on it stays readable over anything. A tint '
                'fills either, and two lenses that come close flow into one '
                'body.',
                style: TextStyle(color: secondary, fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 14),
              for (final size in const [22.0, 17.0, 13.0, 11.0])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'The quick brown fox jumps over the lazy dog',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: TextStyle(color: label, fontSize: size),
                  ),
                ),
              const SizedBox(height: 8),
              const _Rules(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Straight lines, which show a bend best.
class _Rules extends StatelessWidget {
  const _Rules();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 220,
    width: double.infinity,
    child: CustomPaint(
      painter: _RulesPainter(
        GlassDynamicColor.resolve(GlassColors.label, context),
      ),
    ),
  );
}

class _RulesPainter extends CustomPainter {
  const _RulesPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final thin = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final strong = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1.5;
    for (var x = 0.0; x <= size.width; x += 16) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        x % 80 == 0 ? strong : thin,
      );
    }
    for (var y = 0.0; y <= size.height; y += 16) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        y % 80 == 0 ? strong : thin,
      );
    }
  }

  @override
  bool shouldRepaint(_RulesPainter old) => old.color != color;
}
