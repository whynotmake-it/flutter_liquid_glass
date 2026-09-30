import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

/// Backdrops for judging glass. Each is a page that scrolls vertically, so
/// the glass can be watched moving over real content: photographs for color
/// and tone, a long article and a grid that make refraction easy to read.
enum Backdrop {
  photos('Photos', 'assets/backdrops/coast.webp'),
  night('Night', 'assets/backdrops/city.webp'),
  article('Article', null),
  grid('Grid', null);

  const Backdrop(this.label, this.thumbnail);

  final String label;

  /// The photograph that represents this backdrop in the picker.
  final String? thumbnail;
}

const _photos = [
  'assets/backdrops/coast.webp',
  'assets/backdrops/alpine.webp',
  'assets/backdrops/bloom.webp',
  'assets/backdrops/dunes.webp',
];
const _nightPhotos = [
  'assets/backdrops/city.webp',
  'assets/backdrops/aurora.webp',
];

/// Every photograph a backdrop can show.
const backdropPhotos = [..._photos, ..._nightPhotos];

/// Pages between the backdrops horizontally and keeps [backdrop] in sync.
///
/// Choosing a backdrop elsewhere springs the pager to it.
class BackdropPager extends StatefulWidget {
  const BackdropPager({required this.backdrop, super.key});

  final ValueNotifier<Backdrop> backdrop;

  @override
  State<BackdropPager> createState() => _BackdropPagerState();
}

