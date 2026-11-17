package graphics.shaders;

/**
 * Main forward 3D PBR-inspired lit shader for WebGPU.
 * Reads `SceneUniforms` + 160-byte `InstanceData` storage buffer (`@builtin(instance_index)`).
 * Handles Track surfaces (asphalt procedural grain/lane stripes, galvanized rails),
 * Sandbox Map analytic anti-aliased cyber-grid, automotive clearcoat + LED emissives,
 * and optional MRT screen-space velocity output (`WGSL_TAA`) for temporal anti-aliasing.
 */
class SceneLitShader {
    public static final SCENE_UNIFORM_BYTES:Int = 336; // 3 * mat4 (192) + 9 * vec4 (144)

    public static final WGSL:String = buildWgsl(false);
    public static final WGSL_TAA:String = buildWgsl(true);

    private static function buildWgsl(mrtVelocity:Bool):String {
        var extraOutFields = mrtVelocity ? '
    @location(5) currUnjitteredClip : vec4<f32>,
    @location(6) prevUnjitteredClip : vec4<f32>,
' : '';
        var extraVsAssign = mrtVelocity ? '
    let prevWp4 = inst.prevModel * vec4<f32>(in.pos, 1.0);
    out.currUnjitteredClip = scene.unjitteredViewProj * wp4;
    out.prevUnjitteredClip = scene.prevViewProj * prevWp4;
' : '';
        var fragHeader = mrtVelocity ? '
struct LitFragOut {
    @location(0) color : vec4<f32>,
    @location(1) velocity : vec2<f32>,
};

@fragment
fn fs_main(in : VertOut) -> LitFragOut {
' : '
@fragment
fn fs_main(in : VertOut) -> @location(0) vec4<f32> {
';
        var fragReturn = mrtVelocity ? '
    let currW = select(in.currUnjitteredClip.w, 1e-4, abs(in.currUnjitteredClip.w) < 1e-4);
    let prevW = select(in.prevUnjitteredClip.w, 1e-4, abs(in.prevUnjitteredClip.w) < 1e-4);
    var vel = (in.currUnjitteredClip.xy / currW - in.prevUnjitteredClip.xy / prevW) * vec2<f32>(0.5, -0.5);
    if (in.prevUnjitteredClip.w <= 0.0 || in.currUnjitteredClip.w <= 0.0) {
        vel = vec2<f32>(2.0, 2.0);
    }
    var out : LitFragOut;
    out.color = vec4<f32>(lit, 1.0);
    out.velocity = vel;
    return out;
' : '
    return vec4<f32>(lit, 1.0);
';

        return '
struct SceneUniforms {
    viewProj           : mat4x4<f32>,
    unjitteredViewProj : mat4x4<f32>,
    prevViewProj       : mat4x4<f32>,
    cameraPos          : vec4<f32>,
    sunDir             : vec4<f32>, // xyz = dir toward sun, w = specScale (0 disables spec)
    sunColor           : vec4<f32>,
    fillDir            : vec4<f32>, // xyz = dir toward fill light
    fillColor          : vec4<f32>,
    ambientColor       : vec4<f32>,
    fogColor           : vec4<f32>, // rgb = horizon fog color, w = fogDensity
    fxParams           : vec4<f32>, // x = reflScale, y = shadowStrength, z = surfaceDetail, w = lightScale
    taaParams          : vec4<f32>, // xy = jitterNdc, z = taaActive, w = pad
};

struct InstanceData {
    model     : mat4x4<f32>,
    prevModel : mat4x4<f32>,
    color     : vec4<f32>,
    material  : vec4<f32>, // x = emissive, y = roughness, z = gridScale, w = surfaceFlags
};

@group(0) @binding(0) var<uniform> scene : SceneUniforms;
@group(0) @binding(1) var<storage, read> instances : array<InstanceData>;

struct VertIn {
    @location(0) pos    : vec3<f32>,
    @location(1) normal : vec3<f32>,
    @location(2) uv     : vec2<f32>,
    @builtin(instance_index) instIdx : u32,
};

struct VertOut {
    @builtin(position) clipPos : vec4<f32>,
    @location(0) worldPos : vec3<f32>,
    @location(1) worldNorm : vec3<f32>,
    @location(2) uv : vec2<f32>,
    @location(3) color : vec4<f32>,
    @location(4) matParams : vec4<f32>,
' + extraOutFields + '
};

@vertex
fn vs_main(in : VertIn) -> VertOut {
    let inst = instances[in.instIdx];
    let wp4 = inst.model * vec4<f32>(in.pos, 1.0);

    // Cofactor normal transform handles non-uniform primitive scales accurately
    let c0 = cross(inst.model[1].xyz, inst.model[2].xyz);
    let c1 = cross(inst.model[2].xyz, inst.model[0].xyz);
    let c2 = cross(inst.model[0].xyz, inst.model[1].xyz);
    let rawN = c0 * in.normal.x + c1 * in.normal.y + c2 * in.normal.z;
    let lenSq = dot(rawN, rawN);
    let wn = select(vec3<f32>(0.0, 0.0, 1.0), rawN * inverseSqrt(lenSq), lenSq > 1e-10);

    var out : VertOut;
    out.clipPos = scene.viewProj * wp4;
    out.worldPos = wp4.xyz;
    out.worldNorm = wn;
    out.uv = in.uv;
    out.color = inst.color;
    out.matParams = inst.material;
' + extraVsAssign + '
    return out;
}
' + fragHeader + '
    let n = normalize(in.worldNorm);
    let viewVec = scene.cameraPos.xyz - in.worldPos;
    let dist = length(viewVec);
    let v = viewVec / max(dist, 1e-4);

    var albedo = in.color.rgb;
    let emissive = in.matParams.x;
    var roughness = clamp(in.matParams.y, 0.08, 0.98);
    let gridScale = in.matParams.z;
    let surfFlag = i32(in.matParams.w + 0.5);

    // Compute analytic grid derivatives in uniform control flow
    let gridDiv = max(gridScale, 0.01);
    let coord = in.worldPos.xy / gridDiv;
    let gDeriv = max(fwidth(coord), vec2<f32>(0.0001));
    let coordMajor = in.worldPos.xy / (gridDiv * 5.0);
    let gDerivMaj = max(fwidth(coordMajor), vec2<f32>(0.0001));

    // Procedural anti-aliased Sandbox grid
    if (gridScale > 0.01) {
        let grid = abs(fract(coord - 0.5) - 0.5) / gDeriv;
        let lineMinor = 1.0 - min(min(grid.x, grid.y), 1.0);

        let gridMaj = abs(fract(coordMajor - 0.5) - 0.5) / gDerivMaj;
        let lineMajor = 1.0 - min(min(gridMaj.x, gridMaj.y), 1.0);

        let elevation = in.worldPos.z;
        let baseGround = mix(vec3<f32>(0.11, 0.14, 0.19), vec3<f32>(0.18, 0.22, 0.28), clamp(elevation * 0.08, 0.0, 1.0));
        albedo = mix(baseGround, vec3<f32>(0.21, 0.30, 0.42), lineMinor * 0.45);
        albedo = mix(albedo, vec3<f32>(0.0, 0.72, 0.95), lineMajor * 0.65);
    } else if (in.uv.x < -0.5) {
        // Track gravel / sub-base embankment
        let grain = sin(in.worldPos.x * 9.7) * cos(in.worldPos.y * 9.7) * 0.02 * scene.fxParams.z;
        albedo = clamp(vec3<f32>(0.106, 0.118, 0.141) + vec3<f32>(grain), vec3<f32>(0.02), vec3<f32>(0.4));
        roughness = 0.85;
    } else if (in.uv.x > 1.5 && surfFlag == 1) {
        // Galvanized W-beam guardrail corrugation profile along vertical UV
        let rib = sin((in.uv.x - 2.0) * 3.14159 * 4.0) * 0.12 * scene.fxParams.z;
        albedo = clamp(vec3<f32>(0.62, 0.675, 0.72) + vec3<f32>(rib), vec3<f32>(0.05), vec3<f32>(0.95));
        roughness = 0.32;
    } else if (surfFlag == 1) {
        // Track asphalt ribbon: crisp center dashed yellow/white lane + edge shoulders
        let uEdge = abs(in.uv.x - 0.5) * 2.0; // 0 at center, 1 at guardrails
        let shoulderLine = smoothstep(0.88, 0.90, uEdge) * (1.0 - smoothstep(0.92, 0.94, uEdge));
        let dashPhase = fract(in.uv.y * 0.75);
        let centerLine = (1.0 - smoothstep(0.015, 0.025, abs(in.uv.x - 0.5))) * step(dashPhase, 0.48);
        let grain = sin(in.worldPos.x * 19.3) * cos(in.worldPos.y * 19.3) * 0.025 * scene.fxParams.z;
        albedo = clamp(vec3<f32>(0.157, 0.176, 0.208) + vec3<f32>(grain), vec3<f32>(0.0), vec3<f32>(1.0));
        albedo = mix(albedo, vec3<f32>(0.85, 0.88, 0.92), shoulderLine * 0.75);
        albedo = mix(albedo, vec3<f32>(0.95, 0.78, 0.20), centerLine * 0.85);
        roughness = 0.78;
    } else if (surfFlag == 2) {
        // Galvanized W-beam guardrail corrugation profile along vertical UV
        let rib = sin(in.uv.x * 3.14159 * 4.0) * 0.12 * scene.fxParams.z;
        albedo = clamp(albedo + vec3<f32>(rib), vec3<f32>(0.05), vec3<f32>(0.95));
        roughness = 0.32;
    }

    // Two-sided effective normal for thin double-sided geometry
    let effN = select(n, -n, dot(n, v) < 0.0);

    // Key directional light (sun) + shadow ambient grounding contrast
    let lSun = normalize(scene.sunDir.xyz);
    let nDotSun = max(dot(effN, lSun), 0.0);
    let shadowOcc = 1.0 - scene.fxParams.y * (1.0 - smoothstep(-0.15, 0.65, effN.z)) * 0.42;
    let halfSun = normalize(lSun + v);
    let shininess = mix(96.0, 8.0, roughness);
    let specPow = pow(max(dot(effN, halfSun), 0.0), shininess) * scene.sunDir.w * (1.0 - roughness * 0.75);

    // Secondary fill light
    let lFill = normalize(scene.fillDir.xyz);
    let nDotFill = max(dot(effN, lFill), 0.0);

    // Clearcoat Fresnel rim highlight controlled by Screen Reflections setting
    let fresnel = pow(1.0 - max(dot(effN, v), 0.0), 4.0) * (1.0 - roughness) * 0.38 * scene.fxParams.x;

    var lit = albedo * (scene.ambientColor.rgb * shadowOcc + scene.sunColor.rgb * nDotSun * scene.fxParams.w + scene.fillColor.rgb * nDotFill * scene.fxParams.w);
    lit += scene.sunColor.rgb * specPow * 0.55 * max(0.35, scene.fxParams.x * 0.65);
    lit += mix(albedo, vec3<f32>(1.0), 0.7) * fresnel;
    lit += albedo * emissive;

    // Gentle distance aerial perspective toward horizon fog
    let fogAmount = clamp(1.0 - exp(-dist * scene.fogColor.w), 0.0, 0.75);
    lit = mix(lit, scene.fogColor.rgb, fogAmount);
' + fragReturn + '
}
';
    }
}
