package world;

import config.WorldConfig;
import graphics.Primitives.Sphere;
import graphics.SceneGraph.CullModeDesc;
import graphics.SceneGraph.DepthCompareDesc;
import graphics.SceneGraph.MeshNode;
import graphics.SceneGraph.Object3D;

/**
 * Palette & atmospheric parameters for the WebGPU fullscreen `SkyShader`.
 */
class SkyGradientConfig {
    public var topHex:Int;
    public var horizonHex:Int;
    public var groundHex:Int;

    public function new(topHex:Int = 0x1052B8, horizonHex:Int = 0x7AC2F2, groundHex:Int = 0x141A24) {
        this.topHex = topHex;
        this.horizonHex = horizonHex;
        this.groundHex = groundHex;
    }
}

/**
 * Procedural atmospheric sky dome descriptor and scene node.
 * Rendered fullscreen via `SkyShader` in `WebGpuRenderer` with palette colors stored here.
 */
class Skybox extends Object3D {
    public var skyMesh:MeshNode;
    public var skyShader:SkyGradientConfig;
    public var config:SkyboxConfig;

    public function new(?parent:Object3D, ?skyConfig:SkyboxConfig) {
        super(parent);
        this.config = skyConfig != null ? skyConfig : WorldConfig.getDefaultSkybox();
        this.skyShader = new SkyGradientConfig(this.config.topColor, this.config.horizonColor, 0x141A24);

        var spherePrim = new Sphere(this.config.radius, this.config.segments, 24);
        skyMesh = new MeshNode(spherePrim, this);
        skyMesh.material.isSkybox = true;
        skyMesh.material.culling = CullModeDesc.None;
        skyMesh.material.shadows = false;
        skyMesh.material.depthWrite = false;
        skyMesh.material.depthTest = DepthCompareDesc.LessEqual;
    }

    /** Centers sky dome at the active camera position. */
    public inline function syncCamera(camPos:math.Vec3):Void {
        if (camPos != null) {
            setPosition(camPos.x, camPos.y, camPos.z);
        }
    }
}