class _BackdropPagerState extends State<BackdropPager>
    with SingleTickerProviderStateMixin {
  late final _pages = PageController(initialPage: widget.backdrop.value.index);
  late final _spring = SingleMotionController(
    motion: const CupertinoMotion.smooth(),
    vsync: this,
  )..addListener(_followSpring);
  var _paging = false;

  @override
  void initState() {
    super.initState();
    widget.backdrop.addListener(_springToBackdrop);
  }

  @override
  void dispose() {
    widget.backdrop.removeListener(_springToBackdrop);
    _spring.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _springToBackdrop() {
    if (_paging || !_pages.hasClients) return;
    final position = _pages.position;
    final target = widget.backdrop.value.index * position.viewportDimension;
    if ((position.pixels - target).abs() < 1) return;
    _spring
      ..value = position.pixels
      ..animateTo(target);
  }

  void _followSpring() {
    if (_pages.hasClients && _spring.isAnimating) {
      _pages.position.jumpTo(_spring.value);
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth == 0 &&
        notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _spring.stop();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(
        context,
      ).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: PageView(
          controller: _pages,
          onPageChanged: (page) {
            if (_spring.isAnimating) return;
            _paging = true;
            widget.backdrop.value = Backdrop.values[page];
            _paging = false;
          },
          children: [
            for (final backdrop in Backdrop.values)
              RepaintBoundary(
                child: switch (backdrop) {
                  Backdrop.photos => const _PhotoFeed(
                    key: PageStorageKey(Backdrop.photos),
                    photos: _photos,
                    color: Color(0xFFFFFFFF),
                  ),
                  Backdrop.night => const _NightPage(
                    key: PageStorageKey(Backdrop.night),
                  ),
                  Backdrop.article => const _ArticlePage(
                    key: PageStorageKey(Backdrop.article),
                  ),
                  Backdrop.grid => const _GridPage(
                    key: PageStorageKey(Backdrop.grid),
                  ),
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// A small preview of [backdrop] for the picker.
class BackdropThumbnail extends StatelessWidget {
  const BackdropThumbnail({required this.backdrop, super.key});

  final Backdrop backdrop;

  @override
  Widget build(BuildContext context) {
    if (backdrop.thumbnail case final asset?) {
      return Image.asset(asset, fit: BoxFit.cover, cacheWidth: 160);
    }
    return FittedBox(
      fit: BoxFit.cover,
      alignment: Alignment.topLeft,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: 480,
        height: 600,
        child: switch (backdrop) {
          Backdrop.grid => const _GridPaper(),
          _ => const _ArticleHeader(),
        },
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo(this.asset);

  final String asset;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Image.asset(asset, fit: BoxFit.cover, gaplessPlayback: true),
    );
  }
}

class _PhotoFeed extends StatelessWidget {
  const _PhotoFeed({required this.photos, required this.color, super.key});

  final List<String> photos;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: photos.length,
        separatorBuilder: (context, index) => const SizedBox(height: 4),
        itemBuilder: (context, index) => _Photo(photos[index]),
      ),
    );
  }
}

const _ink = Color(0xFF111111);
const _paper = Color(0xFFF7F5F0);
const _accent = Color(0xFFE5402F);
const _column = 640.0;

const _body =
    'Glass is a flat face with a rounded bevel. Only the bevel refracts: '
    'straight lines bend as they reach the rim, text stays crisp through the '
    'middle, and a thin glint traces the edge where light catches it. Scroll '
    'this page beneath the glass to see how far inside the silhouette the '
    'backdrop is sampled, and drag shapes together to see them merge.';

class _ArticleHeader extends StatelessWidget {
  const _ArticleHeader();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: _paper,
      child: Padding(
        padding: EdgeInsets.fromLTRB(28, 56, 28, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ISSUE 27 — OPTICS',
              style: TextStyle(
                color: _accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Light, bent\nbeautifully.',
              style: TextStyle(
                color: _ink,
                fontSize: 64,
                height: 0.98,
                fontWeight: FontWeight.w800,
                letterSpacing: -2.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A long, left-aligned editorial page. The column keeps its width on narrow
/// screens and is cropped at the edge, like a magazine spread.
class _ArticlePage extends StatelessWidget {
  const _ArticlePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _paper,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: const [
          _ArticleHeader(),
          _Column(children: [_Rule(), Text(_body)]),
          _Column(
            children: [
              Text(
                'Aa Bb Cc 0123456789',
                style: TextStyle(fontSize: 44, fontWeight: FontWeight.w300),
              ),
            ],
          ),
          _Photo('assets/backdrops/bloom.webp'),
          _Column(
            children: [
              Text(
                'Refraction.',
                style: TextStyle(
                  fontSize: 88,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -3.5,
                ),
              ),
              Text(_body),
              _Rule(),
              Text(_body, style: TextStyle(fontSize: 13, height: 1.5)),
            ],
          ),
          _Photo('assets/backdrops/dunes.webp'),
          _Column(
            children: [
              Text(
                '“The face stays still.\nOnly the rim bends.”',
                style: TextStyle(
                  fontSize: 34,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                ),
              ),
              Text(_body),
              Text(_body),
            ],
          ),
        ],
      ),
    );
  }
}

class _NightPage extends StatelessWidget {
  const _NightPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF07070A),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: const [
          _Photo('assets/backdrops/city.webp'),
          _Column(
            color: Color(0xFFF2F2F7),
            children: [
              Text(
                'After dark.',
                style: TextStyle(
                  fontSize: 64,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2.4,
                ),
              ),
              Text(_body),
            ],
          ),
          _Photo('assets/backdrops/aurora.webp'),
        ],
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.children, this.color = _ink});

  final List<Widget> children;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          maxWidth: _column + 56,
          fit: OverflowBoxFit.deferToChild,
          child: SizedBox(
            width: _column + 56,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  height: 1.45,
                  letterSpacing: -0.1,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 16,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _column,
      height: 2,
      child: ColoredBox(color: DefaultTextStyle.of(context).style.color!),
    );
  }
}

/// A tall grid with bands of color that scrolls beneath the glass.
class _GridPage extends StatelessWidget {
  const _GridPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: 6,
      itemExtent: _GridPainter.tile,
      itemBuilder: (context, index) => const _GridPaper(),
    );
  }
}

class _GridPaper extends StatelessWidget {
  const _GridPaper();

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: CustomPaint(painter: _GridPainter(), child: SizedBox.expand()),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  static const _cell = 24.0;

  /// Height of one repeat: sixteen rows of grid, then six bands of color.
  static const tile = _cell * 28;

  static const _bands = [
    Color(0xFFFF3B30),
    Color(0xFFFF9500),
    Color(0xFFFFCC00),
    Color(0xFF34C759),
    Color(0xFF007AFF),
    Color(0xFFAF52DE),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    const bandHeight = _cell * 2;
    const bandTop = _cell * 16;
    for (var i = 0; i < _bands.length; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, bandTop + i * bandHeight, size.width, bandHeight),
        Paint()..color = _bands[i],
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
    for (var y = 0.0; y < size.height; y += _cell, index++) {
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
