package world;

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

        var pixelColor : Vec4;
        var transformedPosition : Vec3;

        function fragment() {
            var dir = normalize(transformedPosition);
            var h = dir.z; // Vertical elevation (+Z is sky in our coordinate system)
            var col : Vec3;
            if (h > 0.0) {
                // Sky gradient: smooth power curve from atmospheric horizon to deep zenith
                var t = pow(h, 0.55);
                col = mix(horizonColor, topColor, t);
            } else {
                // Ground transition: rapid falloff below horizon
                var t = clamp(-h * 4.0, 0.0, 1.0);
                col = mix(horizonColor, groundColor, t);
            }
            pixelColor = vec4(col, 1.0);
        }
    };

    /**
     * Constructs and initializes the gradient blue sky shader.
     */
    public function new() {
        super();
        // Radiant arcade sky: deep azure zenith, bright celestial blue horizon, dark dusk nadir
        topColor.set(0.06, 0.32, 0.72);      // #1052B8 Deep radiant blue
        horizonColor.set(0.48, 0.76, 0.95);  // #7AC2F2 Bright atmospheric cyan
        groundColor.set(0.08, 0.10, 0.14);   // #141A24 Deep asphalt ground tone
    }
}

/**
 * Procedural panoramic skybox sphere encompassing the 3D scene.
 * Translates dynamically with the active camera to project an infinite atmospheric horizon.
 */
class Skybox extends Object {
    /** High-density inverted celestial dome mesh. */
    public var skyMesh:Mesh;

    /** Active atmospheric gradient shader instance. */
    public var skyShader:SkyGradientShader;

    /**
     * Constructs the procedural gradient blue skybox.
     *
     * @param parent Optional parent 3D scene graph node.
     */
    public function new(?parent:Object) {
        super(parent);

        // Geodesic celestial dome (radius: 950m, 32 longitude segments, 24 latitude segments)
        var spherePrim = new Sphere(950.0, 32, 24);
        spherePrim.addNormals();

        skyMesh = new Mesh(spherePrim, this);
        // Disable backface culling on main pass so interior of sphere is fully visible
        skyMesh.material.mainPass.culling = None;
        skyMesh.material.shadows = false;

        skyShader = new SkyGradientShader();
        skyMesh.material.mainPass.addShader(skyShader);
    }

    /**
     * Synchronizes skybox center position with the active camera eye point.
     * Keeps the celestial horizon stationary regardless of vehicle movement.
     *
     * @param camPos World coordinate position of the active scene camera.
     */
    public function syncCamera(camPos:Vector) {
        if (camPos == null) return;
        this.x = camPos.x;
        this.y = camPos.y;
        this.z = camPos.z;
    }
}

