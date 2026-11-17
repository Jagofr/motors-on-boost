package graphics;

import math.Vec3;

/**
 * Radial velocity blur post-processing shader state + WGSL source for WebGPU.
 * Samples 8 taps radiating from `blurOrigin` scaled by `blurIntensity` (boost / high-speed effect).
 */
class RadialBlurShader {
    public static final UNIFORM_BYTES:Int = 32; // 2 * vec4<f32>: (intensity, originX, originY, aaMode, aaStrength, texelW, texelH, pad)

    public static final WGSL:String = '
struct BlurUniforms {
    intensity  : f32,
    originX    : f32,
    originY    : f32,
    aaMode     : f32,
    aaStrength : f32,
    texelW     : f32,
    texelH     : f32,
    pad        : f32,
};

@group(0) @binding(0) var<uniform> params : BlurUniforms;
@group(0) @binding(1) var sceneTex : texture_2d<f32>;
@group(0) @binding(2) var sceneSampler : sampler;

struct PostOut {
    @builtin(position) clipPos : vec4<f32>,
    @location(0) uv : vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) vid : u32) -> PostOut {
    var coords = array<vec2<f32>, 3>(
        vec2<f32>(-1.0, -1.0),
        vec2<f32>( 3.0, -1.0),
        vec2<f32>(-1.0,  3.0)
    );
    let ndc = coords[vid];
    var out : PostOut;
    out.clipPos = vec4<f32>(ndc.x, ndc.y, 0.0, 1.0);
    // WebGPU texture coordinates have (0,0) at top-left while NDC +Y is top
    out.uv = vec2<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    return out;
}

