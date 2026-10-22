package world;

import h3d.scene.Object;
import h3d.scene.Mesh;
import h3d.prim.Polygon;
import h3d.prim.Cube;
import h3d.col.Point;
import h3d.Vector;
import hxd.IndexBuffer;

/**
 * Open Sandbox Proving Grounds environment for full-spectrum physics testing.
 * Implements IGroundProvider with analytical continuous elevation and normal gradients.
 * Features:
 * - Flat central skidpad & staging tarmac for zero-to-sixty timing, burnouts, and donuts.
 * - Rolling sinusoidal moguls and washboard ridges for suspension frequency and anti-roll testing.
 * - Steep 12.5-meter apex hill for uphill engine torque, downshifting, and downhill braking dive.
 * - Inclined launch ramp with a sharp drop-off crest for ballistic airborne flight and landing suspension travel.
 * - Banked 25-degree high-speed bowl for high lateral-G cornering and Pacejka drift breakaway.
 * - 4 high-mast perimeter floodlight towers providing balanced illumination without harsh shadows.
 * - Invisible elastic boundary walls at +/-195 meters.
 */
class SandboxMap extends Object implements IGroundProvider {
    /** Primary terrain surface mesh. */
    public var terrainMesh:Mesh;

    /** Center circular asphalt skidpad mesh. */
    public var skidpadMesh:Mesh;

    /** Array of perimeter floodlight stanchion meshes. */
    public var floodlights:Array<Mesh> = [];

    /** Array of slalom and agility obstacle meshes. */
    public var obstacles:Array<Mesh> = [];

    /** Proving grounds half-span width in meters. */
    public static inline var HALF_SPAN:Float = 200.0;

    /** Invisible collision wall perimeter boundary in meters. */
    public static inline var WALL_LIMIT:Float = 195.0;

    /** Apex hill maximum elevation in meters. */
    public static inline var HILL_APEX_Z:Float = 12.5;

    /** Launch ramp crest elevation in meters. */
    public static inline var RAMP_CREST_Z:Float = 3.8;

    var scratchNormal:Vector = new Vector();

    /**
     * Constructs and initializes the open sandbox proving grounds.
     *
     * @param parent Optional parent 3D scene graph node.
     */
    public function new(?parent:Object) {
        super(parent);
        buildTerrainMesh();
        buildSkidpad();
        buildFloodlights();
        buildObstacles();
    }

    /**
     * Analytical ground elevation function evaluating continuous elevation at coordinate (x, y).
     *
     * @param x World X coordinate in meters.
     * @param y World Y coordinate in meters.
     * @return Contact plane elevation Z in meters.
     */
    public function getGroundElevation(x:Float, y:Float):Float {
        var distFromCenterSq = x * x + y * y;

        // 1. Center Flat Skidpad (Radius: 36m)
        if (distFromCenterSq < 36.0 * 36.0) {
            return 0.0;
        }

        var elev = 0.0;

        // 2. Rolling Moguls / Suspension Washboard (X in [35, 140], Y in [-50, 50])
        if (x > 35.0 && x < 140.0 && y > -50.0 && y < 50.0) {
            var xFrac = (x - 35.0) / 105.0;
            var yFrac = (y + 50.0) / 100.0;
            var envelope = Math.sin(xFrac * Math.PI) * Math.sin(yFrac * Math.PI);
            var waves = Math.sin(x * 0.38) * Math.cos(y * 0.24);
            elev += waves * 1.35 * envelope;
        }

        // 3. Steep Apex Mountain / Hill Climb (Centered at X: -95, Y: +95, Radius ~55m)
        var hillDx = x - (-95.0);
        var hillDy = y - 95.0;
        var hillDistSq = hillDx * hillDx + hillDy * hillDy;
        if (hillDistSq < 60.0 * 60.0) {
            var hillEnvelope = Math.exp(-hillDistSq / 1100.0);
            elev += HILL_APEX_Z * hillEnvelope;
        }

        // 4. Inclined Launch Ramp (X in [-22, 22], Y in [70, 125])
        if (x >= -22.0 && x <= 22.0 && y >= 70.0 && y <= 125.0) {
            var xEdgeDist = Math.min(22.0 - Math.abs(x), 4.0) / 4.0;
            if (y <= 120.0) {
                var rampFrac = (y - 70.0) / 50.0;
                elev += Math.max(0.0, rampFrac * rampFrac * RAMP_CREST_Z * xEdgeDist);
            } else {
                // Sharp drop-off crest lip over 5 meters
                var dropFrac = 1.0 - ((y - 120.0) / 5.0);
                elev += Math.max(0.0, dropFrac * RAMP_CREST_Z * xEdgeDist);
            }
        }

        // 5. Banked High-Speed Bowl (Centered at X: -100, Y: -100)
        var bowlDx = x - (-100.0);
        var bowlDy = y - (-100.0);
        var bowlDist = Math.sqrt(bowlDx * bowlDx + bowlDy * bowlDy);
        if (bowlDist > 25.0 && bowlDist < 75.0) {
            var bowlFrac = (bowlDist - 25.0) / 50.0;
            elev += Math.sin(bowlFrac * (Math.PI * 0.5)) * 5.2;
        }

        return elev;
    }

