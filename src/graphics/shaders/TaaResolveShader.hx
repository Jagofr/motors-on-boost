package graphics.shaders;

/**
 * TSAA / TAA (Temporal Super-Sampling Anti-Aliasing) resolve shader for WebGPU.
 *
 * Features:
 * - 3x3 longest screen-space velocity dilation for clean moving vehicle silhouette edges.
 * - 5-tap Catmull-Rom bicubic history reconstruction (eliminates bilinear temporal blur).
 * - YCoCg 3x3 variance clipping (Salvi 2016) to suppress trailing ghost silhouettes.
 * - Out-of-bounds / disocclusion / scene-cut reset fallback to current frame.
 */
class TaaResolveShader {
    public static final UNIFORM_BYTES:Int = 32; // 2 * vec4<f32>

    public static final WGSL:String = '
struct TaaUniforms {
    texelW       : f32,
    texelH       : f32,
    baseAlpha    : f32,
    gammaClip    : f32,
    resetHistory : f32,
    pad0         : f32,
    pad1         : f32,
    pad2         : f32,
};

@group(0) @binding(0) var<uniform> params : TaaUniforms;
@group(0) @binding(1) var currTex : texture_2d<f32>;
@group(0) @binding(2) var historyTex : texture_2d<f32>;
@group(0) @binding(3) var velocityTex : texture_2d<f32>;
@group(0) @binding(4) var linearSampler : sampler;

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

fn rgbToYcocg(c : vec3<f32>) -> vec3<f32> {
    let co = c.r - c.b;
    let tmp = c.b + co * 0.5;
    let cg = c.g - tmp;
    let y = tmp + cg * 0.5;
    return vec3<f32>(y, co, cg);
}

fn ycocgToRgb(ycc : vec3<f32>) -> vec3<f32> {
    let tmp = ycc.x - ycc.z * 0.5;
    let g = ycc.z + tmp;
    let b = tmp - ycc.y * 0.5;
    let r = b + ycc.y;
    return clamp(vec3<f32>(r, g, b), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn clipAabb(aabbMin : vec3<f32>, aabbMax : vec3<f32>, p : vec3<f32>, center : vec3<f32>) -> vec3<f32> {
    let d = p - center;
    let halfExt = max((aabbMax - aabbMin) * 0.5, vec3<f32>(1e-5));
    let unitOffset = abs(d / halfExt);
    let maxComp = max(unitOffset.x, max(unitOffset.y, unitOffset.z));
    if (maxComp > 1.0) {
        return center + d / maxComp;
    }
    return p;
}

// 5-tap Catmull-Rom bicubic filter using hardware bilinear samples
fn sampleHistoryCatmullRom(uv : vec2<f32>, texSize : vec2<f32>, invSize : vec2<f32>) -> vec3<f32> {
    let minUv = invSize * 0.5;
    let maxUv = vec2<f32>(1.0) - invSize * 0.5;
    let samplePos = uv * texSize;
    let texPos1 = floor(samplePos - 0.5) + 0.5;
    let f = samplePos - texPos1;

    let w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
    let w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
    let w2 = f * (0.5 + f * (2.0 - 1.5 * f));
    let w3 = f * f * (-0.5 + 0.5 * f);

    let w12 = w1 + w2;
    let offset12 = w2 / max(w12, vec2<f32>(1e-5));

    let tc0  = clamp((texPos1 - 1.0) * invSize, minUv, maxUv);
    let tc12 = clamp((texPos1 + offset12) * invSize, minUv, maxUv);
    let tc3  = clamp((texPos1 + 2.0) * invSize, minUv, maxUv);

    let result =
          textureSampleLevel(historyTex, linearSampler, vec2<f32>(tc12.x, tc0.y),  0.0).rgb * (w12.x * w0.y)
        + textureSampleLevel(historyTex, linearSampler, vec2<f32>(tc0.x,  tc12.y), 0.0).rgb * (w0.x  * w12.y)
        + textureSampleLevel(historyTex, linearSampler, vec2<f32>(tc12.x, tc12.y), 0.0).rgb * (w12.x * w12.y)
        + textureSampleLevel(historyTex, linearSampler, vec2<f32>(tc3.x,  tc12.y), 0.0).rgb * (w3.x  * w12.y)
        + textureSampleLevel(historyTex, linearSampler, vec2<f32>(tc12.x, tc3.y),  0.0).rgb * (w12.x * w3.y);

    let normFactor = (w12.x * w0.y) + (w0.x * w12.y) + (w12.x * w12.y) + (w3.x * w12.y) + (w12.x * w3.y);
    return clamp(result / max(normFactor, 1e-4), vec3<f32>(0.0), vec3<f32>(1.0));
}

@fragment
fn fs_main(in : PostOut) -> @location(0) vec4<f32> {
    let dims = vec2<i32>(textureDimensions(currTex, 0));
    let fDims = vec2<f32>(dims);
    let pxCoord = clamp(vec2<i32>(floor(in.clipPos.xy)), vec2<i32>(0, 0), dims - vec2<i32>(1, 1));
    let currCol = textureLoad(currTex, pxCoord, 0).rgb;

    if (params.resetHistory > 0.5) {
        return vec4<f32>(currCol, 1.0);
    }

    // 3x3 longest-velocity dilation for sharp moving car silhouette reprojection
    var bestVel = vec2<f32>(0.0);
    var bestMag = -1.0;
    for (var dy : i32 = -1; dy <= 1; dy++) {
        for (var dx : i32 = -1; dx <= 1; dx++) {
            let vc = clamp(pxCoord + vec2<i32>(dx, dy), vec2<i32>(0, 0), dims - vec2<i32>(1, 1));
            let v = textureLoad(velocityTex, vc, 0).xy;
            let mag = dot(v, v);
            if (mag > bestMag) {
                bestMag = mag;
                bestVel = v;
            }
        }
    }

    let prevUv = in.uv - bestVel;
    if (prevUv.x < 0.0 || prevUv.x > 1.0 || prevUv.y < 0.0 || prevUv.y > 1.0) {
        return vec4<f32>(currCol, 1.0);
    }

    // 3x3 neighborhood YCoCg moments (variance clipping)
    var m1 = vec3<f32>(0.0);
    var m2 = vec3<f32>(0.0);
    for (var dy : i32 = -1; dy <= 1; dy++) {
        for (var dx : i32 = -1; dx <= 1; dx++) {
            let sc = clamp(pxCoord + vec2<i32>(dx, dy), vec2<i32>(0, 0), dims - vec2<i32>(1, 1));
            let ycc = rgbToYcocg(textureLoad(currTex, sc, 0).rgb);
            m1 += ycc;
            m2 += ycc * ycc;
        }
    }

    let mean = m1 / 9.0;
    let sigma = sqrt(max(vec3<f32>(0.0), (m2 / 9.0) - mean * mean));
    let pxSpeed = length(bestVel * fDims);

    // Tighten variance box under rapid motion to completely reject trailing ghosts
    let dynGamma = mix(params.gammaClip, max(0.75, params.gammaClip * 0.78), clamp(pxSpeed * 0.08, 0.0, 1.0));
    let boxMin = mean - sigma * dynGamma;
    let boxMax = mean + sigma * dynGamma;

    let invSize = vec2<f32>(max(params.texelW, 0.0001), max(params.texelH, 0.0001));
    let histRgb = sampleHistoryCatmullRom(prevUv, fDims, invSize);
    let histYcc = rgbToYcocg(histRgb);
    let clippedHistRgb = ycocgToRgb(clipAabb(boxMin, boxMax, histYcc, mean));

    // Adaptive temporal blend: slow smooth convergence when stationary, fast response during motion
    let alpha = mix(params.baseAlpha, max(params.baseAlpha, 0.28), clamp(pxSpeed * 0.05, 0.0, 1.0));

    // Luminance-weighted resolve reduces high-contrast subpixel strobing
    let wCurr = alpha / (1.0 + dot(currCol, vec3<f32>(0.299, 0.587, 0.114)));
    let wHist = (1.0 - alpha) / (1.0 + dot(clippedHistRgb, vec3<f32>(0.299, 0.587, 0.114)));
    let resolved = (currCol * wCurr + clippedHistRgb * wHist) / max(wCurr + wHist, 1e-4);

    return vec4<f32>(resolved, 1.0);
}
';
}
