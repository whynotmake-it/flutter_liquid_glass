import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/composer/plan_scenery.dart';
import 'package:liquid_glass_renderer/src/composer/plan_site.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_form.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_underlay.dart';

import 'generated_layers.dart';

const _dpr = 2.625;

class _Blurred extends OffsetLayer {
  _Blurred(this.sigma);

  final double sigma;
}

typedef _Seen = ({ui.Picture? picture, Rect screen, int order});

Map<Layer, _Seen> _leaves(GlassForm form) {
  final seen = Map<Layer, _Seen>.identity();
  for (var i = 0; i < form.length; i++) {
    final node = form.nodeAt(i);
    switch (node) {
      case PictureNode(:final picture, :final screen):
        seen[node.layer] = (picture: picture, screen: screen, order: i);
      case VolatileNode(:final screen):
        seen[node.layer] = (picture: null, screen: screen, order: i);
      case OpenNode() || OutputNode():
        break;
    }
  }
  return seen;
}

void _expectSameAsFresh(GlassForm form, ContainerLayer root, String why) {
  final fresh = GlassForm()..lower(root, _dpr, GeneratedLayers.screen);
  expect(form.length, fresh.length, reason: why);
  for (var i = 0; i < form.length; i++) {
    final a = form.nodeAt(i);
    final b = fresh.nodeAt(i);
    expect(identical(a.layer, b.layer), isTrue, reason: '$why at $i');
    expect(a.extent, b.extent, reason: '$why extent at $i ${a.runtimeType}');
    if (a is OpenNode && b is OpenNode) {
      expect(a.end, b.end, reason: '$why end at $i');
      expect(a.world.dx, b.world.dx, reason: '$why dx at $i');
      expect(a.world.dy, b.world.dy, reason: '$why dy at $i');
      expect(a.world.clip, b.world.clip, reason: '$why clip at $i');
      expect(a.world.filtered, b.world.filtered, reason: '$why filtered at $i');
      expect(a.world.state.same(b.world.state), isTrue, reason: '$why at $i');
      expect(
        a.world.base.storage,
        b.world.base.storage,
        reason: '$why base at $i',
      );
    }
  }
}

