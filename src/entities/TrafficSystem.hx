package entities;

import config.WorldConfig;
import graphics.SceneGraph.Object3D;
import math.Vec3;
import physics.CarPhysics;
import physics.SplineMath;
import camera.ChaseCamera;

/**
 * Highway traffic lane orientation and corridor assignment.
 */
enum abstract TrafficLane(Int) from Int to Int {
    /** Right-hand travel corridor along travel direction (+4.8m offset). */
    var RightLane = 0;

    /** Left-hand passing/oncoming corridor (-4.8m offset). */
    var LeftLane = 1;
}

/**
 * Individual civilian autonomous traffic vehicle instance.
 * Maintains assigned spline navigation waypoint, target cruise speed, lane offset, and heading.
 */
class TrafficCar {
    /** Associated 3D visual mesh attached to the scene graph. */
    public var carMesh:TrafficCarMesh;

    /** Current position in world coordinates. */
    public var pos:Vec3 = new Vec3();

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

    /** Assigned highway lane offset from track centerline in meters (+4.8 = oncoming, -4.8 = same direction). */
    public var laneOffset:Float = 0.0;

    /** Dynamic smoothed lane offset reacting to obstacles, passing, and avoidance. */
    public var currentLaneOffset:Float = 0.0;

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
        this.laneOffset = oncoming ? 4.8 : -4.8;
        this.currentLaneOffset = this.laneOffset;
    }

    /**
     * Populates out vector with civilian traffic vehicle unit forward heading Vec3.
     */
    public function getForwardVector(?out:Vec3):Vec3 {
        if (out == null) out = new Vec3();
        out.set(Math.cos(yaw), Math.sin(yaw), 0);
        return out;
    }

    /**
     * Populates out vector with civilian traffic vehicle unit rightward Vec3.
     */
    public function getRightVector(?out:Vec3):Vec3 {
        if (out == null) out = new Vec3();
        out.set(Math.sin(yaw), -Math.cos(yaw), 0);
        return out;
    }
}

/**
 * Multi-agent traffic simulation, autonomous spacing AI, and collision resolution system.
 * Simulates highway traffic streams flowing in both directions, enforces two-car follow buffers,
 * handles player-to-traffic vehicular impacts with impulse exchange, and bounds vehicles to track rails.
 *
 * @class TrafficSystem
 * @extends h3d.scene.Object
 * @module entities/TrafficSystem
 */
class TrafficSystem extends Object3D {
    /** Collection of active traffic vehicle agents in the world. */
    public var trafficList:Array<TrafficCar> = [];

    /** Reference to circuit centerline waypoint spline coordinates. */
    var trackWaypoints:Array<Vec3>;

    /** Active traffic simulation configuration parameters. */
    public var config:config.WorldConfig.TrafficConfig;

    /** Reusable scratch direction vector to eliminate per-frame allocations during track clamping. */
    var scratchFromCenter:Vec3 = new Vec3();
    var scratchFwd:Vec3 = new Vec3();
    var scratchRight:Vec3 = new Vec3();

    /** Half-width threshold of the roadway before collision contact with outer Armco rails. @default 9.7 */
    public static inline var ACTIVE_HALF_WIDTH:Float = 9.7;

    /** Maximum speed clamp in m/s to prevent out-of-bounds clipping. @default 95.0 */
    static inline var MAX_SPEED_CAP:Float = 95.0;

    /** Bounding cylinder collision radius of player race vehicle in meters. @default 1.6 */
    static inline var PLAYER_RADIUS:Float = 1.6;

    /** Bounding cylinder collision radius of civilian traffic vehicle in meters. @default 1.5 */
    static inline var TRAFFIC_RADIUS:Float = 1.5;

    /** Combined radial distance threshold triggering player-traffic collision. @default 3.1 */
    static inline var HIT_THRESHOLD:Float = PLAYER_RADIUS + TRAFFIC_RADIUS;

    /** Radial distance threshold triggering mutual traffic-to-traffic collision. @default 3.0 */
    static inline var TRAFFIC_HIT_THRESHOLD:Float = TRAFFIC_RADIUS * 2.0;

    /** Forward distance in meters where trailing vehicles detect lead cars and brake. @default 10.0 */
    static inline var TRAFFIC_FOLLOW_BUFFER:Float = 10.0;

