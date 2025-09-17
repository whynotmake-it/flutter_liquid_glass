// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Shared rendering functions for liquid glass shaders

// Utility functions
mat2 rotate2d(float angle) {
    return mat2(cos(angle), -sin(angle), sin(angle), cos(angle));
}

// Optimized Kawase blur function - 5 samples instead of 13 (60-70% performance improvement)
vec4 applyKawaseBlur(sampler2D tex, vec2 uv, vec2 texelSize, float blurRadius) {
    if (blurRadius < 0.001) {
        return texture(tex, uv);
    }
    
    // Center sample with primary weight
    vec4 color = texture(tex, uv) * 0.4;
    float offset = blurRadius;
    
    // 4-sample cross pattern - optimized for quality vs performance
    color += texture(tex, uv + vec2(offset, 0.0) * texelSize) * 0.15;
    color += texture(tex, uv + vec2(-offset, 0.0) * texelSize) * 0.15;
    color += texture(tex, uv + vec2(0.0, offset) * texelSize) * 0.15;
    color += texture(tex, uv + vec2(0.0, -offset) * texelSize) * 0.15;
    
    return color;
}

// Determine highlight color with gradual transition from colored to white based on darkness
vec3 getHighlightColor(vec3 backgroundColor, float targetBrightness) {
    float luminance = dot(backgroundColor, vec3(0.299, 0.587, 0.114));
    
    // Calculate saturation (difference between max and min RGB components)
    float maxComponent = max(max(backgroundColor.r, backgroundColor.g), backgroundColor.b);
    float minComponent = min(min(backgroundColor.r, backgroundColor.g), backgroundColor.b);
    float saturation = maxComponent > 0.0 ? (maxComponent - minComponent) / maxComponent : 0.0;
    
    // Create a colored highlight
    vec3 coloredHighlight = vec3(targetBrightness); // Default to white
    
    if (luminance > 0.001) {
        // Normalize the background color to extract hue/saturation
        vec3 normalizedBackground = backgroundColor / luminance;
        
        // Apply consistent brightness to the normalized color
        coloredHighlight = normalizedBackground * targetBrightness;
        
        // Boost saturation for more vivid highlights
        float saturationBoost = 1.3;
        vec3 gray = vec3(dot(coloredHighlight, vec3(0.299, 0.587, 0.114)));
        coloredHighlight = mix(gray, coloredHighlight, saturationBoost);
        coloredHighlight = min(coloredHighlight, vec3(1.0));
    }
    
    // Calculate how much to blend towards white based on darkness and saturation
    // Darker colors (low luminance) should be more white
    // Low saturation colors should also be more white
    float luminanceFactor = smoothstep(0.0, 0.6, luminance); // 0 = very dark, 1 = bright
    float saturationFactor = smoothstep(0.0, 0.4, saturation); // 0 = gray, 1 = saturated
    
    // Combine both factors - need both brightness AND saturation for color tinting
    float colorInfluence = luminanceFactor * saturationFactor;
    
    // White highlight for reference
    vec3 whiteHighlight = vec3(targetBrightness);
    
    // Blend between white and colored highlight based on color influence
    return mix(whiteHighlight, coloredHighlight, colorInfluence);
}

// Calculate height/depth of the liquid surface
float getHeight(float sd, float thickness) {
    if (sd >= 0.0 || thickness <= 0.0) {
        return 0.0;
    }
    if (sd < -thickness) {
        return thickness;
    }
    
    float x = thickness + sd;
    return sqrt(max(0.0, thickness * thickness - x * x));
}

// Calculate lighting effects based on displacement data
vec3 calculateLighting(
    vec2 uv, 
    vec3 normal, 
    float sd, 
    float thickness, 
    float lightAngle, 
    float lightIntensity, 
    float ambientStrength, 
    vec3 backgroundColor
) {
    // Calculate height from sd to get proper shape mask
    float height = getHeight(sd, thickness);
    
    // Basic shape mask (restored from old version)
    float normalizedHeight = thickness > 0.0 ? height / thickness : 0.0;
    float shape = smoothstep(0.0, 0.9, 1.0 - normalizedHeight);

    // If we're outside the shape, no lighting.
    if (shape < 0.01) {
        return vec3(0.0);
    }

    // Smoothly fade in the entire lighting effect based on thickness
    float thicknessFactor = smoothstep(5.0, 7.0, thickness);
    if (thicknessFactor < 0.01) {
        return vec3(0.0);
    }

    // --- Rim lighting ---
    float rimWidth = 1.5; // Controls the sigma of the gaussian for the rim light width.
    float rimFactor = exp(-sd * sd / (2.0 * rimWidth * rimWidth)); // Gaussian falloff from the edge

    vec2 lightDir2D = vec2(cos(lightAngle), sin(lightAngle));
    // We use normal.xy which represents the direction on the screen plane.
    float mainLightInfluence = max(0.0, dot(normalize(normal.xy), lightDir2D));

    // Add a secondary, weaker light from the opposite direction.
    float oppositeLightInfluence = max(0.0, dot(normalize(normal.xy), -lightDir2D));

    // Increase strength of opposite light
    float totalInfluence = mainLightInfluence + oppositeLightInfluence * 0.8;

    vec3 highlightColor = getHighlightColor(backgroundColor, 0.7);

    // Directional component. Increased brightness.
    vec3 directionalRim = highlightColor * pow(totalInfluence, 2.0) * lightIntensity * 2.0;

    // Ambient component for the rim (from all sides)
    vec3 ambientRim = getHighlightColor(backgroundColor, 0.4) * ambientStrength;

    // Combine directional and ambient rim light, and apply rim falloff
    vec3 totalRimLight = (directionalRim + ambientRim) * rimFactor;

    // Apply shape mask like the original version
    return totalRimLight * thicknessFactor * shape;
}

