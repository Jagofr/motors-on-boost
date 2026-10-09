package entities;

import h3d.scene.Object;
import h3d.Vector;
import physics.CarPhysics;
import physics.SplineMath;
import camera.ChaseCamera;

/**
 * Individual civilian autonomous traffic vehicle instance.
 * Maintains assigned spline navigation waypoint, target cruise speed, lane offset, and heading.
 */
class TrafficCar {
    /** Associated 3D visual mesh attached to the scene graph. */
    public var carMesh:TrafficCarMesh;

    /** Current position in world coordinates. */
    public var pos:Vector = new Vector();

    /** Yaw heading angle in radians. */
    public var yaw:Float = 0.0;

    /** Desired steady-state cruising speed in m/s (~60-65 km/h). */
    public var cruiseSpeed:Float = 17.0;

    /** Instantaneous dynamic speed in m/s reacting to lead vehicle braking. */
    public var currentSpeed:Float = 17.0;

    /** Index of the current target track spline waypoint being steered towards. */
    public var waypointIdx:Int = 0;

    /** True if driving against player direction in the oncoming oncoming traffic lane. */
    public var isOncoming:Bool = false;

    /**
     * Instantiates a new autonomous traffic vehicle agent.
     *
     * @param mesh Visual 3D model node.
     * @param startWp Initial waypoint index along the circuit spline.
     * @param oncoming Boolean flag indicating whether vehicle travels in reverse waypoint order.
     * @param speed Target cruise speed in m/s.
     */
    public function new(mesh:TrafficCarMesh, startWp:Int, oncoming:Bool = false, speed:Float = 17.0) {
        this.carMesh = mesh;
        this.waypointIdx = startWp;
        this.isOncoming = oncoming;
        this.cruiseSpeed = speed;
        this.currentSpeed = speed;
    }
}

/**
 * Multi-agent traffic simulation, autonomous spacing AI, and collision resolution system.
 * Simulates highway traffic streams flowing in both directions, enforces two-car follow buffers,
 * handles player-to-traffic vehicular impacts with impulse exchange, and bounds vehicles to track rails.
 */
class TrafficSystem extends Object {
    /** Collection of active traffic vehicle agents in the world. */
    public var trafficList:Array<TrafficCar> = [];

    /** Reference to circuit centerline waypoint spline coordinates. */
    var trackWaypoints:Array<Vector>;

    /** Reusable scratch direction vector to eliminate per-frame allocations during track clamping. */
    var scratchFromCenter:Vector = new Vector();

    /** Half-width threshold of the roadway before collision contact with outer Armco rails. */
    public static inline var ACTIVE_HALF_WIDTH:Float = 9.7;

    /** Maximum speed clamp in m/s to prevent out-of-bounds clipping. */
    static inline var MAX_SPEED_CAP:Float = 95.0;

    /** Bounding cylinder collision radius of player race vehicle in meters. */
    static inline var PLAYER_RADIUS:Float = 1.6;

    /** Bounding cylinder collision radius of civilian traffic vehicle in meters. */
    static inline var TRAFFIC_RADIUS:Float = 1.5;

    /** Combined radial distance threshold triggering player-traffic collision. */
    static inline var HIT_THRESHOLD:Float = PLAYER_RADIUS + TRAFFIC_RADIUS;

    /** Radial distance threshold triggering mutual traffic-to-traffic collision. */
    static inline var TRAFFIC_HIT_THRESHOLD:Float = TRAFFIC_RADIUS * 2.0;

    /** Forward distance in meters where trailing vehicles detect lead cars and brake. */
    static inline var TRAFFIC_FOLLOW_BUFFER:Float = 10.0;

    /** Friction velocity conservation multiplier applied when player scrapes guardrails. */
    static inline var WALL_STICKINESS:Float = 0.94;

    /**
     * Initializes the traffic system and populates the highway circuit with civilian vehicles.
     *
     * @param trackWaypoints Array of circuit spline waypoints.
     * @param parent Optional parent 3D scene graph node.
     */
    public function new(trackWaypoints:Array<Vector>, ?parent:Object) {
        super(parent);
        this.trackWaypoints = trackWaypoints;
        spawnTrafficFleet();
    }

