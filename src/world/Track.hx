package world;

import h3d.scene.Object;
import h3d.scene.Mesh;
import h3d.prim.Polygon;
import h3d.prim.Cube;
import h3d.col.Point;
import h3d.Vector;
import hxd.IndexBuffer;
import physics.SplineMath;

/**
 * Procedural circuit track builder and environment generator.
 * Generates continuous Catmull-Rom roadbed ribbon geometry, asphalt surface mesh,
 * continuous galvanized Armco guardrails, vertical steel support stanchions,
 * and background urban skyscraper geometry.
 */
class Track extends Object implements IGroundProvider {
    /** High-density discrete Catmull-Rom spline waypoints defining track centerline. */
    public var waypoints:Array<Vector> = [];

    /** Asphalt road surface polygon ribbon mesh. */
    public var roadMesh:Mesh;

    /** Gravel and concrete sub-base foundation ribbon mesh. */
    public var bedMesh:Mesh;

    /** Continuous left-hand side steel barrier ribbon mesh. */
    public var leftRailMesh:Mesh;

    /** Continuous right-hand side steel barrier ribbon mesh. */
    public var rightRailMesh:Mesh;

    /** Array of procedural highway street light meshes lining the circuit. */
    public var streetLights:Array<Mesh> = [];

    var scratchQuery:Vector = new Vector();
    var scratchFromCenter:Vector = new Vector();

    /** Total roadway width in meters across all four lanes. */
    public static inline var ROAD_WIDTH:Float = 20.0;

    /** Distance from track centerline to outer edge of asphalt. */
    public static inline var HALF_WIDTH:Float = 10.0;

    /** Additional gravel shoulder width extending past asphalt borders. */
    public static inline var BED_EXTRA_WIDTH:Float = 4.0;

    /** Vertical elevation offset preventing coplanar Z-fighting between asphalt and sub-base. */
    public static inline var ROAD_LIFT:Float = 0.06;

    /** Height of steel barrier guardrails above the asphalt plane in meters. */
    public static inline var RAIL_HEIGHT:Float = 0.65;

    /**
     * Constructs and synthesizes the procedural circuit world.
     *
     * @param parent Optional parent 3D scene graph node.
     */
    public function new(?parent:Object) {
        super(parent);
        buildCircuitWaypoints();
        buildRoadBed();
        buildRoadRibbon();
        buildContinuousGuardrails();
        buildStreetLights();
        buildCityscape();
    }

    /**
     * Interpolates control keypoints using cubic Catmull-Rom splines into dense waypoint arrays.
     */
    function buildCircuitWaypoints() {
        var rawNodes = [
            new Vector(0,    0,    0),
            new Vector(0,    85,   0),
            new Vector(30,   170,  1.5),
            new Vector(90,   240,  3.0),
            new Vector(170,  260,  3.0),
            new Vector(250,  215,  1.5),
            new Vector(280,  135,  0),
            new Vector(255,  45,  -1.0),
            new Vector(175, -25,  -1.0),
            new Vector(110,  10,   0),
            new Vector(60,  -40,   0),
            new Vector(10,  -60,   0)
        ];

        var segments = 16;
        var n = rawNodes.length;
        for (i in 0...n) {
            var p0 = rawNodes[(i - 1 + n) % n];
            var p1 = rawNodes[i];
            var p2 = rawNodes[(i + 1) % n];
            var p3 = rawNodes[(i + 2) % n];

            for (step in 0...segments) {
                var t = step / segments;
                var x = SplineMath.catmullRom(p0.x, p1.x, p2.x, p3.x, t);
                var y = SplineMath.catmullRom(p0.y, p1.y, p2.y, p3.y, t);
                var z = SplineMath.catmullRom(p0.z, p1.z, p2.z, p3.z, t);
                waypoints.push(new Vector(x, y, z));
            }
        }
    }

