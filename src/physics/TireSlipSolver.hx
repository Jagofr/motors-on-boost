package physics;

import entities.CarMesh;
import physics.CarConfig;
import physics.SuspensionSolver;

/**
 * Aggregated tire traction result acting in chassis horizontal plane (Forward, Right, Yaw).
 *
 * @typedef {Object} TireForceResult
 */
typedef TireForceResult = {
    var forceFwd:Float;
    var forceRight:Float;
    var yawTorque:Float;
    var frontSteerAngle:Float;
    var lateralSlipAngle:Float;
    var isStictionActive:Bool;
}

/**
 * Computes longitudinal axle weight transfer, speed-blended Ackermann wheel angles,
 * relaxation-length filtered slip angles, Pacejka Magic Formula lateral forces,
 * combined Friction Circle clamping, and zero-creep low-speed stiction holding.
 *
 * Strictly follows project heading convention:
 * - steerInput < 0 -> Left turn (wheels angle toward -Right, producing negative yawRate)
 * - steerInput > 0 -> Right turn (wheels angle toward +Right, producing positive yawRate)
 *
 * @class TireSlipSolver
 * @module physics/TireSlipSolver
 */
class TireSlipSolver {
    var smoothedSlip:Array<Float>;

    /**
     * Constructs a tire solver preserving per-wheel relaxation-length slip memory.
     */
    public function new() {
        smoothedSlip = [0.0, 0.0, 0.0, 0.0];
    }

    /**
     * Clears stored slip angle relaxation memory upon reset.
     */
    public function reset():Void {
        for (i in 0...4) smoothedSlip[i] = 0.0;
    }

