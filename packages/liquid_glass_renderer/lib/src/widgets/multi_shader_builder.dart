// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/rendering.dart';

/// A callback used by [MultiShaderBuilder].
typedef MultiShaderBuilderCallback = Widget Function(
  BuildContext,
  List<ui.FragmentShader>,
  Widget?,
);

/// Loads and caches [ui.FragmentProgram]s by asset key and builds with one
/// shader per key, in [assetKeys] order, once all have loaded; until then it
/// shows [child], or nothing. Programs precached with
/// [GlassShaderPrograms.precacheShaders] are there on the first build.
class MultiShaderBuilder extends StatefulWidget {
  /// Create a new [MultiShaderBuilder].
  const MultiShaderBuilder(
    this.builder, {
    required this.assetKeys,
    super.key,
    this.child,
  });

  /// The asset keys used to lookup shaders.
  final List<String> assetKeys;

  /// The child widget to pass through to the [builder], optional.
  final Widget? child;

  /// The builder that provides access to [ui.FragmentShader]s.
  final MultiShaderBuilderCallback builder;

  @override
  State<MultiShaderBuilder> createState() => _MultiShaderBuilderState();
}

class _MultiShaderBuilderState extends State<MultiShaderBuilder> {
  final Map<String, ui.FragmentShader> _shaders = {};

  @override
  void initState() {
    super.initState();
    _loadShaders(widget.assetKeys);
  }

  @override
  void didUpdateWidget(covariant MultiShaderBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.assetKeys, widget.assetKeys)) {
      _loadShaders(widget.assetKeys);
    }
  }

  void _loadShaders(List<String> assetKeys) {
    _disposeShaders();
    for (final assetKey in assetKeys) {
      if (GlassShaderPrograms.cached(assetKey) case final program?) {
        _shaders[assetKey] = program.fragmentShader();
        continue;
      }
      GlassShaderPrograms.precacheShader(assetKey).then((_) {
        final program = GlassShaderPrograms.cached(assetKey);
        if (!mounted || program == null) return;
        setState(() => _shaders[assetKey] = program.fragmentShader());
      });
    }
  }

  void _disposeShaders() {
    for (final shader in _shaders.values) {
      shader.dispose();
    }
    _shaders.clear();
  }

  @override
  void dispose() {
    _disposeShaders();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_shaders.length != widget.assetKeys.length) {
      return widget.child ?? const SizedBox.shrink();
    }
    final shaders = widget.assetKeys.map((key) => _shaders[key]!).toList();
    return widget.builder(context, shaders, widget.child);
  }
}
