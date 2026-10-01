# Benchmark scene registry, sourced by benchmark.sh (Metal) and
# android_gpu_bench.sh (Pixel). Every name is a `BenchmarkScenario` value in
# integration_test/benchmark_test.dart; both runners build that same file.

# App-like chrome over a scrolling list (top bar and bottom pill), plus idle.
BENCH_SUITE_APP="appScrollOpaque appScrollPlainBlur appScrollFake appScrollReal appScrollRealOneLayer appScrollRealShadow appScrollRealTabs appScrollFakeShadow appIdleReal appIdleOpaque"

# The default for both runners.
BENCH_SUITE_CORE="$BENCH_SUITE_APP baselineMotion realToolbarMaterial fakeToolbarMaterial"

# Renderer microbenchmarks: one cost axis per scene.
BENCH_SUITE_MICRO="baselineMotion staticSingle realLightingOnly fakeLightingOnly realBlurOnly fakeBlurOnly realHighBlurOnly fakeHighBlurOnly realSaturationOnly fakeSaturationOnly realBlurSaturation fakeBlurSaturation realToolbarMaterial fakeToolbarMaterial realToFakeTransition translatedSingle ancestorTranslatedLayer scaledRotatedSingle grouped4Motion fakeGrouped4Motion fakeUngrouped4Motion grouped8Motion grouped16Motion independent4Motion independent8Motion independent16Motion independent16SharedBackdrop sparse16Motion relativeBlendMotion dynamicBlend16 resizeAnimated layerChurn largeStatic largeResize largeShrinkSettled fakeStatic fakeLarge"

# The Pixel 10 A/B scenes (android_ab_bench.py), which also run on Metal:
# stable-size stretch, blend motion, resize sweeps and multi-pass layers, plus
# the mixed-appearance Colors blend group.
BENCH_SUITE_PIXEL="pxButtonStatic pxButtonStretch pxPillStretch pxBlend5Motion resizeAnimated pxSheetResize pxMultiLayer colorsBlendStatic colorsBlendMotion"

BENCH_SCENES_DART="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/integration_test/benchmark_test.dart"

# Prints every scene of the enum, one per line.
bench_all_scenes() {
  sed -n '/^enum BenchmarkScenario {/,/^}/p' "$BENCH_SCENES_DART" |
    sed -n 's/^  \([A-Za-z0-9]*\),$/\1/p'
}

# bench_resolve_scenes "core" | "app" | "micro" | "pixel" | "all" | "scene scene ..."
# Prints the scene names, or fails on a name the registry doesn't have.
bench_resolve_scenes() {
  local spec="$1" scenes known name
  case "$spec" in
    core) scenes="$BENCH_SUITE_CORE" ;;
    app) scenes="$BENCH_SUITE_APP" ;;
    micro) scenes="$BENCH_SUITE_MICRO" ;;
    pixel) scenes="$BENCH_SUITE_PIXEL" ;;
    all) scenes="$(bench_all_scenes | tr '\n' ' ')" ;;
    *) scenes="$spec" ;;
  esac
  known=" $(bench_all_scenes | tr '\n' ' ') "
  for name in $scenes; do
    if [[ "$known" != *" $name "* ]]; then
      echo "error: unknown benchmark scene '$name' (see BenchmarkScenario in $BENCH_SCENES_DART)" >&2
      return 1
    fi
  done
  echo "$scenes"
}
