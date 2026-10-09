package camera;

import h3d.Camera;
import h3d.Vector;
import physics.CarPhysics;

/**
 * Third-person spring-arm chase camera system.
 * Features velocity look-ahead targeting, speed-dependent field of view (FOV) dilation,
 * and non-linear trauma screen shake damping for tactile high-speed immersion.
 */
class ChaseCamera {
    /** Target 3D camera instance managed by the Heaps 3D scene renderer. */
    var cam:Camera;

    /** Current smoothed position of the camera eye point in world coordinates. */
    var currentPos:Vector = new Vector();

    /** Current smoothed focal point in world coordinates that the camera looks towards. */
    var currentTarget:Vector = new Vector();

    /** Base follow distance in meters behind the vehicle chassis at zero speed. */
    static inline var BASE_DISTANCE:Float = 9.2;

    /** Base vertical elevation in meters above the vehicle chassis at zero speed. */
    static inline var BASE_HEIGHT:Float = 3.4;

    /** Distance in meters ahead of the vehicle along heading vector to position the focal target. */
    static inline var LOOK_AHEAD_DIST:Float = 6.0;

    /** Vertical offset in meters above vehicle center point for the look-ahead focal point. */
    static inline var LOOK_AHEAD_HEIGHT:Float = 1.0;

    /** Default vertical field of view angle in degrees when idling or cruising at low speed. */
    static inline var BASE_FOV:Float = 52.0;

    /** Maximum additional FOV expansion kicked in at terminal vehicle speed. */
    static inline var MAX_FOV_KICK:Float = 22.0;

    /** Current screen trauma intensity scalar in range [0.0, 1.0] used to drive camera shake. */
    public var trauma:Float = 0.0;

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
     * Value is clamped to a maximum ceiling of 1.0.
     *
     * @param amount Trauma intensity to inject [0.0 - 1.0].
     */
    public function addTrauma(amount:Float) {
        trauma = Math.min(1.0, trauma + amount);
    }

    /**
     * Updates spring-arm position, look-ahead target vector, FOV dilation, and shake offsets.
     *
     * @param dt Delta time elapsed since last frame in seconds.
     * @param carPhysics Active vehicle physics state.
     * @param isNitroActive Boolean flag denoting if nitrous injection boost is currently active.
     */
    public function update(dt:Float, carPhysics:CarPhysics, isNitroActive:Bool) {
        // Calculate normalized velocity ratio [0, 1] relative to top speed
        var speedRatio = Math.min(1.0, Math.abs(carPhysics.forwardSpeed) / 75.0);

        // Dynamically dilate camera FOV for speed perception, adding extra kick under nitrous oxide
        var targetFov = BASE_FOV + (speedRatio * MAX_FOV_KICK);
        if (isNitroActive) targetFov += 5.0;
        cam.fovY += (targetFov - cam.fovY) * Math.min(1.0, 6.0 * dt);

        // Calculate vehicle orientation including chassis drift slip angle offset
        var effectiveYaw = carPhysics.yaw + (carPhysics.driftAngle * 0.45);
        var fwdX = -Math.sin(effectiveYaw);
        var fwdY =  Math.cos(effectiveYaw);

        // Expand follow distance and elevation proportionally with speed
        var dist = BASE_DISTANCE + (speedRatio * 1.8);
        var height = BASE_HEIGHT + (speedRatio * 0.4);

        // Determine ideal target eye and look-at positions
        var targetCamX = carPhysics.pos.x - (fwdX * dist);
        var targetCamY = carPhysics.pos.y - (fwdY * dist);
        var targetCamZ = carPhysics.pos.z + height;

        var targetLookX = carPhysics.pos.x + (fwdX * LOOK_AHEAD_DIST);
        var targetLookY = carPhysics.pos.y + (fwdY * LOOK_AHEAD_DIST);
        var targetLookZ = carPhysics.pos.z + LOOK_AHEAD_HEIGHT;

        // Exponential smoothing damping factors
        var posLerp = Math.min(1.0, 8.5 * dt);
        var lookLerp = Math.min(1.0, 12.0 * dt);

        currentPos.x += (targetCamX - currentPos.x) * posLerp;
        currentPos.y += (targetCamY - currentPos.y) * posLerp;
        currentPos.z += (targetCamZ - currentPos.z) * posLerp;

        currentTarget.x += (targetLookX - currentTarget.x) * lookLerp;
        currentTarget.y += (targetLookY - currentTarget.y) * lookLerp;
        currentTarget.z += (targetLookZ - currentTarget.z) * lookLerp;

        // Compute high-frequency screen shake based on non-linear squared trauma
        var shakeX = 0.0;
        var shakeY = 0.0;
        var shakeZ = 0.0;

        if (trauma > 0.001) {
            var shakeStrength = trauma * trauma;
            var t = hxd.Timer.lastTimeStamp * 45.0;

            shakeX = Math.sin(t * 1.3) * 0.28 * shakeStrength;
            shakeY = Math.cos(t * 1.7) * 0.28 * shakeStrength;
            shakeZ = Math.sin(t * 2.1) * 0.22 * shakeStrength;

            // Decay trauma over time
            trauma = Math.max(0.0, trauma - 1.8 * dt);
        }

        // Apply final combined positions to Heaps camera
        cam.pos.set(currentPos.x + shakeX, currentPos.y + shakeY, currentPos.z + shakeZ);
        cam.target.set(currentTarget.x, currentTarget.y, currentTarget.z);
    }
}