    /**
     * Analytical normal gradient calculator using finite-difference spatial partial derivatives.
     *
     * @param x World X coordinate in meters.
     * @param y World Y coordinate in meters.
     * @param outNormal Scratch vector populated with unit-length normal.
     */
    public function getGroundNormal(x:Float, y:Float, outNormal:Vector):Void {
        var eps = 0.15;
        var zCenter = getGroundElevation(x, y);
        var zDx = getGroundElevation(x + eps, y) - zCenter;
        var zDy = getGroundElevation(x, y + eps) - zCenter;

        var nx = -zDx / eps;
        var ny = -zDy / eps;
        var nz = 1.0;

        var len = Math.sqrt(nx * nx + ny * ny + nz * nz);
        outNormal.set(nx / len, ny / len, nz / len);
    }

    /**
     * Enforces invisible boundary walls at +/-195 meters with elastic bumper restitution.
     */
    public function enforceBoundaries(pos:Vector, forwardSpeed:Float, lateralVelocity:Float):{ hitWall:Bool, speedMult:Float, latMult:Float } {
        var hit = false;
        var sMult = 1.0;
        var lMult = 1.0;

        if (pos.x < -WALL_LIMIT) {
            pos.x = -WALL_LIMIT;
            hit = true;
            lMult = -0.4;
            sMult = 0.7;
        } else if (pos.x > WALL_LIMIT) {
            pos.x = WALL_LIMIT;
            hit = true;
            lMult = -0.4;
            sMult = 0.7;
        }

        if (pos.y < -WALL_LIMIT) {
            pos.y = -WALL_LIMIT;
            hit = true;
            sMult = -0.3;
            lMult = 0.5;
        } else if (pos.y > WALL_LIMIT) {
            pos.y = WALL_LIMIT;
            hit = true;
            sMult = -0.3;
            lMult = 0.5;
        }

        return { hitWall: hit, speedMult: sMult, latMult: lMult };
    }

    /**
     * Registers static rigid body boundary walls in the OimoPhysics world.
     *
     * @param world Target Oimo physics world.
     */
    public function registerPhysicsColliders(world:oimo.dynamics.World):Void {
        if (world == null) return;
        var wallThickness = 4.0;
        var wallHeight = 40.0;

        // West wall (-X)
        createStaticWall(world, -WALL_LIMIT - (wallThickness * 0.5), 0.0, 10.0, wallThickness * 0.5, HALF_SPAN, wallHeight * 0.5);
        // East wall (+X)
        createStaticWall(world,  WALL_LIMIT + (wallThickness * 0.5), 0.0, 10.0, wallThickness * 0.5, HALF_SPAN, wallHeight * 0.5);
        // South wall (-Y)
        createStaticWall(world, 0.0, -WALL_LIMIT - (wallThickness * 0.5), 10.0, HALF_SPAN, wallThickness * 0.5, wallHeight * 0.5);
        // North wall (+Y)
        createStaticWall(world, 0.0,  WALL_LIMIT + (wallThickness * 0.5), 10.0, HALF_SPAN, wallThickness * 0.5, wallHeight * 0.5);
    }

