package graphics;

import haxe.io.Bytes;

/**
 * 3D vertex/point coordinate helper replacing `h3d.col.Point` / `h3d.prim.UV`.
 */
class Point {
    public var x:Float;
    public var y:Float;
    public var z:Float;

    public inline function new(x:Float = 0.0, y:Float = 0.0, z:Float = 0.0) {
        this.x = x;
        this.y = y;
        this.z = z;
    }

    public inline function set(x:Float = 0.0, y:Float = 0.0, z:Float = 0.0):Void {
        this.x = x;
        this.y = y;
        this.z = z;
    }

    public inline function load(p:Point):Void {
        this.x = p.x;
        this.y = p.y;
        this.z = p.z;
    }

    public inline function clone():Point {
        return new Point(x, y, z);
    }

    public inline function sub(p:Point):Point {
        return new Point(x - p.x, y - p.y, z - p.z);
    }

    public inline function add(p:Point):Point {
        return new Point(x + p.x, y + p.y, z + p.z);
    }

    public inline function cross(p:Point):Point {
        return new Point(
            y * p.z - z * p.y,
            z * p.x - x * p.z,
            x * p.y - y * p.x
        );
    }

    public inline function dot(p:Point):Float {
        return x * p.x + y * p.y + z * p.z;
    }

    public inline function length():Float {
        return Math.sqrt(x * x + y * y + z * z);
    }

    public inline function normalize():Void {
        var len = length();
        if (len > 1e-10) {
            var inv = 1.0 / len;
            x *= inv;
            y *= inv;
            z *= inv;
        }
    }
}

class UV {
    public var u:Float;
    public var v:Float;

    public inline function new(u:Float = 0.0, v:Float = 0.0) {
        this.u = u;
        this.v = v;
    }
}

/**
 * Interleaved procedural geometry primitive backing WebGPU vertex + index buffers.
 * Vertex layout (32 bytes / vertex): `[px, py, pz, nx, ny, nz, u, v]` (Float32).
 */
class PrimitiveDesc {
    public static inline var VERTEX_STRIDE_BYTES:Int = 32;
    private static var NEXT_GPU_ID:Int = 1;

    public var gpuId(default, null):Int;
    public var points:Array<Point>;
    public var normals:Array<Point>;
    public var uvs:Array<UV>;
    public var idx:Array<Int>;

    public var dirty:Bool = true;
    public var vertexBytes:Null<Bytes> = null;
    public var indexBytes:Null<Bytes> = null;
    public var vertexCount:Int = 0;
    public var indexCount:Int = 0;

    public function new() {
        gpuId = NEXT_GPU_ID++;
        points = [];
        normals = [];
        uvs = [];
        idx = [];
    }

    public function triCount():Int {
        return idx.length > 0 ? Std.int(idx.length / 3) : Std.int(points.length / 3);
    }

    public function vertexCountEstimate():Int {
        return points.length;
    }

    /**
     * Expands indexed triangles into unique per-triangle vertices (preserving sharp flat normals).
     */
    public function unindex():Void {
        if (points.length == 0) return;
        var hasIdx = idx != null && idx.length > 0;
        var count = hasIdx ? idx.length : points.length;
        var newPts:Array<Point> = [];
        var newUvs:Array<UV> = [];
        var newNorms:Array<Point> = [];
        var hasUv = uvs != null && uvs.length == points.length;
        var hasNorm = normals != null && normals.length == points.length;

        for (k in 0...count) {
            var vi = hasIdx ? idx[k] : k;
            newPts.push(points[vi].clone());
            newUvs.push(hasUv ? new UV(uvs[vi].u, uvs[vi].v) : new UV(0.0, 0.0));
            if (hasNorm) newNorms.push(normals[vi].clone());
        }

        points = newPts;
        uvs = newUvs;
        normals = newNorms;
        idx = [for (i in 0...newPts.length) i];
        dirty = true;
    }

