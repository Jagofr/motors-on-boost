package math;

import haxe.io.Bytes;
import haxe.io.Float32Array;

/**
 * Structure-of-Arrays (SoA) batch buffer for dynamic 3D mesh instances and draw records.
 * Avoids per-frame GC allocations by storing contiguous `Float32Array` channels and
 * packing them directly into WGSL `std140`/`std430` 160-byte aligned instance records:
 *   - offset   0..63  : `model: mat4x4<f32>` (16 floats)
 *   - offset  64..127 : `prevModel: mat4x4<f32>` (16 floats, per-object velocity for TAA)
 *   - offset 128..143 : `color: vec4<f32>` (RGBA)
 *   - offset 144..159 : `material: vec4<f32>` (emissive, roughness, gridScale, flags)
 */
class SoABuffer {
    public static inline var INSTANCE_FLOATS:Int = 40;
    public static inline var INSTANCE_STRIDE_BYTES:Int = 160; // 10 * 16 bytes (std140/std430 safe)

    public var capacity:Int;
    public var count:Int = 0;

    // Raw column-major world & previous-frame matrices per slot (16 floats per instance)
    public var worldMats:Float32Array;
    public var prevWorldMats:Float32Array;
    // Material/color RGBA + flags per slot (8 floats per instance)
    public var colorR:Float32Array;
    public var colorG:Float32Array;
    public var colorB:Float32Array;
    public var colorA:Float32Array;
    public var emissive:Float32Array;
    public var roughness:Float32Array;
    public var gridScale:Float32Array;
    public var flags:Float32Array;

    // Reusable staging bytes for queue.writeBuffer
    public var stagingBytes:Bytes;

    public function new(initialCapacity:Int = 256) {
        capacity = initialCapacity < 16 ? 16 : initialCapacity;
        allocate(capacity);
    }

    private function allocate(cap:Int):Void {
        capacity = cap;
        worldMats = new Float32Array(cap * 16);
        prevWorldMats = new Float32Array(cap * 16);
        colorR = new Float32Array(cap);
        colorG = new Float32Array(cap);
        colorB = new Float32Array(cap);
        colorA = new Float32Array(cap);
        emissive = new Float32Array(cap);
        roughness = new Float32Array(cap);
        gridScale = new Float32Array(cap);
        flags = new Float32Array(cap);
        stagingBytes = Bytes.alloc(cap * INSTANCE_STRIDE_BYTES);
    }

    public function ensureCapacity(needed:Int):Void {
        if (needed <= capacity) return;
        var nextCap = capacity * 2;
        while (nextCap < needed) nextCap *= 2;

        var oldMats = worldMats;
        var oldPrevMats = prevWorldMats;
        var oldR = colorR;
        var oldG = colorG;
        var oldB = colorB;
        var oldA = colorA;
        var oldE = emissive;
        var oldRough = roughness;
        var oldGrid = gridScale;
        var oldFlags = flags;
        var oldCount = count;

        allocate(nextCap);

        for (i in 0...(oldCount * 16)) {
            worldMats[i] = oldMats[i];
            prevWorldMats[i] = oldPrevMats[i];
        }
        for (i in 0...oldCount) {
            colorR[i] = oldR[i];
            colorG[i] = oldG[i];
            colorB[i] = oldB[i];
            colorA[i] = oldA[i];
            emissive[i] = oldE[i];
            roughness[i] = oldRough[i];
            gridScale[i] = oldGrid[i];
            flags[i] = oldFlags[i];
        }
    }

    public inline function reset():Void {
        count = 0;
    }

    public function pushInstance(
        mat:Mat4,
        r:Float, g:Float, b:Float, a:Float,
        emissiveVal:Float = 0.0,
        roughnessVal:Float = 0.45,
        gridScaleVal:Float = 0.0,
        flagsVal:Float = 0.0,
        ?prevMat:Mat4
    ):Int {
        var idx = count;
        if (idx >= capacity) ensureCapacity(idx + 1);
        var mOff = idx * 16;
        var mm = mat.m;
        var pmm = prevMat != null ? prevMat.m : mm;
        for (k in 0...16) {
            worldMats[mOff + k] = mm[k];
            prevWorldMats[mOff + k] = pmm[k];
        }
        colorR[idx] = r;
        colorG[idx] = g;
        colorB[idx] = b;
        colorA[idx] = a;
        emissive[idx] = emissiveVal;
        roughness[idx] = roughnessVal;
        gridScale[idx] = gridScaleVal;
        flags[idx] = flagsVal;
        count = idx + 1;
        return idx;
    }

    /**
     * Packs `[0, count)` into `stagingBytes` with strict 16-byte std140/std430 alignment.
     * Returns byte length written.
     */
    public function packToBytes():Int {
        var n = count;
        for (i in 0...n) {
            var bOff = i * INSTANCE_STRIDE_BYTES;
            var mOff = i * 16;
            for (k in 0...16) {
                stagingBytes.setFloat(bOff + (k << 2), worldMats[mOff + k]);
                stagingBytes.setFloat(bOff + 64 + (k << 2), prevWorldMats[mOff + k]);
            }
            stagingBytes.setFloat(bOff + 128, colorR[i]);
            stagingBytes.setFloat(bOff + 132, colorG[i]);
            stagingBytes.setFloat(bOff + 136, colorB[i]);
            stagingBytes.setFloat(bOff + 140, colorA[i]);
            stagingBytes.setFloat(bOff + 144, emissive[i]);
            stagingBytes.setFloat(bOff + 148, roughness[i]);
            stagingBytes.setFloat(bOff + 152, gridScale[i]);
            stagingBytes.setFloat(bOff + 156, flags[i]);
        }
        return n * INSTANCE_STRIDE_BYTES;
    }

    /**
     * Helper to write a padded WGSL `vec3<f32>` (3 floats + 1 float padding = 16 bytes).
     */
    public static inline function writeVec3Std140(bytes:Bytes, byteOffset:Int, x:Float, y:Float, z:Float, wPad:Float = 0.0):Void {
        bytes.setFloat(byteOffset, x);
        bytes.setFloat(byteOffset + 4, y);
        bytes.setFloat(byteOffset + 8, z);
        bytes.setFloat(byteOffset + 12, wPad);
    }

    /**
     * Helper to write a WGSL `vec4<f32>` (16 bytes).
     */
    public static inline function writeVec4Std140(bytes:Bytes, byteOffset:Int, x:Float, y:Float, z:Float, w:Float):Void {
        bytes.setFloat(byteOffset, x);
        bytes.setFloat(byteOffset + 4, y);
        bytes.setFloat(byteOffset + 8, z);
        bytes.setFloat(byteOffset + 12, w);
    }
}
