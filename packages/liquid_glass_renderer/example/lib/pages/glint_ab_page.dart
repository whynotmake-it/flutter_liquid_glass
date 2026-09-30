import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/playground/backdrops.dart';

enum _Side { apple, ours, both }

/// Apple's system Liquid Glass and this renderer's at the same spot over the
/// same photographs, to judge the glint by eye on a device.
///
/// Apple's side is a `UIGlassEffect` platform view registered by the iOS
/// runner. "Apple" and "Ours" flip one capsule in place; "Both" stacks them.
/// The glint slider only changes this renderer's `highlight`.
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
                  if (_side != _Side.ours) _apple(),
                  if (_side == _Side.both) const SizedBox(height: 24),
                  if (_side != _Side.apple) _ours(brightness),
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
                for (final preset in const [1.0, 1.5, 2.0])
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: () => setState(() => _glint = preset),
                    child: Text(preset.toStringAsFixed(1)),
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