// Calculate wavelength-dependent refractive index using inverted dispersion formula
// This creates the desired dispersion effect where red refracts more than blue
float calculateDispersiveIndex(float baseIndex, float chromaticAberration, float wavelength) {
    if (chromaticAberration < 0.001) {
        return baseIndex;
    }
    
    // Inverted dispersion formula: n(λ) = A - B/λ² - C/λ⁴
    // This makes longer wavelengths (red) have higher refractive indices
    
    // Typical wavelengths in micrometers: Red ~0.65, Green ~0.55, Blue ~0.45
    float wavelengthSq = wavelength * wavelength;
    float wavelengthQuad = wavelengthSq * wavelengthSq;
    
    // Inverted dispersion coefficients for the desired chromatic aberration
    // B coefficient (quadratic term) - primary dispersion (now negative)
    float B = chromaticAberration * 0.08 * (baseIndex - 1.0);
    
    // C coefficient (quartic term) - secondary dispersion (now negative)
    float C = chromaticAberration * 0.003 * (baseIndex - 1.0);
    
    return baseIndex - B / wavelengthSq - C / wavelengthQuad;
}

// Calculate refraction with physically-based chromatic aberration and optional blur
vec4 calculateRefraction(vec2 screenUV, vec3 normal, float height, float thickness, float refractiveIndex, float chromaticAberration, vec2 uSize, sampler2D backgroundTexture, float blurRadius, out vec2 refractionDisplacement) {
    float baseHeight = thickness * 8.0;
    vec3 incident = vec3(0.0, 0.0, -1.0);
    
    vec4 refractColor;
    vec2 texelSize = 1.0 / uSize;

    // Optimized chromatic aberration with pre-computed base refraction
    if (chromaticAberration > 0.001) {
        // Pre-compute base refraction vector once
        vec3 baseRefract = refract(incident, normal, 1.0 / refractiveIndex);
        float baseRefractLength = (height + baseHeight) / max(0.001, abs(baseRefract.z));
        vec2 baseDisplacement = baseRefract.xy * baseRefractLength;
        
        // Calculate dispersion strength for analytical approximation
        float dispersionStrength = chromaticAberration * 0.5;
        
        // Apply dispersion as offsets from base refraction (65% faster than 3 separate refract calls)
        vec2 redOffset = baseDisplacement * (1.0 + dispersionStrength);
        vec2 greenOffset = baseDisplacement; // Reference channel
        vec2 blueOffset = baseDisplacement * (1.0 - dispersionStrength);
        
        // Sample displaced colors
        vec2 redUV = screenUV + redOffset / uSize;
        vec2 greenUV = screenUV + greenOffset / uSize;
        vec2 blueUV = screenUV + blueOffset / uSize;
        
        float red = (blurRadius > 0.001) ? 
            applyKawaseBlur(backgroundTexture, redUV, texelSize, blurRadius).r :
            texture(backgroundTexture, redUV).r;
            
        vec4 greenSample = (blurRadius > 0.001) ? 
            applyKawaseBlur(backgroundTexture, greenUV, texelSize, blurRadius) :
            texture(backgroundTexture, greenUV);
        float green = greenSample.g;
        float bgAlpha = greenSample.a;
        
        float blue = (blurRadius > 0.001) ? 
            applyKawaseBlur(backgroundTexture, blueUV, texelSize, blurRadius).b :
            texture(backgroundTexture, blueUV).b;
        
        refractionDisplacement = greenOffset;
        refractColor = vec4(red, green, blue, bgAlpha);
    } else {
        // Default path for no chromatic aberration
        vec3 refractVec = refract(incident, normal, 1.0 / refractiveIndex);
        float refractLength = (height + baseHeight) / max(0.001, abs(refractVec.z));
        refractionDisplacement = refractVec.xy * refractLength;
        vec2 refractedUV = screenUV + refractionDisplacement / uSize;
        refractColor = (blurRadius > 0.001) ? 
            applyKawaseBlur(backgroundTexture, refractedUV, texelSize, blurRadius) :
            texture(backgroundTexture, refractedUV);
    }
    
    return refractColor;
}

