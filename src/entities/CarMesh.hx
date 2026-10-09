package entities;

import h3d.scene.Object;
import h3d.scene.Mesh;
import h3d.prim.Cube;
import h3d.prim.Cylinder;
import h3d.prim.Disc;

/**
 * Procedural 3D composite mesh representation of the player race vehicle.
 * Constructed with higher polygon density and layered geometric volumes:
 * aerodynamic lower chassis, sculpted hood, front splitter, side skirts,
 * rear diffuser, cabin canopy with windshield taper, aerodynamic wing spoiler
 * with support stanchions, quad exhaust tips, LED headlights/taillights,
 * and high-resolution wheel assemblies with outer rim caps.
 */
class CarMesh extends Object {
    /** Primary lower chassis body mesh. */
    public var bodyMesh:Mesh;

    /** Sculpted front nose and hood wedge mesh. */
    public var hoodMesh:Mesh;

    /** Upper cockpit canopy and tinted cabin greenhouse mesh. */
    public var cabinMesh:Mesh;

    /** Front aerodynamic ground-effect splitter mesh. */
    public var frontSplitter:Mesh;

    /** Rear aerodynamic diffuser undertray mesh. */
    public var rearDiffuser:Mesh;

    /** Left and right side skirt aero ground-effect blades. */
    public var leftSkirt:Mesh;
    public var rightSkirt:Mesh;

    /** Rear downforce wing spoiler blade mesh. */
    public var spoilerMesh:Mesh;

    /** Left and right vertical stanchions supporting the wing. */
    public var leftStanchion:Mesh;
    public var rightStanchion:Mesh;

    /** Front dual LED headlight cluster mesh. */
    public var headlights:Mesh;

    /** Rear full-width neon brake light bar mesh. */
    public var taillights:Mesh;

    /** Quad performance exhaust tips. */
    public var exhausts:Array<Mesh> = [];

    /** Array of wheel cylinder meshes representing front and rear wheels. */
    public var wheels:Array<Mesh> = [];

    /** Array of wheel outer rim face caps. */
    public var rimCaps:Array<Mesh> = [];