    /**
     * Populates the circuit with alternating same-direction and oncoming traffic vehicles.
     * Positions cars along left (-4.8m) and right (+4.8m) highway lane corridors.
     */
    function spawnTrafficFleet() {
        var carColors = [0x2A52BE, 0x8B7355, 0x2E6F40, 0x8B2500, 0xD0D7DE];
        var spacing = 24; // Waypoint stride between successive traffic vehicles
        var total = Math.floor(trackWaypoints.length / spacing);

        for (i in 0...total) {
            var wpIdx = (i * spacing + 10) % trackWaypoints.length;
            var oncoming = (i % 2 == 1);
            var baseSpeed = oncoming ? 17.5 : 16.0;

            var visual = new TrafficCarMesh(carColors[i % carColors.length], this);
            var tc = new TrafficCar(visual, wpIdx, oncoming, baseSpeed);

            var wp = trackWaypoints[wpIdx];
            var nextWp = trackWaypoints[(wpIdx + 1) % trackWaypoints.length];
            var fwd = nextWp.sub(wp);
            fwd.z = 0;
            fwd.normalize();
            var right = new Vector(-fwd.y, fwd.x, 0);

            // Left-hand traffic offset rule: Same-direction = left (-4.8m), Oncoming = right (+4.8m)
            var laneOffset = oncoming ? 4.8 : -4.8;
            tc.pos.set(wp.x + right.x * laneOffset, wp.y + right.y * laneOffset, wp.z);
            tc.yaw = Math.atan2(fwd.y, fwd.x) + (oncoming ? Math.PI : 0.0);

            trafficList.push(tc);
        }
    }

