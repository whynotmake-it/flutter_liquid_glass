# Liquid Glass Renderer Improvements Plan

Based on analysis of the kube.io liquid glass CSS/SVG implementation vs the current Flutter implementation.

## Summary of Findings

### kube.io Implementation Techniques:
1. **4 Edge Profiles**: Convex Circle, Convex Squircle, Concave, Lip (blend)
2. **Pre-computed specular maps** as separate PNG textures
3. **Saturation boost** applied after displacement
4. **Filter chain**: Blur → Displacement → Saturate → Specular composite → Blend

### Current Flutter Implementation:
- Single spherical edge profile: `sqrt(thickness² - x²)`
- Specular calculated on-the-fly using displacement direction as normal proxy
- Rim-focused highlights with limited shape variation
- **Problem**: Specular width scales with thickness (user wants fixed width like kube.io)

---

## Implementation Tasks

### Task 1: Add Configurable Edge Profiles

**Files to modify:**
- `lib/src/liquid_glass_settings.dart`
- `lib/assets/shaders/liquid_glass_geometry_blended.frag`
- `lib/assets/shaders/shared.glsl`

**Edge profile formulas (from kube.io):**
```glsl
// Convex Circle: y = sqrt(1-(1-x)²) where x = normalized distance from edge (0-1)
float convexCircle(float x) {
    return sqrt(1.0 - (1.0 - x) * (1.0 - x));
}

// Convex Squircle: y = (1-(1-x)⁴)^(1/4) - superellipse, softer edges
float convexSquircle(float x) {
    float t = 1.0 - x;
    return pow(1.0 - t*t*t*t, 0.25);
}

// Concave: y = 1 - convex(x) - inverted profile
float concave(float x) {
    return 1.0 - convexCircle(x);
}

// Lip: blend of convex and concave via smootherstep - convex outside, concave inside
float lip(float x) {
    float convexPart = convexSquircle(x * 2.0);
    float concavePart = concave(x) + 0.1;
    float blend = 6.0*x*x*x*x*x - 15.0*x*x*x*x + 10.0*x*x*x; // smootherstep
    return mix(convexPart, concavePart, blend);
}
```

**Normal Calculation for Different Profiles:**

The kube.io approach computes normal from profile derivative:
```glsl
// Numerical derivative of profile function
float delta = 0.001;
float y1 = profile(x - delta);
float y2 = profile(x + delta);
float derivative = (y2 - y1) / (2.0 * delta);

// Normal from derivative (2D, then extended to 3D)
// derivative > 0 means surface slopes up → normal points "backward" (outward refraction)
// derivative < 0 means surface slopes down → normal points "forward" (inward refraction)
float normalLen = sqrt(derivative * derivative + 1.0);
vec2 normal2D = vec2(-derivative / normalLen, 1.0 / normalLen);
```

For concave profiles where center is lower than edges:
- derivative is positive going from edge to center
- This flips the effective normal direction
- Refraction bends outward instead of inward

**Current vs Required:**
```glsl
// CURRENT (always assumes convex):
float n_sin = sqrt(max(0.0, 1.0 - n_cos * n_cos));  // Always positive!
vec3 normal = normalize(vec3(dx * n_cos, dy * n_cos, n_sin));

// REQUIRED (profile-aware):
float profileDerivative = getProfileDerivative(normalizedDist, profileType);
// Use derivative to determine normal direction, including sign
```

**Changes:**

1. Add `EdgeProfile` enum to settings:
```dart
enum EdgeProfile {
  convexCircle,   // Current default - hemisphere
  convexSquircle, // Softer superellipse
  concave,        // Inverted - lower in middle
  lip,            // Convex outside, concave inside
}
```

2. Add `edgeProfile` field to `LiquidGlassSettings`

3. Pass edge profile type to geometry shader as uniform

4. Modify `getHeight()` in shared.glsl to use selected profile

5. **Critical: Update normal calculation for concave profiles**
   - Current normal.z is always positive (assumes convex surface)
   - Concave profiles need negative normal.z in depressed regions
   - Normal must be computed from profile derivative, not just SDF gradient
   - This affects refraction direction (inward for convex, outward for concave)

---

### Task 2: Fix Specular Highlights (Thickness-Independent)

**Files to modify:**
- `lib/assets/shaders/liquid_glass_final_render.frag`
- `lib/assets/shaders/liquid_glass_geometry_blended.frag`

**Current problem (lines 99-114 in final_render.frag):**
```glsl
// BUG: Specular width scales with thickness
float thicknessScale = clamp(40.0 / max(uThickness, 1.0), 1.0, 4.0);
float edgeThreshold = mix(0.8, 0.5, 1.0 / thicknessScale);
float edgeFactor = 1.0 - smoothstep(0.0, edgeThreshold, normalizedHeight);
float brightness = ... * thicknessScale * 0.8;  // Scales with thickness!
```

