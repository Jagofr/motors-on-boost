package graphics.shaders;

/**
 * WGSL compute shader generating track roadbed, asphalt ribbon, and double-sided
 * galvanized steel guardrails directly into vertex, index, and DrawIndexedIndirect buffers.
 *
 * Vertex layout matches `PrimitiveDesc.VERTEX_STRIDE_BYTES = 32` (`px, py, pz, nx, ny, nz, u, v`).
 */
class TrackComputeShader {
    public static final WGSL:String = '
struct TrackParams {
    numPoints : u32,
    pad0 : u32,
    roadHalfWidth : f32,
    bedHalfWidth : f32,
    roadLift : f32,
    bedDrop : f32,
    railHeight : f32,
    uvScale : f32,
};

struct TrackVert {
    px : f32,
    py : f32,
    pz : f32,
    nx : f32,
    ny : f32,
    nz : f32,
    u  : f32,
    v  : f32,
};

struct IndirectArgs {
    indexCount    : u32,
    instanceCount : u32,
    firstIndex    : u32,
    baseVertex    : i32,
    firstInstance : u32,
};

@group(0) @binding(0) var<uniform> params : TrackParams;
@group(0) @binding(1) var<storage, read> splines : array<vec4<f32>>;
@group(0) @binding(2) var<storage, read_write> verts : array<TrackVert>;
@group(0) @binding(3) var<storage, read_write> indices : array<u32>;
@group(0) @binding(4) var<storage, read_write> indirectArgs : array<IndirectArgs>;

fn makeVert(pos : vec3<f32>, norm : vec3<f32>, u : f32, v : f32) -> TrackVert {
    var tv : TrackVert;
    tv.px = pos.x;
    tv.py = pos.y;
    tv.pz = pos.z;
    tv.nx = norm.x;
    tv.ny = norm.y;
    tv.nz = norm.z;
    tv.u  = u;
    tv.v  = v;
    return tv;
}

@compute @workgroup_size(64)
fn cs_main(@builtin(global_invocation_id) gid : vec3<u32>) {
    let i = gid.x;
    let n = params.numPoints;
    if (i >= n || n < 3u) {
        return;
    }

    let nextIdx = (i + 1u) % n;
    let prevIdx = (i + n - 1u) % n;

    let currData = splines[i];
    let curr = currData.xyz;
    let arcU = currData.w * params.uvScale;
    let prev = splines[prevIdx].xyz;
    let next = splines[nextIdx].xyz;

    let delta3 = next - prev;
    let fwdFlat = normalize(vec3<f32>(delta3.x, delta3.y, 0.0) + vec3<f32>(0.0, 1e-6, 0.0));
    let side = vec3<f32>(-fwdFlat.y, fwdFlat.x, 0.0);
    let tanLen = max(length(delta3), 1e-5);
    let tan3 = delta3 / tanLen;
    var upN = cross(tan3, side);
    let upLen = max(length(upN), 1e-5);
    upN = upN / upLen;

    // 1. Roadbed ribbon: [0 .. 2N), encoded u in [-2.0, -1.0] for portable indirect draws
    let bedL = curr - side * params.bedHalfWidth + vec3<f32>(0.0, 0.0, -params.bedDrop);
    let bedR = curr + side * params.bedHalfWidth + vec3<f32>(0.0, 0.0, -params.bedDrop);
    let bedBase = 0u;
    verts[bedBase + i * 2u]      = makeVert(bedL, upN, -2.0, arcU);
    verts[bedBase + i * 2u + 1u] = makeVert(bedR, upN, -1.0, arcU);

    // 2. Asphalt ribbon: [2N .. 4N), u in [0.0, 1.0]
    let roadBase = n * 2u;
    let roadL = curr - side * params.roadHalfWidth + vec3<f32>(0.0, 0.0, params.roadLift);
    let roadR = curr + side * params.roadHalfWidth + vec3<f32>(0.0, 0.0, params.roadLift);
    verts[roadBase + i * 2u]      = makeVert(roadL, upN, 0.0, arcU);
    verts[roadBase + i * 2u + 1u] = makeVert(roadR, upN, 1.0, arcU);

    // 3. Left Guardrail: [4N .. 6N), encoded u in [2.0, 3.0]
    let leftBase = n * 4u;
    let railNormL = side;
    let railZ0 = curr.z + params.roadLift;
    let railZ1 = railZ0 + params.railHeight;
    let rlPos = curr - side * params.roadHalfWidth;
    verts[leftBase + i * 2u]      = makeVert(vec3<f32>(rlPos.x, rlPos.y, railZ0), railNormL, 2.0, arcU);
    verts[leftBase + i * 2u + 1u] = makeVert(vec3<f32>(rlPos.x, rlPos.y, railZ1), railNormL, 3.0, arcU);

    // 4. Right Guardrail: [6N .. 8N), encoded u in [2.0, 3.0]
    let rightBase = n * 6u;
    let railNormR = -side;
    let rrPos = curr + side * params.roadHalfWidth;
    verts[rightBase + i * 2u]      = makeVert(vec3<f32>(rrPos.x, rrPos.y, railZ0), railNormR, 2.0, arcU);
    verts[rightBase + i * 2u + 1u] = makeVert(vec3<f32>(rrPos.x, rrPos.y, railZ1), railNormR, 3.0, arcU);

    // Index generation per segment
    let bi0 = bedBase + i * 2u;
    let bi1 = bi0 + 1u;
    let bi2 = bedBase + nextIdx * 2u;
    let bi3 = bi2 + 1u;
    let bIdxBase = i * 6u;
    indices[bIdxBase + 0u] = bi0;
    indices[bIdxBase + 1u] = bi2;
    indices[bIdxBase + 2u] = bi1;
    indices[bIdxBase + 3u] = bi1;
    indices[bIdxBase + 4u] = bi2;
    indices[bIdxBase + 5u] = bi3;

    let ri0 = roadBase + i * 2u;
    let ri1 = ri0 + 1u;
    let ri2 = roadBase + nextIdx * 2u;
    let ri3 = ri2 + 1u;
    let rIdxBase = n * 6u + i * 6u;
    indices[rIdxBase + 0u] = ri0;
    indices[rIdxBase + 1u] = ri2;
    indices[rIdxBase + 2u] = ri1;
    indices[rIdxBase + 3u] = ri1;
    indices[rIdxBase + 4u] = ri2;
    indices[rIdxBase + 5u] = ri3;

    // Left rail double-sided
    let li0 = leftBase + i * 2u;
    let li1 = li0 + 1u;
    let li2 = leftBase + nextIdx * 2u;
    let li3 = li2 + 1u;
    let lIdxBase = n * 12u + i * 12u;
    indices[lIdxBase + 0u]  = li0; indices[lIdxBase + 1u]  = li2; indices[lIdxBase + 2u]  = li1;
    indices[lIdxBase + 3u]  = li1; indices[lIdxBase + 4u]  = li2; indices[lIdxBase + 5u]  = li3;
    indices[lIdxBase + 6u]  = li0; indices[lIdxBase + 7u]  = li1; indices[lIdxBase + 8u]  = li2;
    indices[lIdxBase + 9u]  = li1; indices[lIdxBase + 10u] = li3; indices[lIdxBase + 11u] = li2;

    // Right rail double-sided
    let gi0 = rightBase + i * 2u;
    let gi1 = gi0 + 1u;
    let gi2 = rightBase + nextIdx * 2u;
    let gi3 = gi2 + 1u;
    let gIdxBase = n * 24u + i * 12u;
    indices[gIdxBase + 0u]  = gi0; indices[gIdxBase + 1u]  = gi1; indices[gIdxBase + 2u]  = gi2;
    indices[gIdxBase + 3u]  = gi1; indices[gIdxBase + 4u]  = gi3; indices[gIdxBase + 5u]  = gi2;
    indices[gIdxBase + 6u]  = gi0; indices[gIdxBase + 7u]  = gi2; indices[gIdxBase + 8u]  = gi1;
    indices[gIdxBase + 9u]  = gi1; indices[gIdxBase + 10u] = gi2; indices[gIdxBase + 11u] = gi3;

    if (i == 0u) {
        // Roadbed indirect args (uses slot 0, differentiated in shader via uv.x)
        indirectArgs[0] = IndirectArgs(n * 6u, 1u, 0u, 0, 0u);
        // Asphalt indirect args
        indirectArgs[1] = IndirectArgs(n * 6u, 1u, n * 6u, 0, 0u);
        // Left guardrail indirect args
        indirectArgs[2] = IndirectArgs(n * 12u, 1u, n * 12u, 0, 0u);
        // Right guardrail indirect args
        indirectArgs[3] = IndirectArgs(n * 12u, 1u, n * 24u, 0, 0u);
    }
}
';
}
