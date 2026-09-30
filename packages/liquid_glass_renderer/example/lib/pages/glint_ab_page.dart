import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/playground/backdrops.dart';

enum _Side { none, apple, ours, both }

/// Apple's system Liquid Glass and this renderer's at the same spot over the
/// same backdrops, to judge the glint and refraction by eye on a device.
///
/// Apple's side is a `UIGlassEffect` platform view registered by the iOS
/// runner. "Apple" and "Ours" flip one capsule in place, "Both" stacks them
/// and "None" shows the bare backdrop. The glint slider only changes this
/// renderer's `highlight`. The line grid shows how far each glass displaces
/// its backdrop.
class GlintAbPage extends StatefulWidget {
  const GlintAbPage({super.key});

  @override
  State<GlintAbPage> createState() => _GlintAbPageState();
}

class _GlintAbPageState extends State<GlintAbPage> {
  static const _size = Size(300, 64);

  /// The solid probes the glint was fitted on, before the photographs.
  static const _solids = [
    Color(0xFFFFFFFF),
    Color(0xFF808080),
    Color(0xFF000000),
  ];

  final _pages = PageController();
  _Side _side = _Side.apple;
  bool _clear = false;
  double _glint = 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    return CupertinoPageScaffold(
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView(
            controller: _pages,
            children: [
              for (final color in _solids) ColoredBox(color: color),
              const CustomPaint(painter: _LineGridPainter()),
              for (final photo in backdropPhotos)
                Image.asset(photo, fit: BoxFit.cover, gaplessPlayback: true),
            ],
          ),
          Align(
            alignment: const Alignment(0, 0.2),
            child: IgnorePointer(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_side case _Side.apple || _Side.both) _apple(),
                  if (_side == _Side.both) const SizedBox(height: 24),
                  if (_side case _Side.ours || _Side.both) _ours(brightness),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(child: _controls()),
          ),
        ],
      ),
    );
  }

  Widget _apple() => SizedBox.fromSize(
    size: _size,
    child: UiKitView(
      key: ValueKey(_clear),
      viewType: 'native-glass',
      creationParams: {'style': _clear ? 'clear' : 'regular'},
      creationParamsCodec: const StandardMessageCodec(),
    ),
  );

  Widget _ours(Brightness brightness) {
    final settings = _clear
        ? LiquidGlassSettings.ios27Clear()
        : LiquidGlassSettings.ios27Toolbar(brightness: brightness);
    return LiquidGlass.withOwnLayer(
      settings: settings.copyWith(highlight: _glint),
      appearance: _clear
          ? const LiquidGlassAppearance.ios27Clear()
          : LiquidGlassAppearance.ios27Toolbar(brightness: brightness),
      shape: LiquidRoundedRectangle(borderRadius: _size.height / 2),
      child: SizedBox.fromSize(size: _size),
    );
  }

  Widget _controls() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: const Color(0xE6202022),
        borderRadius: BorderRadius.circular(20),
      ),
      child: CupertinoTheme(
        data: const CupertinoThemeData(brightness: Brightness.dark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoSlidingSegmentedControl<_Side>(
              groupValue: _side,
              onValueChanged: (side) => setState(() => _side = side!),
              children: const {
                _Side.none: Text('None'),
                _Side.apple: Text('Apple'),
                _Side.ours: Text('Ours'),
                _Side.both: Text('Both'),
              },
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Text('Clear', style: TextStyle(color: Color(0xFFFFFFFF))),
                const SizedBox(width: 8),
                CupertinoSwitch(
                  value: _clear,
                  onChanged: (clear) => setState(() => _clear = clear),
                ),
                const Spacer(),
                // 0.56 is the glint of Apple's SDR simulator captures.
                for (final preset in const [0.56, 1.0, 1.5])
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: () => setState(() => _glint = preset),
                    child: Text(preset.toStringAsFixed(2)),
                  ),
              ],
            ),
            Row(
              children: [
                Text(
                  'Glint ${_glint.toStringAsFixed(2)}',
                  style: const TextStyle(color: Color(0xFFFFFFFF)),
                ),
                Expanded(
                  child: CupertinoSlider(
                    value: _glint,
                    max: 3,
                    onChanged: (glint) => setState(() => _glint = glint),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Black 1 pt lines every 8 pt on white, centered on 4 + 8k in both axes.
class _LineGridPainter extends CustomPainter {
  const _LineGridPainter();

  static const spacing = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final line = Paint()..color = const Color(0xFF000000);
    for (var x = spacing / 2; x < size.width; x += spacing) {
      canvas.drawRect(Rect.fromLTWH(x - 0.5, 0, 1, size.height), line);
    }
    for (var y = spacing / 2; y < size.height; y += spacing) {
      canvas.drawRect(Rect.fromLTWH(0, y - 0.5, size.width, 1), line);
    }
  }

  @override
  bool shouldRepaint(_LineGridPainter oldDelegate) => false;
}
