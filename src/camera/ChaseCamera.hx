package camera;

import graphics.SceneGraph.Camera3D;
import math.Vec3;
import physics.CarPhysics;

/**
 * Velocity-aligned critically-damped spring-damper 3D chase camera with dynamic speed/boost FOV,
 * subtle lateral-G cornering roll banking, quadratic trauma shake decay, and terrain floor clearance.
 *
 * @class ChaseCamera
 * @module camera/ChaseCamera
 */
class ChaseCamera {
    /** Nominal trailing chase distance behind the player vehicle in meters. */
    public static inline var BASE_DISTANCE:Float = 6.8;

    /** Nominal vertical camera elevation offset above vehicle contact plane in meters. */
    public static inline var BASE_HEIGHT:Float = 2.55;

    /** Default vertical field of view in degrees at rest. */
    public static inline var BASE_FOV:Float = 65.0;

    /** Additional progressive FOV expansion proportional to forward speed. */
    public static inline var SPEED_FOV_BONUS:Float = 10.5;

    /** Additional FOV impulse applied during nitrous boost injection. */
    public static inline var BOOST_FOV_BONUS:Float = 11.5;

    /** Maximum subtle cornering roll bank in radians (~3.2 deg) to preserve horizon readability. */
    public static inline var MAX_BANK_RAD:Float = 0.055;

    /** Minimum vertical clearance maintained above ground terrain surface in meters. */
    public static inline var MIN_GROUND_CLEARANCE:Float = 0.95;

    /** Normalized collision/bump camera shake intensity [0.0, 1.0]. */
    public var trauma:Float = 0.0;

    var cam:Camera3D;
    var camPos:Vec3;
    var camVel:Vec3;
    var lookTarget:Vec3;
    var chaseDirX:Float = 0.0;
    var chaseDirY:Float = 1.0;
    var currentFov:Float = BASE_FOV;
    var currentBank:Float = 0.0;
    var shakePhase:Float = 0.0;

    /**
     * Constructs a chase camera controller bound to the active Heaps 3D camera.
     *
     * @param {Camera} camera Active h3d.Camera scene camera instance.
     * @param {Float} startX Initial world camera X coordinate.
     * @param {Float} startY Initial world camera Y coordinate.
     * @param {Float} startZ Initial world camera Z coordinate.
     */
    public function new(camera:Camera3D, startX:Float, startY:Float, startZ:Float) {
        this.cam = camera;
        this.camPos = new Vec3(startX, startY, startZ);
        this.camVel = new Vec3(0.0, 0.0, 0.0);
        this.lookTarget = new Vec3(startX, startY + BASE_DISTANCE, startZ - 1.2);
        syncToCamera();
    }

    /**
     * Injects camera shake trauma softened cleanly for playable visual feedback and clamped [0, 1].
     *
     * @param {Float} amount Incoming raw shock trauma factor.
     */
    public function addTrauma(amount:Float):Void {
        if (amount <= 0.0 || Math.isNaN(amount)) return;
        trauma = Math.min(1.0, trauma + amount * 0.5);
    }

    /**
     * Resets chase camera smoothly behind a newly placed vehicle without transition whips.
     *
     * @param {CarPhysics} carPhysics Target player vehicle state.
     */
    public function snapBehind(carPhysics:CarPhysics):Void {
        if (carPhysics == null) return;
        var fwdX = Math.sin(carPhysics.yaw);
        var fwdY = Math.cos(carPhysics.yaw);
        chaseDirX = fwdX;
        chaseDirY = fwdY;
        camPos.set(
            carPhysics.pos.x - fwdX * BASE_DISTANCE,
            carPhysics.pos.y - fwdY * BASE_DISTANCE,
            carPhysics.pos.z + BASE_HEIGHT
        );
        camVel.set(0.0, 0.0, 0.0);
        lookTarget.set(
            carPhysics.pos.x + fwdX * 3.0,
            carPhysics.pos.y + fwdY * 3.0,
            carPhysics.pos.z + 1.15
        );
        currentFov = BASE_FOV;
        currentBank = 0.0;
        trauma = 0.0;
        syncToCamera();
    }

