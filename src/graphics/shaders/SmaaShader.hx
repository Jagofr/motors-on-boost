package graphics.shaders;

/**
 * SMAA 1x (Subpixel Morphological Anti-Aliasing) 3-Pass WGSL shaders for WebGPU.
 *
 * Pipeline order when `aaModeCode == 3`:
 * - Pass 2A (`EDGE_WGSL`): Luma + chroma local-contrast edge detection (`sceneTex` -> `smaaEdgeTex`).
 * - Pass 2B (`WEIGHT_WGSL`): Orthogonal contour search + analytical trapezoid coverage (`smaaEdgeTex` -> `smaaBlendTex`).
 * - Pass 2C (`RESOLVE_WGSL`): 4-neighbor bilinear morphological resolve + optional radial speed blur (`swapView`).
 */
class SmaaShader {
    public static final EDGE_WGSL:String = '
struct SmaaUniforms {
    intensity  : f32,
    originX    : f32,
    originY    : f32,
    aaMode     : f32,
    aaStrength : f32,
    texelW     : f32,
    texelH     : f32,
    pad        : f32,
};

@group(0) @binding(0) var<uniform> params : SmaaUniforms;
@group(0) @binding(1) var sceneTex : texture_2d<f32>;
@group(0) @binding(2) var linearSampler : sampler;

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
    out.uv = vec2<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    return out;
}

fn edgeMetric(a : vec3<f32>, b : vec3<f32>) -> f32 {
    let lA = dot(a, vec3<f32>(0.299, 0.587, 0.114));
    let lB = dot(b, vec3<f32>(0.299, 0.587, 0.114));
    let lDiff = abs(lA - lB);
    let cDiff = max(abs(a.r - b.r), max(abs(a.g - b.g), abs(a.b - b.b)));
    return max(lDiff, cDiff * 0.72);
}

@fragment
fn fs_main(in : PostOut) -> @location(0) vec4<f32> {
    let px = vec2<f32>(max(params.texelW, 0.0001), max(params.texelH, 0.0001));
    let minUv = px * 0.5;
    let maxUv = vec2<f32>(1.0) - px * 0.5;

    // Quality threshold mapped from Low (<0.58), Medium (<0.86), High (>=0.86)
    var threshold : f32 = 0.08;
    if (params.aaStrength < 0.58) {
        threshold = 0.12;
    } else if (params.aaStrength >= 0.86) {
        threshold = 0.05;
    }

    let cC  = textureSampleLevel(sceneTex, linearSampler, clamp(in.uv, minUv, maxUv), 0.0).rgb;
    let cL  = textureSampleLevel(sceneTex, linearSampler, clamp(in.uv + vec2<f32>(-px.x, 0.0), minUv, maxUv), 0.0).rgb;
    let cT  = textureSampleLevel(sceneTex, linearSampler, clamp(in.uv + vec2<f32>(0.0, -px.y), minUv, maxUv), 0.0).rgb;
    let cR  = textureSampleLevel(sceneTex, linearSampler, clamp(in.uv + vec2<f32>( px.x, 0.0), minUv, maxUv), 0.0).rgb;
    let cB  = textureSampleLevel(sceneTex, linearSampler, clamp(in.uv + vec2<f32>(0.0,  px.y), minUv, maxUv), 0.0).rgb;
    let cLL = textureSampleLevel(sceneTex, linearSampler, clamp(in.uv + vec2<f32>(-2.0 * px.x, 0.0), minUv, maxUv), 0.0).rgb;
    let cTT = textureSampleLevel(sceneTex, linearSampler, clamp(in.uv + vec2<f32>(0.0, -2.0 * px.y), minUv, maxUv), 0.0).rgb;

    let dLeft  = edgeMetric(cC, cL);
    let dTop   = edgeMetric(cC, cT);
    let dRight = edgeMetric(cC, cR);
    let dBot   = edgeMetric(cC, cB);
    let dLL    = edgeMetric(cL, cLL);
    let dTT    = edgeMetric(cT, cTT);

    let maxD = max(max(max(dLeft, dTop), max(dRight, dBot)), max(dLL, dTT));
    let edgeL = select(0.0, 1.0, dLeft >= threshold && dLeft >= maxD * 0.45);
    let edgeT = select(0.0, 1.0, dTop  >= threshold && dTop  >= maxD * 0.45);

    return vec4<f32>(edgeL, edgeT, 0.0, 1.0);
}
';

    public static final WEIGHT_WGSL:String = '
struct SmaaUniforms {
    intensity  : f32,
    originX    : f32,
    originY    : f32,
    aaMode     : f32,
    aaStrength : f32,
    texelW     : f32,
    texelH     : f32,
    pad        : f32,
};

@group(0) @binding(0) var<uniform> params : SmaaUniforms;
@group(0) @binding(1) var edgeTex : texture_2d<f32>;

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
    out.uv = vec2<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    return out;
}

