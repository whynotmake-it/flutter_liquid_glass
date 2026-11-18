import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A photo library: every photo zooms into its own page, which shrinks back
/// into the grid when it closes. Select swaps the bar's items and brings a
/// toolbar whose items change with the selection.
class PhotosPage extends StatefulWidget {
  const PhotosPage({super.key});

  @override
  State<PhotosPage> createState() => _PhotosPageState();
}

class _Photo {
  _Photo(this.wallpaper, this.alignment);

  final Wallpaper wallpaper;
  final Alignment alignment;
  final source = MotionSource();
}

class _PhotosPageState extends State<PhotosPage> {
  static const _crops = [
    Alignment.center,
    Alignment(-0.8, -0.4),
    Alignment(0.7, 0.5),
    Alignment(-0.3, 0.9),
    Alignment(0.9, -0.8),
    Alignment.topCenter,
  ];

  late final _photos = [
    for (var i = 0; i < 60; i++)
      _Photo(
        Wallpaper.values[(i * 5 + i ~/ 6) % Wallpaper.values.length],
        _crops[(i * 7) % _crops.length],
      ),
  ];

  var _selecting = false;
  final _selected = <_Photo>{};

  void _select({required bool on}) => setState(() {
    _selecting = on;
    _selected.clear();
  });

  void _toggle(_Photo photo) => setState(() {
    if (!_selected.remove(photo)) _selected.add(photo);
  });

  void _delete() => setState(() {
    _photos.removeWhere(_selected.contains);
    _selected.clear();
    _selecting = false;
  });

  GlassToolbar _toolbar() {
    final count = _selected.length;
    return GlassToolbar(
      items: [
        GlassBarItem(
          icon: const Icon(CupertinoIcons.share),
          semanticLabel: 'Share',
          onPressed: count == 0 ? null : () {},
        ),
        const GlassBarSpacer.flexible(),
        GlassBarItem.custom(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              switch (count) {
                0 => 'Select Items',
                1 => '1 Photo Selected',
                _ => '$count Photos Selected',
              },
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const GlassBarSpacer.flexible(),
        GlassBarItem(
          icon: const Icon(CupertinoIcons.trash),
          semanticLabel: 'Delete Selected',
          onPressed: count == 0 ? null : _delete,
        ),
      ],
    );
  }

  void _open(_Photo photo) => unawaited(
    Navigator.of(context).push(
      GlassPageRoute<void>(
        source: photo.source,
        builder: (context) => _PhotoPage(photo: photo),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => GlassPageScaffold(
    navigationBar: GlassNavigationBar(
      largeTitle: const Text('Photos'),
      trailing: _selecting
          ? [
              GlassBarItem.prominent(
                label: const Text('Done'),
                onPressed: () => _select(on: false),
              ),
            ]
          : [
              GlassBarItem(
                label: const Text('Select'),
                onPressed: () => _select(on: true),
              ),
              settingsItem(context),
            ],
    ),
    toolbar: _selecting ? _toolbar() : null,
    child: GlassContentScroll(
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: _photos.length,
        itemBuilder: (context, index) {
          final photo = _photos[index];
          return GlassContextMenu(
            menuChildren: [
              GlassMenuItem(
                title: 'Share',
                icon: const Icon(CupertinoIcons.share),
                onPressed: () {},
              ),
              GlassMenuItem(
                title: 'Favorite',
                icon: const Icon(CupertinoIcons.heart),
                onPressed: () {},
              ),
              GlassMenuItem(
                title: 'Copy',
                icon: const Icon(CupertinoIcons.doc_on_doc),
                onPressed: () {},
              ),
              GlassMenuSection(
                children: [
                  GlassMenuItem(
                    title: 'Delete',
                    icon: const Icon(CupertinoIcons.trash),
                    destructive: true,
                    onPressed: () {},
                  ),
                ],
              ),
            ],
            child: GestureDetector(
              onTap: () => _selecting ? _toggle(photo) : _open(photo),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GlassZoomSource(
                    source: photo.source,
                    child: Image(
                      image: photo.wallpaper.image,
                      fit: BoxFit.cover,
                      alignment: photo.alignment,
                    ),
                  ),
                  if (_selected.contains(photo))
                    const Positioned(
                      right: 6,
                      bottom: 6,
                      child: Icon(
                        CupertinoIcons.checkmark_circle_fill,
                        color: Color(0xFFFFFFFF),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _PhotoPage extends StatefulWidget {
  const _PhotoPage({required this.photo});

  final _Photo photo;

  @override
  State<_PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<_PhotoPage> {
  var _favorite = false;

  @override
  Widget build(BuildContext context) => AnnotatedRegion(
    value: SystemUiOverlayStyle.light,
    child: GlassTheme(
      data: const GlassThemeData(brightness: Brightness.dark),
      child: GlassPageScaffold(
        backgroundColor: const Color(0xFF000000),
        navigationBar: GlassNavigationBar(
          title: Text(widget.photo.wallpaper.title),
          previousPageTitle: 'Photos',
          trailing: [GlassBarItem(label: const Text('Edit'), onPressed: () {})],
        ),
        toolbar: GlassToolbar(
          items: [
            GlassBarItem(
              icon: const Icon(CupertinoIcons.share),
              semanticLabel: 'Share',
              onPressed: () {},
            ),
            const GlassBarSpacer.flexible(),
            GlassBarItem(
              icon: Icon(
                _favorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
              ),
              semanticLabel: 'Favorite',
              onPressed: () => setState(() => _favorite = !_favorite),
            ),
            GlassBarItem(
              icon: const Icon(CupertinoIcons.info),
              semanticLabel: 'Info',
              onPressed: () {},
            ),
            GlassBarItem(
              icon: const Icon(CupertinoIcons.slider_horizontal_3),
              semanticLabel: 'Adjust',
              onPressed: () {},
            ),
            const GlassBarSpacer.flexible(),
            GlassBarItem(
              icon: const Icon(CupertinoIcons.trash),
              semanticLabel: 'Delete',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        child: InteractiveViewer(
          maxScale: 4,
          child: Center(
            child: Image(
              image: widget.photo.wallpaper.image,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    ),
  );
}
