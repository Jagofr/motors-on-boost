package entities;

import h3d.scene.Object;
import h3d.Vector;
import physics.CarPhysics;
import physics.SplineMath;
import core.ChaseCamera;

class TrafficCar {
    public var carMesh:TrafficCarMesh;
    public var pos:Vector = new Vector();
    public var yaw:Float = 0.0;
    public var cruiseSpeed:Float = 17.0;
    public var currentSpeed:Float = 17.0;
    public var waypointIdx:Int = 0;
    public var isOncoming:Bool = false;

    public function new(mesh:TrafficCarMesh, startWp:Int, oncoming:Bool = false, speed:Float = 17.0) {
        this.carMesh = mesh;
        this.waypointIdx = startWp;
        this.isOncoming = oncoming;
        this.cruiseSpeed = speed;
        this.currentSpeed = speed;
    }
}

class TrafficSystem extends Object {
    public var trafficList:Array<TrafficCar> = [];
    var trackWaypoints:Array<Vector>;

    public static inline var ACTIVE_HALF_WIDTH:Float = 9.7;
    static inline var MAX_SPEED_CAP:Float = 95.0;

    static inline var PLAYER_RADIUS:Float = 1.6;
    static inline var TRAFFIC_RADIUS:Float = 1.5;
    static inline var HIT_THRESHOLD:Float = PLAYER_RADIUS + TRAFFIC_RADIUS;
    static inline var TRAFFIC_HIT_THRESHOLD:Float = TRAFFIC_RADIUS * 2.0;

    static inline var TRAFFIC_FOLLOW_BUFFER:Float = 10.0;
    static inline var WALL_STICKINESS:Float = 0.94;

    public function new(trackWaypoints:Array<Vector>, ?parent:Object) {
        super(parent);
        this.trackWaypoints = trackWaypoints;
        spawnTrafficFleet();
    }

    function spawnTrafficFleet() {
        var carColors = [0x2A52BE, 0x8B7355, 0x2E6F40, 0x8B2500, 0xD0D7DE];
        var spacing = 24;
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

            // Left-hand traffic rule: Same-direction = left (-4.8m), Oncoming = right (+4.8m)
            var laneOffset = oncoming ? 4.8 : -4.8;
            tc.pos.set(wp.x + right.x * laneOffset, wp.y + right.y * laneOffset, wp.z);
            tc.yaw = Math.atan2(fwd.y, fwd.x) + (oncoming ? Math.PI : 0.0);

            trafficList.push(tc);
        }
    }

    public function update(dt:Float, playerPhysics:CarPhysics, chaseCam:ChaseCamera) {
        var numWaypoints = trackWaypoints.length;

        // 1. Autonomous Traffic Spacing AI
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

                if (dist < TRAFFIC_FOLLOW_BUFFER && dist > 0.001) {
                    var dot = (dx * fwdX + dy * fwdY) / dist;
                    if (dot > 0.7) {
                        var headway = dist / TRAFFIC_FOLLOW_BUFFER;
                        targetSpeed = Math.min(targetSpeed, other.currentSpeed * (headway * 0.8));
                    }
                }
            }

            tc.currentSpeed += (targetSpeed - tc.currentSpeed) * 5.0 * dt;
            if (tc.currentSpeed < 0) tc.currentSpeed = 0;
        }

        // 2. Traffic Movement along Assigned Lanes
        for (tc in trafficList) {
            var targetIdx = tc.isOncoming ? (tc.waypointIdx - 1 + numWaypoints) % numWaypoints : (tc.waypointIdx + 1) % numWaypoints;
            var targetWp = trackWaypoints[targetIdx];
            var dir = targetWp.sub(tc.pos);
            dir.z = 0;

            if (dir.length() < 8.0) tc.waypointIdx = targetIdx;

            dir.normalize();
            tc.pos.x += dir.x * tc.currentSpeed * dt;
            tc.pos.y += dir.y * tc.currentSpeed * dt;
            tc.yaw = Math.atan2(dir.y, dir.x);

            clampToTrack(tc.pos, ACTIVE_HALF_WIDTH - 0.5);

            tc.carMesh.x = tc.pos.x;
            tc.carMesh.y = tc.pos.y;
            tc.carMesh.z = tc.pos.z;
            tc.carMesh.setRotation(0, 0, tc.yaw - 1.5707963);
        }

        // 3. Traffic-to-Traffic Hard Separation
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

        // 4. Solid Player-to-Traffic Collisions
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

                var pFwdX = -Math.sin(playerPhysics.yaw);
                var pFwdY =  Math.cos(playerPhysics.yaw);
                var dotApproach = pFwdX * nx + pFwdY * ny;

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

        // 5. Guardrail Boundary Clamping
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

    function clampToTrack(point:Vector, maxHalfWidth:Float):Bool {
        var proj = SplineMath.getClosestSegment(point, trackWaypoints);
        point.z = proj.z;

        var lateralDist = Math.sqrt(proj.distSq);
        if (lateralDist > maxHalfWidth && lateralDist > 0.001) {
            var fromCenter = point.sub(proj.centerPoint);
            fromCenter.z = 0;
            fromCenter.normalize();

            point.x = proj.centerPoint.x + fromCenter.x * maxHalfWidth;
            point.y = proj.centerPoint.y + fromCenter.y * maxHalfWidth;
            return true;
        }

        return false;
    }
}