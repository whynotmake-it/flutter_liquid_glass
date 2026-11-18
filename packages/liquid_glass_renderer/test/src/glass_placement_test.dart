import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';

const _shape = LiquidRoundedSuperellipse(radius: 12);

final _frame = ValueNotifier(const LiquidGlassShapeFrame(shape: _shape));

final _glass = <String, Widget Function(Widget)>{
  'a shape': (child) => LiquidGlass(shape: _shape, child: child),
  'a live shape': (child) => LiquidGlass.live(frame: _frame, child: child),
};

typedef _Place = ({Widget Function(Widget) build, bool nests, bool joins});

final _places = <String, _Place>{
  'beside other glass': (build: (inner) => inner, nests: false, joins: false),
  'in a blend group': (
    build: (inner) => LiquidGlassBlendGroup(child: inner),
    nests: false,
    joins: true,
  ),
  'in a body': (
    build: (inner) => LiquidGlass(shape: _shape, child: inner),
    nests: true,
    joins: false,
  ),
  'in a body in a blend group': (
    build: (inner) => LiquidGlassBlendGroup(
      child: LiquidGlass(shape: _shape, child: inner),
    ),
    nests: true,
    joins: false,
  ),
  'in a blend group in a body': (
    build: (inner) => LiquidGlass(
      shape: _shape,
      child: LiquidGlassBlendGroup(child: inner),
    ),
    nests: true,
    joins: true,
  ),
  'on a layer in a blend group': (
    build: (inner) => LiquidGlassBlendGroup(
      child: LiquidGlassLayer(fake: true, child: inner),
    ),
    nests: true,
    joins: false,
  ),
};

Widget _scene(Widget Function(Widget) place, Widget inner) => Directionality(
  textDirection: TextDirection.ltr,
  child: LiquidGlassLayer(
    fake: true,
    child: Center(
      child: SizedBox(
        width: 200,
        height: 120,
        child: place(
          Center(child: SizedBox.square(dimension: 40, child: inner)),
        ),
      ),
    ),
  ),
);

bool _holds(LiquidGlassRenderObject layer, RenderLiquidGlass glass) =>
    layer.link.shapes.any(
      (shape) =>
          identical(shape, glass) ||
          shape is RenderLiquidGlassBlendGroup &&
              shape.link.shapes.contains(glass),
    );

void main() {
  tearDownAll(_frame.dispose);

  for (final MapEntry(key: where, value: place) in _places.entries) {
    for (final MapEntry(key: what, value: glass) in _glass.entries) {
      testWidgets('$what $where draws on '
          '${place.nests ? 'a layer of its own' : 'the outer layer'}'
          '${place.joins ? ', in the group' : ''}', (tester) async {
        await tester.pumpWidget(
          _scene(place.build, glass(const SizedBox.expand())),
        );
        await tester.pump();

        final layers = tester.allRenderObjects
            .whereType<LiquidGlassRenderObject>()
            .toSet()
            .toList();
        final inner = tester.allRenderObjects
            .whereType<RenderLiquidGlass>()
            .toSet()
            .singleWhere((glass) => glass.size == const Size.square(40));
        expect(layers, hasLength(place.nests ? 2 : 1));
        final holder = layers.singleWhere((layer) => _holds(layer, inner));
        expect(identical(holder, layers.first), !place.nests);
        expect(holder.link.shapes.contains(inner), !place.joins);
      });
    }
  }
}