    /**
     * Generates the gravel sub-base shoulder foundation mesh underlying the roadway.
     */
    function buildRoadBed() {
        var count = waypoints.length;
        var pts:Array<Point> = [];
        var idxBuf = new IndexBuffer();
        var totalHalfW = HALF_WIDTH + BED_EXTRA_WIDTH;

        for (i in 0...count) {
            var curr = waypoints[i];
            var next = waypoints[(i + 1) % count];
            var prev = waypoints[(i - 1 + count) % count];

            var fwd = next.sub(prev);
            fwd.z = 0;
            fwd.normalize();

            var right = new Vector(-fwd.y, fwd.x, 0);
            var leftPos = curr.add(right.scaled(-totalHalfW));
            var rightPos = curr.add(right.scaled(totalHalfW));

            pts.push(new Point(leftPos.x, leftPos.y, leftPos.z - 0.3));
            pts.push(new Point(rightPos.x, rightPos.y, rightPos.z - 0.3));
        }

        for (i in 0...count) {
            var i0 = i * 2;
            var i1 = i0 + 1;
            var i2 = ((i + 1) % count) * 2;
            var i3 = i2 + 1;

            idxBuf.push(i0); idxBuf.push(i2); idxBuf.push(i1);
            idxBuf.push(i1); idxBuf.push(i2); idxBuf.push(i3);
        }

        var poly = new Polygon(pts, idxBuf);
        poly.addNormals();
        bedMesh = new Mesh(poly, this);
        bedMesh.material.color.setColor(0x1B1E24);
    }

    /**
     * Generates the asphalt 4-lane driving ribbon surface polygon mesh.
     */
    function buildRoadRibbon() {
        var count = waypoints.length;
        var pts:Array<Point> = [];
        var idxBuf = new IndexBuffer();

        for (i in 0...count) {
            var curr = waypoints[i];
            var next = waypoints[(i + 1) % count];
            var prev = waypoints[(i - 1 + count) % count];

            var fwd = next.sub(prev);
            fwd.z = 0;
            fwd.normalize();

            var right = new Vector(-fwd.y, fwd.x, 0);
            var leftPos = curr.add(right.scaled(-HALF_WIDTH));
            var rightPos = curr.add(right.scaled(HALF_WIDTH));

            pts.push(new Point(leftPos.x, leftPos.y, leftPos.z + ROAD_LIFT));
            pts.push(new Point(rightPos.x, rightPos.y, rightPos.z + ROAD_LIFT));
        }

        for (i in 0...count) {
            var i0 = i * 2;
            var i1 = i0 + 1;
            var i2 = ((i + 1) % count) * 2;
            var i3 = i2 + 1;

            idxBuf.push(i0); idxBuf.push(i2); idxBuf.push(i1);
            idxBuf.push(i1); idxBuf.push(i2); idxBuf.push(i3);
        }

        var poly = new Polygon(pts, idxBuf);
        poly.addNormals();
        roadMesh = new Mesh(poly, this);
        roadMesh.material.color.setColor(0x282D35);
    }

    /**
     * Builds continuous extruded steel Armco crash barriers along both track boundaries,
     * including vertical galvanized posts spaced at regular intervals.
     */
    function buildContinuousGuardrails() {
        var count = waypoints.length;

        var leftPts:Array<Point> = [];
        var rightPts:Array<Point> = [];
        var leftIdx = new IndexBuffer();
        var rightIdx = new IndexBuffer();

        for (i in 0...count) {
            var curr = waypoints[i];
            var next = waypoints[(i + 1) % count];
            var prev = waypoints[(i - 1 + count) % count];

            var fwd = next.sub(prev);
            fwd.z = 0;
            fwd.normalize();
            var right = new Vector(-fwd.y, fwd.x, 0);

            var lBase = curr.add(right.scaled(-HALF_WIDTH));
            var rBase = curr.add(right.scaled(HALF_WIDTH));

            var baseZ = curr.z + ROAD_LIFT;
            leftPts.push(new Point(lBase.x, lBase.y, baseZ));
            leftPts.push(new Point(lBase.x, lBase.y, baseZ + RAIL_HEIGHT));

            rightPts.push(new Point(rBase.x, rBase.y, baseZ));
            rightPts.push(new Point(rBase.x, rBase.y, baseZ + RAIL_HEIGHT));
        }

        for (i in 0...count) {
            var i0 = i * 2;
            var i1 = i0 + 1;
            var i2 = ((i + 1) % count) * 2;
            var i3 = i2 + 1;

            // Double-sided quad winding for inner and outer visibility
            leftIdx.push(i0); leftIdx.push(i2); leftIdx.push(i1);
            leftIdx.push(i1); leftIdx.push(i2); leftIdx.push(i3);
            leftIdx.push(i0); leftIdx.push(i1); leftIdx.push(i2);
            leftIdx.push(i1); leftIdx.push(i3); leftIdx.push(i2);

            rightIdx.push(i0); rightIdx.push(i1); rightIdx.push(i2);
            rightIdx.push(i1); rightIdx.push(i3); rightIdx.push(i2);
            rightIdx.push(i0); rightIdx.push(i2); rightIdx.push(i1);
            rightIdx.push(i1); rightIdx.push(i2); rightIdx.push(i3);
        }

        var polyL = new Polygon(leftPts, leftIdx);
        polyL.addNormals();
        leftRailMesh = new Mesh(polyL, this);
        leftRailMesh.material.color.setColor(0x9EACB8);

        var polyR = new Polygon(rightPts, rightIdx);
        polyR.addNormals();
        rightRailMesh = new Mesh(polyR, this);
        rightRailMesh.material.color.setColor(0x9EACB8);

        // Vertical support stanchion post geometry
        var postPrim = new Cube(0.25, 0.25, RAIL_HEIGHT + 0.1, true);
        postPrim.unindex();
        postPrim.addNormals();

        for (i in 0...Math.floor(count / 3)) {
            var idx = i * 3;
            var curr = waypoints[idx];
            var next = waypoints[(idx + 1) % count];
            var prev = waypoints[(idx - 1 + count) % count];

            var fwd = next.sub(prev);
            fwd.z = 0;
            fwd.normalize();
            var right = new Vector(-fwd.y, fwd.x, 0);

            var pL = curr.add(right.scaled(-HALF_WIDTH - 0.12));
            var postL = new Mesh(postPrim, this);
            postL.material.color.setColor(0x5A626A);
            postL.x = pL.x; postL.y = pL.y; postL.z = pL.z + ROAD_LIFT + (RAIL_HEIGHT * 0.5);

            var pR = curr.add(right.scaled(HALF_WIDTH + 0.12));
            var postR = new Mesh(postPrim, this);
            postR.material.color.setColor(0x5A626A);
            postR.x = pR.x; postR.y = pR.y; postR.z = pR.z + ROAD_LIFT + (RAIL_HEIGHT * 0.5);
        }
    }