    /**
     * Initializes the traffic system and populates the highway circuit with civilian vehicles.
     *
     * @param {Array<Vec3>} trackWaypoints Array of circuit spline waypoints.
     * @param {Null<Object>} [parent] Optional parent 3D scene graph node.
     * @param {Null<config.WorldConfig.TrafficConfig>} [config] Optional traffic configuration overrides.
     */
    public function new(trackWaypoints:Array<Vec3>, ?parent:Object3D, ?config:config.WorldConfig.TrafficConfig) {
        super(parent);
        this.trackWaypoints = trackWaypoints;
        this.config = config != null ? config : WorldConfig.getDefaultTraffic();
        spawnTrafficFleet();
    }

    /**
     * Populates the circuit with alternating same-direction and oncoming traffic vehicles.
     *
     * @returns {Void}
     */
    function spawnTrafficFleet():Void {
        var carColors = config.paintPalette;
        var spacing = 24;
        var total = Math.floor(trackWaypoints.length / spacing);

        for (i in 0...total) {
            var wpIdx = (i * spacing + 10) % trackWaypoints.length;
            var oncoming = (i % 2 == 1);
            var baseSpeed = oncoming ? 17.5 : 16.0;

            var visual = new TrafficCarMesh(carColors[i % carColors.length], this);
            var tc = new TrafficCar(visual, wpIdx, oncoming, baseSpeed);
            placeTrafficAgentAtWaypoint(tc, wpIdx, oncoming);
            trafficList.push(tc);
        }
    }

    /**
     * Resets all traffic vehicles back to their starting grid spline intervals and nominal cruise speeds.
     *
     * @returns {Void}
     */
    public function resetPositions():Void {
        var spacing = 24;
        for (i in 0...trafficList.length) {
            var tc = trafficList[i];
            var wpIdx = (i * spacing + 10) % trackWaypoints.length;
            var oncoming = (i % 2 == 1);
            tc.waypointIdx = wpIdx;
            tc.isOncoming = oncoming;
            tc.currentSpeed = tc.cruiseSpeed;
            placeTrafficAgentAtWaypoint(tc, wpIdx, oncoming);
        }
    }

    /**
     * Positions a traffic vehicle onto its assigned highway lane at a waypoint index.
     *
     * @param {TrafficCar} tc Target traffic agent.
     * @param {Int} wpIdx Spline waypoint index.
     * @param {Bool} oncoming True when running reverse against player direction.
     * @returns {Void}
     */
    private function placeTrafficAgentAtWaypoint(tc:TrafficCar, wpIdx:Int, oncoming:Bool):Void {
        var wp = trackWaypoints[wpIdx];
        var nextWp = trackWaypoints[(wpIdx + 1) % trackWaypoints.length];
        scratchFwd.set(nextWp.x - wp.x, nextWp.y - wp.y, 0);
        scratchFwd.normalize();
        scratchRight.set(-scratchFwd.y, scratchFwd.x, 0);

        var offset = oncoming ? 4.8 : -4.8;
        tc.laneOffset = offset;
        tc.currentLaneOffset = offset;
        tc.pos.set(wp.x + scratchRight.x * offset, wp.y + scratchRight.y * offset, wp.z + world.Track.ROAD_LIFT);
        tc.yaw = Math.atan2(scratchFwd.y, scratchFwd.x) + (oncoming ? Math.PI : 0.0);
        if (tc.carMesh != null) {
            tc.carMesh.x = tc.pos.x;
            tc.carMesh.y = tc.pos.y;
            tc.carMesh.z = tc.pos.z;
            tc.carMesh.setRotation(0, 0, tc.yaw - 1.5707963);
        }
    }

    /**
     * Updates traffic AI speed modulation, lane obstacle avoidance, traffic-traffic separation,
     * and player collision impulse resolution.
     *
     * @param {Float} dt Delta time elapsed since last frame in seconds.
     * @param {CarPhysics} playerPhysics Active player vehicle physics instance.
     * @param {ChaseCamera} chaseCam Active chase camera instance for trauma shake injection.
     * @returns {Void}
     */
    public function update(dt:Float, playerPhysics:CarPhysics, chaseCam:ChaseCamera):Void {
        updateSpeedControl(dt);
        updateSteeringAndAvoidance(dt, playerPhysics);
        resolveTrafficMutualCollisions();
        resolvePlayerCollisions(playerPhysics, chaseCam);
    }

