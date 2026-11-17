package graphics.shaders;

/**
 * Fullscreen Z-up atmospheric gradient sky shader with subtle solar disc bloom.
 * Reconstructs world-space ray directions directly from camera basis uniforms.
 */
class SkyShader {
    public static final UNIFORM_BYTES:Int = 256; // 8 * vec4<f32> (128) + 2 * mat4x4<f32> (128)

    public static final WGSL:String = buildWgsl(false);
    public static final WGSL_TAA:String = buildWgsl(true);

    private static function buildWgsl(mrtVelocity:Bool):String {
        var fragRet = mrtVelocity ? '
struct SkyFragOut {
    @location(0) color : vec4<f32>,
    @location(1) velocity : vec2<f32>,
};

@fragment
fn fs_main(in : SkyOut) -> SkyFragOut {
' : '
@fragment
fn fs_main(in : SkyOut) -> @location(0) vec4<f32> {
';
        var fragEnd = mrtVelocity ? '
    let currClip = sky.unjitteredViewProj * vec4<f32>(dir, 0.0);
    let prevClip = sky.prevViewProj * vec4<f32>(dir, 0.0);
    let currW = select(currClip.w, 1e-4, abs(currClip.w) < 1e-4);
    let prevW = select(prevClip.w, 1e-4, abs(prevClip.w) < 1e-4);
    var vel = (currClip.xy / currW - prevClip.xy / prevW) * vec2<f32>(0.5, -0.5);
    if (prevClip.w <= 0.0 || currClip.w <= 0.0) {
        vel = vec2<f32>(2.0, 2.0);
    }
    var res : SkyFragOut;
    res.color = vec4<f32>(col, 1.0);
    res.velocity = vel;
    return res;
' : '
    return vec4<f32>(col, 1.0);
';

        return '
struct SkyUniforms {
    camForward         : vec4<f32>, // xyz = forward, w = tanHalfFovY
    camRight           : vec4<f32>, // xyz = right, w = aspect
    camUp              : vec4<f32>, // xyz = up, w = 0
    topColor           : vec4<f32>,
    horizonColor       : vec4<f32>,
    groundColor        : vec4<f32>,
    sunDir             : vec4<f32>, // xyz = direction toward sun
    jitterParams       : vec4<f32>, // xy = jitterNdc
    unjitteredViewProj : mat4x4<f32>,
    prevViewProj       : mat4x4<f32>,
};

@group(0) @binding(0) var<uniform> sky : SkyUniforms;

struct SkyOut {
    @builtin(position) clipPos : vec4<f32>,
    @location(0) rayDir : vec3<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) vid : u32) -> SkyOut {
    var coords = array<vec2<f32>, 3>(
        vec2<f32>(-1.0, -1.0),
        vec2<f32>( 3.0, -1.0),
        vec2<f32>(-1.0,  3.0)
    );
    let ndc = coords[vid];
    let rayNdc = ndc - sky.jitterParams.xy;
    var out : SkyOut;
    out.clipPos = vec4<f32>(ndc.x, ndc.y, 1.0, 1.0);
    out.rayDir = sky.camForward.xyz
        + sky.camRight.xyz * (rayNdc.x * sky.camRight.w * sky.camForward.w)
        + sky.camUp.xyz    * (rayNdc.y * sky.camForward.w);
    return out;
}
' + fragRet + '
    let dir = normalize(in.rayDir);
    let h = dir.z;
    var col : vec3<f32>;
    if (h > 0.0) {
        let t = pow(h, 0.45);
        col = mix(sky.horizonColor.rgb, sky.topColor.rgb, t);
    } else {
        let t = clamp(-h * 5.0, 0.0, 1.0);
        col = mix(sky.horizonColor.rgb, sky.groundColor.rgb, t);
    }

    // Subtle atmospheric sun disc and horizon haze glow
    let toSun = normalize(sky.sunDir.xyz);
    let sunDot = max(dot(dir, toSun), 0.0);
    let halo = pow(sunDot, 16.0) * 0.22;
    let disc = smoothstep(0.9975, 0.9994, sunDot) * 0.85;
    let warmSun = vec3<f32>(1.0, 0.95, 0.84);
    col += warmSun * (halo + disc) * smoothstep(-0.08, 0.12, h);
' + fragEnd + '
}
';
    }
}
