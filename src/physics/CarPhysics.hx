package physics;

import h3d.Vector;
import input.InputController;

/**
 * Longitudinal, lateral, and brake-to-drift handling simulation for player vehicle.
 * Implements arcade-sim handling characteristics inspired by Need for Speed: Most Wanted (2005)
 * and Burnout Revenge, featuring raycast suspension approximations, weight transfer,
 * lateral slip curves, and aerodynamic drag damping.
 */
class CarPhysics {
    /** World position of the vehicle chassis center point. */
    public var pos:Vector = new Vector();

    /** Yaw orientation in radians (rotation about Z-axis). */
    public var yaw:Float = 1.5707963;

    /** Dynamic chassis pitch in radians representing acceleration squat and braking dive. */
    public var pitch:Float = 0.0;

    /** Dynamic chassis body roll in radians representing lateral centrifugal weight transfer. */
    public var roll:Float = 0.0;

    /** Forward longitudinal velocity along vehicle heading vector in m/s. */
    public var forwardSpeed:Float = 0.0;

    /** Lateral slip velocity perpendicular to vehicle forward heading in m/s. */
    public var lateralVelocity:Float = 0.0;

    /** Flag indicating whether the rear tires have exceeded lateral adhesion threshold into a drift. */
    public var isDrifting:Bool = false;

    /** Sign multiplier of drift orientation (-1.0 for leftward yaw bias, +1.0 for rightward yaw bias). */
    public var driftDirection:Float = 0.0;

    /** Visual vehicle body slip angle offset relative to velocity direction in radians. */
    public var driftAngle:Float = 0.0;

    /** Base maximum forward speed achievable under standard engine throttle (~245 km/h). */
    public static inline var TOP_SPEED:Float = 68.0;

    /** Absolute maximum forward speed ceiling while nitrous oxide injection is active (~316 km/h). */
    public static inline var BOOST_TOP_SPEED:Float = 88.0;

    /** Longitudinal engine torque acceleration rate in m/s². */
    public static inline var ACCELERATION:Float = 28.0;

    /** Nitrous oxide forward acceleration rate in m/s². */
    public static inline var BOOST_ACCEL:Float = 48.0;

    /** Mechanical service brake deceleration rate in m/s². */
    public static inline var BRAKING:Float = 38.0;

    /** Maximum reverse gear velocity limit in m/s (~65 km/h). */
    public static inline var REVERSE_TOP_SPEED:Float = 18.0;

    /** Aerodynamic quadratic drag coefficient (Fd = v² * dragCoeff). */
    public static inline var DRAG_COEFF:Float = 0.0035;

    /** Constant rolling resistance deceleration representing ground friction in m/s². */
    public static inline var ROLLING_RESISTANCE:Float = 2.2;

    /** Baseline cornering steering rack responsiveness factor at normal speeds. */
    public static inline var STEER_AUTHORITY:Float = 2.2;

    /** Rotational angular velocity rate during an active drift slide in rad/s. */
    public static inline var DRIFT_YAW_RATE:Float = 3.2;

    /** Lateral momentum retention damping multiplier applied per 60Hz frame tick during drifts. */
    public static inline var DRIFT_STICKINESS:Float = 0.88;

    /**
     * Constructs a new vehicle physics simulation instance at specified initial coordinates.
     *
     * @param startX Initial X coordinate in world space.
     * @param startY Initial Y coordinate in world space.
     * @param startZ Initial Z elevation coordinate in world space.
     */
    public function new(startX:Float = 0.0, startY:Float = 0.0, startZ:Float = 0.0) {
        pos.set(startX, startY, startZ);
    }

