#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${IOS_27_UDID:?Set IOS_27_UDID to the pinned iOS 27 simulator UDID}"
: "${DEVELOPER_DIR:=/Applications/Xcode-27.0.0-Beta.5.app/Contents/Developer}"
export DEVELOPER_DIR

if [[ "$IOS_27_UDID" != "DB4F41F3-1C36-476D-B775-AFDC3686C75B" ]]; then
  echo "Ground truth must use the pinned iPhone 17 Pro iOS 27 simulator." >&2
  exit 2
fi

# Compact, high-signal matrix. It deliberately avoids a full Cartesian product:
# size is isolated at slider 0, slider response on the toolbar, contour behavior
# on three shape families, and appearance on the toolbar plus one non-capsule.
MATRIX=(
  "0|small_capsule"
  "0|toolbar_capsule"
  "0|large_capsule"
  "0|material_capsule"
  "0|material_circle"
  "0|material_card"
  "0|toolbar_capsule_dark"
  "0|material_card_dark"
  "0|tab_bar_holdout"
  "0.5|toolbar_capsule"
  "0.5|toolbar_capsule_dark"
  "1|toolbar_capsule"
  "1|toolbar_capsule_dark"
)

for entry in "${MATRIX[@]}"; do
  IFS='|' read -r slider scene <<<"$entry"
  percent="$(python3 -c 'import sys; print(f"{round(float(sys.argv[1]) * 100):03d}")' "$slider")"
  reference_set="ios27-iphone17pro-ground-truth-v2/slider-${percent}"
  destination="$ROOT/references/$reference_set/$scene"
  scene_path="$ROOT/scenes/$scene.json"
  if [[ -d "$destination" ]]; then
    if python3 "$ROOT/reference_provenance.py" "$destination" "$scene_path" \
      --source "$ROOT/apple/Sources/AppleMatchApp.swift" \
      --capture-script "$ROOT/apple/capture.sh" >/dev/null 2>&1
    then
      echo "validated existing slider=$slider scene=$scene"
      continue
    fi
    force=1
  else
    force=0
  fi
  echo "capturing slider=$slider scene=$scene"
  captured=0
  for attempt in 1 2 3; do
    echo "capture attempt $attempt/3"
    if SCENE_ID="$scene" \
      REFERENCE_SET="$reference_set" \
      LIQUID_GLASS_TINT_POSITION="$slider" \
      CAPTURE_FRAMES=3 \
      FORCE_REFERENCE="$force" \
      IOS_27_UDID="$IOS_27_UDID" \
      DEVELOPER_DIR="$DEVELOPER_DIR" \
        bash "$ROOT/apple/capture.sh"
    then
      captured=1
      break
    fi
  done
  if [[ "$captured" != "1" ]]; then
    echo "Failed to obtain a stable validated capture: slider=$slider scene=$scene" >&2
    exit 4
  fi
done

python3 "$ROOT/audit_ground_truth.py" \
  --reference-root "$ROOT/references/ios27-iphone17pro-ground-truth-v2"
