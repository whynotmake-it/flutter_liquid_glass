import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/bottom_bar/listenable_transform.dart';
import 'package:liquid_glass_renderer_example/bottom_bar/loupe_tab_bar.dart';
import 'package:liquid_glass_renderer_example/bottom_bar/tab_selection.dart';

void main() {
  testWidgets('the tint source fills the lens and the cover stops at its rim', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 140)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: SizedBox(
            width: 300,
            child: LiquidGlassLayer(
              fake: true,
              child: LiquidGlassBlendGroup(
                child: LoupeTabBar(
                  fake: true,
                  tabs: const [
                    BottomBarTab(
                      icon: CupertinoIcons.house_fill,
                      label: 'Home',
                    ),
                    BottomBarTab(
                      icon: CupertinoIcons.square_grid_2x2_fill,
                      label: 'New',
                    ),
                    BottomBarTab(
                      icon: CupertinoIcons.circle,
                      label: 'Radio',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Home').first),
    );
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final clippers = tester
        .widgetList<ClipPath>(find.byType(ClipPath))
        .map((clip) => clip.clipper)
        .whereType<TabSelectionClipper>()
        .toList(growable: false);
    final tint = clippers.singleWhere(
      (clipper) => !clipper.inverse && clipper.source,
    );
    final cover = clippers.singleWhere(
      (clipper) => clipper.inverse && !clipper.source,
    );
    final selection = tint.selection;
    final clip = tester
        .widgetList<ClipPath>(find.byType(ClipPath))
        .singleWhere((clip) => identical(clip.clipper, tint));
    final size = tester.getSize(find.byWidget(clip));

    final loupe = tester.widget<LiquidGlass>(
      find.byKey(LoupeTabBar.loupeKey),
    );
    final lensRect = selection.restingRect(size);
    final lens = loupe.shape.getOuterPath(lensRect);
    final (:x, :y) = selection.jellyScale;
    final displayedLens = lens.transform(
      scaleAbout(lensRect.center, x, y).storage,
    );
    final expectedSource = lens.transform(
      scaleAbout(lensRect.center, selection.tintScale).storage,
    );

    final source = tint.getClip(size);
    final coverPath = cover.getClip(size);

    expect(selection.tintScale, greaterThan(1));
    expect(source.getBounds(), expectedSource.getBounds());

    // The tint source must cover everything the lens shows, including the
    // rim, or the shrink reveals the untinted row.
    for (var column = 0; column <= 80; column++) {
      for (var row = 0; row <= 40; row++) {
        final point = Offset(
          lensRect.left + lensRect.width * column / 80,
          lensRect.top + lensRect.height * row / 40,
        );
        if (!lens.contains(point)) continue;
        expect(
          source.contains(point),
          isTrue,
          reason: 'tint source does not cover the lens at $point',
        );
      }
    }

    // The cover must match the lens exactly: inside it would hide the tint,
    // outside it hides the source mask's spill.
    for (var column = 0; column <= 80; column++) {
      for (var row = 0; row <= 40; row++) {
        final point = Offset(
          lensRect.left - 4 + (lensRect.width + 8) * column / 80,
          lensRect.top - 4 + (lensRect.height + 8) * row / 40,
        );
        expect(
          coverPath.contains(point),
          !displayedLens.contains(point),
          reason: 'cover and lens disagree at $point',
        );
      }
    }

    // The tint stays in the backdrop, so it must remain a copy of the bar
    // content at the same position. Its distortion comes from the lens, not
    // from moving the source.
    Offset textCenter(String label, {required bool tinted}) => tester.getCenter(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data == label &&
                (widget.style?.foreground != null) == tinted,
          )
          .first,
    );

    for (final label in ['Home', 'New', 'Radio']) {
      expect(
        textCenter(label, tinted: true),
        textCenter(label, tinted: false),
        reason: '$label: the tinted copy moved away from the bar content',
      );
    }

    await gesture.up();
  });
}