    /**
     * Updates traffic AI heading tracking, autonomous headway spacing, inter-traffic separation,
     * solid player collisions with impulse transfer, and track boundary constraint clamping.
     *
     * @param dt Delta time elapsed since last frame in seconds.
     * @param playerPhysics Active player vehicle physics instance.
     * @param chaseCam Active chase camera instance for trauma shake injection.
     */
    public function update(dt:Float, playerPhysics:CarPhysics, chaseCam:ChaseCamera) {
        var numWaypoints = trackWaypoints.length;

        // 1. Autonomous Traffic Spacing AI & Follow-Distance Deceleration
        for (i in 0...trafficList.length) {
            var tc = trafficList[i];
            var targetSpeed = tc.cruiseSpeed;
            var fwdX = Math.cos(tc.yaw);
            var fwdY = Math.sin(tc.yaw);

            for (j in 0...trafficList.length) {
                if (i == j) continue;
                var other = trafficList[j];
                // Only consider traffic travelling in the exact same flow direction
                if (other.isOncoming != tc.isOncoming) continue;

                var dx = other.pos.x - tc.pos.x;
                var dy = other.pos.y - tc.pos.y;
                var dist = Math.sqrt(dx * dx + dy * dy);

                // Detect lead car directly ahead within buffer distance
                if (dist < TRAFFIC_FOLLOW_BUFFER && dist > 0.001) {
                    var dot = (dx * fwdX + dy * fwdY) / dist;
                    if (dot > 0.7) {
                        var headway = dist / TRAFFIC_FOLLOW_BUFFER;
                        targetSpeed = Math.min(targetSpeed, other.currentSpeed * (headway * 0.8));
                    }
                }
            }

            // Smoothly adapt current vehicle speed towards target speed
            tc.currentSpeed += (targetSpeed - tc.currentSpeed) * 5.0 * dt;
            if (tc.currentSpeed < 0) tc.currentSpeed = 0;
        }

        // 2. Traffic Movement along Assigned Waypoints & Meshes Synchronization
        for (tc in trafficList) {
            var targetIdx = tc.isOncoming ? (tc.waypointIdx - 1 + numWaypoints) % numWaypoints : (tc.waypointIdx + 1) % numWaypoints;
            var targetWp = trackWaypoints[targetIdx];
            var dir = targetWp.sub(tc.pos);
            dir.z = 0;

            // Advance target waypoint index upon proximity arrival
            if (dir.length() < 8.0) tc.waypointIdx = targetIdx;

            dir.normalize();
            tc.pos.x += dir.x * tc.currentSpeed * dt;
            tc.pos.y += dir.y * tc.currentSpeed * dt;
            tc.yaw = Math.atan2(dir.y, dir.x);

            clampToTrack(tc.pos, ACTIVE_HALF_WIDTH - 0.5);

            // Synchronize visual 3D mesh transform
            tc.carMesh.x = tc.pos.x;
            tc.carMesh.y = tc.pos.y;
            tc.carMesh.z = tc.pos.z;
            tc.carMesh.setRotation(0, 0, tc.yaw - 1.5707963);
        }

        // 3. Traffic-to-Traffic Mutual Separation Hard Body Collisions
        for (i in 0...trafficList.length) {
            var carA = trafficList[i];
            for (j in (i + 1)...trafficList.length) {
                var carB = trafficList[j];

                var dx = carB.pos.x - carA.pos.x;
                var dy = carB.pos.y - carA.pos.y;
                var distSq = dx * dx + dy * dy;

                if (distSq < TRAFFIC_HIT_THRESHOLD * TRAFFIC_HIT_THRESHOLD && distSq > 0.0001) {
                    var dist = Math.sqrt(distSq);
                    var overlap = TRAFFIC_HIT_THRESHOLD - dist;
                    var nx = dx / dist;
                    var ny = dy / dist;

                    // Push overlapping vehicles symmetrically apart
                    carA.pos.x -= nx * overlap * 0.5;
                    carA.pos.y -= ny * overlap * 0.5;
                    carB.pos.x += nx * overlap * 0.5;
                    carB.pos.y += ny * overlap * 0.5;

                    var avgSpeed = (carA.currentSpeed + carB.currentSpeed) * 0.5;
                    carA.currentSpeed = avgSpeed * 0.9;
                    carB.currentSpeed = avgSpeed * 0.9;
                }
            }
        }

        // 4. Solid Player-to-Traffic Vehicular Impacts
        for (tc in trafficList) {
            var dx = tc.pos.x - playerPhysics.pos.x;
            var dy = tc.pos.y - playerPhysics.pos.y;
            var distSq = dx * dx + dy * dy;

            if (distSq < HIT_THRESHOLD * HIT_THRESHOLD && distSq > 0.0001) {
                var dist = Math.sqrt(distSq);
                var nx = dx / dist;
                var ny = dy / dist;
                var overlap = HIT_THRESHOLD - dist;

                // Push player and traffic apart according to relative mass distribution
                playerPhysics.pos.x -= nx * overlap * 0.6;
                playerPhysics.pos.y -= ny * overlap * 0.6;
                tc.pos.x += nx * overlap * 0.4;
                tc.pos.y += ny * overlap * 0.4;

                var pFwdX = -Math.sin(playerPhysics.yaw);
                var pFwdY =  Math.cos(playerPhysics.yaw);
                var dotApproach = pFwdX * nx + pFwdY * ny;

                // High-penalty crash on head-on collision vs tactical rear-end pit bump
                if (tc.isOncoming || dotApproach < 0.2) {
                    playerPhysics.forwardSpeed *= 0.4;
                    tc.currentSpeed *= 0.3;
                    chaseCam.addTrauma(0.65);
                } else {
                    playerPhysics.forwardSpeed *= 0.75;
                    tc.currentSpeed = Math.max(tc.currentSpeed, Math.abs(playerPhysics.forwardSpeed) * 0.9);
                    chaseCam.addTrauma(0.35);
                }
            }
        }

        // 5. Guardrail Outer Boundary Clamping
        var wallHit = clampToTrack(playerPhysics.pos, ACTIVE_HALF_WIDTH);
        if (wallHit) {
            playerPhysics.forwardSpeed = Math.min(playerPhysics.forwardSpeed * WALL_STICKINESS, MAX_SPEED_CAP);
            playerPhysics.lateralVelocity = 0.0;
            chaseCam.addTrauma(0.12);
        }

        if (Math.abs(playerPhysics.forwardSpeed) > MAX_SPEED_CAP) {
            playerPhysics.forwardSpeed = (playerPhysics.forwardSpeed > 0 ? 1 : -1) * MAX_SPEED_CAP;
        }
    }

    /**
     * Clamps a 3D coordinate point to the legal asphalt half-width corridor.
     * Prevents penetrating the continuous Armco guardrails.
     *
     * @param point World space coordinate vector to project and clamp in-place.
     * @param maxHalfWidth Permissible radial distance from the track centerline.
     * @return True if the point breached the boundary corridor and was repositioned.
     */
    function clampToTrack(point:Vector, maxHalfWidth:Float):Bool {
        var proj = SplineMath.getClosestSegment(point, trackWaypoints);
        point.z = proj.z;

        var lateralDist = Math.sqrt(proj.distSq);
        if (lateralDist > maxHalfWidth && lateralDist > 0.001) {
            scratchFromCenter.set(point.x - proj.centerPoint.x, point.y - proj.centerPoint.y, 0);
            scratchFromCenter.normalize();

            point.x = proj.centerPoint.x + scratchFromCenter.x * maxHalfWidth;
            point.y = proj.centerPoint.y + scratchFromCenter.y * maxHalfWidth;
            return true;
        }

        return false;
    }
}