fn lumaOf(c : vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn sampleFxaa311(uv : vec2<f32>, px : vec2<f32>, strength : f32) -> vec3<f32> {
    let minUv = px * 0.5;
    let maxUv = vec2<f32>(1.0) - px * 0.5;

    let cM = textureSampleLevel(sceneTex, sceneSampler, uv, 0.0).rgb;
    let cN = textureSampleLevel(sceneTex, sceneSampler, clamp(uv + vec2<f32>(0.0, -px.y), minUv, maxUv), 0.0).rgb;
    let cS = textureSampleLevel(sceneTex, sceneSampler, clamp(uv + vec2<f32>(0.0,  px.y), minUv, maxUv), 0.0).rgb;
    let cW = textureSampleLevel(sceneTex, sceneSampler, clamp(uv + vec2<f32>(-px.x, 0.0), minUv, maxUv), 0.0).rgb;
    let cE = textureSampleLevel(sceneTex, sceneSampler, clamp(uv + vec2<f32>( px.x, 0.0), minUv, maxUv), 0.0).rgb;

    let lM = lumaOf(cM);
    let lN = lumaOf(cN);
    let lS = lumaOf(cS);
    let lW = lumaOf(cW);
    let lE = lumaOf(cE);

    let lMin = min(lM, min(min(lN, lS), min(lW, lE)));
    let lMax = max(lM, max(max(lN, lS), max(lW, lE)));
    let lRange = lMax - lMin;

    // Tier parameters mapped from aaStrength: Low (<0.58), Medium (<0.86), High (>=0.86)
    // Subpixel UV shift stays <= 0.48 texels so filtering never overshoots past the edge midpoint
    var edgeThreshMin : f32 = 0.0312;
    var edgeThreshMax : f32 = 0.125;
    var subpixQuality : f32 = 0.38;
    var searchSteps : i32 = 8;
    if (strength < 0.58) {
        edgeThreshMin = 0.0625;
        edgeThreshMax = 0.20;
        subpixQuality = 0.28;
        searchSteps = 4;
    } else if (strength >= 0.86) {
        edgeThreshMin = 0.0200;
        edgeThreshMax = 0.0833;
        subpixQuality = 0.48;
        searchSteps = 12;
    }

    if (lRange < max(edgeThreshMin, lMax * edgeThreshMax)) {
        return cM;
    }

    let lNW = lumaOf(textureSampleLevel(sceneTex, sceneSampler, clamp(uv + vec2<f32>(-px.x, -px.y), minUv, maxUv), 0.0).rgb);
    let lNE = lumaOf(textureSampleLevel(sceneTex, sceneSampler, clamp(uv + vec2<f32>( px.x, -px.y), minUv, maxUv), 0.0).rgb);
    let lSW = lumaOf(textureSampleLevel(sceneTex, sceneSampler, clamp(uv + vec2<f32>(-px.x,  px.y), minUv, maxUv), 0.0).rgb);
    let lSE = lumaOf(textureSampleLevel(sceneTex, sceneSampler, clamp(uv + vec2<f32>( px.x,  px.y), minUv, maxUv), 0.0).rgb);

    let lumaNS = lN + lS;
    let lumaWE = lW + lE;
    let subpixAvg = (2.0 * (lumaNS + lumaWE) + (lNW + lNE + lSW + lSE)) * (1.0 / 12.0);
    let subpixA = clamp(abs(subpixAvg - lM) / max(lRange, 1e-5), 0.0, 1.0);
    let subpixB = (-2.0 * subpixA + 3.0) * (subpixA * subpixA);
    let subpixOffset = (subpixB * subpixB) * subpixQuality;

    let edgeHorz = abs(-2.0 * lW + lNW + lSW)
                 + abs(-2.0 * lM + lumaNS) * 2.0
                 + abs(-2.0 * lE + lNE + lSE);
    let edgeVert = abs(-2.0 * lN + lNW + lNE)
                 + abs(-2.0 * lM + lumaWE) * 2.0
                 + abs(-2.0 * lS + lSW + lSE);
    let isHorz = edgeHorz >= edgeVert;

    let l1 = select(lW, lN, isHorz);
    let l2 = select(lE, lS, isHorz);
    let grad1 = abs(l1 - lM);
    let grad2 = abs(l2 - lM);
    let is1Steepest = grad1 >= grad2;
    let gradientScaled = 0.25 * max(grad1, grad2);

    var stepLength = select(px.x, px.y, isHorz);
    var lumaLocalAvg : f32 = 0.0;
    if (is1Steepest) {
        stepLength = -stepLength;
        lumaLocalAvg = 0.5 * (l1 + lM);
    } else {
        lumaLocalAvg = 0.5 * (l2 + lM);
    }

    var currentUv = uv;
    if (isHorz) {
        currentUv.y += stepLength * 0.5;
    } else {
        currentUv.x += stepLength * 0.5;
    }

    let offset = select(vec2<f32>(0.0, px.y), vec2<f32>(px.x, 0.0), isHorz);
    var uv1 = currentUv - offset;
    var uv2 = currentUv + offset;

    var lumaEnd1 = lumaOf(textureSampleLevel(sceneTex, sceneSampler, clamp(uv1, minUv, maxUv), 0.0).rgb) - lumaLocalAvg;
    var lumaEnd2 = lumaOf(textureSampleLevel(sceneTex, sceneSampler, clamp(uv2, minUv, maxUv), 0.0).rgb) - lumaLocalAvg;
    var reached1 = abs(lumaEnd1) >= gradientScaled;
    var reached2 = abs(lumaEnd2) >= gradientScaled;
    var reachedBoth = reached1 && reached2;

    if (!reached1) { uv1 -= offset; }
    if (!reached2) { uv2 += offset; }

    if (!reachedBoth) {
        for (var i : i32 = 1; i < searchSteps; i++) {
            let mul = select(select(select(1.0, 1.5, i == 3), 2.0, i >= 4 && i <= 7), select(4.0, 8.0, i >= 11), i >= 8);
            if (!reached1) {
                lumaEnd1 = lumaOf(textureSampleLevel(sceneTex, sceneSampler, clamp(uv1, minUv, maxUv), 0.0).rgb) - lumaLocalAvg;
                reached1 = abs(lumaEnd1) >= gradientScaled;
            }
            if (!reached2) {
                lumaEnd2 = lumaOf(textureSampleLevel(sceneTex, sceneSampler, clamp(uv2, minUv, maxUv), 0.0).rgb) - lumaLocalAvg;
                reached2 = abs(lumaEnd2) >= gradientScaled;
            }
            reachedBoth = reached1 && reached2;
            if (!reached1) { uv1 -= offset * mul; }
            if (!reached2) { uv2 += offset * mul; }
            if (reachedBoth) { break; }
        }
    }

    let dist1 = select(uv.y - uv1.y, uv.x - uv1.x, isHorz);
    let dist2 = select(uv2.y - uv.y, uv2.x - uv.x, isHorz);
    let isDir1 = dist1 < dist2;
    let distFinal = min(dist1, dist2);
    let edgeThickness = max(dist1 + dist2, 1e-5);
    let pixelOffset = -distFinal / edgeThickness + 0.5;

    let isLumaMCenterSmaller = lM < lumaLocalAvg;
    let endSign = select(lumaEnd2, lumaEnd1, isDir1) < 0.0;
    let correctVariation = endSign != isLumaMCenterSmaller;

    var finalOffset = select(0.0, pixelOffset, correctVariation && pixelOffset > 0.0);
    finalOffset = max(finalOffset, subpixOffset);

    var finalUv = uv;
    if (isHorz) {
        finalUv.y += finalOffset * stepLength;
    } else {
        finalUv.x += finalOffset * stepLength;
    }
    return textureSampleLevel(sceneTex, sceneSampler, clamp(finalUv, minUv, maxUv), 0.0).rgb;
}

fn sampleAntiAliased(uv : vec2<f32>) -> vec3<f32> {
    if (params.aaMode < 0.5 || params.aaMode >= 1.5) {
        return textureSampleLevel(sceneTex, sceneSampler, uv, 0.0).rgb;
    }

    let px = vec2<f32>(max(params.texelW, 0.0001), max(params.texelH, 0.0001));
    let strength = clamp(params.aaStrength, 0.15, 1.0);
    return sampleFxaa311(uv, px, strength);
}

@fragment
fn fs_main(in : PostOut) -> @location(0) vec4<f32> {
    if (params.intensity <= 0.001) {
        return vec4<f32>(sampleAntiAliased(in.uv), 1.0);
    }

    let origin = vec2<f32>(params.originX, params.originY);
    let dir = origin - in.uv;
    let dist = length(dir);
    let stepVec = dir * (params.intensity * min(dist * 2.2, 1.0)) / 8.0;

    var acc = vec3<f32>(0.0);
    var sampleUv = in.uv;
    for (var i = 0; i < 8; i++) {
        let clampedUv = clamp(sampleUv, vec2<f32>(0.0), vec2<f32>(1.0));
        acc += select(textureSampleLevel(sceneTex, sceneSampler, clampedUv, 0.0).rgb, sampleAntiAliased(clampedUv), i == 0);
        sampleUv += stepVec;
    }
    return vec4<f32>(acc / 8.0, 1.0);
}
';

    public var blurIntensity:Float = 0.0;
    public var blurOrigin:Vec3;

    public function new() {
        blurOrigin = new Vec3(0.5, 0.5, 0.0, 0.0);
    }
}