    function createStaticWall(world:oimo.dynamics.World, x:Float, y:Float, z:Float, hx:Float, hy:Float, hz:Float) {
        var rbConfig = new oimo.dynamics.rigidbody.RigidBodyConfig();
        rbConfig.type = oimo.dynamics.rigidbody.RigidBodyType.STATIC;
        rbConfig.position = new oimo.common.Vec3(x, y, z);
        var body = new oimo.dynamics.rigidbody.RigidBody(rbConfig);

        var shapeConfig = new oimo.dynamics.rigidbody.ShapeConfig();
        shapeConfig.geometry = new oimo.collision.geometry.BoxGeometry(new oimo.common.Vec3(hx, hy, hz));
        shapeConfig.restitution = 0.4;
        shapeConfig.friction = 0.3;
        body.addShape(new oimo.dynamics.rigidbody.Shape(shapeConfig));
        world.addRigidBody(body);
    }

    /**
     * Constructs the 3D polygon mesh representation of the continuous heightfield.
     */
    function buildTerrainMesh() {
        var divisions = 64;
        var step = (HALF_SPAN * 2.0) / divisions;

        var pts:Array<Point> = [];
        var uvs:Array<h3d.prim.UV> = [];
        var idxBuf = new IndexBuffer();

        for (iy in 0...(divisions + 1)) {
            var y = -HALF_SPAN + (iy * step);
            for (ix in 0...(divisions + 1)) {
                var x = -HALF_SPAN + (ix * step);
                var z = getGroundElevation(x, y);
                pts.push(new Point(x, y, z));
                uvs.push(new h3d.prim.UV((x + HALF_SPAN) * 0.16, (y + HALF_SPAN) * 0.16));
            }
        }

        var stride = divisions + 1;
        for (iy in 0...divisions) {
            for (ix in 0...divisions) {
                var i0 = iy * stride + ix;
                var i1 = i0 + 1;
                var i2 = (iy + 1) * stride + ix;
                var i3 = i2 + 1;

                // Counter-clockwise triangle winding for upward facing surface normals (+Z)
                idxBuf.push(i0); idxBuf.push(i1); idxBuf.push(i2);
                idxBuf.push(i1); idxBuf.push(i3); idxBuf.push(i2);
            }
        }

        var poly = new Polygon(pts, idxBuf);
        poly.uvs = uvs;
        poly.addNormals();
        terrainMesh = new Mesh(poly, this);
        terrainMesh.material.mainPass.culling = None;
        terrainMesh.material.color.setColor(0xFFFFFF);

        // Procedural high-contrast cyber coordinates grid texture
        #if js
        try {
            var size = 256;
            var pixels = hxd.Pixels.alloc(size, size, hxd.PixelFormat.ARGB);
            for (py in 0...size) {
                for (px in 0...size) {
                    var isMajor = (px == 0 || px == size - 1 || py == 0 || py == size - 1 || px % 32 == 0 || py % 32 == 0);
                    var isMinor = (px % 8 == 0 || py % 8 == 0);
                    var col:Int = 0xFF222C28; // Deep slate-charcoal asphalt
                    if (isMajor) {
                        col = 0xFF3E5048; // Crisp terrain coordinate grid line
                    } else if (isMinor) {
                        col = 0xFF2A3632; // Subtle contour sub-grid
                    }
                    if (px % 32 == 0 && py % 32 == 0) {
                        col = 0xFF00E5FF; // High-visibility electric cyan intersection node
                    }
                    pixels.setPixel(px, py, col);
                }
            }
            var tex = h3d.mat.Texture.fromPixels(pixels);
            tex.wrap = Repeat;
            terrainMesh.material.texture = tex;
        } catch (e:Dynamic) {
            // Headless testing environment fallback
        }
        #end
    }

    /**
     * Constructs the central smooth asphalt circular skidpad.
     */
    function buildSkidpad() {
        var segments = 32;
        var radius = 35.0;
        var pts:Array<Point> = [];
        var uvs:Array<h3d.prim.UV> = [];
        var idxBuf = new IndexBuffer();

        pts.push(new Point(0, 0, 0.05));
        uvs.push(new h3d.prim.UV(0.5, 0.5));
        for (i in 0...segments) {
            var angle = (i / segments) * (Math.PI * 2.0);
            var px = Math.cos(angle) * radius;
            var py = Math.sin(angle) * radius;
            pts.push(new Point(px, py, 0.05));
            uvs.push(new h3d.prim.UV(0.5 + Math.cos(angle) * 0.5, 0.5 + Math.sin(angle) * 0.5));
        }

        for (i in 0...segments) {
            var next = (i + 1) % segments;
            idxBuf.push(0);
            idxBuf.push(1 + i);
            idxBuf.push(1 + next);
        }

        var poly = new Polygon(pts, idxBuf);
        poly.uvs = uvs;
        poly.addNormals();
        skidpadMesh = new Mesh(poly, this);
        skidpadMesh.material.mainPass.culling = None;
        skidpadMesh.material.color.setColor(0x2A2E35);
    }