    /**
     * Evaluates two-car headway braking within each traffic flow stream.
     *
     * @param {Float} dt Step duration in seconds.
     * @returns {Void}
     */
    private function updateSpeedControl(dt:Float):Void {
        var followBuf = TRAFFIC_FOLLOW_BUFFER * config.defaultSpacingMultiplier;
        for (i in 0...trafficList.length) {
            var tc = trafficList[i];
            var targetSpeed = tc.cruiseSpeed;
            var fwdX = Math.cos(tc.yaw);
            var fwdY = Math.sin(tc.yaw);

            for (j in 0...trafficList.length) {
                if (i == j) continue;
                var other = trafficList[j];
                if (other.isOncoming != tc.isOncoming) continue;

                var dx = other.pos.x - tc.pos.x;
                var dy = other.pos.y - tc.pos.y;
                var dist = Math.sqrt(dx * dx + dy * dy);
                if (dist < followBuf && dist > 0.001) {
                    var dot = (dx * fwdX + dy * fwdY) / dist;
                    if (dot > 0.7) {
                        var headway = dist / followBuf;
                        targetSpeed = Math.min(targetSpeed, other.currentSpeed * (headway * 0.8));
                    }
                }
            }

            tc.currentSpeed += (targetSpeed - tc.currentSpeed) * 5.0 * dt;
            if (tc.currentSpeed < 0) tc.currentSpeed = 0;
        }
    }

    /**
     * Steers traffic cars along waypoints while dynamically swerving around player and peer traffic.
     *
     * @param {Float} dt Step duration in seconds.
     * @param {CarPhysics} playerPhysics Active player physics state.
     * @returns {Void}
     */
    private function updateSteeringAndAvoidance(dt:Float, playerPhysics:CarPhysics):Void {
        var numWaypoints = trackWaypoints.length;
        var maxOffset = config.activeHalfWidth - 2.0;

        for (tc in trafficList) {
            var targetIdx = tc.isOncoming ? (tc.waypointIdx - 1 + numWaypoints) % numWaypoints : (tc.waypointIdx + 1) % numWaypoints;
            var targetWp = trackWaypoints[targetIdx];
            var nextWp = tc.isOncoming ? trackWaypoints[(targetIdx - 1 + numWaypoints) % numWaypoints] : trackWaypoints[(targetIdx + 1) % numWaypoints];

            scratchFwd.set(nextWp.x - targetWp.x, nextWp.y - targetWp.y, 0);
            scratchFwd.normalize();
            scratchRight.set(-scratchFwd.y, scratchFwd.x, 0);

            var desiredOffset = tc.laneOffset;
            var fwdX = Math.cos(tc.yaw);
            var fwdY = Math.sin(tc.yaw);

            // Avoid oncoming or lagging player ahead within sensor cone
            var dxP = playerPhysics.pos.x - tc.pos.x;
            var dyP = playerPhysics.pos.y - tc.pos.y;
            var distP = Math.sqrt(dxP * dxP + dyP * dyP);
            if (distP < 32.0 && distP > 0.001) {
                var dotP = (dxP * fwdX + dyP * fwdY) / distP;
                if (dotP > 0.25) {
                    var sideDot = (dxP * (-fwdY) + dyP * fwdX);
                    desiredOffset += (sideDot > 0.0 ? -2.5 : 2.5);
                    if (distP < 18.0) {
                        tc.currentSpeed = Math.max(4.0, tc.currentSpeed - 14.0 * dt);
                    }
                }
            }

            // Avoid peer civilian traffic
            for (other in trafficList) {
                if (other == tc) continue;
                var dxO = other.pos.x - tc.pos.x;
                var dyO = other.pos.y - tc.pos.y;
                var distO = Math.sqrt(dxO * dxO + dyO * dyO);
                if (distO < 16.0 && distO > 0.001) {
                    var dotO = (dxO * fwdX + dyO * fwdY) / distO;
                    if (dotO > 0.5) {
                        if (other.isOncoming != tc.isOncoming) {
                            desiredOffset += (tc.isOncoming ? 2.0 : -2.0);
                        } else {
                            tc.currentSpeed = Math.min(tc.currentSpeed, other.currentSpeed * 0.85);
                        }
                    }
                }
            }

            desiredOffset = Math.max(-maxOffset, Math.min(maxOffset, desiredOffset));
            tc.currentLaneOffset += (desiredOffset - tc.currentLaneOffset) * Math.min(1.0, 4.0 * dt);

            var targetX = targetWp.x + scratchRight.x * tc.currentLaneOffset;
            var targetY = targetWp.y + scratchRight.y * tc.currentLaneOffset;
            var targetZ = targetWp.z + world.Track.ROAD_LIFT;

            var toTargetX = targetX - tc.pos.x;
            var toTargetY = targetY - tc.pos.y;
            var distToTarget = Math.sqrt(toTargetX * toTargetX + toTargetY * toTargetY);

            if (distToTarget < 9.0) tc.waypointIdx = targetIdx;
            if (distToTarget > 0.001) {
                toTargetX /= distToTarget;
                toTargetY /= distToTarget;
            }

            var targetYaw = Math.atan2(toTargetY, toTargetX);
            var yawDiff = targetYaw - tc.yaw;
            while (yawDiff > Math.PI) yawDiff -= 2.0 * Math.PI;
            while (yawDiff < -Math.PI) yawDiff += 2.0 * Math.PI;
            tc.yaw += yawDiff * Math.min(1.0, 6.0 * dt);

            var moveDist = tc.currentSpeed * dt;
            tc.pos.x += Math.cos(tc.yaw) * moveDist;
            tc.pos.y += Math.sin(tc.yaw) * moveDist;
            tc.pos.z = targetZ;

            clampToTrack(tc.pos, config.activeHalfWidth - 0.5);

            if (tc.carMesh != null) {
                tc.carMesh.x = tc.pos.x;
                tc.carMesh.y = tc.pos.y;
                tc.carMesh.z = tc.pos.z;
                tc.carMesh.setRotation(0, 0, tc.yaw - 1.5707963);
            }
        }
    }

