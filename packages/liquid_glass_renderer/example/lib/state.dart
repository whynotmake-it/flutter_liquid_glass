import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// Start from the fitted toolbar material. Frost-free glass is reserved for
/// the explicit clear-glass/loupe examples.
LiquidGlassSettings exampleDefaultGlassSettingsForBrightness(
  Brightness brightness,
) {
  final settings = LiquidGlassSettings.ios27Toolbar(brightness: brightness);
  return _useTestBackground
      ? settings.copyWith(frost: _testBlur.toDouble())
      : settings;
}

LiquidGlassAppearance exampleDefaultAppearanceFor(Brightness brightness) =>
    const LiquidGlassAppearance.ios27ToolbarLight().copyWith(
      tint: brightness == Brightness.dark
          ? const LiquidGlassAppearance.ios27ToolbarDark().tint
          : const LiquidGlassAppearance.ios27ToolbarLight().tint,
    );

/// Live material settings edited by the playground and applied to every glass
/// shape in the app through the single shared [LiquidGlassLayer].
final settingsNotifier = ValueNotifier(
  exampleDefaultGlassSettingsForBrightness(Brightness.light),
);

final appearanceNotifier = ValueNotifier<LiquidGlassAppearance>(
  const LiquidGlassAppearance.ios27ToolbarLight(),
);

/// Whether every surface uses the Skia-compatible [FakeGlass] fallback
/// instead of the full Flutter-GPU renderer.
final fakeNotifier = ValueNotifier<bool>(false);

/// The backdrop rendered behind all glass: `image`, `grid`, `black`, `white`.
final backgroundNotifier = ValueNotifier<String>('image');

/// Bumped when an asynchronous backdrop finishes loading. Recreating the
/// retained glass layer at that point prevents its initial black frame from
/// persisting until an unrelated scroll invalidates it.
final backgroundRevisionNotifier = ValueNotifier<int>(0);

const _useTestBackground = bool.fromEnvironment(
  'LIQUID_GLASS_EXAMPLE_TEST_BACKGROUND',
);
const _testBlur = int.fromEnvironment(
  'LIQUID_GLASS_EXAMPLE_TEST_BLUR',
);
