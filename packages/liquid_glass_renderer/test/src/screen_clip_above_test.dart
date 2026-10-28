import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/ancestor_clip.dart';

const _key = ValueKey('leaf');

/// The intersection of every clip above [node], each mapped by its owner's
/// own `getTransformTo(null)`: the per-clip walk [screenClipAbove] must match.
Rect? _reference(RenderObject node) {
  Rect? result;
  var child = node;
  for (
    var ancestor = child.parent;
    ancestor != null;
    child = ancestor, ancestor = ancestor.parent
  ) {
    final clip = clipOfAncestor(ancestor, child);
    if (clip == null) continue;
    final screenClip = MatrixUtils.transformRect(
      ancestor.getTransformTo(null),
      clip,
    );
    result = result?.intersect(screenClip) ?? screenClip;
  }
  return result;
}

void main() {
  testWidgets('the screen clip above a node matches a walk per clip', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 21, 7, 5),
          child: ClipRect(
            child: Transform.scale(
              scale: 0.8,
              child: Transform.translate(
                offset: const Offset(17, -9),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ListView(
                    children: [
                      const SizedBox(height: 40),
                      Center(
                        child: ClipPath(
                          clipper: const ShapeBorderClipper(
                            shape: StadiumBorder(),
                          ),
                          child: Transform.rotate(
                            angle: 0.1,
                            child: const SizedBox(
                              key: _key,
                              width: 120,
                              height: 60,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2000),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -30));
    await tester.pump();

    final leaf = tester.renderObject(find.byKey(_key));
    final expected = _reference(leaf)!;
    final actual = screenClipAbove(leaf)!;
    expect(actual.left, moreOrLessEquals(expected.left, epsilon: 1e-6));
    expect(actual.top, moreOrLessEquals(expected.top, epsilon: 1e-6));
    expect(actual.right, moreOrLessEquals(expected.right, epsilon: 1e-6));
    expect(actual.bottom, moreOrLessEquals(expected.bottom, epsilon: 1e-6));
  });
}
