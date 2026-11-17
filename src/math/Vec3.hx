package math;

/**
 * Pure Haxe 3D/4D vector math class replacing `h3d.Vector` for the WebGPU backend.
 * Follows Z-up right-handed world conventions (+X Right, +Y Forward, +Z Up)
 * and provides RGBA accessors (`r`, `g`, `b`, `a`) for color/uniform interop.
 */
class Vec3 {
    public var x:Float;
    public var y:Float;
    public var z:Float;
    public var w:Float;

    public var r(get, set):Float;
    public var g(get, set):Float;
    public var b(get, set):Float;
    public var a(get, set):Float;

    inline function get_r():Float return x;
    inline function set_r(v:Float):Float return x = v;
    inline function get_g():Float return y;
    inline function set_g(v:Float):Float return y = v;
    inline function get_b():Float return z;
    inline function set_b(v:Float):Float return z = v;
    inline function get_a():Float return w;
    inline function set_a(v:Float):Float return w = v;

    public inline function new(x:Float = 0.0, y:Float = 0.0, z:Float = 0.0, w:Float = 1.0) {
        this.x = x;
        this.y = y;
        this.z = z;
        this.w = w;
    }

    /** Create a Vec3 from a 0xAARRGGBB or 0xRRGGBB integer color. */
    public static inline function fromColor(c:Int):Vec3 {
        var v = new Vec3();
        v.setColor(c);
        return v;
    }

    public inline function set(x:Float = 0.0, y:Float = 0.0, z:Float = 0.0, w:Float = 1.0):Void {
        this.x = x;
        this.y = y;
        this.z = z;
        this.w = w;
    }

    public inline function load(v:Vec3):Void {
        this.x = v.x;
        this.y = v.y;
        this.z = v.z;
        this.w = v.w;
    }

    public inline function clone():Vec3 {
        return new Vec3(x, y, z, w);
    }

    public inline function add(v:Vec3):Vec3 {
        return new Vec3(x + v.x, y + v.y, z + v.z, w + v.w);
    }

    public inline function addSelf(v:Vec3):Vec3 {
        x += v.x;
        y += v.y;
        z += v.z;
        return this;
    }

    public inline function sub(v:Vec3):Vec3 {
        return new Vec3(x - v.x, y - v.y, z - v.z, w - v.w);
    }

    public inline function subSelf(v:Vec3):Vec3 {
        x -= v.x;
        y -= v.y;
        z -= v.z;
        return this;
    }

    /** Mutates this vector in-place by multiplying XYZ by `f`. */
    public inline function scale(f:Float):Void {
        x *= f;
        y *= f;
        z *= f;
    }

    /** Returns a new vector with XYZ scaled by `f`. */
    public inline function scaled(f:Float):Vec3 {
        return new Vec3(x * f, y * f, z * f, w);
    }

    public inline function scale3(f:Float):Vec3 {
        return new Vec3(x * f, y * f, z * f, w);
    }

    public inline function dot(v:Vec3):Float {
        return x * v.x + y * v.y + z * v.z;
    }

    public inline function dot3(v:Vec3):Float {
        return x * v.x + y * v.y + z * v.z;
    }

    public inline function dot4(v:Vec3):Float {
        return x * v.x + y * v.y + z * v.z + w * v.w;
    }

    public inline function cross(v:Vec3):Vec3 {
        return new Vec3(
            y * v.z - z * v.y,
            z * v.x - x * v.z,
            x * v.y - y * v.x,
            1.0
        );
    }

    public inline function lengthSq():Float {
        return x * x + y * y + z * z;
    }

    public inline function length():Float {
        return Math.sqrt(lengthSq());
    }

    public inline function distanceSq(v:Vec3):Float {
        var dx = x - v.x;
        var dy = y - v.y;
        var dz = z - v.z;
        return dx * dx + dy * dy + dz * dz;
    }

    public inline function distance(v:Vec3):Float {
        return Math.sqrt(distanceSq(v));
    }

    public inline function normalize():Void {
        var k = lengthSq();
        if (k < 1e-10) {
            k = 0.0;
        } else {
            k = 1.0 / Math.sqrt(k);
        }
        x *= k;
        y *= k;
        z *= k;
    }

    public inline function normalized():Vec3 {
        var k = lengthSq();
        if (k < 1e-10) {
            return new Vec3(0.0, 0.0, 0.0, w);
        }
        k = 1.0 / Math.sqrt(k);
        return new Vec3(x * k, y * k, z * k, w);
    }

    public inline function lerp(v1:Vec3, v2:Vec3, k:Float):Void {
        x = v1.x + (v2.x - v1.x) * k;
        y = v1.y + (v2.y - v1.y) * k;
        z = v1.z + (v2.z - v1.z) * k;
        w = v1.w + (v2.w - v1.w) * k;
    }

    /** Sets RGB(A) components in [0, 1] from 0xAARRGGBB color integer. */
    public inline function setColor(c:Int):Void {
        x = ((c >> 16) & 0xFF) / 255.0;
        y = ((c >> 8) & 0xFF) / 255.0;
        z = (c & 0xFF) / 255.0;
        w = ((c >>> 24) & 0xFF) / 255.0;
    }

    public inline function toColor():Int {
        inline function clampByte(v:Float):Int {
            var i = Math.round(v * 255.0);
            return i < 0 ? 0 : (i > 255 ? 255 : i);
        }
        return (clampByte(w) << 24) | (clampByte(x) << 16) | (clampByte(y) << 8) | clampByte(z);
    }

    public inline function transform(m:Mat4):Vec3 {
        var tx = x * m.m[0] + y * m.m[4] + z * m.m[8] + w * m.m[12];
        var ty = x * m.m[1] + y * m.m[5] + z * m.m[9] + w * m.m[13];
        var tz = x * m.m[2] + y * m.m[6] + z * m.m[10] + w * m.m[14];
        var tw = x * m.m[3] + y * m.m[7] + z * m.m[11] + w * m.m[15];
        x = tx;
        y = ty;
        z = tz;
        w = tw;
        return this;
    }

    public inline function transformed(m:Mat4):Vec3 {
        return clone().transform(m);
    }

    public inline function transform3x3(m:Mat4):Vec3 {
        var tx = x * m.m[0] + y * m.m[4] + z * m.m[8];
        var ty = x * m.m[1] + y * m.m[5] + z * m.m[9];
        var tz = x * m.m[2] + y * m.m[6] + z * m.m[10];
        x = tx;
        y = ty;
        z = tz;
        return this;
    }

    public inline function equals(v:Vec3):Bool {
        return x == v.x && y == v.y && z == v.z && w == v.w;
    }

    public function toString():String {
        return '{${Math.round(x * 1000) / 1000}, ${Math.round(y * 1000) / 1000}, ${Math.round(z * 1000) / 1000}}';
    }
}
