import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/transform_tracking_render_object_mixin.dart';
import 'package:material_ui/material_ui.dart';

Widget _glass() => LiquidGlassLayer(
  settings: LiquidGlassSettings.ios27RegularLight(),
  child: const SizedBox(
    width: 120,
    height: 60,
    child: LiquidGlass(
      shape: LiquidRoundedSuperellipse(borderRadius: 20),
      child: SizedBox.expand(),
    ),
  ),
);

List<GlassComposer> _composers() =>
    GlassComposer.debugAllUnder(RendererBinding.instance.rootPipelineOwner);

void main() {
  testWidgets('glass of one view shares one composer, dropped with the last', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [_glass(), _glass()]),
      ),
    );
    expect(_composers(), hasLength(1));
    final census = _composers().single.census;
    final frames = census.frames;
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(census.frames, frames + 1);
    expect(census.sites, census.frames * 2);

    await tester.pumpWidget(const SizedBox());
    expect(_composers(), isEmpty);
  });

  testWidgets('glass built lazily during layout adopts and drops a composer', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ListView.builder(
          controller: controller,
          itemExtent: 100,
          itemCount: 100,
          itemBuilder: (context, index) =>
              index.isEven ? _glass() : const SizedBox.shrink(),
        ),
      ),
    );
    expect(_composers(), hasLength(1));
    controller.jumpTo(5000);
    await tester.pump();
    expect(_composers(), hasLength(1));

    await tester.pumpWidget(const SizedBox());
    expect(_composers(), isEmpty);
  });

  testWidgets('a composer lives with semantics on', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      Directionality(textDirection: TextDirection.ltr, child: _glass()),
    );
    expect(_composers(), hasLength(1));
    await tester.pumpWidget(const SizedBox());
    expect(_composers(), isEmpty);
    semantics.dispose();
  });

  testWidgets('the composer plans a frame ahead of the scene, and a scene it '
      'did not plan plans its own', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            _glass(),
            RepaintBoundary(
              child: _Recorder(
                log: log,
                name: 'outer',
                child: _Recorder(
                  log: log,
                  name: 'inner',
                  child: const SizedBox.square(dimension: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    log.clear();
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(log, ['outer planned', 'inner planned']);

    log.clear();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find
          .ancestor(
            of: find.byType(_Recorder).first,
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    (await tester.runAsync(boundary.toImage))!.dispose();
    expect(log, ['outer unplanned', 'inner unplanned']);
  });

  testWidgets('a view whose only composed layer a host holds has one composer '
      'while the host is attached, planned ahead, and none once it detaches', (
    tester,
  ) async {
    final log = <String>[];
    GlassComposer.debugComposedAlone = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          child: _Recorder(
            log: log,
            name: 'host',
            hosts: true,
            child: const SizedBox.square(dimension: 20),
          ),
        ),
      ),
    );
    expect(_composers(), hasLength(1));
    final composer = _composers().single;
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(_composers().single, same(composer));
    expect(log, isNotEmpty);
    expect(log, everyElement('host planned'));
    expect(GlassComposer.debugComposedAlone, 0);

    await tester.pumpWidget(const SizedBox());
    expect(_composers(), isEmpty);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('fake glass alone in a view holds a composer while attached', (
    tester,
  ) async {
    GlassComposer.debugComposedAlone = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 120,
            height: 60,
            child: FakeGlass(
              shape: const LiquidRoundedSuperellipse(borderRadius: 20),
              settings: LiquidGlassSettings.ios27RegularLight(),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    expect(_composers(), hasLength(1));
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(GlassComposer.debugComposedAlone, 0);

    await tester.pumpWidget(const SizedBox());
    expect(_composers(), isEmpty);
  });

  testWidgets('a composed layer in a frame with no registered holder asserts', (
    tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          child: _Recorder(
            log: log,
            name: 'stray',
            child: const SizedBox.square(dimension: 20),
          ),
        ),
      ),
    );
    final error = tester.takeException();
    expect(error, isA<AssertionError>());
    expect(
      '$error',
      allOf(
        contains('_RecordingLayer'),
        contains('LiquidGlassBackdropFilterHost'),
      ),
    );
    await tester.pumpWidget(const SizedBox());
  });

  test('each owner gets its own composer and can be disposed after', () {
    final a = PipelineOwner();
    final b = PipelineOwner();
    final siteA = _Site();
    final siteB = _Site();
    GlassComposer.track(a, siteA);
    GlassComposer.track(b, siteB);
    final composers = [
      ...GlassComposer.debugAllUnder(a),
      ...GlassComposer.debugAllUnder(b),
    ];
    expect(composers, hasLength(2));
    expect(identical(composers.first, composers.last), isFalse);

    GlassComposer.untrack(a, siteA);
    GlassComposer.untrack(b, siteB);
    expect(GlassComposer.debugAllUnder(a), isEmpty);
    a.dispose();
    b.dispose();
  });
}

class _Site extends RenderProxyBox with TransformTrackingRenderObjectMixin {
  @override
  void onTransformChanged() {}
}

class _Recorder extends SingleChildRenderObjectWidget {
  const _Recorder({
    required this.log,
    required this.name,
    this.hosts = false,
    super.child,
  });

  final List<String> log;
  final String name;
  final bool hosts;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      hosts ? _RenderHostRecorder(log, name) : _RenderRecorder(log, name);
}

class _RenderRecorder extends RenderProxyBox {
  _RenderRecorder(this.log, this.name);

  final List<String> log;
  final String name;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final layer =
        (this.layer as _RecordingLayer?) ?? _RecordingLayer(log, name);
    this.layer = layer;
    context.pushLayer(layer, super.paint, offset);
  }
}

class _RenderHostRecorder extends _RenderRecorder
    with LiquidGlassBackdropFilterHost {
  _RenderHostRecorder(super.log, super.name);

  @override
  Layer? get composedLayer => layer;
}

class _RecordingLayer extends OffsetLayer with ComposedLayer {
  _RecordingLayer(this.log, this.name);

  final List<String> log;
  final String name;

  @override
  void updateSubtreeNeedsAddToScene() {
    log.add('$name ${composedAhead ? 'planned' : 'unplanned'}');
    super.updateSubtreeNeedsAddToScene();
  }
}
