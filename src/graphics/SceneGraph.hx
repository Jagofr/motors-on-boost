package graphics;

import haxe.io.Bytes;
import math.Mat4;
import math.Vec3;
import graphics.Primitives.PrimitiveDesc;

enum CullModeDesc {
    Back;
    None;
    Front;
}

enum DepthCompareDesc {
    Less;
    LessEqual;
    Greater;
    Always;
}

class TextureHandle {
    private static var NEXT_TEX_ID:Int = 1;

    public var id(default, null):Int;
    public var width:Int;
    public var height:Int;
    public var bytes:Null<Bytes>;
    public var solidColor:Int;
    public var dirty:Bool = true;
    public var isCyberGrid:Bool = false;

    public function new(width:Int, height:Int, ?bytes:Bytes, solidColor:Int = 0xFFFFFFFF) {
        this.id = NEXT_TEX_ID++;
        this.width = width > 0 ? width : 1;
        this.height = height > 0 ? height : 1;
        this.bytes = bytes;
        this.solidColor = solidColor;
    }

    public static function fromColor(color:Int, alpha:Float = 1.0):TextureHandle {
        var r = (color >> 16) & 0xFF;
        var g = (color >> 8) & 0xFF;
        var b = color & 0xFF;
        var a = Math.round((alpha < 0 ? 0 : (alpha > 1 ? 1 : alpha)) * 255.0);
        var bytes = Bytes.alloc(4);
        bytes.set(0, r);
        bytes.set(1, g);
        bytes.set(2, b);
        bytes.set(3, a);
        return new TextureHandle(1, 1, bytes, (a << 24) | (color & 0xFFFFFF));
    }

    public static function fromRGBA(width:Int, height:Int, rgbaBytes:Bytes):TextureHandle {
        return new TextureHandle(width, height, rgbaBytes, 0xFFFFFFFF);
    }

    public function dispose():Void {
        bytes = null;
        dirty = false;
    }
}

class MaterialDesc {
    public var color:Vec3;
    public var texture:Null<TextureHandle> = null;
    public var emissive:Float = 0.0;
    public var roughness:Float = 0.45;
    public var gridScale:Float = 0.0;
    public var flags:Float = 0.0;
    public var shadows:Bool = true;
    public var culling:CullModeDesc = CullModeDesc.Back;
    public var depthWrite:Bool = true;
    public var depthTest:DepthCompareDesc = DepthCompareDesc.Less;
    public var isSkybox:Bool = false;
    public var shaders:Array<Dynamic>;

    public var mainPass(get, never):MaterialDesc;
    inline function get_mainPass():MaterialDesc return this;

    public function new() {
        color = new Vec3(1.0, 1.0, 1.0, 1.0);
        shaders = [];
    }

    public function addShader(shader:Dynamic):Void {
        if (shader != null) shaders.push(shader);
    }
}

/**
 * Hierarchical 3D transform node replacing `h3d.scene.Object`.
 */
class Object3D {
    public var name:String = "";
    public var x:Float = 0.0;
    public var y:Float = 0.0;
    public var z:Float = 0.0;
    public var scaleX:Float = 1.0;
    public var scaleY:Float = 1.0;
    public var scaleZ:Float = 1.0;

    public var qx:Float = 0.0;
    public var qy:Float = 0.0;
    public var qz:Float = 0.0;
    public var qw:Float = 1.0;

    public var visible:Bool = true;
    public var parent:Null<Object3D> = null;
    public var children:Array<Object3D>;
    public var localMatrix:Mat4;
    public var worldMatrix:Mat4;

    public var numChildren(get, never):Int;
    inline function get_numChildren():Int return children.length;

    public function new(?parent:Object3D) {
        children = [];
        localMatrix = new Mat4();
        worldMatrix = new Mat4();
        if (parent != null) {
            parent.addChild(this);
        }
    }

    public function addChild(child:Object3D):Void {
        if (child == null || child == this) return;
        if (child.parent != null && child.parent != this) {
            child.parent.removeChild(child);
        }
        if (child.parent != this) {
            child.parent = this;
            children.push(child);
        }
    }

    public function removeChild(child:Object3D):Void {
        if (child == null) return;
        if (children.remove(child)) {
            if (child.parent == this) child.parent = null;
        }
    }

    public function remove():Void {
        if (parent != null) {
            parent.removeChild(this);
        }
    }

    public function removeChildren():Void {
        for (c in children) {
            c.parent = null;
        }
        children.resize(0);
    }

