import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/gallery_bar.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

const _white = Color(0xFFFFFFFF);

/// What the glass is made of, a property at a time: each stage shows one
/// thing the material does and gives it one control to try it with.
class GlassPage extends StatelessWidget {
  const GlassPage({super.key});

  @override
  Widget build(BuildContext context) => GlassPageScaffold(
    backgroundColor: GlassColors.systemGroupedBackground,
    navigationBar: GlassNavigationBar(
      largeTitle: const Text('Glass'),
      trailing: galleryItems(context),
    ),
    child: GlassContentScroll(
      child: Builder(
        builder: (context) {
          final padding = MediaQuery.paddingOf(context);
          return ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              padding.top + 4,
              16,
              padding.bottom + 24,
            ),
            children: const [
              _Bends(),
              _Kinds(),
              _Outlines(),
              _Fuses(),
              _Layers(),
              _Renderers(),
              _Brightness(),
            ],
          );
        },
      ),
    ),
  );
}

/// One property of the glass: what it is, in a sentence, and a stage that
/// shows it.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.title,
    required this.text,
    required this.child,
    this.height = 230,
    this.control,
  });

  final String title;
  final String text;
  final double height;
  final Widget child;
  final Widget? control;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: GlassDynamicColor.resolve(GlassColors.label, context),
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          text,
          style: TextStyle(
            color: GlassDynamicColor.resolve(
              GlassColors.secondaryLabel,
              context,
            ),
            fontSize: 16,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        ClipRSuperellipse(
          borderRadius: BorderRadius.circular(28),
          child: SizedBox(height: height, child: child),
        ),
        if (control case final control?) ...[
          const SizedBox(height: 12),
          control,
        ],
      ],
    ),
  );
}

Widget _photo(Wallpaper wallpaper) => Image(
  image: wallpaper.image,
  fit: BoxFit.cover,
  width: double.infinity,
  height: double.infinity,
);

/// A lens to drag over a page of text.
class _Bends extends StatefulWidget {
  const _Bends();

  @override
  State<_Bends> createState() => _BendsState();
}

class _BendsState extends State<_Bends> with SingleTickerProviderStateMixin {
  // The lens sweeps the page by itself until a finger takes it.
  late final _sweep = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  )..repeat(reverse: true);
  Alignment? _held;

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = GlassDynamicColor.resolve(GlassColors.label, context);
    return _Stage(
      title: 'It bends light',
      text:
          'Glass keeps what lies under it and bends it at the rim, like '
          'the edge of a real lens. Drag the lens.',
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => _sweep.stop(),
          onPanUpdate: (details) => setState(() {
            final at = _held ?? Alignment(_sweep.value * 1.4 - 0.7, 0);
            _held = Alignment(
              (at.x + 2 * details.delta.dx / (constraints.maxWidth - 130))
                  .clamp(-1, 1),
              (at.y + 2 * details.delta.dy / (constraints.maxHeight - 130))
                  .clamp(-1, 1),
            );
          }),
          child: ColoredBox(
            color: GlassDynamicColor.resolve(
              GlassColors.secondarySystemGroupedBackground,
              context,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    'The quick brown fox jumps over the lazy dog. Pack my '
                    'box with five dozen liquor jugs. How vexingly quick '
                    'daft zebras jump. Sphinx of black quartz, judge my '
                    'vow. The five boxing wizards jump quickly.',
                    overflow: TextOverflow.fade,
                    style: TextStyle(color: label, fontSize: 24, height: 1.25),
                  ),
                ),
                AnimatedBuilder(
                  animation: _sweep,
                  builder: (context, child) => Align(
                    alignment:
                        _held ??
                        Alignment(
                          Curves.easeInOut.transform(_sweep.value) * 1.4 - 0.7,
                          0,
                        ),
                    child: child,
                  ),
                  child: const SizedBox.square(
                    dimension: 130,
                    child: GlassSurface(
                      shape: LiquidOval(),
                      glass: Glass.clear(),
                      child: SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Clear and regular glass side by side, in a tint.
class _Kinds extends StatefulWidget {
  const _Kinds();

  @override
  State<_Kinds> createState() => _KindsState();
}

class _KindsState extends State<_Kinds> {
  static const _tints = <Color?>[
    null,
    Color(0x800A84FF),
    Color(0x80FF375F),
    Color(0x80FFD60A),
    Color(0x8030D158),
    Color(0x99000000),
  ];
  var _tint = 0;

  @override
  Widget build(BuildContext context) => _Stage(
    title: 'Clear, regular, tinted',
    text:
        'Clear glass passes the page through. Regular glass frosts it, so '
        'a label on it reads over anything. A tint colors either.',
    control: Row(
      children: [
        for (final (index, tint) in _tints.indexed)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _Swatch(
              color: tint,
              selected: index == _tint,
              onPressed: () => setState(() => _tint = index),
            ),
          ),
      ],
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        _photo(Wallpaper.bloom),
        Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              for (final (name, glass) in [
                ('Clear', Glass.clear(tint: _tints[_tint])),
                ('Regular', Glass.regular(tint: _tints[_tint])),
              ]) ...[
                Expanded(
                  child: GlassSurface(
                    shape: const LiquidRoundedSuperellipse(radius: 30),
                    glass: glass,
                    child: Center(
                      child: PhotoText(name, size: 20, weight: FontWeight.w600),
                    ),
                  ),
                ),
                if (name == 'Clear') const SizedBox(width: 18),
              ],
            ],
          ),
        ),
      ],
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
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color?.withValues(alpha: 1),
            border: Border.all(
              color: label.withValues(alpha: selected ? 1 : 0.25),
              width: selected ? 2.5 : 1,
            ),
          ),
          child: color == null
              ? Icon(CupertinoIcons.nosign, size: 18, color: label)
              : null,
        ),
      ),
    );
  }
}