    /**
     * Builds skyline skyscrapers surrounding the track to furnish parallax depth.
     */
    function buildCityscape() {
        var bldgPrim = new Cube(1.0, 1.0, 1.0, true);
        bldgPrim.unindex();
        bldgPrim.addNormals();

        var buildingLayouts = [
            { x: -40.0, y: 40.0,  w: 22.0, l: 30.0, h: 45.0, col: 0x363A40 },
            { x: -55.0, y: 110.0, w: 28.0, l: 24.0, h: 65.0, col: 0x2A2E35 },
            { x:  70.0, y: 90.0,  w: 35.0, l: 35.0, h: 50.0, col: 0x40454D },
            { x: 130.0, y: 110.0, w: 40.0, l: 28.0, h: 80.0, col: 0x242830 },
            { x: 190.0, y: 80.0,  w: 30.0, l: 45.0, h: 55.0, col: 0x3A3F47 },
            { x: 200.0, y: -60.0, w: 50.0, l: 40.0, h: 40.0, col: 0x33373E },
            { x: -30.0, y: -75.0, w: 25.0, l: 35.0, h: 48.0, col: 0x2F333B }
        ];

        for (b in buildingLayouts) {
            var bldg = new Mesh(bldgPrim, this);
            bldg.material.color.setColor(b.col);
            bldg.scaleX = b.w;
            bldg.scaleY = b.l;
            bldg.scaleZ = b.h;
            bldg.x = b.x;
            bldg.y = b.y;
            bldg.z = b.h * 0.5 - 1.0;
        }
    }

