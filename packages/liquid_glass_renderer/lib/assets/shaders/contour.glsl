#ifndef CONTOUR_GLSL
#define CONTOUR_GLSL

float contourIntegral(float t, float width) {
  float u = clamp(t, 0.0, width);
  return u - u * u / (2.0 * width);
}

#endif