    /**
     * Computes net horizontal forces and yaw moment across all 4 grounded tire patches.
     *
     * @param {Float} dt Fixed physics sub-step in seconds.
     * @param {VehicleConfigData} cfg Validated vehicle tuning config.
     * @param {Array<WheelContact>} wheels 4-wheel suspension contact records [FL, FR, RL, RR].
     * @param {Float} vLong Chassis speed along horizontal forward axis (m/s).
     * @param {Float} vLat Chassis speed along horizontal right axis (m/s).
     * @param {Float} yawRate Current heading angular velocity in rad/s (+ = turning Right).
     * @param {Float} steerInput Conditioned steering input in [-1.0, +1.0] (- = Left, + = Right).
     * @param {Float} driveForce Net engine/boost longitudinal force (N).
     * @param {Float} brakeForce Magnitude of service braking force (N).
     * @param {Bool} handbrake True when handbrake locks rear lateral grip.
     * @param {Float} longAccel Previous step longitudinal acceleration (m/s^2) for weight transfer.
     * @param {Float} slopeFwdSin Sine of road pitch angle along forward axis for stiction compensation.
     * @param {Float} slopeRightSin Sine of road roll angle along right axis for stiction compensation.
     * @param {Float} gravityMag Positive gravity magnitude (m/s^2).
     * @returns {TireForceResult} Resolved horizontal force vector, yaw moment, and slip state.
     */
    public function solve(
        dt:Float,
        cfg:VehicleConfigData,
        wheels:Array<WheelContact>,
        vLong:Float,
        vLat:Float,
        yawRate:Float,
        steerInput:Float,
        driveForce:Float,
        brakeForce:Float,
        handbrake:Bool,
        longAccel:Float,
        slopeFwdSin:Float,
        slopeRightSin:Float,
        gravityMag:Float
    ):TireForceResult {
        var chassisCfg = cfg.chassis;
        var tireCfg = cfg.tires;
        var absLong = Math.abs(vLong);
        var totalSpeed = Math.sqrt(vLong * vLong + vLat * vLat);

        // Speed-sensitive maximum front steering angle preventing high-speed spinouts
        var steerAngleBase = (steerInput * tireCfg.maxSteerAngle) / (1.0 + absLong * tireCfg.highSpeedSteerDamp);

        // Ackermann geometry: inner wheel turns tighter around turning radius R
        var leftWheelAngle = steerAngleBase;
        var rightWheelAngle = steerAngleBase;
        var absSteer = Math.abs(steerAngleBase);
        if (absSteer > 0.015) {
            var tanA = Math.tan(absSteer);
            var radius = chassisCfg.wheelbase / Math.max(0.01, tanA);
            var halfTrack = chassisCfg.trackWidth * 0.5;
            var rIn = Math.max(0.4, radius - halfTrack);
            var rOut = radius + halfTrack;
            var innerAng = Math.atan2(chassisCfg.wheelbase, rIn);
            var outerAng = Math.atan2(chassisCfg.wheelbase, rOut);
            var ack = tireCfg.ackermannFactor;

            if (steerAngleBase < 0.0) {
                // Turning LEFT (-): Left front is inner, Right front is outer
                leftWheelAngle = -(absSteer + (innerAng - absSteer) * ack);
                rightWheelAngle = -(absSteer + (outerAng - absSteer) * ack);
            } else {
                // Turning RIGHT (+): Right front is inner, Left front is outer
                rightWheelAngle = (absSteer + (innerAng - absSteer) * ack);
                leftWheelAngle = (absSteer + (outerAng - absSteer) * ack);
            }
        }

        var groundedCount = 0;
        var totalNormalLoad = 0.0;
        var avgMu = 0.0;
        for (i in 0...4) {
            if (wheels[i].grounded && wheels[i].normalLoad > 0.0) {
                groundedCount++;
                totalNormalLoad += wheels[i].normalLoad;
                avgMu += wheels[i].mu;
            }
        }
        if (groundedCount == 0) {
            for (i in 0...4) smoothedSlip[i] *= Math.max(0.0, 1.0 - dt * 8.0);
            return {
                forceFwd: 0.0,
                forceRight: 0.0,
                yawTorque: 0.0,
                frontSteerAngle: steerAngleBase,
                lateralSlipAngle: 0.0,
                isStictionActive: false
            };
        }
        avgMu /= groundedCount;

        // Low-speed static friction ("stiction") holding when parked with no drive command
        var idleNoDrive = Math.abs(driveForce) < 50.0;
        if (totalSpeed < tireCfg.stictionSpeed && idleNoDrive && !handbrake) {
            var maxStatic = avgMu * totalNormalLoad;
            // Cancel gravity slope component plus micro-velocity within tire static friction cone
            var cancelFwd = -vLong * chassisCfg.massKg * 18.0 + chassisCfg.massKg * gravityMag * slopeFwdSin;
            var cancelRight = -vLat * chassisCfg.massKg * 18.0 + chassisCfg.massKg * gravityMag * slopeRightSin;
            var mag = Math.sqrt(cancelFwd * cancelFwd + cancelRight * cancelRight);
            if (mag > maxStatic && mag > 0.001) {
                var scale = maxStatic / mag;
                cancelFwd *= scale;
                cancelRight *= scale;
            }
            for (i in 0...4) smoothedSlip[i] = 0.0;
            return {
                forceFwd: cancelFwd,
                forceRight: cancelRight,
                yawTorque: -yawRate * chassisCfg.yawInertia * 16.0,
                frontSteerAngle: steerAngleBase,
                lateralSlipAngle: 0.0,
                isStictionActive: true
            };
        }

        // Longitudinal axle weight transfer from acceleration/braking
        var dFzTotal = (longAccel * chassisCfg.massKg * chassisCfg.cogHeight) / chassisCfg.wheelbase;
        if (dFzTotal > 3200.0) dFzTotal = 3200.0;
        else if (dFzTotal < -3200.0) dFzTotal = -3200.0;
        var frontAxleTransfer = -0.5 * dFzTotal; // Accelerating (longAccel > 0) unloads front
        var rearAxleTransfer = 0.5 * dFzTotal;   // Accelerating loads rear

        // Drivetrain torque split across grounded wheels: FWD = 1.0/0.0, AWD = 0.35/0.65, RWD = 0.0/1.0
        var fSplit = cfg.drivetrain.frontDriveSplit != null ? cfg.drivetrain.frontDriveSplit : 0.35;
        fSplit = Math.max(0.0, Math.min(1.0, fSplit));
        var rSplit = 1.0 - fSplit;
        var frontGrounded = (wheels[0].grounded ? 1 : 0) + (wheels[1].grounded ? 1 : 0);
        var rearGrounded = (wheels[2].grounded ? 1 : 0) + (wheels[3].grounded ? 1 : 0);
        var frontShare = frontGrounded > 0 ? (rearGrounded > 0 ? fSplit : (fSplit > 0.0 ? 1.0 : 0.0)) / frontGrounded : 0.0;
        var rearShare = rearGrounded > 0 ? (frontGrounded > 0 ? rSplit : (rSplit > 0.0 ? 1.0 : 0.0)) / rearGrounded : 0.0;
        var halfWheelbase = chassisCfg.wheelbase * 0.5;
        var halfTrack = chassisCfg.trackWidth * 0.5;

        var totalForceFwd = 0.0;
        var totalForceRight = 0.0;
        var totalYawTorque = 0.0;
        var maxSlipObserved = 0.0;

        var B = tireCfg.pacejkaB;
        var C = tireCfg.pacejkaC;
        var D = tireCfg.pacejkaD;
        var E = tireCfg.pacejkaE;
        var lambda = tireCfg.relaxationLength;

        for (i in 0...4) {
            var wc = wheels[i];
            if (!wc.grounded || wc.normalLoad <= 0.0) {
                smoothedSlip[i] *= Math.max(0.0, 1.0 - dt * 8.0);
                continue;
            }

            var isFront = i < 2;
            var isLeft = (i == 0 || i == 2);
            var offsetX = isLeft ? -halfTrack : halfTrack;
            var offsetY = isFront ? halfWheelbase : -halfWheelbase;
            var fz = wc.normalLoad + (isFront ? frontAxleTransfer : rearAxleTransfer);
            if (fz < 150.0) fz = 150.0;

            var delta = (i == 0) ? leftWheelAngle : ((i == 1) ? rightWheelAngle : 0.0);
            var cosD = Math.cos(delta);
            var sinD = Math.sin(delta);

            // Rigid body velocity at wheel patch (wx, wy) in chassis horizontal (Fwd, Right) frame
            // d/dt(forward) = +yawRate * right => vFwd = vLong - yawRate * wx; vRight = vLat + yawRate * wy
            var vPatchFwd = vLong - yawRate * offsetX;
            var vPatchRight = vLat + yawRate * offsetY;

            // Project onto wheel local axes
            var vWheelFwd = vPatchFwd * cosD + vPatchRight * sinD;
            var vWheelRight = -vPatchFwd * sinD + vPatchRight * cosD;

            // Slip angle with smooth low-speed denominator protection & relaxation length filter
            var denom = Math.max(Math.abs(vWheelFwd), tireCfg.minSlipSpeed);
            var speedGate = Math.min(1.0, totalSpeed / 1.5);
            var rawAlpha = Math.atan2(vWheelRight, denom) * speedGate;

            var travelDist = Math.max(Math.abs(vWheelFwd), 2.5) * dt;
            var relaxAlpha = 1.0 - Math.exp(-travelDist / lambda);
            smoothedSlip[i] += (rawAlpha - smoothedSlip[i]) * relaxAlpha;
            var alpha = smoothedSlip[i];

            if (!isFront && Math.abs(alpha) > maxSlipObserved) {
                maxSlipObserved = Math.abs(alpha);
            }

            // Pacejka Magic Formula lateral tire force opposing lateral slip velocity
            var ba = B * alpha;
            var shapeTerm = ba - E * (ba - Math.atan(ba));
            var normLat = D * Math.sin(C * Math.atan(shapeTerm));
            var gripMult = (!isFront && handbrake) ? tireCfg.handbrakeRearGrip : 1.0;
            var tractionLimit = wc.mu * fz;
            var fyWheel = -tractionLimit * gripMult * normLat;

            // Longitudinal drive & braking force per wheel
            var fxWheel = driveForce * (isFront ? frontShare : rearShare);
            if (brakeForce > 0.0) {
                var brakeSplit = isFront ? (0.62 / Math.max(1, frontGrounded)) : (0.38 / Math.max(1, rearGrounded));
                if (!isFront && handbrake) {
                    brakeSplit *= 1.35;
                }
                if (Math.abs(vWheelFwd) > 0.25) {
                    fxWheel += (vWheelFwd > 0.0 ? -1.0 : 1.0) * brakeForce * brakeSplit;
                } else {
                    fxWheel += -vWheelFwd * chassisCfg.massKg * 3.0;
                }
            } else if (!isFront && handbrake && Math.abs(vWheelFwd) > 0.4) {
                fxWheel += (vWheelFwd > 0.0 ? -1.0 : 1.0) * wc.mu * fz * 0.45;
            }

            // Combined Friction Circle enforcement: |F_xy| <= mu * F_z
            var forceMag = Math.sqrt(fxWheel * fxWheel + fyWheel * fyWheel);
            if (forceMag > tractionLimit && forceMag > 0.001) {
                var circleScale = tractionLimit / forceMag;
                fxWheel *= circleScale;
                fyWheel *= circleScale;
            }

            // Rotate wheel forces back into chassis horizontal (Fwd, Right) frame
            var fxChassis = fxWheel * cosD - fyWheel * sinD;
            var fyChassis = fxWheel * sinD + fyWheel * cosD;

            totalForceFwd += fxChassis;
            totalForceRight += fyChassis;
            // Yaw moment (+ = clockwise toward +Right / +X): front pushed +Right => +, right pushed +Fwd => -
            totalYawTorque += offsetY * fyChassis - offsetX * fxChassis;
        }

        // Subtle aerodynamic rolling drag and quadratic aero drag
        var aeroDrag = chassisCfg.aeroDragArea * vLong * Math.abs(vLong);
        var rolling = chassisCfg.massKg * gravityMag * chassisCfg.rollingResistance * (Math.abs(vLong) > 0.2 ? (vLong > 0 ? 1.0 : -1.0) : 0.0);
        totalForceFwd -= (aeroDrag + rolling);

        return {
            forceFwd: totalForceFwd,
            forceRight: totalForceRight,
            yawTorque: totalYawTorque,
            frontSteerAngle: steerAngleBase,
            lateralSlipAngle: maxSlipObserved,
            isStictionActive: false
        };
    }
}
