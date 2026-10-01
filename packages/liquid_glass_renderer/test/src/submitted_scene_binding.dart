import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures the submitted scene, without a second layer-tree traversal.
class SubmittedSceneBinding extends AutomatedTestWidgetsFlutterBinding
    with SubmittedSceneCapture {}

/// Shared submitted-scene capture for host and device integration tests.
mixin SubmittedSceneCapture on RendererBinding {
  bool captureNextScene = false;
  Future<ui.Image>? captured;
  int captureWidth = 1080;
  int captureHeight = 2100;

  @override
  ui.SceneBuilder createSceneBuilder() =>
      _CaptureBuilder(super.createSceneBuilder(), this);
}

class _CaptureBuilder extends Fake implements ui.SceneBuilder {
  _CaptureBuilder(this.delegate, this.binding);
  final ui.SceneBuilder delegate;
  final SubmittedSceneCapture binding;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #build) {
      final scene = delegate.build();
      if (binding.captureNextScene) {
        binding.captureNextScene = false;
        binding.captured = scene.toImage(
          binding.captureWidth,
          binding.captureHeight,
        );
      }
      return scene;
    }
    final method = switch (invocation.memberName) {
      #pushTransform => delegate.pushTransform,
      #pushOffset => delegate.pushOffset,
      #pushClipRect => delegate.pushClipRect,
      #pushClipRRect => delegate.pushClipRRect,
      #pushClipRSuperellipse => delegate.pushClipRSuperellipse,
      #pushClipPath => delegate.pushClipPath,
      #pushOpacity => delegate.pushOpacity,
      #pushColorFilter => delegate.pushColorFilter,
      #pushImageFilter => delegate.pushImageFilter,
      #pushBackdropFilter => delegate.pushBackdropFilter,
      #pushShaderMask => delegate.pushShaderMask,
      #pop => delegate.pop,
      #addRetained => delegate.addRetained,
      #addPicture => delegate.addPicture,
      #addTexture => delegate.addTexture,
      #addPerformanceOverlay => delegate.addPerformanceOverlay,
      _ => throw UnsupportedError('${invocation.memberName}'),
    };
    return Function.apply(
      method,
      invocation.positionalArguments,
      invocation.namedArguments,
    );
  }
}