fn loadEdge(coord : vec2<i32>, dims : vec2<i32>) -> vec2<f32> {
    let clamped = clamp(coord, vec2<i32>(0, 0), dims - vec2<i32>(1, 1));
    return textureLoad(edgeTex, clamped, 0).rg;
}

// Analytical SMAA trapezoid coverage weights along a contour segment of length (dA + dB + 1)
// Returns vec2(negativeNeighborWeight, positiveNeighborWeight) bounded in [0, 0.5]
fn computeSpanWeights(dA : f32, dB : f32, cA_neg : bool, cA_pos : bool, cB_neg : bool, cB_pos : bool) -> vec2<f32> {
    let totalLen = dA + dB + 1.0;
    let posNorm = (dA + 0.5) / totalLen;

    // Crossing orientation at each endpoint: -1 (turns toward neg neighbor), +1 (toward pos neighbor), 0 (flat/corner)
    let hA = select(0.0, 0.5, cA_pos && !cA_neg) + select(0.0, -0.5, cA_neg && !cA_pos);
    let hB = select(0.0, 0.5, cB_pos && !cB_neg) + select(0.0, -0.5, cB_neg && !cB_pos);

    var wNeg : f32 = 0.0;
    var wPos : f32 = 0.0;

    if (abs(hA) > 0.1 && abs(hB) > 0.1) {
        if (hA * hB < 0.0) {
            // Opposing crossings ("/" or "\"): positive offset blends neg neighbor into pos side (left/top), negative pulls pos neighbor
            let signedOffset = mix(hA, hB, posNorm);
            wNeg = max(0.0,  signedOffset);
            wPos = max(0.0, -signedOffset);
        } else {
            // Same-side U-plateau crossing: blend half-trapezoids near endpoints
            let endFactor = 1.0 - 2.0 * min(posNorm, 1.0 - posNorm);
            let amt = max(0.0, endFactor) * 0.45;
            if (hA > 0.0) { wNeg = amt; } else { wPos = amt; }
        }
    } else if (abs(hA) > 0.1) {
        // Single step at start A
        let amt = max(0.0, 1.0 - posNorm * 2.0) * 0.5;
        if (hA > 0.0) { wNeg = amt; } else { wPos = amt; }
    } else if (abs(hB) > 0.1) {
        // Single step at end B
        let amt = max(0.0, (posNorm - 0.5) * 2.0) * 0.5;
        if (hB > 0.0) { wNeg = amt; } else { wPos = amt; }
    }

    // Preserve true 90-degree corners where orthogonal contour continues on both sides
    let bothCornerA = cA_neg && cA_pos;
    let bothCornerB = cB_neg && cB_pos;
    if (bothCornerA || bothCornerB) {
        wNeg *= 0.25;
        wPos *= 0.25;
    }

    return vec2<f32>(wNeg, wPos);
}

@fragment
fn fs_main(in : PostOut) -> @location(0) vec4<f32> {
    let dims = vec2<i32>(textureDimensions(edgeTex, 0));
    let pxCoord = clamp(vec2<i32>(floor(in.clipPos.xy)), vec2<i32>(0, 0), dims - vec2<i32>(1, 1));
    let e = textureLoad(edgeTex, pxCoord, 0).rg;

    var maxSearchSteps : i32 = 12;
    if (params.aaStrength < 0.58) {
        maxSearchSteps = 6;
    } else if (params.aaStrength >= 0.86) {
        maxSearchSteps = 20;
    }

    var wTop : f32 = 0.0;
    var wBottom : f32 = 0.0;
    var wLeft : f32 = 0.0;
    var wRight : f32 = 0.0;

    // 1. Horizontal edge between pixel (x, y) and (x, y - 1) stored in e.g
    if (e.g > 0.5) {
        var dLeft : i32 = 0;
        for (var i : i32 = 1; i <= maxSearchSteps; i++) {
            if (loadEdge(pxCoord + vec2<i32>(-i, 0), dims).g < 0.5) { break; }
            dLeft = i;
        }
        var dRight : i32 = 0;
        for (var i : i32 = 1; i <= maxSearchSteps; i++) {
            if (loadEdge(pxCoord + vec2<i32>(i, 0), dims).g < 0.5) { break; }
            dRight = i;
        }

        // Check perpendicular vertical edges at left and right ends of horizontal span
        let leftUp   = loadEdge(pxCoord + vec2<i32>(-dLeft, -1), dims).r > 0.5;
        let leftDn   = loadEdge(pxCoord + vec2<i32>(-dLeft,  0), dims).r > 0.5;
        let rightUp  = loadEdge(pxCoord + vec2<i32>( dRight + 1, -1), dims).r > 0.5;
        let rightDn  = loadEdge(pxCoord + vec2<i32>( dRight + 1,  0), dims).r > 0.5;

        let wV = computeSpanWeights(f32(dLeft), f32(dRight), leftUp, leftDn, rightUp, rightDn);
        wTop = wV.x;
        wBottom = wV.y;
    }

    // 2. Vertical edge between pixel (x, y) and (x - 1, y) stored in e.r
    if (e.r > 0.5) {
        var dUp : i32 = 0;
        for (var i : i32 = 1; i <= maxSearchSteps; i++) {
            if (loadEdge(pxCoord + vec2<i32>(0, -i), dims).r < 0.5) { break; }
            dUp = i;
        }
        var dDown : i32 = 0;
        for (var i : i32 = 1; i <= maxSearchSteps; i++) {
            if (loadEdge(pxCoord + vec2<i32>(0, i), dims).r < 0.5) { break; }
            dDown = i;
        }

        // Check perpendicular horizontal edges at top and bottom ends of vertical span
        let upLeft   = loadEdge(pxCoord + vec2<i32>(-1, -dUp), dims).g > 0.5;
        let upRight  = loadEdge(pxCoord + vec2<i32>( 0, -dUp), dims).g > 0.5;
        let dnLeft   = loadEdge(pxCoord + vec2<i32>(-1,  dDown + 1), dims).g > 0.5;
        let dnRight  = loadEdge(pxCoord + vec2<i32>( 0,  dDown + 1), dims).g > 0.5;

        let wH = computeSpanWeights(f32(dUp), f32(dDown), upLeft, upRight, dnLeft, dnRight);
        wLeft = wH.x;
        wRight = wH.y;
    }

    return vec4<f32>(wTop, wBottom, wLeft, wRight);
}
';

    public static final RESOLVE_WGSL:String = '