    /**
     * Computes smooth vertex normals (or flat face normals if unindexed).
     */
    public function addNormals():Void {
        var nVerts = points.length;
        normals = [for (_ in 0...nVerts) new Point(0.0, 0.0, 0.0)];
        var indices = (idx != null && idx.length > 0) ? idx : [for (i in 0...nVerts) i];

        var tri = 0;
        while (tri + 2 < indices.length) {
            var i0 = indices[tri];
            var i1 = indices[tri + 1];
            var i2 = indices[tri + 2];
            tri += 3;
            if (i0 < 0 || i1 < 0 || i2 < 0 || i0 >= nVerts || i1 >= nVerts || i2 >= nVerts) continue;

            var p0 = points[i0];
            var p1 = points[i1];
            var p2 = points[i2];
            var e1x = p1.x - p0.x, e1y = p1.y - p0.y, e1z = p1.z - p0.z;
            var e2x = p2.x - p0.x, e2y = p2.y - p0.y, e2z = p2.z - p0.z;
            var nx = e1y * e2z - e1z * e2y;
            var ny = e1z * e2x - e1x * e2z;
            var nz = e1x * e2y - e1y * e2x;

            normals[i0].x += nx; normals[i0].y += ny; normals[i0].z += nz;
            normals[i1].x += nx; normals[i1].y += ny; normals[i1].z += nz;
            normals[i2].x += nx; normals[i2].y += ny; normals[i2].z += nz;
        }

        for (n in normals) {
            var lSq = n.x * n.x + n.y * n.y + n.z * n.z;
            if (lSq > 1e-12) {
                var inv = 1.0 / Math.sqrt(lSq);
                n.x *= inv;
                n.y *= inv;
                n.z *= inv;
            } else {
                n.set(0.0, 0.0, 1.0);
            }
        }
        dirty = true;
    }

    public function addUVs():Void {
        if (uvs != null && uvs.length == points.length) return;
        uvs = [for (p in points) new UV(p.x, p.y)];
        dirty = true;
    }

    public function translate(dx:Float, dy:Float, dz:Float):Void {
        for (p in points) {
            p.x += dx;
            p.y += dy;
            p.z += dz;
        }
        dirty = true;
    }

    /**
     * Packs interleaved vertex + Uint32 index bytes into host staging buffers for GPU upload.
     */
    public function packGpuData():Void {
        if (!dirty && vertexBytes != null && indexBytes != null) return;
        if (normals.length != points.length) addNormals();
        if (uvs.length != points.length) addUVs();

        var indices = (idx != null && idx.length > 0) ? idx : [for (i in 0...points.length) i];
        vertexCount = points.length;
        indexCount = indices.length;

        vertexBytes = Bytes.alloc(vertexCount * VERTEX_STRIDE_BYTES);
        for (i in 0...vertexCount) {
            var p = points[i];
            var n = normals[i];
            var uv = uvs[i];
            var off = i * VERTEX_STRIDE_BYTES;
            vertexBytes.setFloat(off,      p.x);
            vertexBytes.setFloat(off + 4,  p.y);
            vertexBytes.setFloat(off + 8,  p.z);
            vertexBytes.setFloat(off + 12, n.x);
            vertexBytes.setFloat(off + 16, n.y);
            vertexBytes.setFloat(off + 20, n.z);
            vertexBytes.setFloat(off + 24, uv.u);
            vertexBytes.setFloat(off + 28, uv.v);
        }

        indexBytes = Bytes.alloc(indexCount * 4);
        for (i in 0...indexCount) {
            indexBytes.setInt32(i << 2, indices[i]);
        }

        dirty = false;
    }
}

class Cube extends PrimitiveDesc {
    public function new(width:Float = 1.0, height:Float = 1.0, depth:Float = 1.0, centered:Bool = false) {
        super();
        var x0 = centered ? -width * 0.5 : 0.0;
        var x1 = x0 + width;
        var y0 = centered ? -height * 0.5 : 0.0;
        var y1 = y0 + height;
        var z0 = centered ? -depth * 0.5 : 0.0;
        var z1 = z0 + depth;

        inline function addQuad(
            p0x:Float, p0y:Float, p0z:Float,
            p1x:Float, p1y:Float, p1z:Float,
            p2x:Float, p2y:Float, p2z:Float,
            p3x:Float, p3y:Float, p3z:Float,
            nx:Float, ny:Float, nz:Float
        ):Void {
            var base = points.length;
            points.push(new Point(p0x, p0y, p0z));
            points.push(new Point(p1x, p1y, p1z));
            points.push(new Point(p2x, p2y, p2z));
            points.push(new Point(p3x, p3y, p3z));
            for (_ in 0...4) normals.push(new Point(nx, ny, nz));
            uvs.push(new UV(0.0, 0.0));
            uvs.push(new UV(1.0, 0.0));
            uvs.push(new UV(1.0, 1.0));
            uvs.push(new UV(0.0, 1.0));
            idx.push(base);     idx.push(base + 1); idx.push(base + 2);
            idx.push(base);     idx.push(base + 2); idx.push(base + 3);
        }

        // +Z top
        addQuad(x0, y0, z1,  x1, y0, z1,  x1, y1, z1,  x0, y1, z1,   0,  0,  1);
        // -Z bottom
        addQuad(x0, y1, z0,  x1, y1, z0,  x1, y0, z0,  x0, y0, z0,   0,  0, -1);
        // +X right
        addQuad(x1, y0, z0,  x1, y1, z0,  x1, y1, z1,  x1, y0, z1,   1,  0,  0);
        // -X left
        addQuad(x0, y1, z0,  x0, y0, z0,  x0, y0, z1,  x0, y1, z1,  -1,  0,  0);
        // +Y front
        addQuad(x1, y1, z0,  x0, y1, z0,  x0, y1, z1,  x1, y1, z1,   0,  1,  0);
        // -Y back
        addQuad(x0, y0, z0,  x1, y0, z0,  x1, y0, z1,  x0, y0, z1,   0, -1,  0);
    }
}

