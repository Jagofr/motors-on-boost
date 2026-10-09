package camera;

import h3d.Camera;
import h3d.Vector;
import physics.CarPhysics;

/**
 * Third-person spring-damped chase camera with acceleration pull-back,
 * velocity-dependent FOV dilation, and toned-down, punchy collision trauma dampening.
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
    static inline var BASE_DISTANCE:Float = 8.8;

    /** Base vertical elevation in meters above the vehicle chassis at zero speed. */
    static inline var BASE_HEIGHT:Float = 3.2;

    /** Distance in meters ahead of the vehicle along heading vector to position the focal target. */
    static inline var LOOK_AHEAD_DIST:Float = 6.5;

    /** Vertical offset in meters above vehicle center point for the look-ahead focal point. */
    static inline var LOOK_AHEAD_HEIGHT:Float = 1.0;

    /** Base vertical field of view angle in degrees when cruising at low speed. */
    static inline var BASE_FOV:Float = 65.0;

    /** Target vertical field of view angle in degrees at top speed. */
    static inline var MAX_SPEED_FOV:Float = 85.0;

    /** Maximum additional FOV expansion under nitrous oxide boost. */
    static inline var BOOST_FOV_EXTRA:Float = 5.0;

    /** Maximum trauma ceiling preventing disorienting or violent screen shake. */
    static inline var MAX_TRAUMA_CEILING:Float = 0.55;

    /** Rapid exponential decay rate per second settling trauma quickly. */
    static inline var TRAUMA_DECAY_RATE:Float = 3.8;

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
     * Updates spring-arm position, acceleration pull-back lag, look-ahead target vector,
     * speed-dependent dynamic FOV, and toned-down camera shake offsets.
     *
     * @param dt Delta time elapsed since last frame in seconds.
     * @param carPhysics Active vehicle physics state.
     * @param isNitroActive Boolean flag denoting if nitrous injection boost is currently active.
     */
    public function update(dt:Float, carPhysics:CarPhysics, isNitroActive:Bool) {
        if (dt <= 0.0) return;
        var clampedDt = Math.min(dt, 0.05);

        // 1. Dynamic FOV Scaling (65° base smoothly scaling up to 85° at top speed)
        var speedAbs = Math.abs(carPhysics.forwardSpeed);
        var speedRatio = Math.min(1.0, speedAbs / CarPhysics.TOP_SPEED);
        var targetFov = BASE_FOV + (speedRatio * (MAX_SPEED_FOV - BASE_FOV));
        if (isNitroActive) targetFov += BOOST_FOV_EXTRA;

        // Smooth spring interpolation for FOV transition
        var fovStiffness = 7.5;
        cam.fovY += (targetFov - cam.fovY) * Math.min(1.0, fovStiffness * clampedDt);

        // 2. Acceleration Pull-Back Lag
        var currentAccel = (carPhysics.forwardSpeed - prevSpeed) / clampedDt;
        prevSpeed = carPhysics.forwardSpeed;

        var targetPullBack = 0.0;
        if (currentAccel > 2.0) {
            targetPullBack = Math.min(2.5, currentAccel * 0.06);
        }
        if (isNitroActive && speedAbs > 15.0) {
            targetPullBack += 1.2;
        }
        accelPullBack += (targetPullBack - accelPullBack) * Math.min(1.0, 5.0 * clampedDt);

        // 3. Spring-Damped Follow Distance & Dynamic Camera Orientation
        var effectiveYaw = carPhysics.yaw + (carPhysics.driftAngle * 0.40);
        var fwdX = -Math.sin(effectiveYaw);
        var fwdY =  Math.cos(effectiveYaw);

        // Expand follow distance with forward speed and acceleration pull-back
        var dist = BASE_DISTANCE + (speedRatio * 1.5) + accelPullBack;
        var height = BASE_HEIGHT + (speedRatio * 0.35);

        // Target eye and look-at positions in world space
        var targetCamX = carPhysics.pos.x - (fwdX * dist);
        var targetCamY = carPhysics.pos.y - (fwdY * dist);
        var targetCamZ = carPhysics.pos.z + height;

        var targetLookX = carPhysics.pos.x + (fwdX * LOOK_AHEAD_DIST);
        var targetLookY = carPhysics.pos.y + (fwdY * LOOK_AHEAD_DIST);
        var targetLookZ = carPhysics.pos.z + LOOK_AHEAD_HEIGHT;

        // Spring-damped target follow stiffness: camPos.lerp(targetPos, dt * stiffness)
        var posStiffness = 8.5;
        var lookStiffness = 12.0;

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