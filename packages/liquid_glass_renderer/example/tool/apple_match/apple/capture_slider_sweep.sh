#!/usr/bin/env bash
set -uo pipefail

# Capture Reduce Motion off references across the Settings → Appearance →
# Liquid Glass "Tint Amount" slider. Each checkpoint lands in
# references/ios27-iphone17pro-reduce-motion-off/slider-XXX/<scene>, and every
# metadata.json records the declared and read-back slider value.
#
# Required env:
#   IOS_27_UDID  a dedicated iOS 27 simulator (never a user's booted device)
# Optional env:
#   SLIDERS       space-separated positions in 0...1 (default 0 0.25 0.5 0.75 1)
#   SCENES        capture.sh scenes (default: the slider-model scene set)
#   LOUPE_SCENES  capture_loupe.sh scenes (default loupe loupe_dark)
#   SWEEP_LOG     result log (default references/.staging/slider-sweep.log)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${IOS_27_UDID:?Set IOS_27_UDID to a dedicated iOS 27 simulator UDID}"
: "${SLIDERS:=0 0.25 0.5 0.75 1}"
: "${SCENES:=toolbar_capsule toolbar_capsule_dark small_capsule small_capsule_dark large_capsule large_capsule_dark material_card material_card_dark material_circle material_circle_dark material_capsule_clear material_capsule_clear_dark material_card_clear material_card_clear_dark material_solid_palette material_solid_palette_dark material_solid_palette_clear material_solid_palette_clear_dark}"
: "${LOUPE_SCENES:=loupe loupe_dark}"
: "${SWEEP_LOG:=$ROOT/references/.staging/slider-sweep.log}"
export IOS_27_UDID
mkdir -p "$(dirname "$SWEEP_LOG")"

log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$SWEEP_LOG"; }

for slider in $SLIDERS; do
  percent="$(python3 -c 'import sys; print(f"{round(float(sys.argv[1]) * 100):03d}")' "$slider")"
  reference_set="ios27-iphone17pro-reduce-motion-off/slider-$percent"
  bash "$ROOT/apple/set_transparency_slider.sh" "$slider" >/dev/null || {
    log "slider=$slider could not be set; skipping checkpoint"
    continue
  }
  for scene in $SCENES; do
    destination="$ROOT/references/$reference_set/$scene"
    if [[ -d "$destination" ]] && python3 - "$destination" "$slider" <<'PY'
import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]).parents[3]))
import reference_provenance as provenance
root = Path(sys.argv[1]).parents[3]
metadata = provenance.validate_reference_for_scene(
    Path(sys.argv[1]), root / "scenes" / f"{Path(sys.argv[1]).name}.json"
)
ok = metadata["reduceMotion"] is False and abs(
    float(metadata["liquidGlassTintPositionReadback"]) - float(sys.argv[2])
) <= 0.001
raise SystemExit(0 if ok else 1)
PY
    then
      log "slider=$slider scene=$scene existing reference validated"
      continue
    fi
    force=0
    [[ -d "$destination" ]] && force=1
    captured=0
    for attempt in 1 2 3; do
      if REDUCE_MOTION=0 SCENE_ID="$scene" REFERENCE_SET="$reference_set" \
        LIQUID_GLASS_TINT_POSITION="$slider" FORCE_REFERENCE="$force" \
        bash "$ROOT/apple/capture.sh" >"$ROOT/references/.staging/$scene-$percent.log" 2>&1
      then
        captured=1
        break
      fi
      force=1
    done
    log "slider=$slider scene=$scene $([[ $captured == 1 ]] && echo captured || echo FAILED)"
  done
  for scene in $LOUPE_SCENES; do
    destination="$ROOT/references/$reference_set/$scene"
    if [[ -f "$destination/metadata.json" ]] && python3 - "$destination/metadata.json" "$slider" <<'PY'
import json, sys
metadata = json.load(open(sys.argv[1]))
readback = metadata.get("liquidGlassTintPositionReadback")
ok = metadata["reduceMotion"] is False and readback is not None and abs(
    float(readback) - float(sys.argv[2])
) <= 0.001
raise SystemExit(0 if ok else 1)
PY
    then
      log "slider=$slider scene=$scene existing loupe reference validated"
      continue
    fi
    captured=0
    for attempt in 1 2; do
      if REDUCE_MOTION=0 SCENE_ID="$scene" REFERENCE_SET="$reference_set" \
        LIQUID_GLASS_TINT_POSITION="$slider" FORCE_REFERENCE=1 \
        bash "$ROOT/apple/capture_loupe.sh" >"$ROOT/references/.staging/$scene-$percent.log" 2>&1
      then
        captured=1
        break
      fi
    done
    log "slider=$slider scene=$scene $([[ $captured == 1 ]] && echo captured || echo FAILED)"
  done
done
log "sweep done"
