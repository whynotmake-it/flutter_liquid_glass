// The plan's count of a frame's targets against the layers the frame's scene
// really holds for its glass. The raster thread pays for each of them
// whatever it draws, so a plan that counts fewer than it issues spends frames
// it does not know of.
//
// flutter test --enable-impeller --enable-flutter-gpu \
//   test/glass_targets_host_test.dart
//

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/app.dart';
import 'package:apple_liquid_glass_example/stand/stand_home.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:liquid_glass_renderer/src/plan/plan.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/pinned_layer.dart';

const _frame = Duration(milliseconds: 16);
const _screen = Size(411, 914);
const _dpr = 2.625;

enum _Kind { plain, fade, saved, blur, glass }

// One engine layer of a scene, as far as its passes go.
class _Layer {
  _Layer(this.kind);

  final _Kind kind;
  final children = <_Layer>[];
  int ownPictures = 0;

  int get pictures =>
      children.fold(ownPictures, (sum, child) => sum + child.pictures);

  // What the plan counts for it: a blur is its layer and two passes of its
  // own, an opacity around nothing but a blur is that blur's layer, and one
  // picture fades with no layer at all.
  int get targets {
    final inside = children.fold(0, (sum, child) => sum + child.targets);
    return switch (kind) {
      _Kind.plain => inside,
      _Kind.fade
          when pictures < 2 ||
              children.length == 1 && children[0].kind == _Kind.blur =>
        inside,
      _Kind.fade || _Kind.saved || _Kind.glass => 1 + inside,
      _Kind.blur => 3 + inside,
    };
  }

  // The targets of the glass in it: every layer a shader filters, with all it
  // holds. A shader filter in this app is glass or its frost.
  int get glassTargets => kind == _Kind.glass
      ? targets
      : children.fold(0, (sum, child) => sum + child.glassTargets);
}

final _layers = Expando<_Layer>();
int _sceneTargets = 0;

// Shader layers whose first draw was not their pin: glass and its frost read
// fragments counted from the layer's corner, which only a pin holds.
int _unpinned = 0;

class _Counting implements ui.SceneBuilder {
  _Counting(this._builder);

  final ui.SceneBuilder _builder;
  final _open = [_Layer(_Kind.plain)];
  bool _awaitsPin = false;

  void _settlePin([ui.Picture? picture]) {
    if (_awaitsPin && (picture == null || !PinnedLayers.isPin(picture))) {
      _unpinned++;
    }
    _awaitsPin = false;
  }

  T _push<T extends ui.EngineLayer>(T engine, _Kind kind) {
    _settlePin();
    final layer = _Layer(kind);
    _open.last.children.add(layer);
    _open.add(layer);
    _layers[engine] = layer;
    return engine;
  }

  static _Kind _clip(ui.Clip behavior) =>
      behavior == ui.Clip.antiAliasWithSaveLayer ? _Kind.saved : _Kind.plain;

  @override
  ui.TransformEngineLayer pushTransform(
    Float64List matrix4, {
    ui.TransformEngineLayer? oldLayer,
  }) => _push(
    _builder.pushTransform(matrix4, oldLayer: oldLayer),
    _Kind.plain,
  );

  @override
  ui.OffsetEngineLayer pushOffset(
    double dx,
    double dy, {
    ui.OffsetEngineLayer? oldLayer,
  }) => _push(_builder.pushOffset(dx, dy, oldLayer: oldLayer), _Kind.plain);

  @override
  ui.ClipRectEngineLayer pushClipRect(
    ui.Rect rect, {
    ui.Clip clipBehavior = ui.Clip.antiAlias,
    ui.ClipRectEngineLayer? oldLayer,
  }) => _push(
    _builder.pushClipRect(
      rect,
      clipBehavior: clipBehavior,
      oldLayer: oldLayer,
    ),
    _clip(clipBehavior),
  );

  @override
  ui.ClipRRectEngineLayer pushClipRRect(
    ui.RRect rrect, {
    ui.Clip clipBehavior = ui.Clip.antiAlias,
    ui.ClipRRectEngineLayer? oldLayer,
  }) => _push(
    _builder.pushClipRRect(
      rrect,
      clipBehavior: clipBehavior,
      oldLayer: oldLayer,
    ),
    _clip(clipBehavior),
  );

