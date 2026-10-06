package entities;

import h3d.scene.Object;
import h3d.scene.Mesh;
import h3d.prim.Cube;

class TrafficCarMesh extends Object {
    public var body:Mesh;
    public var cabin:Mesh;
    public var headlights:Mesh;
    public var taillights:Mesh;

    public function new(colorHex:Int, ?parent:Object) {
        super(parent);

        var bodyPrim = new Cube(1.8, 4.0, 0.55, true);
        bodyPrim.unindex();
        bodyPrim.addNormals();
        body = new Mesh(bodyPrim, this);
        body.material.color.setColor(colorHex);
        body.z = 0.38;

        var cabinPrim = new Cube(1.4, 2.0, 0.45, true);
        cabinPrim.unindex();
        cabinPrim.addNormals();
        cabin = new Mesh(cabinPrim, this);
        cabin.material.color.setColor(0x15181C);
        cabin.y = -0.3;
        cabin.z = 0.85;

        // Front Headlights (+Y)
        var headPrim = new Cube(1.5, 0.15, 0.18, true);
        headPrim.unindex();
        headPrim.addNormals();
        headlights = new Mesh(headPrim, this);
        headlights.material.color.setColor(0xFFF2AA);
        headlights.y = 2.0;
        headlights.z = 0.42;

        // Rear Taillights (-Y)
        var tailPrim = new Cube(1.5, 0.15, 0.18, true);
        tailPrim.unindex();
        tailPrim.addNormals();
        taillights = new Mesh(tailPrim, this);
        taillights.material.color.setColor(0xFF1100);
        taillights.y = -2.0;
        taillights.z = 0.42;
    }
}