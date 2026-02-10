import 'package:blur_progressive/blur_progressive.dart';
import 'package:flutter/cupertino.dart';
import 'package:progressive_blur/progressive_blur.dart' as pb;
import 'package:soft_edge_blur/soft_edge_blur.dart' as seb;

void main() {
  pb.ProgressiveBlurWidget.precache();
  runApp(const CupertinoApp(home: BlurComparisonApp()));
}

enum BlurMode { backdrop, progressiveBlur, softEdgeBlur }

class BlurComparisonApp extends StatefulWidget {
  const BlurComparisonApp({super.key});

  @override
  State<BlurComparisonApp> createState() => _BlurComparisonAppState();
}

class _BlurComparisonAppState extends State<BlurComparisonApp> {
  BlurMode _mode = BlurMode.backdrop;

  Widget _buildScrollContent() {
    return CustomScrollView(
      slivers: [
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => Image.network(
              fit: BoxFit.cover,
              'https://picsum.photos/500/500?random=$index',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBlurredContent() {
    const blurHeight = 200.0;
    const maxSigma = 30.0;

    switch (_mode) {
      case BlurMode.backdrop:
        // Works like a BackdropFilter -- sits on top of content in a Stack.
        return Stack(
          children: [
            _buildScrollContent(),
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: blurHeight,
              child: ProgressiveBlurBackdrop(
                maxBlurRadius: maxSigma,
                gradient: ProgressiveBlurGradient.bottomToTop(),
              ),
            ),
          ],
        );

      case BlurMode.progressiveBlur:
        // Wraps the content -- the child is what gets blurred.
        return pb.ProgressiveBlurWidget(
          sigma: maxSigma,
          linearGradientBlur: const pb.LinearGradientBlur(
            start: Alignment.topCenter,
            end: Alignment.bottomCenter,
            values: [1.0, 0.0],
            stops: [0.0, 1.0],
          ),
          child: _buildScrollContent(),
        );

      case BlurMode.softEdgeBlur:
        // Wraps the content -- the child is what gets blurred.
        return seb.SoftEdgeBlur(
          edges: [
            seb.EdgeBlur(
              type: seb.EdgeType.topEdge,
              size: blurHeight,
              sigma: maxSigma,
              controlPoints: [
                seb.ControlPoint(
                  position: 0.0,
                  type: seb.ControlPointType.visible,
                ),
                seb.ControlPoint(
                  position: 1.0,
                  type: seb.ControlPointType.transparent,
                ),
              ],
            ),
          ],
          child: _buildScrollContent(),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Stack(
        children: [
          _buildBlurredContent(),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: CupertinoSlidingSegmentedControl<BlurMode>(
                  groupValue: _mode,
                  children: const {
                    BlurMode.backdrop: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Ours', style: TextStyle(fontSize: 13)),
                    ),
                    BlurMode.progressiveBlur: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'progressive_blur',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    BlurMode.softEdgeBlur: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'soft_edge_blur',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  },
                  onValueChanged: (value) {
                    if (value != null) setState(() => _mode = value);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
