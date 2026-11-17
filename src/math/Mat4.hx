package math;

import haxe.io.Bytes;
import haxe.io.Float32Array;

/**
 * Column-major 4x4 transformation/projection matrix backed by `Float32Array`.
 * Designed for WGSL `mat4x4<f32>` (`m[col * 4 + row]`) and WebGPU NDC depth `[0, 1]`.
 */
class Mat4 {
    public var m:Float32Array;

    public function new() {
        m = new Float32Array(16);
        setIdentity();
    }

    public inline function setIdentity():Mat4 {
        for (i in 0...16) m[i] = 0.0;
        m[0] = 1.0;
        m[5] = 1.0;
        m[10] = 1.0;
        m[15] = 1.0;
        return this;
    }

    public function clone():Mat4 {
        var c = new Mat4();
        c.load(this);
        return c;
    }

    public inline function load(src:Mat4):Mat4 {
        var sm = src.m;
        for (i in 0...16) m[i] = sm[i];
        return this;
    }

    /** Computes `this = a * b` (column-major; `b` applied first, then `a`). Aliasing safe. */
    public function multiply(a:Mat4, b:Mat4):Mat4 {
        var am = a.m;
        var bm = b.m;
        var a00 = am[0], a10 = am[1], a20 = am[2], a30 = am[3];
        var a01 = am[4], a11 = am[5], a21 = am[6], a31 = am[7];
        var a02 = am[8], a12 = am[9], a22 = am[10], a32 = am[11];
        var a03 = am[12], a13 = am[13], a23 = am[14], a33 = am[15];

        for (c in 0...4) {
            var bc = c * 4;
            var b0 = bm[bc];
            var b1 = bm[bc + 1];
            var b2 = bm[bc + 2];
            var b3 = bm[bc + 3];
            m[bc]     = a00 * b0 + a01 * b1 + a02 * b2 + a03 * b3;
            m[bc + 1] = a10 * b0 + a11 * b1 + a12 * b2 + a13 * b3;
            m[bc + 2] = a20 * b0 + a21 * b1 + a22 * b2 + a23 * b3;
            m[bc + 3] = a30 * b0 + a31 * b1 + a32 * b2 + a33 * b3;
        }
        return this;
    }

    /**
     * Composes `T(tx, ty, tz) * R(qx, qy, qz, qw) * S(sx, sy, sz)` into this matrix.
     */
    public inline function composeFromQuat(
        tx:Float, ty:Float, tz:Float,
        qx:Float, qy:Float, qz:Float, qw:Float,
        sx:Float, sy:Float, sz:Float
    ):Mat4 {
        var x2 = qx + qx;
        var y2 = qy + qy;
        var z2 = qz + qz;
        var xx = qx * x2;
        var xy = qx * y2;
        var xz = qx * z2;
        var yy = qy * y2;
        var yz = qy * z2;
        var zz = qz * z2;
        var wx = qw * x2;
        var wy = qw * y2;
        var wz = qw * z2;

        m[0]  = (1.0 - (yy + zz)) * sx;
        m[1]  = (xy + wz) * sx;
        m[2]  = (xz - wy) * sx;
        m[3]  = 0.0;

        m[4]  = (xy - wz) * sy;
        m[5]  = (1.0 - (xx + zz)) * sy;
        m[6]  = (yz + wx) * sy;
        m[7]  = 0.0;

        m[8]  = (xz + wy) * sz;
        m[9]  = (yz - wx) * sz;
        m[10] = (1.0 - (xx + yy)) * sz;
        m[11] = 0.0;

        m[12] = tx;
        m[13] = ty;
        m[14] = tz;
        m[15] = 1.0;
        return this;
    }