void main() {
  test('a world keeps its base when given an equal matrix', () {
    final held = Matrix4.diagonal3Values(2, 2, 1);
    final world = FormWorld(held);
    final stamp = world.stamp;

    final equal = world.set(
      Matrix4.diagonal3Values(2, 2, 1),
      0,
      0,
      null,
      StateChain.root,
      spread: 0,
    );
    expect(equal, isFalse);
    expect(world.stamp, stamp);

    final moved = world.set(
      Matrix4.diagonal3Values(2, 2, 1),
      4,
      0,
      null,
      StateChain.root,
      spread: 0,
    );
    expect(moved, isTrue);
    expect(world.base, same(held));

    final scaled = Matrix4.diagonal3Values(3, 3, 1);
    expect(world.inherit(FormWorld(scaled)), isTrue);
    expect(world.base, same(scaled));
  });

  group('lower', () {
    test('an unchanged tree logs nothing but its volatile content', () {
      for (var seed = 0; seed < 200; seed++) {
        final scene = GeneratedLayers(seed);
        final form = GlassForm()
          ..lower(scene.root, _dpr, GeneratedLayers.screen);
        final stamps = [
          for (var i = 0; i < form.length; i++) form.nodeAt(i).changedAt,
        ];
        form.lower(scene.root, _dpr, GeneratedLayers.screen);
        final volatile = [
          for (var i = 0; i < form.length; i++)
            if (form.nodeAt(i) case VolatileNode(:final screen)
                when !screen.isEmpty)
              i,
        ];
        expect(
          form.dirty.length,
          volatile.length.clamp(0, DirtyLog.capacity),
          reason: 'seed $seed',
        );
        for (var i = 0; i < form.length; i++) {
          if (form.nodeAt(i) is VolatileNode) continue;
          expect(form.nodeAt(i).changedAt, stamps[i], reason: 'seed $seed');
        }
      }
    });

    test('equals a fresh form after every change', () {
      for (var seed = 0; seed < 300; seed++) {
        final scene = GeneratedLayers(seed);
        final form = GlassForm()
          ..lower(scene.root, _dpr, GeneratedLayers.screen);
        for (var step = 0; step < 30; step++) {
          scene.mutate();
          form.lower(scene.root, _dpr, GeneratedLayers.screen);
          _expectSameAsFresh(form, scene.root, 'seed $seed step $step');
        }
      }
    });

    test('logs every leaf that changed, left or arrived', () {
      for (var seed = 0; seed < 300; seed++) {
        final scene = GeneratedLayers(seed);
        final form = GlassForm()
          ..lower(scene.root, _dpr, GeneratedLayers.screen);
        for (var step = 0; step < 30; step++) {
          final before = _leaves(form);
          scene.mutate();
          form.lower(scene.root, _dpr, GeneratedLayers.screen);
          final after = _leaves(form);
          void expectLogged(Rect rect, String what) {
            if (rect.isEmpty) return;
            expect(
              form.dirty.meets(1 << 30, rect),
              isTrue,
              reason: 'seed $seed step $step: $what $rect',
            );
          }

          after.forEach((layer, now) {
            final was = before[layer];
            if (was == null) {
              expectLogged(now.screen, 'arrived');
            } else if (!identical(was.picture, now.picture) ||
                was.screen != now.screen) {
              expectLogged(was.screen, 'moved from');
              expectLogged(now.screen, 'moved to');
            }
          });
          before.forEach((layer, was) {
            if (!after.containsKey(layer)) expectLogged(was.screen, 'left');
          });
        }
      }
    });

    test('a scroll logs its boundary once, not each of its cells', () {
      final list = OffsetLayer();
      for (var i = 0; i < 40; i++) {
        final cell = OffsetLayer(offset: Offset(0, i * 60.0));
        final picture = PictureLayer(const Rect.fromLTWH(0, 0, 400, 60));
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawPaint(Paint());
        picture.picture = recorder.endRecording();
        cell.append(picture);
        list.append(cell);
      }
      final root = ContainerLayer()..append(list);
      final form = GlassForm()..lower(root, _dpr, GeneratedLayers.screen);
      list.offset = const Offset(0, -10);
      form.lower(root, _dpr, GeneratedLayers.screen);
      expect(form.dirty.length, 2);
    });

    test('a layer a composited update changes shows up in the walk', () {
      final fade = OpacityLayer(alpha: 200);
      final picture = PictureLayer(const Rect.fromLTWH(0, 0, 100, 100));
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawPaint(Paint());
      picture.picture = recorder.endRecording();
      fade.append(picture);
      final root = ContainerLayer()..append(fade);
      final form = GlassForm()
        ..lower(root, _dpr, GeneratedLayers.screen)
        ..lower(root, _dpr, GeneratedLayers.screen);
      expect(form.dirty.isEmpty, isTrue);
      fade.alpha = 100;
      form.lower(root, _dpr, GeneratedLayers.screen);
      expect(form.dirty.isEmpty, isFalse);
      expect(
        form.lastChangedUnder(100, const Rect.fromLTWH(0, 0, 10, 10)),
        form.frame,
      );
    });

    test('a blur of a known width spreads what it holds only so far', () {
      LiquidGlassUnderlay.registerLayer<_Blurred>(
        (layer) => (
          transform: Matrix4.translationValues(
            layer.offset.dx,
            layer.offset.dy,
            0,
          ),
          clip: null,
          alpha: null,
          blur: layer.sigma,
        ),
      );
      PictureLayer leaf() {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawPaint(Paint());
        return PictureLayer(const Rect.fromLTWH(0, 0, 105, 42))
          ..picture = recorder.endRecording();
      }

      final known = leaf();
      final unknown = leaf();
      final root = ContainerLayer()
        ..append(
          _Blurred(5.25)
            ..offset = const Offset(210, 525)
            ..append(known),
        )
        ..append(
          ImageFilterLayer(
            imageFilter: ui.ImageFilter.blur(sigmaX: 5.25, sigmaY: 5.25),
          )..append(unknown),
        );
      final form = GlassForm()..lower(root, _dpr, GeneratedLayers.screen);
      final leaves = _leaves(form);
      // Four sigmas of two logical pixels around the picture.
      expect(
        leaves[known]!.screen,
        const Rect.fromLTWH(80, 200, 40, 16).inflate(8),
      );
      expect(leaves[unknown]!.screen, Rect.largest);
    });
  });

  group('asks', () {
    test('an equal ask is kept; another replans and logs what it draws', () {
      final form = GlassForm();
      final root = ContainerLayer();
      final site = SiteFacts(Object());
      const rect = Rect.fromLTWH(10, 10, 44, 44);
      SiteAsk ask({NoJoin? noJoin, Object? paints}) => SiteAsk(
        drawn: rect,
        reads: rect.inflate(8),
        noJoin: noJoin,
        paints: paints,
      );
      form
        ..lower(root, _dpr, GeneratedLayers.screen)
        ..noteAsk(site, ask());
      final first = site.ask;

      form
        ..lower(root, _dpr, GeneratedLayers.screen)
        ..noteAsk(site, ask());
      expect(identical(site.ask, first), isTrue);
      expect(form.asksChanged, isFalse);
      expect(form.dirty.isEmpty, isTrue);

      form
        ..lower(root, _dpr, GeneratedLayers.screen)
        ..noteAsk(site, ask(noJoin: NoJoin.field));
      expect(form.asksChanged, isTrue);
      expect(form.dirty.isEmpty, isTrue, reason: 'it draws the same');

      form
        ..lower(root, _dpr, GeneratedLayers.screen)
        ..noteAsk(site, ask(noJoin: NoJoin.field, paints: 1));
      expect(form.dirty.meets(1, rect), isTrue);

      form
        ..lower(root, _dpr, GeneratedLayers.screen)
        ..noteAsk(site, SiteAsk.none);
      expect(form.dirty.meets(1, rect), isTrue, reason: 'what it drew left');
    });
  });
}
