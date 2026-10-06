package entities;

import h3d.scene.Object;
import h3d.scene.Mesh;
import h3d.prim.Cube;
import h3d.prim.Cylinder;

class CarMesh extends Object {
    public var bodyMesh:Mesh;
    public var cabinMesh:Mesh;
    public var spoilerMesh:Mesh;
    public var wheels:Array<Mesh> = [];

    public function new(?parent:Object) {
        super(parent);

        // Lower Wedge Chassis
        var bodyPrim = new Cube(1.8, 4.2, 0.55, true);
        bodyPrim.unindex();
        bodyPrim.addNormals();
        bodyMesh = new Mesh(bodyPrim, this);
        bodyMesh.material.color.setColor(0xE64A19);
        bodyMesh.z = 0.45;

        // Cabin Greenhouse
        var cabinPrim = new Cube(1.3, 2.1, 0.5, true);
        cabinPrim.unindex();
        cabinPrim.addNormals();
        cabinMesh = new Mesh(cabinPrim, this);
        cabinMesh.material.color.setColor(0x181818);
        cabinMesh.y = -0.3;
        cabinMesh.z = 0.95;

        // Rear Wing
        var spoilerPrim = new Cube(1.9, 0.35, 0.08, true);
        spoilerPrim.unindex();
        spoilerPrim.addNormals();
        spoilerMesh = new Mesh(spoilerPrim, this);
        spoilerMesh.material.color.setColor(0x111111);
        spoilerMesh.y = -1.8;
        spoilerMesh.z = 1.05;

        // Wheels
        var wheelOffsets = [
            { x: -0.98, y:  1.35 },
            { x:  0.98, y:  1.35 },
            { x: -0.98, y: -1.35 },
            { x:  0.98, y: -1.35 }
        ];

        for (offset in wheelOffsets) {
            var wheelPrim = new Cylinder(16, 0.36, 0.28);
            wheelPrim.addNormals();
            var wheel = new Mesh(wheelPrim, this);
            wheel.material.color.setColor(0x222222);
            wheel.rotate(0, 1.5707963, 0);
            wheel.x = offset.x;
            wheel.y = offset.y;
            wheel.z = 0.36;
            wheels.push(wheel);
        }
    }
}