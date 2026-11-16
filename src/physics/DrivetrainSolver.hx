package physics;

import physics.CarConfig;

/**
 * Computed drivetrain forces, transmission gear state, and nitrous reserve readout.
 *
 * @typedef {Object} DrivetrainResult
 */
typedef DrivetrainResult = {
    var driveForce:Float;
    var brakeForce:Float;
    var nitroThrust:Float;
    var currentGear:Int;
    var engineRPM:Float;
    var boostFuel:Float;
    var isBoosting:Bool;
    var rearWheelSpinDelta:Float;
}

/**
 * Simulates a 6-forward + reverse sequential automatic gearbox, bell-shaped engine torque curve,
 * braking / reverse interlock, engine braking, and nitrous boost injection.
 *
 * @class DrivetrainSolver
 * @module physics/DrivetrainSolver
 */
class DrivetrainSolver {
    var shiftCooldown:Float = 0.0;

    /**
     * Constructs a stateful drivetrain solver tracking gear shift hysteresis timing.
     */
    public function new() {}

    /**
     * Resets shift hysteresis cooldown upon vehicle respawn.
     */
    public function reset():Void {
        shiftCooldown = 0.0;
    }

    /**
     * Evaluates gearbox gear selection, RPM sweep, tractive wheel force, service brakes,
     * and nitrous boost reserve for the current physics sub-step.
     *
     * @param {Float} dt Fixed physics sub-step in seconds.
     * @param {VehicleConfigData} cfg Validated vehicle config.
     * @param {Float} throttle Input throttle [0.0, 1.0].
     * @param {Float} brake Input service brake / reverse [0.0, 1.0].
     * @param {Bool} handbrake True when rear handbrake is engaged.
     * @param {Bool} boostInput True when player holds nitrous boost.
     * @param {Float} forwardSpeed Current vehicle longitudinal speed in m/s.
     * @param {Int} currentGear Active gear (-1 = Reverse, 1..6 = Forward).
     * @param {Float} boostFuel Normalized remaining nitrous fuel [0.0, 1.0].
     * @param {Int} groundedCount Number of grounded wheels [0..4].
     * @returns {DrivetrainResult} Net longitudinal drive/brake forces and transmission telemetry.
     */
    public function solve(
        dt:Float,
        cfg:VehicleConfigData,
        throttle:Float,
        brake:Float,
        handbrake:Bool,
        boostInput:Bool,
        forwardSpeed:Float,
        currentGear:Int,
        boostFuel:Float,
        groundedCount:Int
    ):DrivetrainResult {
        var driveCfg = cfg.drivetrain;
        var boostCfg = cfg.boost;
        var tireRadius = CarConfig.TIRE_RADIUS;
        var numGears = driveCfg.gearRatios.length;

        if (shiftCooldown > 0.0) {
            shiftCooldown = Math.max(0.0, shiftCooldown - dt);
        }

        // Nitrous boost reserve update
        var isBoosting = false;
        var fuel = boostFuel;
        if (boostInput && fuel > 0.02 && (throttle > 0.05 || forwardSpeed > 3.0)) {
            isBoosting = true;
            fuel = Math.max(0.0, fuel - boostCfg.burnRate * dt);
        } else {
            fuel = Math.min(boostCfg.maxFuel, fuel + boostCfg.regenRate * dt);
        }

        // Determine gear state cleanly (Reverse -1 when braking at rest or rolling backward)
        var gear = currentGear;
        if (gear == 0) gear = 1;

        if (brake > 0.1 && throttle < 0.1 && forwardSpeed <= 1.2) {
            gear = -1;
        } else if (gear < 0 && (throttle > 0.1 || forwardSpeed > 0.8)) {
            gear = 1;
        } else if (gear < 0 && brake <= 0.1 && forwardSpeed > -0.5) {
            gear = 1;
        }

        var gearRatio = gear < 0 ? driveCfg.reverseRatio : driveCfg.gearRatios[gear - 1];
        var wheelOmega = Math.abs(forwardSpeed) / tireRadius;
        var rawRPM = (wheelOmega * Math.abs(gearRatio) * driveCfg.finalDrive) * (60.0 / (2.0 * Math.PI));

        // Add subtle clutch slip & throttle rev flare at launch or low speeds
        var targetRPM = Math.max(driveCfg.idleRPM + throttle * 1600.0, rawRPM);
        if (isBoosting) targetRPM += 450.0;
        var clampedRPM = Math.min(driveCfg.redlineRPM, Math.max(driveCfg.idleRPM, targetRPM));

        // Automatic gear shifts with hysteresis and shift cooldown
        if (gear > 0 && shiftCooldown <= 0.0 && groundedCount > 0) {
            if (clampedRPM >= driveCfg.shiftUpRPM && gear < numGears && throttle > 0.15) {
                gear++;
                shiftCooldown = 0.22;
                gearRatio = driveCfg.gearRatios[gear - 1];
                rawRPM = (wheelOmega * Math.abs(gearRatio) * driveCfg.finalDrive) * (60.0 / (2.0 * Math.PI));
                clampedRPM = Math.min(driveCfg.redlineRPM, Math.max(driveCfg.idleRPM + throttle * 900.0, rawRPM));
            } else if (clampedRPM <= driveCfg.shiftDownRPM && gear > 1) {
                gear--;
                shiftCooldown = 0.22;
                gearRatio = driveCfg.gearRatios[gear - 1];
                rawRPM = (wheelOmega * Math.abs(gearRatio) * driveCfg.finalDrive) * (60.0 / (2.0 * Math.PI));
                clampedRPM = Math.min(driveCfg.redlineRPM, Math.max(driveCfg.idleRPM, rawRPM));
            }
        }

        // Smooth bell-shaped engine torque factor over RPM band [0.68..1.05]
        var rpmNorm = (clampedRPM - driveCfg.idleRPM) / Math.max(100.0, driveCfg.redlineRPM - driveCfg.idleRPM);
        var torqueFactor = 0.72 + 0.34 * Math.sin(Math.min(1.0, Math.max(0.0, rpmNorm)) * Math.PI * 0.85);
        var effectiveMaxSpeed = driveCfg.maxForwardSpeed + (isBoosting ? boostCfg.speedBonus : 0.0);

        var driveForce = 0.0;
        var brakeForce = 0.0;
        var nitroThrust = 0.0;

        if (gear > 0) {
            // Forward drive torque
            if (throttle > 0.01) {
                var boostTorqueMult = isBoosting ? 1.25 : 1.0;
                var wheelTorque = throttle * driveCfg.peakTorqueNm * boostTorqueMult * torqueFactor * gearRatio * driveCfg.finalDrive;
                driveForce = wheelTorque / tireRadius;

                // Soft governor tapering above top speed
                if (forwardSpeed > effectiveMaxSpeed - 6.0) {
                    var gov = 1.0 - (forwardSpeed - (effectiveMaxSpeed - 6.0)) / 6.0;
                    driveForce *= Math.max(0.0, Math.min(1.0, gov));
                }
            } else if (brake < 0.05 && Math.abs(forwardSpeed) > 0.8) {
                // Coasting engine braking
                var ebForce = (driveCfg.engineBrakeTorque * Math.min(gearRatio, 2.6)) / tireRadius;
                driveForce = forwardSpeed > 0.0 ? -ebForce : ebForce;
            }

            if (isBoosting && forwardSpeed < effectiveMaxSpeed) {
                nitroThrust = boostCfg.thrustForce;
            }

            // Foot brakes oppose current direction of travel
            if (brake > 0.01) {
                brakeForce = brake * driveCfg.brakeForce;
            }
        } else {
            // Reverse gear
            if (brake > 0.01) {
                if (forwardSpeed > 0.5) {
                    brakeForce = brake * driveCfg.brakeForce;
                } else {
                    var revFactor = forwardSpeed < -(driveCfg.maxReverseSpeed - 3.0)
                        ? Math.max(0.0, 1.0 - (Math.abs(forwardSpeed) - (driveCfg.maxReverseSpeed - 3.0)) / 3.0)
                        : 1.0;
                    var revWheelTorque = brake * driveCfg.peakTorqueNm * 0.65 * driveCfg.reverseRatio * driveCfg.finalDrive;
                    driveForce = (revWheelTorque / tireRadius) * revFactor; // Negative force reverses car
                }
            }
        }

        // Visual rear wheel slip velocity delta for wheelspin / handbrake lock animation
        var rearSpinDelta = 0.0;
        if (handbrake && Math.abs(forwardSpeed) > 1.0) {
            rearSpinDelta = -(forwardSpeed / tireRadius);
        } else if ((isBoosting || (throttle > 0.7 && gear == 1)) && Math.abs(forwardSpeed) < 18.0) {
            rearSpinDelta = 18.0;
        }

        return {
            driveForce: driveForce,
            brakeForce: brakeForce,
            nitroThrust: nitroThrust,
            currentGear: gear,
            engineRPM: clampedRPM,
            boostFuel: fuel,
            isBoosting: isBoosting,
            rearWheelSpinDelta: rearSpinDelta
        };
    }
}
