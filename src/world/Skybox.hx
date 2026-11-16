package world;

import config.WorldConfig;
import h3d.scene.Object;
import h3d.scene.Mesh;
import h3d.prim.Sphere;
import h3d.Vector;
import hxsl.Shader;

/**
 * Procedural atmospheric gradient sky shader.
 * Blends between deep zenith blue, bright cyan-blue horizon, and nadir ground haze.
 */
class SkyGradientShader extends Shader {
    static var SRC = {
        /** Sky zenith color at highest vertical elevation. */
        @param var topColor : Vec3;

        /** Atmospheric haze color along horizontal horizon line. */
        @param var horizonColor : Vec3;

        /** Foundation color below horizon level. */
        @param var groundColor : Vec3;

        @input var input : {
            var position : Vec3;
        };
        @var var skyDir : Vec3;
        var pixelColor : Vec4;

        function vertex() {
            skyDir = normalize(input.position);
        }

        function fragment() {
            var h = skyDir.z; // Vertical elevation (+Z is sky in our coordinate system)
            var col : Vec3;
            if (h > 0.0) {
                // Sky gradient: smooth power curve from atmospheric horizon to deep zenith
                var t = pow(h, 0.45);
                col = mix(horizonColor, topColor, t);
            } else {
                // Ground transition: rapid falloff below horizon
                var t = clamp(-h * 5.0, 0.0, 1.0);
                col = mix(horizonColor, groundColor, t);
            }
            pixelColor = vec4(col, 1.0);
        }
    };

    /**
     * Constructs and initializes the sky gradient shader with configurable palette.
     *
     * @param {Int} [topHex=0x1052B8] Zenith sky color.
     * @param {Int} [horizonHex=0x7AC2F2] Horizon atmosphere blend color.
     * @param {Int} [groundHex=0x141A24] Lower hemisphere nadir fill color.
     */
    public function new(topHex:Int = 0x1052B8, horizonHex:Int = 0x7AC2F2, groundHex:Int = 0x141A24) {
        super();
        setHexColor(topColor, topHex);
        setHexColor(horizonColor, horizonHex);
        setHexColor(groundColor, groundHex);
    }

    /** Converts a 24-bit RGB hex integer into normalized shader Vec3 channels. */
    private static function setHexColor(target:h3d.Vector, hex:Int):Void {
        target.set(
            ((hex >> 16) & 0xFF) / 255.0,
            ((hex >> 8) & 0xFF) / 255.0,
            (hex & 0xFF) / 255.0
        );
    }
}

/**
 * Procedural panoramic skybox sphere encompassing the 3D scene.
 * Translates dynamically with the active camera to project an infinite atmospheric horizon.
 *
 * @class Skybox
 * @module world/Skybox
 */
class Skybox extends Object {
    /** High-density inverted celestial dome mesh. */
    public var skyMesh:Mesh;

    /** Active atmospheric gradient shader instance. */
    public var skyShader:SkyGradientShader;

    /** Active skybox configuration profile. */
    public var config:config.WorldConfig.SkyboxConfig;

    /**
     * Constructs the procedural skybox from optional configuration settings.
     *
     * @param {Null<Object>} [parent] Optional parent 3D scene graph node.
     * @param {Null<config.WorldConfig.SkyboxConfig>} [config] Optional geometry & color palette config.
     */
    public function new(?parent:Object, ?config:config.WorldConfig.SkyboxConfig) {
        super(parent);
        this.config = config != null ? config : WorldConfig.getDefaultSkybox();

        var spherePrim = new Sphere(this.config.radius, this.config.segments, 24);
        spherePrim.addNormals();

        skyMesh = new Mesh(spherePrim, this);
        skyMesh.material.mainPass.culling = None;
        skyMesh.material.shadows = false;
        skyMesh.material.mainPass.depthWrite = false;
        skyMesh.material.mainPass.depthTest = LessEqual;

        skyShader = new SkyGradientShader(this.config.topColor, this.config.horizonColor);
        skyMesh.material.mainPass.addShader(skyShader);
    }

    /**
     * Synchronizes skybox center position with the active camera eye point.
     *
     * @param {Vector} camPos World coordinate position of the active scene camera.
     * @returns {Void}
     */
    public function syncCamera(camPos:Vector):Void {
        if (camPos == null) return;
        this.x = camPos.x;
        this.y = camPos.y;
        this.z = camPos.z;
    }
}

