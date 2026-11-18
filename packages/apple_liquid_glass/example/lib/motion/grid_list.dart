import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

/// Glass tiles that switch between a grid and a list in one `withSpring`.
///
/// Each tile adopts its layout item: the layout draws it in place, and its
/// glass takes the item's rect, scale and opacity as its frame, so the
/// glass slides and stretches while nothing lays out again.
class GridListSection extends StatefulWidget {
  const GridListSection({super.key});

  @override
  State<GridListSection> createState() => _GridListSectionState();
}

enum _Arrangement { grid, list }

class _GridListSectionState extends State<GridListSection> {
  static const _tiles = [
    (CupertinoIcons.sun_max_fill, 'Sun'),
    (CupertinoIcons.moon_fill, 'Moon'),
    (CupertinoIcons.cloud_fill, 'Clouds'),
    (CupertinoIcons.snow, 'Snow'),
    (CupertinoIcons.wind, 'Wind'),
    (CupertinoIcons.drop_fill, 'Rain'),
  ];

  final _layout = LayoutMotion();
  final _frames = <(Key, LiquidShape), MotionSelection<GlassFrame>>{};
  var _arrangement = _Arrangement.grid;

  // The layout knows each tile by its key.
  MotionSelection<GlassFrame> _frameOf(Key id, LiquidShape shape) =>
      _frames[(id, shape)] ??= _layout.select((layout) {
        final box = layout.laidOut(id);
        if (box == null) return GlassFrame(shape: shape);
        final item = layout.itemAt(id);
        return GlassFrame(
          shape: shape,
          rect: item.rect.shift(-box.topLeft),
          scaleX: item.scale,
          scaleY: item.scale,
          opacity: item.opacity,
        );
      });

  @override
  Widget build(BuildContext context) => GlassListSection(
    header: const Text('Grid and list'),
    footer: const Text(
      'One withSpring switches the layout; the glass of each tile follows '
      'its layout item.',
    ),
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: GlassSegmentedControl<_Arrangement>(
          segments: const [
            GlassSegment(
              value: _Arrangement.grid,
              label: Icon(CupertinoIcons.square_grid_2x2),
              semanticLabel: 'Grid',
            ),
            GlassSegment(
              value: _Arrangement.list,
              label: Icon(CupertinoIcons.list_bullet),
              semanticLabel: 'List',
            ),
          ],
          groupValue: _arrangement,
          onChanged: (arrangement) => withSpring(
            Spring.snappy,
            () => setState(() => _arrangement = arrangement),
          ),
        ),
      ),
      ClipRect(
        child: Stack(
          children: [
            Positioned.fill(
              child: Image(image: Wallpaper.coast.image, fit: BoxFit.cover),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: LayoutBuilder(
                builder: (context, constraints) => _arranged(
                  constraints.maxWidth,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _arranged(double width) {
    final grid = _arrangement == _Arrangement.grid;
    final side = (width - 2 * 10) / 3;
    final size = grid ? Size.square(side) : Size(width, 56);
    final shape = LiquidRoundedSuperellipse(radius: grid ? 22 : 16);
    return MotionLayout(
      motion: _layout,
      layoutBuilder: (context, children) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: children,
      ),
      children: [
        for (final (icon, title) in _tiles)
          SizedBox.fromSize(
            key: ValueKey(title),
            size: size,
            child: _Tile(
              frame: _frameOf(ValueKey(title), shape),
              child: grid
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 30, color: const Color(0xFFFFFFFF)),
                        const SizedBox(height: 6),
                        PhotoText(title),
                      ],
                    )
                  : Row(
                      children: [
                        const SizedBox(width: 16),
                        Icon(icon, color: const Color(0xFFFFFFFF)),
                        const SizedBox(width: 12),
                        PhotoText(title, size: 17),
                      ],
                    ),
            ),
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.frame, required this.child});

  final MotionSelection<GlassFrame> frame;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    MotionLayout.adoptItem(context);
    return GlassSurface.live(
      frame: frame,
      glass: const Glass.clear(),
      child: child,
    );
  }
}