class Cylinder extends PrimitiveDesc {
    public function new(segments:Int, radius:Float, height:Float, centered:Bool = false) {
        super();
        var seg = segments < 3 ? 3 : segments;
        var z0 = centered ? -height * 0.5 : 0.0;
        var z1 = z0 + height;

        for (i in 0...(seg + 1)) {
            var u = i / seg;
            var angle = u * Math.PI * 2.0;
            var ca = Math.cos(angle);
            var sa = Math.sin(angle);
            var px = ca * radius;
            var py = sa * radius;
            points.push(new Point(px, py, z0));
            normals.push(new Point(ca, sa, 0.0));
            uvs.push(new UV(u, 0.0));

            points.push(new Point(px, py, z1));
            normals.push(new Point(ca, sa, 0.0));
            uvs.push(new UV(u, 1.0));
        }

        for (i in 0...seg) {
            var b0 = i * 2;
            var t0 = b0 + 1;
            var b1 = b0 + 2;
            var t1 = b0 + 3;
            idx.push(b0); idx.push(b1); idx.push(t1);
            idx.push(b0); idx.push(t1); idx.push(t0);
        }
    }
}

class Disc extends PrimitiveDesc {
    public function new(radius:Float, segments:Int = 16) {
        super();
        var seg = segments < 3 ? 3 : segments;
        points.push(new Point(0.0, 0.0, 0.0));
        normals.push(new Point(0.0, 0.0, 1.0));
        uvs.push(new UV(0.5, 0.5));

        for (i in 0...(seg + 1)) {
            var angle = (i / seg) * Math.PI * 2.0;
            var ca = Math.cos(angle);
            var sa = Math.sin(angle);
            points.push(new Point(ca * radius, sa * radius, 0.0));
            normals.push(new Point(0.0, 0.0, 1.0));
            uvs.push(new UV(0.5 + ca * 0.5, 0.5 + sa * 0.5));
        }

        for (i in 0...seg) {
            idx.push(0);
            idx.push(1 + i);
            idx.push(2 + i);
        }
    }
}

class Sphere extends PrimitiveDesc {
    public function new(radius:Float = 1.0, segW:Int = 16, segH:Int = 12) {
        super();
        var w = segW < 4 ? 4 : segW;
        var h = segH < 3 ? 3 : segH;

        for (j in 0...(h + 1)) {
            var v = j / h;
            var phi = (v - 0.5) * Math.PI;
            var cPhi = Math.cos(phi);
            var sPhi = Math.sin(phi);
            for (i in 0...(w + 1)) {
                var u = i / w;
                var theta = u * Math.PI * 2.0;
                var cTh = Math.cos(theta);
                var sTh = Math.sin(theta);
                var nx = cPhi * cTh;
                var ny = cPhi * sTh;
                var nz = sPhi;
                points.push(new Point(nx * radius, ny * radius, nz * radius));
                normals.push(new Point(nx, ny, nz));
                uvs.push(new UV(u, v));
            }
        }

        var row = w + 1;
        for (j in 0...h) {
            for (i in 0...w) {
                var a = j * row + i;
                var b = a + 1;
                var c = a + row;
                var d = c + 1;
                idx.push(a); idx.push(b); idx.push(d);
                idx.push(a); idx.push(d); idx.push(c);
            }
        }
    }
}

class Polygon extends PrimitiveDesc {
    public function new(pts:Array<Point>, ?indices:Array<Int>) {
        super();
        points = [for (p in pts) p.clone()];
        if (indices != null) {
            idx = indices.copy();
        } else {
            idx = [for (i in 0...pts.length) i];
        }
        addUVs();
    }
}
