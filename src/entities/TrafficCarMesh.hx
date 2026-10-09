package entities;

import h3d.scene.Object;
import h3d.scene.Mesh;
import h3d.prim.Cube;

/**
 * Procedural 3D composite mesh representation of civilian traffic vehicles.
 * Generates chassis, tinted cabin glass, illuminated front headlights, and red taillights.
 */
class TrafficCarMesh extends Object {
    /** Main chassis body mesh rendered with assigned traffic paint color. */
    public var body:Mesh;

    /** Passenger cabin canopy mesh. */
    public var cabin:Mesh;

    /** Front bumper headlight illumination strip mesh. */
    public var headlights:Mesh;

    /** Rear bumper taillight strip mesh. */
    public var taillights:Mesh;

    /**
     * Constructs a civilian traffic vehicle mesh with the specified body color.
     *
     * @param colorHex Hexadecimal color integer applied to the body material.
     * @param parent Optional parent 3D scene graph node.
     */
    public function new(colorHex:Int, ?parent:Object) {
        super(parent);

        // 1. Traffic Vehicle Lower Body Chassis (1.8m width, 4.0m length, 0.55m height)
        var bodyPrim = new Cube(1.8, 4.0, 0.55, true);
        bodyPrim.unindex();
        bodyPrim.addNormals();
        body = new Mesh(bodyPrim, this);
        body.material.color.setColor(colorHex);
        body.z = 0.38;

        // 2. Cabin Canopy (1.4m width, 2.0m length, 0.45m height)
        var cabinPrim = new Cube(1.4, 2.0, 0.45, true);
        cabinPrim.unindex();
        cabinPrim.addNormals();
        cabin = new Mesh(cabinPrim, this);
        cabin.material.color.setColor(0x15181C); // Dark tinted window glass
        cabin.y = -0.3;
        cabin.z = 0.85;

        // 3. Front Headlights (+Y forward facing direction)
        var headPrim = new Cube(1.5, 0.15, 0.18, true);
        headPrim.unindex();
        headPrim.addNormals();
        headlights = new Mesh(headPrim, this);
        headlights.material.color.setColor(0xFFF2AA); // Warm halogen glow
        headlights.y = 2.0;
        headlights.z = 0.42;

        // 4. Rear Taillights (-Y rear facing direction)
        var tailPrim = new Cube(1.5, 0.15, 0.18, true);
        tailPrim.unindex();
        tailPrim.addNormals();
        taillights = new Mesh(tailPrim, this);
        taillights.material.color.setColor(0xFF1100); // Vivid brake red
        taillights.y = -2.0;
        tailPrim.unindex();
        taillights.z = 0.42;
    }
}