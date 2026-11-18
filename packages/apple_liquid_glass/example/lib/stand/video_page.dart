import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

/// A playing video under glass: bars, buttons and a list of the same video.
///
/// The clip is a test pattern with a counter and two bars that move every
/// frame, so glass showing another frame than the one around it shows the
/// bars broken at its edge.
class VideoPage extends StatefulWidget {
  const VideoPage({super.key});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  final _video = VideoPlayerController.asset('assets/video/frames.mp4');

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _video.initialize();
    await _video.setLooping(true);
    await _video.setVolume(0);
    await _video.play();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _video.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_video.value.isPlaying) {
      _video.pause();
    } else {
      _video.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion(
    value: SystemUiOverlayStyle.light,
    child: GlassTheme(
      data: const GlassThemeData(brightness: Brightness.dark),
      child: GlassPageScaffold(
        backgroundColor: const Color(0xFF000000),
        navigationBar: GlassNavigationBar(
          title: const Text('Video'),
          previousPageTitle: 'Present',
          trailing: [settingsItem(context)],
        ),
        toolbar: GlassToolbar(
          items: [
            GlassBarItem(
              icon: Icon(
                _video.value.isPlaying
                    ? CupertinoIcons.pause_fill
                    : CupertinoIcons.play_fill,
              ),
              semanticLabel: 'Play',
              onPressed: _toggle,
            ),
            const GlassBarSpacer.flexible(),
            GlassBarItem(
              icon: const Icon(CupertinoIcons.share),
              semanticLabel: 'Share',
              onPressed: () {},
            ),
          ],
        ),
        child: GlassContentScroll(
          child: Builder(
            builder: (context) => ListView(
              padding: MediaQuery.paddingOf(context),
              children: [
                _Clip(video: _video, height: 560, onPlay: _toggle),
                for (var i = 0; i < 6; i++)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: ClipRSuperellipse(
                      borderRadius: BorderRadius.circular(16),
                      child: _Clip(video: _video, height: 200, onPlay: _toggle),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Clip extends StatelessWidget {
  const _Clip({
    required this.video,
    required this.height,
    required this.onPlay,
  });

  final VideoPlayerController video;
  final double height;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(width: 720, height: 1280, child: VideoPlayer(video)),
        ),
        Center(
          child: GlassButton(
            onPressed: onPlay,
            semanticLabel: 'Play',
            child: const Icon(CupertinoIcons.play_fill),
          ),
        ),
        Positioned(
          left: 12,
          bottom: 12,
          child: GlassButton(onPressed: () {}, child: const Text('Live')),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: GlassButton.clear(
            onPressed: () {},
            child: const Icon(CupertinoIcons.fullscreen),
          ),
        ),
      ],
    ),
  );
}
