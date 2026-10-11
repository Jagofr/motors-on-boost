package camera;

import h3d.Camera;
import h3d.Vector;
import physics.CarPhysics;

/**
 * Third-person spring-damped chase camera with subtle acceleration pull-back lag,
 * dynamic speed-based FOV expansion (bounded to prevent extreme distortion), and
 * toned-down, punchy collision trauma dampening.
 * Designed with zero runtime allocations in update loops.
 */
class ChaseCamera {
    /** Target 3D camera instance managed by the Heaps 3D scene renderer. */
    var cam:Camera;

    /** Current smoothed position of the camera eye point in world coordinates. */
    var currentPos:Vector = new Vector();

    /** Current smoothed focal point in world coordinates that the camera looks towards. */
    var currentTarget:Vector = new Vector();

    /** Base follow distance in meters behind the vehicle chassis at zero speed. */
    public static inline var BASE_DISTANCE:Float = 7.5;

    /** Base vertical elevation in meters above the vehicle chassis at zero speed. */
    public static inline var BASE_HEIGHT:Float = 2.8;

    /** Distance in meters ahead of the vehicle along heading vector to position the focal target. */
    public static inline var LOOK_AHEAD_DIST:Float = 6.2;

    /** Vertical offset in meters above vehicle center point for the look-ahead focal point. */
    public static inline var LOOK_AHEAD_HEIGHT:Float = 1.0;

    /** Base vertical field of view angle in degrees when stationary or cruising at low speed. */
    public static inline var BASE_FOV:Float = 65.0;

    /** Target vertical field of view angle in degrees at top speed without boost (bounded to avoid extreme distortion). */
    public static inline var MAX_SPEED_FOV:Float = 77.0;

    /** Maximum additional FOV expansion in degrees under nitrous oxide boost. */
    public static inline var BOOST_FOV_EXTRA:Float = 3.5;

    /** Maximum trauma ceiling preventing disorienting or violent screen shake. */
    public static inline var MAX_TRAUMA_CEILING:Float = 0.55;

    /** Rapid exponential decay rate per second settling trauma quickly. */
    public static inline var TRAUMA_DECAY_RATE:Float = 3.8;

    /** Current screen trauma intensity scalar in range [0.0, MAX_TRAUMA_CEILING]. */
    public var trauma:Float = 0.0;

    /** Smoothed previous frame vehicle velocity to compute acceleration pull-back. */
    var prevSpeed:Float = 0.0;

    /** Dynamic follow distance pull-back offset under acceleration in meters. */
    var accelPullBack:Float = 0.0;

    /**
     * Instantiates a new chase camera tracking controller.
     *
     * @param camera The active scene camera instance.
     * @param startX Initial X coordinate in world space.
     * @param startY Initial Y coordinate in world space.
     * @param startZ Initial Z elevation coordinate in world space.
     */
    public function new(camera:Camera, startX:Float = 0.0, startY:Float = -10.0, startZ:Float = 4.0) {
        this.cam = camera;
        this.currentPos.set(startX, startY, startZ);
        this.currentTarget.set(startX, startY + 10.0, 1.0);

        cam.pos.load(currentPos);
        cam.target.load(currentTarget);
        cam.fovY = BASE_FOV;
    }

    /**
     * Returns current camera eye position vector in world space.
     */
    public inline function getPos():Vector return currentPos;

    /**
     * Returns current focal target vector in world space.
     */
    public inline function getTarget():Vector return currentTarget;

    /**
     * Adds an impulse of impact or drift trauma to trigger rotational/translational screen shake.
     * Softened and clamped to a toned-down ceiling to avoid disorienting the player.
     *
     * @param amount Trauma intensity to inject.
     */
    public function addTrauma(amount:Float) {
        // Soften raw incoming impulse by 50% and clamp strictly to maximum ceiling
        var softened = amount * 0.50;
        trauma = Math.min(MAX_TRAUMA_CEILING, trauma + softened);
    }