    /**
     * Builds illuminated highway street light poles along the circuit perimeter.
     * Features vertical galvanized columns, cantilevered cross-arms, and warm luminaire heads
     * that bathe the road surface in light to eliminate harsh shadow contrasts.
     */
    function buildStreetLights() {
        var count = waypoints.length;
        var poleHeight = 6.2;
        var armReach = 2.4;

        var polePrim = new Cube(0.24, 0.24, poleHeight, true);
        polePrim.unindex();
        polePrim.addNormals();

        var armPrim = new Cube(0.18, armReach, 0.18, true);
        armPrim.unindex();
        armPrim.addNormals();

        var headPrim = new Cube(0.55, 0.85, 0.22, true);
        headPrim.unindex();
        headPrim.addNormals();

        var lumPrim = new Cube(0.48, 0.75, 0.08, true);
        lumPrim.unindex();
        lumPrim.addNormals();

        var stride = 12; // Every 12 waypoints (~16 street lights around circuit)
        var totalLights = Math.floor(count / stride);

        for (i in 0...totalLights) {
            var idx = i * stride;
            var curr = waypoints[idx];
            var next = waypoints[(idx + 1) % count];
            var prev = waypoints[(idx - 1 + count) % count];

            var fwd = next.sub(prev);
            fwd.z = 0;
            fwd.normalize();
            var right = new Vector(-fwd.y, fwd.x, 0);

            // Alternate placement: even on right shoulder (+HALF_WIDTH + 0.85m), odd on left (-HALF_WIDTH - 0.85m)
            var isRightSide = (i % 2 == 0);
            var sideSign = isRightSide ? 1.0 : -1.0;
            var baseOffset = HALF_WIDTH + 0.85;

            var polePos = curr.add(right.scaled(baseOffset * sideSign));
            var baseZ = curr.z + ROAD_LIFT;

            // 1. Vertical Steel Pole
            var pole = new Mesh(polePrim, this);
            pole.material.color.setColor(0x353B42);
            pole.x = polePos.x;
            pole.y = polePos.y;
            pole.z = baseZ + (poleHeight * 0.5);
            streetLights.push(pole);

            // 2. Overhanging Horizontal Cantilever Arm extending toward roadway center
            var armPos = polePos.add(right.scaled(-sideSign * (armReach * 0.5)));
            var arm = new Mesh(armPrim, this);
            arm.material.color.setColor(0x424A54);
            arm.x = armPos.x;
            arm.y = armPos.y;
            arm.z = baseZ + poleHeight - 0.15;
            var angle = Math.atan2(right.y * -sideSign, right.x * -sideSign);
            arm.setRotation(0, 0, angle - 1.5707963);
            streetLights.push(arm);

            // 3. Luminaire Fixture Head Casing
            var headPos = polePos.add(right.scaled(-sideSign * armReach));
            var head = new Mesh(headPrim, this);
            head.material.color.setColor(0x22262B);
            head.x = headPos.x;
            head.y = headPos.y;
            head.z = baseZ + poleHeight - 0.22;
            head.setRotation(0, 0, angle - 1.5707963);
            streetLights.push(head);

            // 4. Glowing Emissive Luminaire Lens (Warm high-efficiency street light phosphor)
            var lum = new Mesh(lumPrim, this);
            lum.material.color.setColor(0xFFF2B0);
            lum.x = headPos.x;
            lum.y = headPos.y;
            lum.z = baseZ + poleHeight - 0.32;
            lum.setRotation(0, 0, angle - 1.5707963);
            streetLights.push(lum);
        }
    }

    /**
     * Computes the asphalt road elevation at the closest track centerline point.
     *
     * @param x World X coordinate in meters.
     * @param y World Y coordinate in meters.
     * @return Road surface elevation Z in meters.
     */
    public function getGroundElevation(x:Float, y:Float):Float {
        scratchQuery.set(x, y, 0);
        var proj = SplineMath.getClosestSegment(scratchQuery, waypoints);
        return proj.z + ROAD_LIFT;
    }

    /**
     * Computes road surface normal gradient at the closest track segment.
     *
     * @param x World X coordinate in meters.
     * @param y World Y coordinate in meters.
     * @param outNormal Scratch vector populated with unit-length normal vector.
     */
    public function getGroundNormal(x:Float, y:Float, outNormal:Vector):Void {
        scratchQuery.set(x, y, 0);
        var proj = SplineMath.getClosestSegment(scratchQuery, waypoints);
        var nx = -proj.segDirY * 0.04;
        var ny =  proj.segDirX * 0.04;
        var nz = Math.sqrt(Math.max(0.01, 1.0 - (nx * nx + ny * ny)));
        outNormal.set(nx, ny, nz);
    }

    /**
     * Enforces continuous Armco guardrail containment boundaries.
     * Clamps vehicle inside the legal asphalt corridor and applies scrape friction.
     */
    public function enforceBoundaries(pos:Vector, forwardSpeed:Float, lateralVelocity:Float):{ hitWall:Bool, speedMult:Float, latMult:Float } {
        scratchQuery.set(pos.x, pos.y, 0);
        var proj = SplineMath.getClosestSegment(scratchQuery, waypoints);
        pos.z = proj.z + ROAD_LIFT;

        var lateralDist = Math.sqrt(proj.distSq);
        var maxHalf = HALF_WIDTH - 0.3; // Armco barrier inner collision rail
        if (lateralDist > maxHalf && lateralDist > 0.001) {
            scratchFromCenter.set(pos.x - proj.centerPoint.x, pos.y - proj.centerPoint.y, 0);
            scratchFromCenter.normalize();
            pos.x = proj.centerPoint.x + scratchFromCenter.x * maxHalf;
            pos.y = proj.centerPoint.y + scratchFromCenter.y * maxHalf;
            return { hitWall: true, speedMult: 0.94, latMult: 0.0 };
        }
        return { hitWall: false, speedMult: 1.0, latMult: 1.0 };
    }
}