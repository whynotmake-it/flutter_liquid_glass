// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Shared rendering functions for liquid glass shaders

// Utility functions
mat2 rotate2d(float angle) {
    return mat2(cos(angle), -sin(angle), sin(angle), cos(angle));
}

// Multi-sampled Kawase blur function - much more performance friendly than Gaussian
vec4 applyKawaseBlur(sampler2D tex, vec2 uv, vec2 texelSize, float blurRadius) {
    if (blurRadius < 0.001) {
        return texture(tex, uv);
    }
    
    vec4 color = vec4(0.0);
    float totalWeight = 0.0;
    
    // Kawase blur uses fewer samples with specific offset patterns
    // This creates multiple "passes" in a single shader call
    float offset = blurRadius;
    
    // Pass 1: Diamond pattern (4 samples)
    vec2 offsets1[4] = vec2[4](
        vec2(-offset, -offset),
        vec2(offset, -offset),
        vec2(-offset, offset),
        vec2(offset, offset)
    );
    
    for (int i = 0; i < 4; i++) {
        vec2 sampleUV = uv + offsets1[i] * texelSize;
        if (sampleUV.x >= 0.0 && sampleUV.x <= 1.0 && sampleUV.y >= 0.0 && sampleUV.y <= 1.0) {
            color += texture(tex, sampleUV);
            totalWeight += 1.0;
        }
    }
    
    // Pass 2: Cross pattern with larger offset (4 samples)
    float offset2 = offset * 1.5;
    vec2 offsets2[4] = vec2[4](
        vec2(0.0, -offset2),
        vec2(0.0, offset2),
        vec2(-offset2, 0.0),
        vec2(offset2, 0.0)
    );
    
    for (int i = 0; i < 4; i++) {
        vec2 sampleUV = uv + offsets2[i] * texelSize;
        if (sampleUV.x >= 0.0 && sampleUV.x <= 1.0 && sampleUV.y >= 0.0 && sampleUV.y <= 1.0) {
            color += texture(tex, sampleUV) * 0.8; // Slightly less weight for outer samples
            totalWeight += 0.8;
        }
    }
    
    // Pass 3: Intermediate diagonal samples (4 samples)
    float offset3 = offset * 0.7;
    vec2 offsets3[4] = vec2[4](
        vec2(-offset3, 0.0),
        vec2(offset3, 0.0),
        vec2(0.0, -offset3),
        vec2(0.0, offset3)
    );
    
    for (int i = 0; i < 4; i++) {
        vec2 sampleUV = uv + offsets3[i] * texelSize;
        if (sampleUV.x >= 0.0 && sampleUV.x <= 1.0 && sampleUV.y >= 0.0 && sampleUV.y <= 1.0) {
            color += texture(tex, sampleUV) * 0.6;
            totalWeight += 0.6;
        }
    }
    
    // Center sample with higher weight
    color += texture(tex, uv) * 2.0;
    totalWeight += 2.0;
    
    return totalWeight > 0.0 ? color / totalWeight : texture(tex, uv);
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
    // Smoothly fade in the entire lighting effect based on thickness
    float thicknessFactor = smoothstep(5.0, 7.0, thickness);
    if (thicknessFactor < 0.01) {
        return vec3(0.0);
    }

    // --- Rim lighting ---
    float rimWidth = 3.0; // Controls the sigma of the gaussian for the rim light width.
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

    return totalRimLight * thicknessFactor;
}

// Calculate refraction with chromatic aberration and optional blur
vec4 calculateRefraction(vec2 screenUV, vec3 normal, float height, float thickness, float refractiveIndex, float chromaticAberration, vec2 uSize, sampler2D backgroundTexture, float blurRadius, out vec2 refractionDisplacement) {
    float baseHeight = thickness * 8.0;
    vec3 incident = vec3(0.0, 0.0, -1.0);
    
    vec4 refractColor;
    vec2 texelSize = 1.0 / uSize;

    // To simulate a prism, we calculate refraction separately for each color channel
    // by slightly varying the refractive index.
    if (chromaticAberration > 0.001) {
        float iorR = refractiveIndex - chromaticAberration * 0.04; // Less deviation for red
        float iorG = refractiveIndex;
        float iorB = refractiveIndex + chromaticAberration * 0.08; // More deviation for blue

        // Red channel
        vec3 refractVecR = refract(incident, normal, 1.0 / iorR);
        float refractLengthR = (height + baseHeight) / max(0.001, abs(refractVecR.z));
        vec2 refractedUVR = screenUV + (refractVecR.xy * refractLengthR) / uSize;
        float red = (blurRadius > 0.001) ? 
            applyKawaseBlur(backgroundTexture, refractedUVR, texelSize, blurRadius).r :
            texture(backgroundTexture, refractedUVR).r;

        // Green channel (we'll use this for the main displacement and alpha)
        vec3 refractVecG = refract(incident, normal, 1.0 / iorG);
        float refractLengthG = (height + baseHeight) / max(0.001, abs(refractVecG.z));
        refractionDisplacement = refractVecG.xy * refractLengthG; 
        vec2 refractedUVG = screenUV + refractionDisplacement / uSize;
        vec4 greenSample = (blurRadius > 0.001) ? 
            applyKawaseBlur(backgroundTexture, refractedUVG, texelSize, blurRadius) :
            texture(backgroundTexture, refractedUVG);
        float green = greenSample.g;
        float bgAlpha = greenSample.a;

        // Blue channel
        vec3 refractVecB = refract(incident, normal, 1.0 / iorB);
        float refractLengthB = (height + baseHeight) / max(0.001, abs(refractVecB.z));
        vec2 refractedUVB = screenUV + (refractVecB.xy * refractLengthB) / uSize;
        float blue = (blurRadius > 0.001) ? 
            applyKawaseBlur(backgroundTexture, refractedUVB, texelSize, blurRadius).b :
            texture(backgroundTexture, refractedUVB).b;
        
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
vec4 renderLiquidGlass(vec2 screenUV, vec2 p, vec2 uSize, float sd, float thickness, float refractiveIndex, float chromaticAberration, vec4 glassColor, float lightAngle, float lightIntensity, float ambientStrength, sampler2D backgroundTexture, vec3 normal, float foregroundAlpha, float gaussianBlur) {
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