    public inline function setPosition(px:Float, py:Float, pz:Float):Void {
        x = px;
        y = py;
        z = pz;
    }

    public inline function setScale(s:Float):Void {
        scaleX = s;
        scaleY = s;
        scaleZ = s;
    }

    /**
     * Sets Euler rotation matching Heaps extrinsic XYZ (`Rz(rz) * Ry(ry) * Rx(rx)`).
     */
    public function setRotation(rx:Float, ry:Float, rz:Float):Void {
        var hx = rx * 0.5;
        var hy = ry * 0.5;
        var hz = rz * 0.5;
        var sxR = Math.sin(hx), cxR = Math.cos(hx);
        var syR = Math.sin(hy), cyR = Math.cos(hy);
        var szR = Math.sin(hz), czR = Math.cos(hz);

        qx = sxR * cyR * czR - cxR * syR * szR;
        qy = cxR * syR * czR + sxR * cyR * szR;
        qz = cxR * cyR * szR - sxR * syR * czR;
        qw = cxR * cyR * czR + sxR * syR * szR;
    }

    /**
     * Composes an additional parent-frame rotation `dQ = Rz(rz) * Ry(ry) * Rx(rx)`
     * after the current rotation (`q = dQ * q`).
     */
    public function rotate(rx:Float, ry:Float, rz:Float):Void {
        var hx = rx * 0.5;
        var hy = ry * 0.5;
        var hz = rz * 0.5;
        var sxR = Math.sin(hx), cxR = Math.cos(hx);
        var syR = Math.sin(hy), cyR = Math.cos(hy);
        var szR = Math.sin(hz), czR = Math.cos(hz);

        var dx = sxR * cyR * czR - cxR * syR * szR;
        var dy = cxR * syR * czR + sxR * cyR * szR;
        var dz = cxR * cyR * szR - sxR * syR * czR;
        var dw = cxR * cyR * czR + sxR * syR * szR;

        // Column-vector compose: dQ * q
        var nqx = dw * qx + dx * qw + dy * qz - dz * qy;
        var nqy = dw * qy - dx * qz + dy * qw + dz * qx;
        var nqz = dw * qz + dx * qy - dy * qx + dz * qw;
        var nqw = dw * qw - dx * qx - dy * qy - dz * qz;

        var lenSq = nqx * nqx + nqy * nqy + nqz * nqz + nqw * nqw;
        if (lenSq > 1e-12) {
            var inv = 1.0 / Math.sqrt(lenSq);
            qx = nqx * inv;
            qy = nqy * inv;
            qz = nqz * inv;
            qw = nqw * inv;
        }
    }

    public function updateLocalMatrix():Mat4 {
        localMatrix.composeFromQuat(x, y, z, qx, qy, qz, qw, scaleX, scaleY, scaleZ);
        return localMatrix;
    }

    public function updateWorldTransform(?parentWorld:Mat4):Void {
        updateLocalMatrix();
        if (parentWorld != null) {
            worldMatrix.multiply(parentWorld, localMatrix);
        } else {
            worldMatrix.load(localMatrix);
        }
        for (child in children) {
            child.updateWorldTransform(worldMatrix);
        }
    }

    private function computeChainMatrix():Mat4 {
        if (parent == null) {
            updateLocalMatrix();
            worldMatrix.load(localMatrix);
            return worldMatrix;
        }
        var pm = parent.computeChainMatrix();
        updateLocalMatrix();
        worldMatrix.multiply(pm, localMatrix);
        return worldMatrix;
    }

    public function getAbsPos():Vec3 {
        var m = computeChainMatrix().m;
        return new Vec3(m[12], m[13], m[14], 1.0);
    }

    public function localToGlobal(v:Vec3):Vec3 {
        var m = computeChainMatrix();
        return v.transformed(m);
    }
}

class MeshNode extends Object3D {
    public var primitive:PrimitiveDesc;
    public var material:MaterialDesc;
    public var prevWorldMatrix:Mat4;
    public var hasPrevWorldMatrix:Bool = false;

    public function new(primitive:PrimitiveDesc, ?parent:Object3D) {
        super(parent);
        this.primitive = primitive;
        this.material = new MaterialDesc();
        this.prevWorldMatrix = new Mat4();
    }
}

class Camera3D {
    public var pos:Vec3;
    public var target:Vec3;
    public var up:Vec3;
    public var fovY:Float = 60.0;
    public var zNear:Float = 0.4;
    public var zFar:Float = 1200.0;
    public var screenRatio:Float = 16.0 / 9.0;

