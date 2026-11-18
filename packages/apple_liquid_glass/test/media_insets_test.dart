import 'package:apple_liquid_glass/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'an overlay keeps the larger of the safe area and the keyboard clear',
    () {
      const safe = MediaQueryData(padding: EdgeInsets.fromLTRB(1, 2, 3, 34));
      expect(safe.bottomAboveKeyboard, 34);
      expect(safe.paddingAboveKeyboard, const EdgeInsets.fromLTRB(1, 2, 3, 34));

      final typing = safe.copyWith(
        viewInsets: const EdgeInsets.only(bottom: 300),
      );
      expect(typing.bottomAboveKeyboard, 300);
      expect(
        typing.paddingAboveKeyboard,
        const EdgeInsets.fromLTRB(1, 2, 3, 300),
      );
    },
  );
}