  @override
  ui.ClipRSuperellipseEngineLayer pushClipRSuperellipse(
    ui.RSuperellipse rsuperellipse, {
    ui.Clip clipBehavior = ui.Clip.antiAlias,
    ui.ClipRSuperellipseEngineLayer? oldLayer,
  }) => _push(
    _builder.pushClipRSuperellipse(
      rsuperellipse,
      clipBehavior: clipBehavior,
      oldLayer: oldLayer,
    ),
    _clip(clipBehavior),
  );

  @override
  ui.ClipPathEngineLayer pushClipPath(
    ui.Path path, {
    ui.Clip clipBehavior = ui.Clip.antiAlias,
    ui.ClipPathEngineLayer? oldLayer,
  }) => _push(
    _builder.pushClipPath(
      path,
      clipBehavior: clipBehavior,
      oldLayer: oldLayer,
    ),
    _clip(clipBehavior),
  );

  @override
  ui.OpacityEngineLayer pushOpacity(
    int alpha, {
    ui.Offset? offset = ui.Offset.zero,
    ui.OpacityEngineLayer? oldLayer,
  }) => _push(
    _builder.pushOpacity(alpha, offset: offset, oldLayer: oldLayer),
    alpha == 255 ? _Kind.plain : _Kind.fade,
  );

  @override
  ui.ColorFilterEngineLayer pushColorFilter(
    ui.ColorFilter filter, {
    ui.ColorFilterEngineLayer? oldLayer,
  }) => _push(
    _builder.pushColorFilter(filter, oldLayer: oldLayer),
    _Kind.saved,
  );

  @override
  ui.ImageFilterEngineLayer pushImageFilter(
    ui.ImageFilter filter, {
    ui.Offset offset = ui.Offset.zero,
    ui.ImageFilterEngineLayer? oldLayer,
  }) {
    final name = '$filter';
    final pushed = _push(
      _builder.pushImageFilter(filter, offset: offset, oldLayer: oldLayer),
      name.startsWith('ImageFilter.shader')
          ? _Kind.glass
          : name.startsWith('ImageFilter.blur')
          ? _Kind.blur
          : _Kind.saved,
    );
    _awaitsPin = name.startsWith('ImageFilter.shader');
    return pushed;
  }

  @override
  ui.BackdropFilterEngineLayer pushBackdropFilter(
    ui.ImageFilter filter, {
    ui.BlendMode blendMode = ui.BlendMode.srcOver,
    ui.BackdropFilterEngineLayer? oldLayer,
    int? backdropId,
  }) => _push(
    _builder.pushBackdropFilter(
      filter,
      blendMode: blendMode,
      oldLayer: oldLayer,
      backdropId: backdropId,
    ),
    _Kind.glass,
  );

  @override
  ui.ShaderMaskEngineLayer pushShaderMask(
    ui.Shader shader,
    ui.Rect maskRect,
    ui.BlendMode blendMode, {
    ui.ShaderMaskEngineLayer? oldLayer,
    ui.FilterQuality filterQuality = ui.FilterQuality.low,
  }) => _push(
    _builder.pushShaderMask(
      shader,
      maskRect,
      blendMode,
      oldLayer: oldLayer,
      filterQuality: filterQuality,
    ),
    _Kind.saved,
  );

  @override
  void pop() {
    _settlePin();
    _open.removeLast();
    _builder.pop();
  }

  @override
  void addRetained(ui.EngineLayer retainedLayer) {
    _settlePin();
    if (_layers[retainedLayer] case final layer?) {
      _open.last.children.add(layer);
    }
    _builder.addRetained(retainedLayer);
  }

  @override
  void addPerformanceOverlay(int enabledOptions, ui.Rect bounds) =>
      _builder.addPerformanceOverlay(enabledOptions, bounds);

  @override
  void addPicture(
    ui.Offset offset,
    ui.Picture picture, {
    bool isComplexHint = false,
    bool willChangeHint = false,
  }) {
    _settlePin(picture);
    _open.last.ownPictures++;
    _builder.addPicture(
      offset,
      picture,
      isComplexHint: isComplexHint,
      willChangeHint: willChangeHint,
    );
  }