    /**
     * Advances velocity-aligned spring tracking, FOV response, banking, terrain clearance,
     * and quadratic trauma shake over frame delta dt.
     *
     * @param {Float} dt Elapsed frame time in seconds.
     * @param {CarPhysics} carPhysics Player vehicle physics state.
     * @param {Bool} isBoosting True while nitrous boost is actively thrusting.
     */
    public function update(dt:Float, carPhysics:CarPhysics, isBoosting:Bool):Void {
        if (carPhysics == null || dt <= 0.0 || Math.isNaN(dt)) return;
        var safeDt = dt > 0.05 ? 0.05 : dt;

        var fwdX = Math.sin(carPhysics.yaw);
        var fwdY = Math.cos(carPhysics.yaw);

        // Compute horizontal velocity direction for natural drift & corner framing
        var speed = Math.abs(carPhysics.forwardSpeed);
        var lat = carPhysics.lateralVelocity;
        var rightX = Math.cos(carPhysics.yaw);
        var rightY = -Math.sin(carPhysics.yaw);
        var worldVx = carPhysics.forwardSpeed * fwdX + lat * rightX;
        var worldVy = carPhysics.forwardSpeed * fwdY + lat * rightY;
        var horizSpeed = Math.sqrt(worldVx * worldVx + worldVy * worldVy);

        var desiredDirX = fwdX;
        var desiredDirY = fwdY;
        if (horizSpeed > 3.5 && carPhysics.forwardSpeed > -1.0) {
            // Blend velocity vector gently into chase direction (reverse keeps forward chassis view)
            var vDirX = worldVx / horizSpeed;
            var vDirY = worldVy / horizSpeed;
            var velBlend = Math.min(0.45, Math.max(0.0, (horizSpeed - 3.5) / 14.0));
            desiredDirX = fwdX * (1.0 - velBlend) + vDirX * velBlend;
            desiredDirY = fwdY * (1.0 - velBlend) + vDirY * velBlend;
            var len = Math.sqrt(desiredDirX * desiredDirX + desiredDirY * desiredDirY);
            if (len > 0.001) {
                desiredDirX /= len;
                desiredDirY /= len;
            }
        }

        // Smooth angular chase direction tracking
        var dirAlpha = 1.0 - Math.exp(-7.5 * safeDt);
        chaseDirX += (desiredDirX - chaseDirX) * dirAlpha;
        chaseDirY += (desiredDirY - chaseDirY) * dirAlpha;
        var cdLen = Math.sqrt(chaseDirX * chaseDirX + chaseDirY * chaseDirY);
        if (cdLen > 0.001) {
            chaseDirX /= cdLen;
            chaseDirY /= cdLen;
        }

        // Dynamic distance and slope-adaptive elevation
        var targetDist = BASE_DISTANCE + Math.min(1.5, speed * 0.022) + (isBoosting ? 0.75 : 0.0);
        var pitchLift = clampF(-Math.sin(carPhysics.pitch) * 1.1, -0.45, 0.90);
        var idealX = carPhysics.pos.x - chaseDirX * targetDist;
        var idealY = carPhysics.pos.y - chaseDirY * targetDist;
        var idealZ = carPhysics.pos.z + BASE_HEIGHT + pitchLift;

        // Enforce ground terrain clearance behind the vehicle on steep climbs
        if (carPhysics.groundProvider != null) {
            var terrainZ = carPhysics.groundProvider.getGroundElevation(idealX, idealY);
            if (idealZ < terrainZ + MIN_GROUND_CLEARANCE) {
                idealZ = terrainZ + MIN_GROUND_CLEARANCE;
            }
        }

        // Critically damped SmoothDamp position spring tracking
        camPos.x = smoothDamp(camPos.x, idealX, safeDt, 0.09, 0);
        camPos.y = smoothDamp(camPos.y, idealY, safeDt, 0.09, 1);
        camPos.z = smoothDamp(camPos.z, idealZ, safeDt, 0.11, 2);

        if (carPhysics.groundProvider != null) {
            var camGroundZ = carPhysics.groundProvider.getGroundElevation(camPos.x, camPos.y);
            if (camPos.z < camGroundZ + MIN_GROUND_CLEARANCE * 0.75) {
                camPos.z = camGroundZ + MIN_GROUND_CLEARANCE * 0.75;
            }
        }

        // Dynamic look-ahead target ahead of vehicle nose
        var lookAhead = 2.6 + Math.min(3.5, speed * 0.055);
        var targetX = carPhysics.pos.x + chaseDirX * lookAhead;
        var targetY = carPhysics.pos.y + chaseDirY * lookAhead;
        var targetZ = carPhysics.pos.z + 1.15 + Math.sin(carPhysics.pitch) * 0.8;
        var tgtAlpha = 1.0 - Math.exp(-14.0 * safeDt);
        lookTarget.x += (targetX - lookTarget.x) * tgtAlpha;
        lookTarget.y += (targetY - lookTarget.y) * tgtAlpha;
        lookTarget.z += (targetZ - lookTarget.z) * tgtAlpha;

        // Speed & boost FOV response
        var speedRatio = Math.min(1.0, speed / 70.0);
        var targetFov = BASE_FOV + speedRatio * SPEED_FOV_BONUS + (isBoosting ? BOOST_FOV_BONUS : 0.0);
        currentFov += (targetFov - currentFov) * (1.0 - Math.exp(-6.0 * safeDt));

        // Subtle bounded lateral-G banking matching vehicle turn feel
        var targetBank = clampF(-carPhysics.yawRate * 0.032 + carPhysics.roll * 0.18, -MAX_BANK_RAD, MAX_BANK_RAD);
        currentBank += (targetBank - currentBank) * (1.0 - Math.exp(-8.0 * safeDt));

        // Exponential trauma decay and quadratic shake offsets
        shakePhase += safeDt * 42.0;
        var shakeAmp = trauma * trauma * 0.42;
        if (trauma > 0.0) {
            trauma = Math.max(0.0, trauma - safeDt * 1.45);
        }

        syncToCamera(shakeAmp);
    }