    /**
     * Constructs and attaches the composite vehicle hierarchy to the scene graph.
     *
     * @param parent Optional parent 3D scene graph node.
     */
    public function new(?parent:Object) {
        super(parent);

        // Sports car body styling colors
        var colorBodyPaint = 0xE64A19;   // Radiant sports orange
        var colorCarbonAero = 0x111317;  // Carbon fiber dark charcoal
        var colorDarkGlass = 0x14181F;   // Tinted privacy glass
        var colorRimAlloy = 0x8C9AA8;    // Machined silver alloy
        var colorTireRubber = 0x1E2024;  // Deep vulcanized rubber
        var colorLedHeadlight = 0xE6F8FF;// Cold white xenon LED
        var colorLedTaillight = 0xFF1430;// Vivid red neon brake light

        // 1. Main Mid-Section Chassis (Width: 1.84m, Length: 2.8m, Height: 0.44m)
        var bodyPrim = new Cube(1.84, 2.8, 0.44, true);
        bodyPrim.unindex();
        bodyPrim.addNormals();
        bodyMesh = new Mesh(bodyPrim, this);
        bodyMesh.material.color.setColor(colorBodyPaint);
        bodyMesh.y = -0.15;
        bodyMesh.z = 0.42;

        // 2. Sculpted Front Nose & Hood (Width: 1.76m, Length: 1.55m, Height: 0.34m)
        var hoodPrim = new Cube(1.76, 1.55, 0.34, true);
        hoodPrim.unindex();
        hoodPrim.addNormals();
        hoodMesh = new Mesh(hoodPrim, this);
        hoodMesh.material.color.setColor(colorBodyPaint);
        hoodMesh.y = 1.62;
        hoodMesh.z = 0.35;

        // 3. Front Ground-Effect Splitter (Width: 1.88m, Length: 0.45m, Height: 0.08m)
        var splitterPrim = new Cube(1.88, 0.45, 0.08, true);
        splitterPrim.unindex();
        splitterPrim.addNormals();
        frontSplitter = new Mesh(splitterPrim, this);
        frontSplitter.material.color.setColor(colorCarbonAero);
        frontSplitter.y = 2.42;
        frontSplitter.z = 0.16;

        // 4. Side Aero Skirts (Left & Right)
        var skirtPrimL = new Cube(0.12, 2.5, 0.14, true);
        skirtPrimL.unindex();
        skirtPrimL.addNormals();
        leftSkirt = new Mesh(skirtPrimL, this);
        leftSkirt.material.color.setColor(colorCarbonAero);
        leftSkirt.x = -0.96;
        leftSkirt.y = -0.05;
        leftSkirt.z = 0.22;

        var skirtPrimR = new Cube(0.12, 2.5, 0.14, true);
        skirtPrimR.unindex();
        skirtPrimR.addNormals();
        rightSkirt = new Mesh(skirtPrimR, this);
        rightSkirt.material.color.setColor(colorCarbonAero);
        rightSkirt.x = 0.96;
        rightSkirt.y = -0.05;
        rightSkirt.z = 0.22;

        // 5. Rear Aerodynamic Diffuser Undertray (Width: 1.82m, Length: 0.55m, Height: 0.18m)
        var diffuserPrim = new Cube(1.82, 0.55, 0.18, true);
        diffuserPrim.unindex();
        diffuserPrim.addNormals();
        rearDiffuser = new Mesh(diffuserPrim, this);
        rearDiffuser.material.color.setColor(colorCarbonAero);
        rearDiffuser.y = -1.82;
        rearDiffuser.z = 0.28;

        // 6. Cockpit Canopy & Greenhouse (Width: 1.34m, Length: 2.15m, Height: 0.46m)
        var cabinPrim = new Cube(1.34, 2.15, 0.46, true);
        cabinPrim.unindex();
        cabinPrim.addNormals();
        cabinMesh = new Mesh(cabinPrim, this);
        cabinMesh.material.color.setColor(colorDarkGlass);
        cabinMesh.y = -0.32;
        cabinMesh.z = 0.82;

        // 7. Aerodynamic Rear Wing Blade (Width: 1.94m, Length: 0.38m, Height: 0.08m)
        var spoilerPrim = new Cube(1.94, 0.38, 0.08, true);
        spoilerPrim.unindex();
        spoilerPrim.addNormals();
        spoilerMesh = new Mesh(spoilerPrim, this);
        spoilerMesh.material.color.setColor(colorCarbonAero);
        spoilerMesh.y = -1.88;
        spoilerMesh.z = 1.12;

        // Wing Support Stanchions (Pillars)
        var stanchionPrimL = new Cube(0.06, 0.18, 0.38, true);
        stanchionPrimL.unindex();
        stanchionPrimL.addNormals();
        leftStanchion = new Mesh(stanchionPrimL, this);
        leftStanchion.material.color.setColor(colorCarbonAero);
        leftStanchion.x = -0.55;
        leftStanchion.y = -1.82;
        leftStanchion.z = 0.85;

        var stanchionPrimR = new Cube(0.06, 0.18, 0.38, true);
        stanchionPrimR.unindex();
        stanchionPrimR.addNormals();
        rightStanchion = new Mesh(stanchionPrimR, this);
        rightStanchion.material.color.setColor(colorCarbonAero);
        rightStanchion.x = 0.55;
        rightStanchion.y = -1.82;
        rightStanchion.z = 0.85;

        // 8. Dual Front LED Headlight Strips (Width: 1.58m, Length: 0.12m, Height: 0.12m)
        var headPrim = new Cube(1.58, 0.12, 0.12, true);
        headPrim.unindex();
        headPrim.addNormals();
        headlights = new Mesh(headPrim, this);
        headlights.material.color.setColor(colorLedHeadlight);
        headlights.y = 2.38;
        headlights.z = 0.42;

        // 9. Full-Width Rear Taillight Strip (Width: 1.64m, Length: 0.12m, Height: 0.10m)
        var tailPrim = new Cube(1.64, 0.12, 0.10, true);
        tailPrim.unindex();
        tailPrim.addNormals();
        taillights = new Mesh(tailPrim, this);
        taillights.material.color.setColor(colorLedTaillight);
        taillights.y = -1.88;
        taillights.z = 0.54;

        // 10. Quad Performance Exhaust Tips (Twin double barrels on rear bumper)
        var exhaustOffsets = [-0.58, -0.42, 0.42, 0.58];
        for (exX in exhaustOffsets) {
            var exPrim = new Cylinder(16, 0.065, 0.22, true);
            exPrim.addNormals();
            var exMesh = new Mesh(exPrim, this);
            exMesh.material.color.setColor(colorRimAlloy);
            exMesh.rotate(1.5707963, 0, 0); // Point exhaust outwards toward -Y
            exMesh.x = exX;
            exMesh.y = -1.98;
            exMesh.z = 0.26;
            exhausts.push(exMesh);
        }

        // 11. High-Polygon Wheels with Outer Rim Face Caps
        var wheelOffsets = [
            { x: -0.98, y:  1.35, isLeft: true  }, // Front Left
            { x:  0.98, y:  1.35, isLeft: false }, // Front Right
            { x: -0.98, y: -1.35, isLeft: true  }, // Rear Left
            { x:  0.98, y: -1.35, isLeft: false }  // Rear Right
        ];

        var tireRadius = 0.36;
        var tireWidth = 0.30;
        var cylinderSegments = 32; // Higher polygon count for smooth circular curvature

        for (offset in wheelOffsets) {
            // High-density cylinder for tire rubber: centered = true along Z-axis (height: tireWidth)
            var wheelPrim = new Cylinder(cylinderSegments, tireRadius, tireWidth, true);
            wheelPrim.addNormals();
            var wheel = new Mesh(wheelPrim, this);
            wheel.material.color.setColor(colorTireRubber);

            // Orient cylinder axis horizontally: rotate 90 deg around Y so cylinder height aligns with X-axis
            wheel.rotate(0, 1.5707963, 0);
            wheel.x = offset.x;
            wheel.y = offset.y;
            wheel.z = tireRadius;
            wheels.push(wheel);

            // Outer alloy rim face cap
            var rimDisc = new Disc(tireRadius * 0.72, 24);
            rimDisc.addNormals();
            var rimMesh = new Mesh(rimDisc, wheel);
            rimMesh.material.color.setColor(colorRimAlloy);
            // In cylinder local space (where height is along Z), cap is placed at the outer end
            rimMesh.z = offset.isLeft ? -tireWidth * 0.51 : tireWidth * 0.51;
            rimCaps.push(rimMesh);
        }
    }
}