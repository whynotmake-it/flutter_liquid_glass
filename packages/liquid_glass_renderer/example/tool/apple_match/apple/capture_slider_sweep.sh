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
#   LOUPE_SCENES  capture_loupe.sh scenes (default loupe loupe_dark; empty skips)
#   SWEEP_LOG     result log (default references/.staging/slider-sweep.log)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${IOS_27_UDID:?Set IOS_27_UDID to a dedicated iOS 27 simulator UDID}"
: "${SLIDERS:=0 0.25 0.5 0.75 1}"
: "${SCENES:=toolbar_capsule toolbar_capsule_dark small_capsule small_capsule_dark large_capsule large_capsule_dark material_card material_card_dark material_circle material_circle_dark material_capsule_clear material_capsule_clear_dark material_card_clear material_card_clear_dark material_solid_palette material_solid_palette_dark material_solid_palette_clear material_solid_palette_clear_dark}"
: "${LOUPE_SCENES=loupe loupe_dark}"
: "${SWEEP_LOG:=$ROOT/references/.staging/slider-sweep.log}"
export IOS_27_UDID
mkdir -p "$(dirname "$SWEEP_LOG")" "$ROOT/references/.staging"

log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$SWEEP_LOG"; }

failed_checkpoints=()

validate_reference_for_slider() {
  python3 - "$ROOT" "$1" "$2" "$3" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
reference = Path(sys.argv[2])
scene_id = sys.argv[3]
slider = float(sys.argv[4])
sys.path.insert(0, str(root))
import reference_provenance as provenance

metadata = provenance.validate_reference_for_scene(
    reference, root / "scenes" / f"{scene_id}.json"
)
readback = metadata.get("liquidGlassTintPositionReadback")
if metadata["reduceMotion"] is not False or readback is None:
    raise SystemExit(1)
if abs(float(readback) - slider) > 0.001:
    raise SystemExit(1)
PY
}

# Captures one scene list with the shared retry/validation contract. The
# outer slider loop's $slider/$percent/$reference_set globals provide the
# checkpoint; a loupe script name switches the log label and log-file prefix.
capture_scenes() {
  local script="$1" scene_list="$2"
  local label='' log_prefix=''
  if [[ "$script" == capture_loupe.sh ]]; then
    label='loupe '
    log_prefix='loupe-'
  fi
  local scene destination force captured checkpoint attempt
  for scene in $scene_list; do
    destination="$ROOT/references/$reference_set/$scene"
    if [[ -d "$destination" ]] \
      && validate_reference_for_slider "$destination" "$scene" "$slider"; then
      log "slider=$slider ${label}scene=$scene existing reference validated"
      continue
    fi

    force=0
    [[ -d "$destination" ]] && force=1
    captured=0
    checkpoint="slider=$slider ${label}scene=$scene"
    for attempt in 1 2 3; do
      log "slider=$slider ${label}scene=$scene attempt=$attempt"
      if REDUCE_MOTION=0 CAPTURE_SETTLE_SECONDS=3.0 \
        LIQUID_GLASS_TINT_POSITION="$slider" FORCE_REFERENCE="$force" \
        SCENE_ID="$scene" REFERENCE_SET="$reference_set" \
        bash "$ROOT/apple/$script" \
          >"$ROOT/references/.staging/$log_prefix$scene-$percent.log" 2>&1 \
        && validate_reference_for_slider "$destination" "$scene" "$slider"; then
        captured=1
        break
      fi
      force=1
    done
    if [[ "$captured" == "1" ]]; then
      log "slider=$slider ${label}scene=$scene captured"
    else
      log "slider=$slider ${label}scene=$scene FAILED"
      failed_checkpoints+=("$checkpoint")
    fi
  done
}

for slider in $SLIDERS; do
  percent="$(python3 -c 'import sys; print(f"{round(float(sys.argv[1]) * 100):03d}")' "$slider")"
  reference_set="ios27-iphone17pro-reduce-motion-off/slider-$percent"
  if ! bash "$ROOT/apple/set_transparency_slider.sh" "$slider" >/dev/null; then
    log "slider=$slider could not be set; skipping checkpoint"
    failed_checkpoints+=("slider=$slider (slider setting failed; scenes not attempted)")
    continue
  fi

  capture_scenes capture.sh "$SCENES"
  capture_scenes capture_loupe.sh "$LOUPE_SCENES"
done

if ((${#failed_checkpoints[@]})); then
  printf 'Failed checkpoints:\n' >&2
  printf ' - %s\n' "${failed_checkpoints[@]}" >&2
  exit 1
fi

log "sweep done"