    public var viewMat:Mat4;
    public var projMat:Mat4;
    public var unjitteredProjMat:Mat4;
    public var viewProjMat:Mat4;
    public var unjitteredViewProjMat:Mat4;
    public var prevViewProjMat:Mat4;
    public var prevCamPos:Vec3;
    public var hasPrevFrame:Bool = false;
    public var jitterNdcX:Float = 0.0;
    public var jitterNdcY:Float = 0.0;

    public function new() {
        pos = new Vec3(0.0, -10.0, 4.0, 1.0);
        target = new Vec3(0.0, 0.0, 1.0, 1.0);
        up = new Vec3(0.0, 0.0, 1.0, 0.0);
        viewMat = new Mat4();
        projMat = new Mat4();
        unjitteredProjMat = new Mat4();
        viewProjMat = new Mat4();
        unjitteredViewProjMat = new Mat4();
        prevViewProjMat = new Mat4();
        prevCamPos = new Vec3(0.0, -10.0, 4.0, 1.0);
    }

    public function updateMatrices(?aspect:Float, jitterX:Float = 0.0, jitterY:Float = 0.0):Void {
        if (aspect != null && aspect > 1e-4) {
            screenRatio = aspect;
        }
        jitterNdcX = jitterX;
        jitterNdcY = jitterY;
        viewMat.lookAtZUp(pos, target, up);
        unjitteredProjMat.perspectiveWebGPU(fovY, screenRatio, zNear, zFar);
        unjitteredViewProjMat.multiply(unjitteredProjMat, viewMat);

        projMat.load(unjitteredProjMat);
        // Column-major WebGPU projection sets m[11] = -1 (clip.w = -viewZ); negating m[8]/m[9] shifts NDC by (+jitterX, +jitterY)
        projMat.m[8] = -jitterX;
        projMat.m[9] = -jitterY;
        viewProjMat.multiply(projMat, viewMat);
    }
}

class DirLightNode extends Object3D {
    public var direction:Vec3;
    public var color:Vec3;
    public var enableSpecular:Bool = true;

    public function new(dir:Vec3, ?parent:Object3D) {
        super(parent);
        direction = dir != null ? dir.normalized() : new Vec3(0.5, 0.3, -0.8).normalized();
        color = new Vec3(1.0, 1.0, 1.0, 1.0);
    }

    public function setDirection(v:Vec3):Void {
        direction.load(v);
        direction.normalize();
    }
}

class LightSystemDesc {
    public var ambientLight:Vec3;

    public function new() {
        ambientLight = new Vec3(0.35, 0.38, 0.45, 1.0);
    }
}

class SceneRendererDesc {
    public var passes:Array<Dynamic>;
    public function new() {
        passes = [];
    }
    public function getPass<T>(cl:Class<T>):Null<T> {
        for (p in passes) {
            if (Std.isOfType(p, cl)) return cast p;
        }
        return null;
    }
}

class EngineStub {
    public static var current:EngineStub = new EngineStub();

    public var width:Int = 1280;
    public var height:Int = 720;
    public var fps:Float = 60.0;
    public var backgroundColor:Int = 0x0A0E17;

    public function new() {}

    public static function getCurrent():EngineStub {
        return current;
    }

    public function resize(w:Int, h:Int):Void {
        if (w > 0) width = w;
        if (h > 0) height = h;
    }
}

class Scene3D extends Object3D {
    public var camera:Camera3D;
    public var lightSystem:LightSystemDesc;
    public var renderer:SceneRendererDesc;
    public var dirLights:Array<DirLightNode>;

    public function new() {
        super(null);
        camera = new Camera3D();
        lightSystem = new LightSystemDesc();
        renderer = new SceneRendererDesc();
        dirLights = [];
    }

    override public function addChild(child:Object3D):Void {
        super.addChild(child);
        if (Std.isOfType(child, DirLightNode)) {
            var dl:DirLightNode = cast child;
            if (dirLights.indexOf(dl) == -1) dirLights.push(dl);
        }
    }

    override public function removeChild(child:Object3D):Void {
        super.removeChild(child);
        if (Std.isOfType(child, DirLightNode)) {
            var dl:DirLightNode = cast child;
            dirLights.remove(dl);
        }
    }

    public function dispose():Void {
        removeChildren();
        dirLights.resize(0);
    }
}