    /**
     * Composes `T * Rz(rz) * Ry(ry) * Rx(rx) * S` matching Heaps extrinsic XYZ (`initRotation`).
     */
    public function composeSRT(
        tx:Float, ty:Float, tz:Float,
        rx:Float, ry:Float, rz:Float,
        sx:Float, sy:Float, sz:Float
    ):Mat4 {
        var hx = rx * 0.5;
        var hy = ry * 0.5;
        var hz = rz * 0.5;
        var sxR = Math.sin(hx), cxR = Math.cos(hx);
        var syR = Math.sin(hy), cyR = Math.cos(hy);
        var szR = Math.sin(hz), czR = Math.cos(hz);

        // q = qz * qy * qx
        var qx = sxR * cyR * czR - cxR * syR * szR;
        var qy = cxR * syR * czR + sxR * cyR * szR;
        var qz = cxR * cyR * szR - sxR * syR * czR;
        var qw = cxR * cyR * czR + sxR * syR * szR;
        return composeFromQuat(tx, ty, tz, qx, qy, qz, qw, sx, sy, sz);
    }

    /**
     * Builds a right-handed Z-up view matrix looking from `eye` toward `target`.
     * View coordinates: `+X = Right`, `+Y = Up`, `-Z = Forward`.
     */
    public function lookAtZUp(eye:Vec3, target:Vec3, up:Vec3):Mat4 {
        var fx = target.x - eye.x;
        var fy = target.y - eye.y;
        var fz = target.z - eye.z;
        var fLenSq = fx * fx + fy * fy + fz * fz;
        if (fLenSq < 1e-12) {
            fx = 0.0;
            fy = 1.0;
            fz = 0.0;
        } else {
            var invF = 1.0 / Math.sqrt(fLenSq);
            fx *= invF;
            fy *= invF;
            fz *= invF;
        }

        // Right s = normalize(f x up)
        var sx = fy * up.z - fz * up.y;
        var sy = fz * up.x - fx * up.z;
        var sz = fx * up.y - fy * up.x;
        var sLenSq = sx * sx + sy * sy + sz * sz;
        if (sLenSq < 1e-12) {
            // Forward nearly parallel to up; pick +X fallback
            sx = 1.0;
            sy = 0.0;
            sz = 0.0;
        } else {
            var invS = 1.0 / Math.sqrt(sLenSq);
            sx *= invS;
            sy *= invS;
            sz *= invS;
        }

        // Camera Up u = s x f
        var ux = sy * fz - sz * fy;
        var uy = sz * fx - sx * fz;
        var uz = sx * fy - sy * fx;

        m[0] = sx;   m[4] = sy;   m[8]  = sz;   m[12] = -(sx * eye.x + sy * eye.y + sz * eye.z);
        m[1] = ux;   m[5] = uy;   m[9]  = uz;   m[13] = -(ux * eye.x + uy * eye.y + uz * eye.z);
        m[2] = -fx;  m[6] = -fy;  m[10] = -fz;  m[14] =  (fx * eye.x + fy * eye.y + fz * eye.z);
        m[3] = 0.0;  m[7] = 0.0;  m[11] = 0.0;  m[15] = 1.0;
        return this;
    }

    /**
     * Builds a right-handed WebGPU perspective projection matrix mapping `near -> z=0`, `far -> z=1`.
     * @param fovYDeg Vertical field-of-view in degrees.
     */
    public function perspectiveWebGPU(fovYDeg:Float, aspect:Float, near:Float, far:Float):Mat4 {
        var halfRad = (fovYDeg * Math.PI) / 360.0;
        var t = Math.tan(halfRad);
        if (t < 1e-6) t = 1e-6;
        var fy = 1.0 / t;
        var safeAspect = aspect > 1e-4 ? aspect : 1.0;
        var fx = fy / safeAspect;
        var nf = 1.0 / (near - far);

        for (i in 0...16) m[i] = 0.0;
        m[0]  = fx;
        m[5]  = fy;
        m[10] = far * nf;
        m[11] = -1.0;
        m[14] = (far * near) * nf;
        return this;
    }

    /** Writes all 16 float32 values (64 bytes, WGSL std140/std430 aligned) into `bytes`. */
    public inline function writeStd140(bytes:Bytes, byteOffset:Int):Void {
        for (i in 0...16) {
            bytes.setFloat(byteOffset + (i << 2), m[i]);
        }
    }
}
