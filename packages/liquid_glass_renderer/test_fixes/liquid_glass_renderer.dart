import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

const shape = LiquidRoundedSuperellipse(borderRadius: 20);
final key = BackdropKey();

void debugGeometry() {
  debugPaintLiquidGlassGeometry = true;
}

LiquidGlassSettings settings(BuildContext context) =>
    LiquidGlassSettings.of(context);

Widget backdropGroups() {
  return LiquidGlassLayer(
    useBackdropGroup: true,
    backdropKey: key,
    child: Column(
      children: [
        LiquidGlass.auto(
          shape: shape,
          useBackdropGroup: true,
          backdropKey: key,
          child: const SizedBox(),
        ),
        LiquidGlass.withOwnLayer(
          shape: shape,
          useBackdropGroup: true,
          child: const SizedBox(),
        ),
        FakeGlass(shape: shape, backdropKey: key, child: const SizedBox()),
      ],
    ),
  );
}

LiquidGlassSettings slider(LiquidGlassSettings base) {
  final light = LiquidGlassSettings.ios27RegularLight(tintAmount: 0.5);
  final dark = LiquidGlassSettings.ios27RegularDark();
  final regular = LiquidGlassSettings.ios27Regular(
    brightness: Brightness.dark,
    tintAmount: 1,
  );
  final clear = LiquidGlassSettings.ios27Clear(tintAmount: 0.25);
  const plain = LiquidGlassSettings(tintAmount: 0.5, highlight: 0.4);
  return base.copyWith(
    tintAmount: light.tintAmount + dark.tintAmount + clear.tintAmount,
    highlight: regular.highlight + plain.highlight,
  );
}

List<LiquidGlassAppearance> appearances() => [
  LiquidGlassAppearance.ios27RegularLight(),
  LiquidGlassAppearance.ios27RegularDark(tint: const Color(0xFF0A84FF)),
  const LiquidGlassAppearance(
    colorModel: LiquidGlassColorModel.ios27(brightness: Brightness.light),
  ),
];

List<LiquidShape> shapes(LiquidRoundedRectangle box) => [
  LiquidRoundedSuperellipse(borderRadius: 20),
  LiquidRoundedRectangle(borderRadius: 8),
  box.copyWith(borderRadius: 4),
];

Future<void> warm() async {
  await LiquidGlass.precache();
  await Future.wait([LiquidGlass.precache()]).then((_) => LiquidGlass.precache);
}

Widget blended() => LiquidGlassBlendGroup(
  child: Row(
    children: [
      LiquidGlass.grouped(shape: shape, child: const SizedBox()),
      LiquidGlass.grouped(shape: const LiquidOval(), child: const SizedBox()),
    ],
  ),
);