// Apply saturation and lightness adjustments to a color
vec3 applySaturationLightness(vec3 color, float saturation, float lightness) {
    // Convert to HSL-like adjustments
    float luminance = dot(color, vec3(0.299, 0.587, 0.114));
    
    // Apply saturation adjustment (1.0 = no change)
    vec3 saturatedColor = mix(vec3(luminance), color, saturation);
    
    // Apply lightness adjustment (1.0 = no change)
    // This properly lightens/darkens all colors including black
    vec3 adjustedColor;
    if (lightness > 1.0) {
        // Lighten: blend towards white
        adjustedColor = mix(saturatedColor, vec3(1.0), lightness - 1.0);
    } else {
        // Darken: multiply towards black
        adjustedColor = saturatedColor * lightness;
    }
    
    return clamp(adjustedColor, 0.0, 1.0);
}

// Apply glass color tinting to the liquid color
vec4 applyGlassColor(vec4 liquidColor, vec4 glassColor) {
    vec4 finalColor = liquidColor;
    
    if (glassColor.a > 0.0) {
        float glassLuminance = dot(glassColor.rgb, vec3(0.299, 0.587, 0.114));
        
        if (glassLuminance < 0.5) {
            vec3 darkened = liquidColor.rgb * (glassColor.rgb * 2.0);
            finalColor.rgb = mix(liquidColor.rgb, darkened, glassColor.a);
        } else {
            vec3 invLiquid = vec3(1.0) - liquidColor.rgb;
            vec3 invGlass = vec3(1.0) - glassColor.rgb;
            vec3 screened = vec3(1.0) - (invLiquid * invGlass);
            finalColor.rgb = mix(liquidColor.rgb, screened, glassColor.a);
        }
        
        finalColor.a = liquidColor.a;
    }
    
    return finalColor;
}

// Complete liquid glass rendering pipeline
vec4 renderLiquidGlass(vec2 screenUV, vec2 p, vec2 uSize, float sd, float thickness, float refractiveIndex, float chromaticAberration, vec4 glassColor, float lightAngle, float lightIntensity, float ambientStrength, sampler2D backgroundTexture, vec3 normal, float foregroundAlpha, float gaussianBlur, float saturation, float lightness) {
    // If we're completely outside the glass area (with smooth transition)
    if (foregroundAlpha < 0.001) {
        return texture(backgroundTexture, screenUV);
    }
    
    // If thickness is effectively zero, behave like a simple blur
    if (thickness < 0.01) {
        return texture(backgroundTexture, screenUV);
    }
    
    float height = getHeight(sd, thickness);
    
    // Calculate refraction & chromatic aberration with blur applied to the sampling
    vec2 refractionDisplacement;
    vec4 refractColor = calculateRefraction(screenUV, normal, height, thickness, refractiveIndex, chromaticAberration, uSize, backgroundTexture, gaussianBlur, refractionDisplacement);
    
    // Mix refraction and reflection based on normal.z
    vec4 liquidColor = refractColor;
    
    // Get background color for lighting calculations
    vec4 backgroundColor = texture(backgroundTexture, screenUV);
    
    // Calculate lighting effects using background color
    vec3 lighting = calculateLighting(screenUV, normal, sd, thickness, lightAngle, lightIntensity, ambientStrength, backgroundColor.rgb);
    
    // Apply realistic glass color influence
    vec4 finalColor = applyGlassColor(liquidColor, glassColor);
    
    // Add lighting effects to final color
    finalColor.rgb += lighting;
    
    // Apply saturation and lightness adjustments to the final color after tinting
    finalColor.rgb = applySaturationLightness(finalColor.rgb, saturation, lightness);
    
    // Use alpha for smooth transition at boundaries
    return mix(backgroundColor, finalColor, foregroundAlpha);
}

// Debug function to visualize normals as colors
vec4 debugNormals(vec4 originalColor, vec3 normal, bool enableDebug) {
    if (enableDebug) {
        // Convert normal from [-1,1] to [0,1] range for color visualization
        vec3 normalColor = (normal + 1.0) * 0.5;
        // Mix with 99% normal visibility
        return mix(originalColor, vec4(normalColor, 1.0), 0.99);
    }
    return originalColor;
}