    /**
     * Advances the vehicle dynamics simulation by a delta time step.
     * Evaluates longitudinal power delivery, brake-to-drift state transitions,
     * lateral tire slip, world position integration, and visual chassis roll/pitch settling.
     *
     * @param dt Delta time elapsed since previous frame in seconds.
     * @param input Active controller or touch input readings.
     */
    public function update(dt:Float, input:InputController) {
        // Evaluate dynamic speed and acceleration limits based on boost injection state
        var maxSpeed = input.boost ? BOOST_TOP_SPEED : TOP_SPEED;
        var accelRate = input.boost ? BOOST_ACCEL : ACCELERATION;

        // 1. Longitudinal Acceleration & Braking Simulation
        if (input.throttle > 0.0) {
            // Forward engine acceleration clamped to terminal velocity
            if (forwardSpeed < maxSpeed) {
                forwardSpeed += accelRate * input.throttle * dt;
            }
        } else if (input.brake > 0.0) {
            // Progressive braking transitioning into reverse propulsion once halted
            if (forwardSpeed > 0.5) {
                forwardSpeed = Math.max(0.0, forwardSpeed - BRAKING * input.brake * dt);
            } else {
                forwardSpeed = Math.max(-REVERSE_TOP_SPEED, forwardSpeed - (ACCELERATION * 0.5) * input.brake * dt);
            }
        } else {
            // Coasting resistance: combines constant rolling friction and quadratic aerodynamic drag
            var sign = forwardSpeed > 0 ? 1.0 : -1.0;
            var decel = (ROLLING_RESISTANCE + (forwardSpeed * forwardSpeed * DRAG_COEFF)) * dt;
            if (Math.abs(forwardSpeed) <= decel) {
                forwardSpeed = 0.0;
            } else {
                forwardSpeed -= sign * decel;
            }
        }

        // 2. Brake-to-Drift Entry & Exit Threshold Evaluation
        var speedRatio = Math.abs(forwardSpeed) / TOP_SPEED;
        var driftTrigger = (input.handbrake || (input.brake > 0.2 && input.throttle > 0.1)) && Math.abs(input.steer) > 0.25;

        // Initiate drift when handbrake or tap-brake turn is engaged at moderate speed (>50 km/h)
        if (!isDrifting && driftTrigger && forwardSpeed > 14.0) {
            isDrifting = true;
            driftDirection = input.steer < 0 ? -1.0 : 1.0;
        }

        // Exit drift if vehicle drops below critical slide speed or countersteer is vigorously applied
        if (isDrifting) {
            if (forwardSpeed < 10.0 || (driftDirection > 0 && input.steer < -0.6) || (driftDirection < 0 && input.steer > 0.6)) {
                isDrifting = false;
            }
        }

        // 3. Slip Angle & Yaw Integration
        if (isDrifting) {
            // Target slip angle orientation biased towards slide direction
            var targetAngle = driftDirection * 0.65;
            driftAngle += (targetAngle - driftAngle) * 5.0 * dt;
            yaw += (driftDirection * DRIFT_YAW_RATE + input.steer * 1.5) * dt;

            // Lateral velocity injection damped by drift stickiness factor
            lateralVelocity += driftDirection * 15.0 * dt;
            lateralVelocity *= Math.pow(DRIFT_STICKINESS, dt * 60.0);
        } else {
            // Re-align visual chassis slip angle back towards vehicle centerline
            driftAngle += (0.0 - driftAngle) * 10.0 * dt;
            lateralVelocity *= Math.pow(0.5, dt * 60.0);

            // Standard Ackermann cornering authority scaled with speed ratio
            if (Math.abs(forwardSpeed) > 0.2) {
                var steerFactor = input.steer * STEER_AUTHORITY * Math.min(1.0, speedRatio + 0.35);
                var fwdSign = forwardSpeed >= 0 ? 1.0 : -1.0;
                yaw += steerFactor * fwdSign * dt;
            }
        }

        // 4. World Coordinate Position Integration
        var fwdX = -Math.sin(yaw);
        var fwdY =  Math.cos(yaw);
        var rightX =  Math.cos(yaw);
        var rightY =  Math.sin(yaw);

        pos.x += (fwdX * forwardSpeed + rightX * lateralVelocity) * dt;
        pos.y += (fwdY * forwardSpeed + rightY * lateralVelocity) * dt;

        // 5. Weight Transfer Body Roll & Pitch Suspension Simulation
        var targetRoll = -input.steer * Math.min(1.0, speedRatio) * 0.12;
        if (isDrifting) targetRoll *= 1.8;
        roll += (targetRoll - roll) * 8.0 * dt;

        var targetPitch = (input.throttle - input.brake) * 0.06;
        pitch += (targetPitch - pitch) * 8.0 * dt;
    }
}