    /**
     * Updates spring-arm position, controlled acceleration pull-back lag, look-ahead target vector,
     * speed-dependent dynamic FOV, and toned-down camera shake offsets.
     *
     * @param dt Delta time elapsed since last frame in seconds.
     * @param carPhysics Active vehicle physics state.
     * @param isNitroActive Boolean flag denoting if nitrous injection boost is currently active.
     */
    public function update(dt:Float, carPhysics:CarPhysics, isNitroActive:Bool) {
        if (dt <= 0.0) return;
        var clampedDt = Math.min(dt, 0.05);

        // 1. Dynamic FOV Scaling (smooth non-linear expansion bounded to avoid extreme distortion)
        var speedAbs = Math.abs(carPhysics.forwardSpeed);
        var speedRatio = Math.min(1.0, speedAbs / CarPhysics.TOP_SPEED);
        var fovProgress = Math.pow(speedRatio, 1.25);
        var targetFov = BASE_FOV + (fovProgress * (MAX_SPEED_FOV - BASE_FOV));
        if (isNitroActive && speedAbs > 10.0) {
            targetFov += BOOST_FOV_EXTRA * Math.min(1.0, speedAbs / 25.0);
        }

        // Smooth spring interpolation for FOV transition
        var fovStiffness = 7.0;
        cam.fovY += (targetFov - cam.fovY) * Math.min(1.0, fovStiffness * clampedDt);

        // 2. Controlled Acceleration & Punch Pull-Back Lag
        var currentAccel = (carPhysics.forwardSpeed - prevSpeed) / clampedDt;
        prevSpeed = carPhysics.forwardSpeed;

        var targetPullBack = 0.0;
        if (currentAccel > 1.5) {
            targetPullBack = Math.min(0.55, currentAccel * 0.02);
        }
        if (isNitroActive && speedAbs > 10.0) {
            targetPullBack += 0.35;
        }
        accelPullBack += (targetPullBack - accelPullBack) * Math.min(1.0, 5.0 * clampedDt);

        // 3. Spring-Damped Follow Distance & Dynamic Camera Orientation
        // Blend effective yaw with drift angle for natural slide framing
        var effectiveYaw = carPhysics.yaw + (carPhysics.driftAngle * 0.35);
        var fwdX = -Math.sin(effectiveYaw);
        var fwdY =  Math.cos(effectiveYaw);

        // Slight physical lagging back: base distance plus only +0.85m at maximum speed
        var dist = BASE_DISTANCE + (speedRatio * 0.85) + accelPullBack;
        var height = BASE_HEIGHT + (speedRatio * 0.20);

        // Target eye and look-at positions in world space
        var targetCamX = carPhysics.pos.x - (fwdX * dist);
        var targetCamY = carPhysics.pos.y - (fwdY * dist);
        var targetCamZ = carPhysics.pos.z + height;

        var targetLookX = carPhysics.pos.x + (fwdX * LOOK_AHEAD_DIST);
        var targetLookY = carPhysics.pos.y + (fwdY * LOOK_AHEAD_DIST);
        var targetLookZ = carPhysics.pos.z + LOOK_AHEAD_HEIGHT;

        // Velocity feedforward prevents the camera from physically lagging too far back at high speeds (200+ km/h)
        // while preserving natural spring feel during turns and direction changes
        var fwdVelX = -Math.sin(carPhysics.yaw) * carPhysics.forwardSpeed;
        var fwdVelY =  Math.cos(carPhysics.yaw) * carPhysics.forwardSpeed;
        currentPos.x += fwdVelX * clampedDt * 0.65;
        currentPos.y += fwdVelY * clampedDt * 0.65;

        // Spring-damped target follow stiffness: camPos.lerp(targetPos, dt * stiffness)
        var posStiffness = 15.0 + (speedRatio * 4.0);
        var lookStiffness = 14.0;

        currentPos.x += (targetCamX - currentPos.x) * Math.min(1.0, posStiffness * clampedDt);
        currentPos.y += (targetCamY - currentPos.y) * Math.min(1.0, posStiffness * clampedDt);
        currentPos.z += (targetCamZ - currentPos.z) * Math.min(1.0, posStiffness * clampedDt);

        currentTarget.x += (targetLookX - currentTarget.x) * Math.min(1.0, lookStiffness * clampedDt);
        currentTarget.y += (targetLookY - currentTarget.y) * Math.min(1.0, lookStiffness * clampedDt);
        currentTarget.z += (targetLookZ - currentTarget.z) * Math.min(1.0, lookStiffness * clampedDt);

        // 4. Toned-Down Punchy Screen Shake with Rapid Exponential Decay
        var shakeX = 0.0;
        var shakeY = 0.0;
        var shakeZ = 0.0;

        if (trauma > 0.001) {
            // Non-linear trauma squaring for natural perceived amplitude falloff
            var shakeStrength = trauma * trauma;
            var t = hxd.Timer.lastTimeStamp * 48.0;

            // Substantially softened peak offsets (max ~0.08m translation)
            shakeX = Math.sin(t * 1.3) * 0.09 * shakeStrength;
            shakeY = Math.cos(t * 1.7) * 0.09 * shakeStrength;
            shakeZ = Math.sin(t * 2.1) * 0.06 * shakeStrength;

            // Rapid exponential decay for crisp, punchy hits without lingering disorientation
            trauma = Math.max(0.0, trauma - TRAUMA_DECAY_RATE * clampedDt);
        }

        // Apply finalized combined coordinates to Heaps camera
        cam.pos.set(currentPos.x + shakeX, currentPos.y + shakeY, currentPos.z + shakeZ);
        cam.target.set(currentTarget.x, currentTarget.y, currentTarget.z);
    }
}