package physics;

import h3d.Vector;
import input.InputController;

class CarPhysics {
    public var pos:Vector = new Vector();
    public var yaw:Float = 1.5707963;
    public var pitch:Float = 0.0;
    public var roll:Float = 0.0;

    public var forwardSpeed:Float = 0.0;
    public var lateralVelocity:Float = 0.0;

    public var isDrifting:Bool = false;
    public var driftDirection:Float = 0.0;
    public var driftAngle:Float = 0.0;

    static inline var TOP_SPEED:Float = 68.0;          // ~245 km/h
    static inline var BOOST_TOP_SPEED:Float = 88.0;    // ~316 km/h
    static inline var ACCELERATION:Float = 28.0;
    static inline var BOOST_ACCEL:Float = 48.0;
    static inline var BRAKING:Float = 38.0;
    static inline var REVERSE_TOP_SPEED:Float = 18.0;

    static inline var DRAG_COEFF:Float = 0.0035;
    static inline var ROLLING_RESISTANCE:Float = 2.2;

    static inline var STEER_AUTHORITY:Float = 2.2;
    static inline var DRIFT_YAW_RATE:Float = 3.2;
    static inline var DRIFT_STICKINESS:Float = 0.88;

    public function new(startX:Float = 0.0, startY:Float = 0.0, startZ:Float = 0.0) {
        pos.set(startX, startY, startZ);
    }

    public function update(dt:Float, input:InputController) {
        var maxSpeed = input.boost ? BOOST_TOP_SPEED : TOP_SPEED;
        var accelRate = input.boost ? BOOST_ACCEL : ACCELERATION;

        // 1. Longitudinal Acceleration & Braking
        if (input.throttle > 0.0) {
            if (forwardSpeed < maxSpeed) {
                forwardSpeed += accelRate * input.throttle * dt;
            }
        } else if (input.brake > 0.0) {
            if (forwardSpeed > 0.5) {
                forwardSpeed = Math.max(0.0, forwardSpeed - BRAKING * input.brake * dt);
            } else {
                forwardSpeed = Math.max(-REVERSE_TOP_SPEED, forwardSpeed - (ACCELERATION * 0.5) * input.brake * dt);
            }
        } else {
            var sign = forwardSpeed > 0 ? 1.0 : -1.0;
            var decel = (ROLLING_RESISTANCE + (forwardSpeed * forwardSpeed * DRAG_COEFF)) * dt;
            if (Math.abs(forwardSpeed) <= decel) {
                forwardSpeed = 0.0;
            } else {
                forwardSpeed -= sign * decel;
            }
        }

        // 2. Brake-to-Drift Entry & Exit
        var speedRatio = Math.abs(forwardSpeed) / TOP_SPEED;
        var driftTrigger = (input.handbrake || (input.brake > 0.2 && input.throttle > 0.1)) && Math.abs(input.steer) > 0.25;

        if (!isDrifting && driftTrigger && forwardSpeed > 14.0) {
            isDrifting = true;
            driftDirection = input.steer < 0 ? -1.0 : 1.0;
        }

        if (isDrifting) {
            if (forwardSpeed < 10.0 || (driftDirection > 0 && input.steer < -0.6) || (driftDirection < 0 && input.steer > 0.6)) {
                isDrifting = false;
            }
        }

        // 3. Slip Angle & Yaw Calculations
        if (isDrifting) {
            var targetAngle = driftDirection * 0.65;
            driftAngle += (targetAngle - driftAngle) * 5.0 * dt;
            yaw += (driftDirection * DRIFT_YAW_RATE + input.steer * 1.5) * dt;

            lateralVelocity += driftDirection * 15.0 * dt;
            lateralVelocity *= Math.pow(DRIFT_STICKINESS, dt * 60.0);
        } else {
            driftAngle += (0.0 - driftAngle) * 10.0 * dt;
            lateralVelocity *= Math.pow(0.5, dt * 60.0);

            if (Math.abs(forwardSpeed) > 0.2) {
                var steerFactor = input.steer * STEER_AUTHORITY * Math.min(1.0, speedRatio + 0.35);
                var fwdSign = forwardSpeed >= 0 ? 1.0 : -1.0;
                yaw += steerFactor * fwdSign * dt;
            }
        }

        // 4. World Position Integration
        var fwdX = -Math.sin(yaw);
        var fwdY =  Math.cos(yaw);
        var rightX =  Math.cos(yaw);
        var rightY =  Math.sin(yaw);

        pos.x += (fwdX * forwardSpeed + rightX * lateralVelocity) * dt;
        pos.y += (fwdY * forwardSpeed + rightY * lateralVelocity) * dt;

        // 5. Weight Transfer Roll & Pitch
        var targetRoll = -input.steer * Math.min(1.0, speedRatio) * 0.12;
        if (isDrifting) targetRoll *= 1.8;
        roll += (targetRoll - roll) * 8.0 * dt;

        var targetPitch = (input.throttle - input.brake) * 0.06;
        pitch += (targetPitch - pitch) * 8.0 * dt;
    }
}