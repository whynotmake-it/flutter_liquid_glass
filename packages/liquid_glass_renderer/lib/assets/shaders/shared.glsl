// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Shared rendering functions for liquid glass shaders

// Utility functions
mat2 rotate2d(float angle) {
    return mat2(cos(angle), -sin(angle), sin(angle), cos(angle));
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
vec3 calculateLighting(vec2 uv, vec3 normal, float height, vec2 refractionDisplacement, float thickness, float lightAngle, float lightIntensity, float ambientStrength) {
    // Basic shape mask
    float normalizedHeight = thickness > 0.0 ? height / thickness : 0.0;
    float shape = smoothstep(0.0, 0.9, 1.0 - normalizedHeight);

    // If we're outside the shape, no lighting.
    if (shape < 0.01) {
        return vec3(0.0);
    }
    
    vec3 viewDir = vec3(0.0, 0.0, 1.0);

    // --- Rim lighting (Fresnel) ---
    // This creates a constant, soft outline.
    float fresnel = pow(1.0 - max(0.0, dot(normal, viewDir)), 3.0);
    vec3 rimLight = vec3(fresnel * ambientStrength * 0.5);

    // --- Light-dependent effects ---
    vec3 lightDir = normalize(vec3(cos(lightAngle), sin(lightAngle), -0.7));
    vec3 oppositeLightDir = normalize(vec3(-lightDir.xy, lightDir.z));

    // Common vectors needed for both light sources
    vec3 halfwayDir1 = normalize(lightDir + viewDir);
    float specDot1 = max(0.0, dot(normal, halfwayDir1));
    vec3 halfwayDir2 = normalize(oppositeLightDir + viewDir);
    float specDot2 = max(0.0, dot(normal, halfwayDir2));

    // 1. Sharp surface glint (pure white)
    float glintExponent = mix(120.0, 200.0, smoothstep(5.0, 25.0, thickness));
    float sharpFactor = pow(specDot1, glintExponent) + 0.4 * pow(specDot2, glintExponent);

    // Pure white glint without environment tinting
    vec3 sharpGlint = vec3(sharpFactor) * lightIntensity * 2.5;

    // 2. Soft internal bleed, for a subtle "glow"
    float softFactor = pow(specDot1, 20.0) + 0.5 * pow(specDot2, 20.0);
    vec3 softBleed = vec3(softFactor) * lightIntensity * 0.4;
    
    // Combine lighting components
    vec3 lighting = rimLight + sharpGlint + softBleed;

    // Final combination
    return lighting * shape;
}

// Calculate refraction with chromatic aberration
vec4 calculateRefraction(vec2 screenUV, vec3 normal, float height, float thickness, float refractiveIndex, float chromaticAberration, vec2 uSize, sampler2D backgroundTexture, out vec2 refractionDisplacement) {
    float baseHeight = thickness * 8.0;
    vec3 incident = vec3(0.0, 0.0, -1.0);
    
    vec4 refractColor;

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
        float red = texture(backgroundTexture, refractedUVR).r;

        // Green channel (we'll use this for the main displacement and alpha)
        vec3 refractVecG = refract(incident, normal, 1.0 / iorG);
        float refractLengthG = (height + baseHeight) / max(0.001, abs(refractVecG.z));
        refractionDisplacement = refractVecG.xy * refractLengthG; 
        vec2 refractedUVG = screenUV + refractionDisplacement / uSize;
        vec4 greenSample = texture(backgroundTexture, refractedUVG);
        float green = greenSample.g;
        float bgAlpha = greenSample.a;

        // Blue channel
        vec3 refractVecB = refract(incident, normal, 1.0 / iorB);
        float refractLengthB = (height + baseHeight) / max(0.001, abs(refractVecB.z));
        vec2 refractedUVB = screenUV + (refractVecB.xy * refractLengthB) / uSize;
        float blue = texture(backgroundTexture, refractedUVB).b;
        
        refractColor = vec4(red, green, blue, bgAlpha);
    } else {
        // Default path for no chromatic aberration
        vec3 refractVec = refract(incident, normal, 1.0 / refractiveIndex);
        float refractLength = (height + baseHeight) / max(0.001, abs(refractVec.z));
        refractionDisplacement = refractVec.xy * refractLength;
        vec2 refractedUV = screenUV + refractionDisplacement / uSize;
        refractColor = texture(backgroundTexture, refractedUV);
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
vec4 renderLiquidGlass(vec2 screenUV, vec2 p, vec2 uSize, float sd, float thickness, float refractiveIndex, float chromaticAberration, vec4 glassColor, float lightAngle, float lightIntensity, float ambientStrength, sampler2D backgroundTexture, vec3 normal) {
    float alpha = smoothstep(-2.0, 0.0, sd);
    
    // If we're completely outside the glass area (with smooth transition)
    if (alpha > 0.999) {
        return texture(backgroundTexture, screenUV);
    }
    
    // If thickness is effectively zero, behave like a simple blur
    if (thickness < 0.01) {
        return texture(backgroundTexture, screenUV);
    }
    
    float height = getHeight(sd, thickness);
    
    // Calculate refraction & chromatic aberration
    vec2 refractionDisplacement;
    vec4 refractColor = calculateRefraction(screenUV, normal, height, thickness, refractiveIndex, chromaticAberration, uSize, backgroundTexture, refractionDisplacement);
    
    // Mix refraction and reflection based on normal.z
    vec4 liquidColor = refractColor;
    
    // Calculate lighting effects
    vec3 lighting = calculateLighting(screenUV, normal, height, refractionDisplacement, thickness, lightAngle, lightIntensity, ambientStrength);
    
    // Apply realistic glass color influence
    vec4 finalColor = applyGlassColor(liquidColor, glassColor);
    
    // Add lighting effects to final color
    finalColor.rgb += lighting;
    
    // Use alpha for smooth transition at boundaries
    vec4 backgroundColor = texture(backgroundTexture, screenUV);
    return mix(backgroundColor, finalColor, 1.0 - alpha);
}