**kube.io approach (fixed pixel width):**
```glsl
// Fixed-width specular in screen pixels
float rimWidth = 1.5;  // pixels, NOT normalized
float x = sd / rimWidth;  // sd = signed distance in pixels
float rimFactor = 1.0 / (1.0 + 0.89 * x * x);
```

**Fix strategy (Performance-Optimized):**

Key insight: Keep current encoding (normalizedHeight), just fix the specular calculation. Since normalizedHeight is computed using the profile function in geometry shader, specular automatically follows profile shape.

1. **KEEP current encoding** (no change to displacement_encoding.glsl)
   - R=dispX, G=dispY, B=normalizedHeight, A=alpha
   - normalizedHeight already encodes profile shape from geometry shader
   - No extra computation needed in final shader
   - Encoding already supports negative displacement: `(disp/max)*0.5+0.5` maps [-max,+max] → [0,1]
   - Verify: maxDisplacement = thickness * 10.0 may need adjustment for concave outward refraction

2. **Remove thickness-scaled specular:**
```glsl
// REMOVE these thickness-dependent calculations:
// float thicknessScale = clamp(40.0 / max(uThickness, 1.0), 1.0, 4.0);
// float brightness = ... * thicknessScale * 0.8;

// NEW: Fixed-width specular using normalizedHeight directly
float rimFactor = 1.0 / (1.0 + 10.0 * normalizedHeight * normalizedHeight);
float brightness = (directional + ambient) * rimFactor;
```

3. **Specular automatically follows profile:**
   - normalizedHeight already has profile shape baked in from geometry shader
   - No profile function needed in final shader
   - Zero additional per-pixel cost

4. **Saturation boost (already exists, just tune):**
   - Current saturation = 1.5 default already provides boost
   - Can tune highlight saturation in mix operation

---

## Files to Modify Summary

| File | Changes |
|------|---------|
| `lib/src/liquid_glass_settings.dart` | Add `EdgeProfile` enum and `edgeProfile` field |
| `lib/assets/shaders/shared.glsl` | Add edge profile functions, update `getHeight()` |
| `lib/assets/shaders/liquid_glass_geometry_blended.frag` | Pass profile type, use profile in height/normal calculation |
| `lib/assets/shaders/liquid_glass_final_render.frag` | Fix specular to be thickness-independent |
| `lib/src/liquid_glass_blend_group.dart` | Pass edge profile uniform to shader |
| `lib/src/internal/render_liquid_glass_geometry.dart` | Add edgeProfile to `requiresGeometryRebuild()` |

### Uniform Changes

Current `uOpticalProps` (vec4):
- x: refractiveIndex
- y: chromaticAberration
- z: thickness
- w: blend

**Add new uniform** `uEdgeProfile` (float) - index of profile type:
- 0 = convexCircle (default)
- 1 = convexSquircle
- 2 = concave
- 3 = lip

---

## Performance Analysis

**Geometry Shader (runs only when shapes change):**
| Change | Cost |
|--------|------|
| Profile function call | +1 function call per pixel |
| Profile derivative (for normal) | +2 profile calls for numerical derivative |
| Profile function (circle) | `sqrt(1-(1-x)²)` = 1 sqrt, 2 mul |
| Profile function (squircle) | `pow(1-x⁴, 0.25)` = more expensive |
| Profile function (lip) | Most expensive (smootherstep blend) |
| **Total for concave/lip** | ~3x profile calls vs current |

**Final Render Shader (runs every frame):**
| Change | Cost |
|--------|------|
| Remove thicknessScale calc | -1 clamp, -1 div |
| Remove edgeThreshold mix | -1 mix call |
| Simpler rimFactor | ~same (rational approx vs smoothstep) |
| **Net change** | **Slightly faster** |

**Recommendation:**
- Default to convexCircle (cheapest) for backward compatibility
- Document that lip profile has higher GPU cost

---

## Verification Criteria

1. **Visual verification:**
   - Each edge profile should produce visibly different surface curvature
   - Specular width should NOT change when thickness changes
   - Specular should follow the edge profile shape

2. **Regression testing:**
   - Existing golden tests should pass (or be updated)
   - No visual artifacts at shape edges

3. **Performance verification:**
   - Frame rate should not regress
   - Memory usage should remain similar

---

## Implementation Order

1. **Settings** - Add EdgeProfile enum and field to LiquidGlassSettings
2. **Edge profile functions** - Add to shared.glsl (getHeight variant per profile)
3. **Geometry shader** - Add uEdgeProfile uniform, use profile functions
4. **Dart shader bindings** - Pass edge profile to geometry shader
5. **Final render** - Remove thickness-scaled specular (simpler, faster)
6. **Visual tuning** - Adjust specular constants to match kube.io style
