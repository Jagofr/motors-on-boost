package world;

import h3d.scene.Object;
import h3d.scene.Mesh;
import h3d.prim.Polygon;
import h3d.prim.Cube;
import h3d.col.Point;
import h3d.Vector;
import hxd.IndexBuffer;
import physics.SplineMath;

class Track extends Object {
    public var waypoints:Array<Vector> = [];
    public var roadMesh:Mesh;
    public var bedMesh:Mesh;
    public var leftRailMesh:Mesh;
    public var rightRailMesh:Mesh;

    public static inline var ROAD_WIDTH:Float = 20.0;
    public static inline var HALF_WIDTH:Float = 10.0;
    public static inline var BED_EXTRA_WIDTH:Float = 4.0;
    public static inline var ROAD_LIFT:Float = 0.06;
    public static inline var RAIL_HEIGHT:Float = 0.65;

    public function new(?parent:Object) {
        super(parent);
        buildCircuitWaypoints();
        buildRoadBed();
        buildRoadRibbon();
        buildContinuousGuardrails();
        buildCityscape();
    }

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
            { x: 295.0, y: 130.0, w: 42.0, l: 32.0, h: 90.0, col: 0x1E2229 },
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
}