enum _Outline { capsule, squircle, rounded, oval }

/// One body in each outline the glass takes.
class _Outlines extends StatefulWidget {
  const _Outlines();

  @override
  State<_Outlines> createState() => _OutlinesState();
}

class _OutlinesState extends State<_Outlines> {
  var _outline = _Outline.squircle;

  @override
  Widget build(BuildContext context) => _Stage(
    title: 'Any outline',
    text:
        'A capsule, a continuous-corner superellipse, a rounded rectangle '
        'or an oval. The rim follows the outline exactly.',
    control: GlassSegmentedControl<_Outline>(
      segments: const [
        GlassSegment(value: _Outline.capsule, label: Text('Capsule')),
        GlassSegment(value: _Outline.squircle, label: Text('Squircle')),
        GlassSegment(value: _Outline.rounded, label: Text('Rounded')),
        GlassSegment(value: _Outline.oval, label: Text('Oval')),
      ],
      groupValue: _outline,
      onChanged: (outline) => setState(() => _outline = outline),
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        _photo(Wallpaper.coast),
        Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            width: _outline == _Outline.capsule ? 250 : 190,
            height: _outline == _Outline.capsule ? 84 : 150,
            child: GlassSurface(
              shape: switch (_outline) {
                _Outline.capsule => LiquidRoundedSuperellipse.capsule,
                _Outline.squircle => const LiquidRoundedSuperellipse(
                  radius: 44,
                ),
                _Outline.rounded => const LiquidRoundedRectangle(
                  radius: 28,
                ),
                _Outline.oval => const LiquidOval(),
              },
              glass: const Glass.clear(),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Two drops and the distance between them.
class _Fuses extends StatefulWidget {
  const _Fuses();

  @override
  State<_Fuses> createState() => _FusesState();
}

class _FusesState extends State<_Fuses> {
  var _apart = 0.42;

  @override
  Widget build(BuildContext context) => _Stage(
    title: 'It fuses',
    text:
        'Glass in one group flows together where two bodies come close, '
        'and parts again with a neck between them. Bring them together.',
    control: GlassSlider(
      value: _apart,
      semanticLabel: 'Distance',
      onChanged: (value) => setState(() => _apart = value),
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        _photo(Wallpaper.aurora),
        GlassGroup(
          merge: const GlassMerge.spacing(34),
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (final side in const [-1.0, 1.0])
                Align(
                  alignment: Alignment(side * (0.12 + 0.6 * _apart), 0),
                  child: SizedBox.square(
                    dimension: side < 0 ? 120 : 92,
                    child: const GlassSurface(
                      shape: LiquidOval(),
                      glass: Glass.clear(),
                      child: SizedBox.expand(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Controls of glass on a panel of glass.
class _Layers extends StatefulWidget {
  const _Layers();

  @override
  State<_Layers> createState() => _LayersState();
}

class _LayersState extends State<_Layers> {
  var _on = true;
  var _level = 0.6;

  @override
  Widget build(BuildContext context) => _Stage(
    title: 'Glass on glass',
    text:
        'A panel of glass carries controls of glass: each reads what lies '
        'under it, the panel included.',
    child: GlassTheme(
      data: const GlassThemeData(brightness: Brightness.dark),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _photo(Wallpaper.city),
          Padding(
            padding: const EdgeInsets.all(20),
            child: GlassSurface(
              shape: const LiquidRoundedSuperellipse(radius: 30),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Night Light',
                            style: TextStyle(
                              color: _white,
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        GlassSwitch(
                          value: _on,
                          onChanged: (on) => setState(() => _on = on),
                        ),
                      ],
                    ),
                    GlassSlider(
                      value: _level,
                      semanticLabel: 'Level',
                      onChanged: (value) => setState(() => _level = value),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final icon in const [
                          CupertinoIcons.sun_max_fill,
                          CupertinoIcons.moon_fill,
                          CupertinoIcons.timer,
                          CupertinoIcons.ellipsis,
                        ])
                          GlassButton(
                            onPressed: () {},
                            semanticLabel: 'Action',
                            child: Icon(icon),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The same controls drawn by the liquid renderer and by the flat one.
class _Renderers extends StatefulWidget {
  const _Renderers();

  @override
  State<_Renderers> createState() => _RenderersState();
}

class _RenderersState extends State<_Renderers> {
  var _on = true;
  var _level = 0.5;

  @override
  Widget build(BuildContext context) => _Stage(
    title: 'Glass, or flat',
    text:
        'The same widgets and the same motion, drawn in liquid glass or '
        'flat: one line in the theme, for an app or for its user to '
        'choose.',
    height: 250,
    child: Stack(
      fit: StackFit.expand,
      children: [
        _photo(Wallpaper.dunes),
        Row(
          children: [
            for (final (name, renderer) in const [
              ('Liquid', LiquidGlassRenderer()),
              ('Flat', FlatGlassRenderer()),
            ])
              Expanded(
                child: GlassRendererScope(
                  renderer: renderer,
                  child: GlassTheme(
                    data: const GlassThemeData(
                      brightness: Brightness.dark,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          PhotoText(name, size: 17, weight: FontWeight.w600),
                          GlassButton(
                            onPressed: () {},
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text('Button'),
                            ),
                          ),
                          GlassSwitch(
                            value: _on,
                            onChanged: (on) => setState(() => _on = on),
                          ),
                          GlassSlider(
                            value: _level,
                            semanticLabel: '$name level',
                            onChanged: (value) =>
                                setState(() => _level = value),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

/// The same panel in light and in dark.
class _Brightness extends StatelessWidget {
  const _Brightness();

  @override
  Widget build(BuildContext context) => _Stage(
    title: 'Light and dark',
    text:
        'Glass takes its brightness from the theme, for the whole app or '
        'for one part of a page.',
    height: 180,
    child: Stack(
      fit: StackFit.expand,
      children: [
        _photo(Wallpaper.alpine),
        Row(
          children: [
            for (final brightness in Brightness.values.reversed)
              Expanded(
                child: GlassTheme(
                  data: GlassThemeData(brightness: brightness),
                  child: Builder(
                    builder: (context) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: GlassSurface(
                        shape: const LiquidRoundedSuperellipse(
                          radius: 26,
                        ),
                        child: Center(
                          child: Text(
                            brightness == Brightness.light ? 'Light' : 'Dark',
                            style: TextStyle(
                              color: GlassDynamicColor.resolve(
                                GlassColors.label,
                                context,
                              ),
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}