    function syncToCamera(shakeAmp:Float = 0.0):Void {
        if (cam == null) return;
        var offX = shakeAmp > 0.0001 ? Math.sin(shakePhase * 1.37) * shakeAmp : 0.0;
        var offY = shakeAmp > 0.0001 ? Math.cos(shakePhase * 1.91) * shakeAmp * 0.6 : 0.0;
        var offZ = shakeAmp > 0.0001 ? Math.sin(shakePhase * 2.43) * shakeAmp * 0.85 : 0.0;

        cam.pos.set(camPos.x + offX, camPos.y + offY, camPos.z + offZ);
        cam.target.set(lookTarget.x + offX * 0.4, lookTarget.y + offY * 0.4, lookTarget.z + offZ * 0.5);
        cam.fovY = currentFov;

        // Apply subtle camera up-vector roll bank perpendicular to chase view direction
        var rightX = chaseDirY;
        var rightY = -chaseDirX;
        var sb = Math.sin(currentBank);
        var cb = Math.cos(currentBank);
        cam.up.set(rightX * sb, rightY * sb, cb);
    }

    function smoothDamp(current:Float, target:Float, dt:Float, smoothTime:Float, axisIdx:Int):Float {
        var st = smoothTime < 0.01 ? 0.01 : smoothTime;
        var omega = 2.0 / st;
        var x = omega * dt;
        var exp = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x);

        var vel = axisIdx == 0 ? camVel.x : (axisIdx == 1 ? camVel.y : camVel.z);
        var change = current - target;
        var temp = (vel + omega * change) * dt;
        vel = (vel - omega * temp) * exp;
        var output = target + (change + temp) * exp;

        if ((target - current > 0.0) == (output > target)) {
            output = target;
            vel = (output - target) / dt;
        }

        if (axisIdx == 0) camVel.x = vel;
        else if (axisIdx == 1) camVel.y = vel;
        else camVel.z = vel;
        return output;
    }

    static inline function clampF(v:Float, lo:Float, hi:Float):Float {
        return v < lo ? lo : (v > hi ? hi : v);
    }
}
