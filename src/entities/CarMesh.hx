package entities;

import h3d.scene.Object;
import h3d.scene.Mesh;
import h3d.prim.Cube;
import h3d.prim.Cylinder;
import h3d.prim.Disc;
import physics.CarConfig;

/**
 * Procedural 3D composite mesh representation of the player race vehicle.
 *
 * @class CarMesh
 * @module entities/CarMesh
 */
class CarMesh extends Object {
    /** Tire rolling radius in meters shared with physics config. @default 0.36 */
    public static inline var TIRE_RADIUS:Float = CarConfig.TIRE_RADIUS;

    /** Tire tread width in meters shared with physics config. @default 0.30 */
    public static inline var TIRE_WIDTH:Float = CarConfig.TIRE_WIDTH;

    /** Overall vehicle chassis bounding width in meters. @default 1.88 */
    public static inline var CHASSIS_WIDTH:Float = CarConfig.CHASSIS_WIDTH;

    /** Overall vehicle chassis bounding length in meters. @default 4.30 */
    public static inline var CHASSIS_LENGTH:Float = CarConfig.CHASSIS_LENGTH;

    /** Overall vehicle chassis bounding height in meters. @default 0.44 */
    public static inline var CHASSIS_HEIGHT:Float = 0.44;

    /** Local chassis visual hub coordinates for [FL, FR, RL, RR]. */
    public static var WHEEL_OFFSETS(default, never):Array<{x:Float, y:Float, isLeft:Bool}> = [
        { x: -0.98, y:  1.35, isLeft: true  },
        { x:  0.98, y:  1.35, isLeft: false },
        { x: -0.98, y: -1.35, isLeft: true  },
        { x:  0.98, y: -1.35, isLeft: false }
    ];

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
        bodyMesh.y = 0.0;
        bodyMesh.z = 0.42;

        // 2. Sculpted Front Nose & Hood (Width: 1.76m, Length: 1.40m, Height: 0.34m)
        var hoodPrim = new Cube(1.76, 1.40, 0.34, true);
        hoodPrim.unindex();
        hoodPrim.addNormals();
        hoodMesh = new Mesh(hoodPrim, this);
        hoodMesh.material.color.setColor(colorBodyPaint);
        hoodMesh.y = 1.40;
        hoodMesh.z = 0.35;

        // 3. Front Ground-Effect Splitter (Width: 1.88m, Length: 0.45m, Height: 0.08m)
        var splitterPrim = new Cube(1.88, 0.45, 0.08, true);
        splitterPrim.unindex();
        splitterPrim.addNormals();
        frontSplitter = new Mesh(splitterPrim, this);
        frontSplitter.material.color.setColor(colorCarbonAero);
        frontSplitter.y = 1.98;
        frontSplitter.z = 0.16;

        // 4. Side Aero Skirts (Left & Right)
        var skirtPrimL = new Cube(0.12, 2.3, 0.14, true);
        skirtPrimL.unindex();
        skirtPrimL.addNormals();
        leftSkirt = new Mesh(skirtPrimL, this);
        leftSkirt.material.color.setColor(colorCarbonAero);
        leftSkirt.x = -0.96;
        leftSkirt.y = 0.0;
        leftSkirt.z = 0.22;

        var skirtPrimR = new Cube(0.12, 2.3, 0.14, true);
        skirtPrimR.unindex();
        skirtPrimR.addNormals();
        rightSkirt = new Mesh(skirtPrimR, this);
        rightSkirt.material.color.setColor(colorCarbonAero);
        rightSkirt.x = 0.96;
        rightSkirt.y = 0.0;
        rightSkirt.z = 0.22;

        // 5. Rear Aerodynamic Diffuser Undertray (Width: 1.82m, Length: 0.55m, Height: 0.18m)
        var diffuserPrim = new Cube(1.82, 0.55, 0.18, true);
        diffuserPrim.unindex();
        diffuserPrim.addNormals();
        rearDiffuser = new Mesh(diffuserPrim, this);
        rearDiffuser.material.color.setColor(colorCarbonAero);
        rearDiffuser.y = -1.92;
        rearDiffuser.z = 0.28;