    /**
     * Separates overlapping civilian traffic cars and dampens relative speed.
     *
     * @returns {Void}
     */
    private function resolveTrafficMutualCollisions():Void {
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
    }

    /**
     * Resolves player-to-traffic solid body overlaps and transfers impulse and camera shake.
     *
     * @param {CarPhysics} playerPhysics Active player vehicle dynamics.
     * @param {ChaseCamera} chaseCam Target camera receiving trauma feedback.
     * @returns {Void}
     */
    private function resolvePlayerCollisions(playerPhysics:CarPhysics, chaseCam:ChaseCamera):Void {
        var playerSyncNeeded = false;
        for (tc in trafficList) {
            var dx = tc.pos.x - playerPhysics.pos.x;
            var dy = tc.pos.y - playerPhysics.pos.y;
            var distSq = dx * dx + dy * dy;

            if (distSq < HIT_THRESHOLD * HIT_THRESHOLD && distSq > 0.0001) {
                var dist = Math.sqrt(distSq);
                var nx = dx / dist;
                var ny = dy / dist;
                var overlap = HIT_THRESHOLD - dist;

                playerPhysics.pos.x -= nx * overlap * 0.6;
                playerPhysics.pos.y -= ny * overlap * 0.6;
                tc.pos.x += nx * overlap * 0.4;
                tc.pos.y += ny * overlap * 0.4;

                playerPhysics.forwardSpeed *= config.collisionSpeedRetention;
                tc.currentSpeed = Math.max(tc.currentSpeed, Math.abs(playerPhysics.forwardSpeed) * 0.9);
                chaseCam.addTrauma(config.collisionTrauma);
                playerSyncNeeded = true;
            }
        }

        if (playerSyncNeeded) {
            playerPhysics.syncToOimoBody();
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
    function clampToTrack(point:Vec3, maxHalfWidth:Float):Bool {
        var proj = SplineMath.getClosestSegment(point, trackWaypoints);
        point.z = proj.z + world.Track.ROAD_LIFT;

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