    /**
     * Builds perimeter stadium floodlight towers to flood the arena with balanced light
     * and prevent harsh shadows on slopes and valleys.
     */
    function buildFloodlights() {
        var towerPositions = [
            { x: -160.0, y: -160.0 },
            { x:  160.0, y: -160.0 },
            { x: -160.0, y:  160.0 },
            { x:  160.0, y:  160.0 }
        ];

        var towerHeight = 16.0;
        var mastPrim = new Cube(0.8, 0.8, towerHeight, true);
        mastPrim.unindex();
        mastPrim.addNormals();

        var bankPrim = new Cube(3.2, 1.2, 1.4, true);
        bankPrim.unindex();
        bankPrim.addNormals();

        var lumPrim = new Cube(3.0, 1.0, 0.2, true);
        lumPrim.unindex();
        lumPrim.addNormals();

        for (t in towerPositions) {
            var groundZ = getGroundElevation(t.x, t.y);

            // 1. Tower Mast
            var mast = new Mesh(mastPrim, this);
            mast.material.color.setColor(0x3B424A);
            mast.x = t.x;
            mast.y = t.y;
            mast.z = groundZ + (towerHeight * 0.5);
            floodlights.push(mast);

            // 2. Floodlight Head Housing angled downward into map center
            var head = new Mesh(bankPrim, this);
            head.material.color.setColor(0x202428);
            head.x = t.x;
            head.y = t.y;
            head.z = groundZ + towerHeight - 0.5;
            var angleToCenter = Math.atan2(-t.y, -t.x);
            head.setRotation(0, 0.35, angleToCenter);
            floodlights.push(head);

            // 3. Glowing Floodlight Luminaire Bank (High-output daylight floodlight)
            var lum = new Mesh(lumPrim, this);
            lum.material.color.setColor(0xFFFDE6);
            lum.x = t.x;
            lum.y = t.y;
            lum.z = groundZ + towerHeight - 0.7;
            lum.setRotation(0, 0.35, angleToCenter);
            floodlights.push(lum);
        }
    }

    /**
     * Builds geometric testing blocks, agility slalom pylons, and laser perimeter boundary markers.
     */
    function buildObstacles() {
        var pylonPrim = new Cube(0.5, 0.5, 1.2, true);
        pylonPrim.unindex();
        pylonPrim.addNormals();

        // Slalom course along Y axis on tarmac
        for (i in -4...5) {
            if (i == 0) continue;
            var py = i * 6.5;
            var pylon = new Mesh(pylonPrim, this);
            pylon.material.color.setColor(0xFF6B00); // High-visibility safety orange
            pylon.x = 0.0;
            pylon.y = py;
            pylon.z = 0.6;
            obstacles.push(pylon);
        }

        // Perimeter boundary guideposts (subtle laser beacons marking invisible wall limits)
        var postPrim = new Cube(0.3, 0.3, 3.0, true);
        postPrim.unindex();
        postPrim.addNormals();

        var perimeterMarkers = [
            { x: -WALL_LIMIT, y: -WALL_LIMIT },
            { x:  WALL_LIMIT, y: -WALL_LIMIT },
            { x: -WALL_LIMIT, y:  WALL_LIMIT },
            { x:  WALL_LIMIT, y:  WALL_LIMIT },
            { x: 0.0, y: -WALL_LIMIT },
            { x: 0.0, y:  WALL_LIMIT },
            { x: -WALL_LIMIT, y: 0.0 },
            { x:  WALL_LIMIT, y: 0.0 }
        ];

        for (m in perimeterMarkers) {
            var mz = getGroundElevation(m.x, m.y);
            var post = new Mesh(postPrim, this);
            post.material.color.setColor(0x00E5FF); // Electric cyan boundary marker
            post.x = m.x;
            post.y = m.y;
            post.z = mz + 1.5;
            obstacles.push(post);
        }
    }
}