        // 6. Cockpit Canopy & Greenhouse (Width: 1.34m, Length: 2.15m, Height: 0.46m)
        var cabinPrim = new Cube(1.34, 2.15, 0.46, true);
        cabinPrim.unindex();
        cabinPrim.addNormals();
        cabinMesh = new Mesh(cabinPrim, this);
        cabinMesh.material.color.setColor(colorDarkGlass);
        cabinMesh.y = -0.22;
        cabinMesh.z = 0.82;

        // 7. Aerodynamic Rear Wing Blade (Width: 1.94m, Length: 0.38m, Height: 0.08m)
        var spoilerPrim = new Cube(1.94, 0.38, 0.08, true);
        spoilerPrim.unindex();
        spoilerPrim.addNormals();
        spoilerMesh = new Mesh(spoilerPrim, this);
        spoilerMesh.material.color.setColor(colorCarbonAero);
        spoilerMesh.y = -1.98;
        spoilerMesh.z = 1.12;

        // Wing Support Stanchions (Pillars)
        var stanchionPrimL = new Cube(0.06, 0.18, 0.38, true);
        stanchionPrimL.unindex();
        stanchionPrimL.addNormals();
        leftStanchion = new Mesh(stanchionPrimL, this);
        leftStanchion.material.color.setColor(colorCarbonAero);
        leftStanchion.x = -0.55;
        leftStanchion.y = -1.92;
        leftStanchion.z = 0.85;

        var stanchionPrimR = new Cube(0.06, 0.18, 0.38, true);
        stanchionPrimR.unindex();
        stanchionPrimR.addNormals();
        rightStanchion = new Mesh(stanchionPrimR, this);
        rightStanchion.material.color.setColor(colorCarbonAero);
        rightStanchion.x = 0.55;
        rightStanchion.y = -1.92;
        rightStanchion.z = 0.85;

        // 8. Dual Front LED Headlight Strips (Width: 1.58m, Length: 0.12m, Height: 0.12m)
        var headPrim = new Cube(1.58, 0.12, 0.12, true);
        headPrim.unindex();
        headPrim.addNormals();
        headlights = new Mesh(headPrim, this);
        headlights.material.color.setColor(colorLedHeadlight);
        headlights.y = 2.12;
        headlights.z = 0.42;