  @override
  void addTexture(
    int textureId, {
    ui.Offset offset = ui.Offset.zero,
    double width = 0.0,
    double height = 0.0,
    bool freeze = false,
    ui.FilterQuality filterQuality = ui.FilterQuality.low,
  }) => _builder.addTexture(
    textureId,
    offset: offset,
    width: width,
    height: height,
    freeze: freeze,
    filterQuality: filterQuality,
  );

  @override
  void addPlatformView(
    int viewId, {
    ui.Offset offset = ui.Offset.zero,
    double width = 0.0,
    double height = 0.0,
  }) => _builder.addPlatformView(
    viewId,
    offset: offset,
    width: width,
    height: height,
  );

  @override
  ui.Scene build() {
    _settlePin();
    _sceneTargets = _open.first.glassTargets;
    return _builder.build();
  }
}

class _Binding extends AutomatedTestWidgetsFlutterBinding {
  @override
  ui.SceneBuilder createSceneBuilder() => _Counting(super.createSceneBuilder());
}

Future<void> _open(WidgetTester tester, String tab) async {
  tester.view.physicalSize = _screen * _dpr;
  tester.view.devicePixelRatio = _dpr;
  tester.view.padding = const FakeViewPadding(
    top: 62 * _dpr,
    bottom: 34 * _dpr,
  );
  addTearDown(tester.view.reset);
  glassReadsCopies = true;
  addTearDown(() => glassReadsCopies = false);
  // No read buys an image, so every frame shows what its reads issue.
  debugGlassPrices = const PlanPrices(imageRaster: 100000);
  addTearDown(() => debugGlassPrices = const PlanPrices());
  // A frost drawn before its program is loaded is one layer of sparse taps,
  // which the plan counts as the two it becomes.
  await tester.runAsync(precacheGlass);
  await tester.pumpWidget(
    const GalleryApp(home: StandHome()),
  );
  for (var i = 0; i < 40; i++) {
    await tester.pump(_frame);
  }
  await tester.tap(find.text(tab).last);
  for (var i = 0; i < 60; i++) {
    await tester.pump(_frame);
  }
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  for (var i = 0; i < 5; i++) {
    await tester.pump(_frame);
  }
  tester.takeException();
}

void main() {
  _Binding();
  final skip = !ui.ImageFilter.isShaderFilterSupported;
  GlassFrameReport? report;
  void listen(GlassFrameReport next) => report = next;

  setUp(() {
    report = null;
    _unpinned = 0;
    GlassFrameReports.addListener(listen);
  });
  tearDown(() => GlassFrameReports.removeListener(listen));

  for (final tab in ['Controls', 'Motion', 'Photos', 'Present']) {
    testWidgets('a scroll of $tab issues the targets its plan counts', (
      tester,
    ) async {
      await _open(tester, tab);
      final scrollable = tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .firstWhere(
            (state) =>
                state.position.maxScrollExtent > 200 &&
                state.position.axis == Axis.vertical,
          );
      var seen = 0;
      for (var i = 0; i < 40; i++) {
        scrollable.position.jumpTo(60.0 + i * 23);
        await tester.pump(_frame);
        expect(
          _sceneTargets,
          report!.targetCount,
          reason: 'frame $i of $tab\n$report',
        );
        expect(_unpinned, 0, reason: 'frame $i of $tab');
        if (_sceneTargets > seen) seen = _sceneTargets;
      }
      expect(seen, greaterThan(0), reason: 'no read of $tab was in the scene');
      await _close(tester);
    }, skip: skip);
  }

  testWidgets('a lens carried over its bar issues the targets its plan '
      'counts', (tester) async {
    await _open(tester, 'Controls');
    final bar = tester.getRect(find.byType(GlassTabBar));
    final gesture = await tester.startGesture(
      bar.centerLeft + const Offset(40, 0),
    );
    var seen = 0;
    for (var i = 0; i < 50; i++) {
      await gesture.moveBy(const Offset(4, 0));
      await tester.pump(_frame);
      expect(
        _sceneTargets,
        report!.targetCount,
        reason: 'frame $i\n$report',
      );
      expect(_unpinned, 0, reason: 'frame $i');
      if (_sceneTargets > seen) seen = _sceneTargets;
    }
    // The lens holds the bar's read, which its copy draws again.
    expect(seen, greaterThan(2));
    await gesture.up();
    await _close(tester);
  }, skip: skip);
}