struct SmaaUniforms {
    intensity  : f32,
    originX    : f32,
    originY    : f32,
    aaMode     : f32,
    aaStrength : f32,
    texelW     : f32,
    texelH     : f32,
    pad        : f32,
};

@group(0) @binding(0) var<uniform> params : SmaaUniforms;
@group(0) @binding(1) var sceneTex : texture_2d<f32>;
@group(0) @binding(2) var blendTex : texture_2d<f32>;
@group(0) @binding(3) var linearSampler : sampler;

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
    out.uv = vec2<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    return out;
}

fn sampleSmaa(uv : vec2<f32>) -> vec3<f32> {
    let px = vec2<f32>(max(params.texelW, 0.0001), max(params.texelH, 0.0001));
    let minUv = px * 0.5;
    let maxUv = vec2<f32>(1.0) - px * 0.5;
    let cUv = clamp(uv, minUv, maxUv);

    let dims = vec2<i32>(textureDimensions(blendTex, 0));
    let p = clamp(vec2<i32>(floor(cUv * vec2<f32>(dims))), vec2<i32>(0, 0), dims - vec2<i32>(1, 1));
    let pBelow = clamp(p + vec2<i32>(0, 1), vec2<i32>(0, 0), dims - vec2<i32>(1, 1));
    let pRight = clamp(p + vec2<i32>(1, 0), vec2<i32>(0, 0), dims - vec2<i32>(1, 1));

    let wSelf  = textureLoad(blendTex, p, 0);
    let wBelow = textureLoad(blendTex, pBelow, 0);
    let wRight = textureLoad(blendTex, pRight, 0);

    let wTop    = wSelf.r;
    let wBottom = wBelow.g;
    let wLeft   = wSelf.b;
    let wRightW = wRight.a;

    let maxV = max(wTop, wBottom);
    let maxH = max(wLeft, wRightW);
    let totalW = maxV + maxH;
    if (totalW < 1e-4) {
        return textureSampleLevel(sceneTex, linearSampler, cUv, 0.0).rgb;
    }

    let offsetV = select(wBottom, -wTop, wTop >= wBottom);
    let offsetH = select(wRightW, -wLeft, wLeft >= wRightW);
    let colV = textureSampleLevel(sceneTex, linearSampler, clamp(cUv + vec2<f32>(0.0, offsetV * px.y), minUv, maxUv), 0.0).rgb;
    let colH = textureSampleLevel(sceneTex, linearSampler, clamp(cUv + vec2<f32>(offsetH * px.x, 0.0), minUv, maxUv), 0.0).rgb;

    return (colV * maxV + colH * maxH) / totalW;
}

@fragment
fn fs_main(in : PostOut) -> @location(0) vec4<f32> {
    if (params.intensity <= 0.001) {
        return vec4<f32>(sampleSmaa(in.uv), 1.0);
    }

    let origin = vec2<f32>(params.originX, params.originY);
    let dir = origin - in.uv;
    let dist = length(dir);
    let stepVec = dir * (params.intensity * min(dist * 2.2, 1.0)) / 8.0;

    var acc = vec3<f32>(0.0);
    var sampleUv = in.uv;
    for (var i = 0; i < 8; i++) {
        let clampedUv = clamp(sampleUv, vec2<f32>(0.0), vec2<f32>(1.0));
        acc += select(textureSampleLevel(sceneTex, linearSampler, clampedUv, 0.0).rgb, sampleSmaa(clampedUv), i == 0);
        sampleUv += stepVec;
    }
    return vec4<f32>(acc / 8.0, 1.0);
}
';
}