        // 9. Full-Width Rear Taillight Strip (Width: 1.64m, Length: 0.12m, Height: 0.10m)
        var tailPrim = new Cube(1.64, 0.12, 0.10, true);
        tailPrim.unindex();
        tailPrim.addNormals();
        taillights = new Mesh(tailPrim, this);
        taillights.material.color.setColor(colorLedTaillight);
        taillights.y = -1.98;
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
            exMesh.y = -2.08;
            exMesh.z = 0.26;
            exhausts.push(exMesh);
        }

        // 11. High-Polygon Wheels with Solid Tire Sidewalls & 5-Spoke Machined Alloy Rims
        var cylinderSegments = 32; // Higher polygon count for smooth circular curvature

        for (offset in WHEEL_OFFSETS) {
            // High-density cylinder for tire rubber tread: centered = true along Z-axis (height: TIRE_WIDTH)
            var wheelPrim = new Cylinder(cylinderSegments, TIRE_RADIUS, TIRE_WIDTH, true);
            wheelPrim.addNormals();
            var wheel = new Mesh(wheelPrim, this);
            wheel.material.color.setColor(colorTireRubber);
            wheel.material.mainPass.culling = None;

            // Orient cylinder axis horizontally: rotate 90 deg around Y so cylinder height (+Z) aligns with +X axis
            wheel.rotate(0, 1.5707963, 0);
            wheel.x = offset.x;
            wheel.y = offset.y;
            wheel.z = TIRE_RADIUS;
            wheels.push(wheel);

            // Note: h3d.prim.Cylinder is open-ended (no end caps), while h3d.prim.Disc is a solid filled circle on the XY plane (+Z normal).
            // By pairing front-facing and flipped Discs (with culling = None), both Left (-X) and Right (+X) wheels have solid sidewalls & alloy rims!
            var outerSign = offset.isLeft ? -1.0 : 1.0;

            // 11a. Outer & Inner Tire Rubber Sidewall Discs (closes the open cylinder ends completely)
            var tireSidewallDisc = new Disc(TIRE_RADIUS, cylinderSegments);
            tireSidewallDisc.addNormals();
            var outerSidewall = new Mesh(tireSidewallDisc, wheel);
            outerSidewall.material.color.setColor(colorTireRubber);
            outerSidewall.material.mainPass.culling = None;
            if (offset.isLeft) outerSidewall.rotate(0, Math.PI, 0);
            outerSidewall.z = outerSign * (TIRE_WIDTH * 0.49);

            var innerSidewall = new Mesh(tireSidewallDisc, wheel);
            innerSidewall.material.color.setColor(colorTireRubber);
            innerSidewall.material.mainPass.culling = None;
            if (!offset.isLeft) innerSidewall.rotate(0, Math.PI, 0);
            innerSidewall.z = -outerSign * (TIRE_WIDTH * 0.49);

            // 11b. Outer Machined Silver Alloy Rim Face Disc (Left wheels at -Z = Left -X side; Right wheels at +Z = Right +X side)
            var rimDisc = new Disc(TIRE_RADIUS * 0.72, 24);
            rimDisc.addNormals();
            var rimMesh = new Mesh(rimDisc, wheel);
            rimMesh.material.color.setColor(colorRimAlloy);
            rimMesh.material.mainPass.culling = None;
            if (offset.isLeft) {
                rimMesh.rotate(0, Math.PI, 0); // Point disc normal outward toward -X (Left)
                rimMesh.z = -TIRE_WIDTH * 0.52;
            } else {
                rimMesh.z = TIRE_WIDTH * 0.52;  // Point disc normal outward toward +X (Right)
            }

            // 11c. Alloy Spoke Detail Bars on the outer rim face so wheel rolling is clearly visible
            var spokeBarPrim = new Cube(TIRE_RADIUS * 1.32, 0.055, 0.02, true);
            spokeBarPrim.unindex();
            spokeBarPrim.addNormals();
            var spokeBarA = new Mesh(spokeBarPrim, rimMesh);
            spokeBarA.material.color.setColor(colorCarbonAero);
            spokeBarA.z = 0.012;

            var spokeBarB = new Mesh(spokeBarPrim, rimMesh);
            spokeBarB.material.color.setColor(colorCarbonAero);
            spokeBarB.rotate(0, 0, 1.5707963);
            spokeBarB.z = 0.012;

            rimCaps.push(rimMesh);
        }
    }

    /**
     * Updates suspension travel, rolling spin angle, and steering angle for a specific wheel.
     *
     * @param index Wheel index (0=FL, 1=FR, 2=RL, 3=RR).
     * @param suspDeflection Compression displacement in meters relative to rest length.
     * @param spinAngle Longitudinal wheel roll angle in radians.
     * @param steerAngle Front wheel steering rack angle in radians (positive = right).
     */
    public function updateWheelTransform(index:Int, suspDeflection:Float, spinAngle:Float, steerAngle:Float = 0.0):Void {
        if (index < 0 || index >= wheels.length) return;
        var wheel = wheels[index];
        wheel.z = TIRE_RADIUS + (suspDeflection * 0.45);
        wheel.setRotation(0, 1.5707963, 0);
        wheel.rotate(-spinAngle, 0, 0);
        if (steerAngle != 0.0) {
            wheel.rotate(0, 0, steerAngle);
        }
    }
}