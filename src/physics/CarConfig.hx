package physics;

import haxe.Json;

/**
 * Rigid chassis geometry, inertia, and aerodynamic drag/downforce configuration.
 *
 * @typedef {Object} ChassisConfig
 */
typedef ChassisConfig = {
    var massKg:Float;
    var wheelbase:Float;
    var trackWidth:Float;
    var cogHeight:Float;
    var pitchInertia:Float;
    var rollInertia:Float;
    var yawInertia:Float;
    var aeroDragArea:Float;
    var aeroDownforce:Float;
    var rollingResistance:Float;
}

/**
 * Four-wheel raycast strut spring-damper and axle anti-roll bar parameters.
 *
 * @typedef {Object} SuspensionConfig
 */
typedef SuspensionConfig = {
    var restLength:Float;
    var unloadedLength:Float;
    var minLength:Float;
    var springStiffness:Float;
    var bumpDamping:Float;
    var reboundDamping:Float;
    var antiRollStiffness:Float;
    var maxWheelForce:Float;
}

/**
 * Multi-gear automatic transmission, torque curve, braking, and nitrous boost limits.
 *
 * @typedef {Object} DrivetrainConfig
 */
typedef DrivetrainConfig = {
    var idleRPM:Float;
    var redlineRPM:Float;
    var peakTorqueNm:Float;
    var finalDrive:Float;
    var gearRatios:Array<Float>;
    var reverseRatio:Float;
    var shiftUpRPM:Float;
    var shiftDownRPM:Float;
    var maxForwardSpeed:Float;
    var maxReverseSpeed:Float;
    var brakeForce:Float;
    var engineBrakeTorque:Float;
}

/**
 * Pacejka lateral slip curve, speed-blended Ackermann geometry, and low-speed stiction settings.
 *
 * @typedef {Object} TireConfig
 */
typedef TireConfig = {
    var pacejkaB:Float;
    var pacejkaC:Float;
    var pacejkaD:Float;
    var pacejkaE:Float;
    var relaxationLength:Float;
    var minSlipSpeed:Float;
    var stictionSpeed:Float;
    var maxSteerAngle:Float;
    var highSpeedSteerDamp:Float;
    var ackermannFactor:Float;
    var handbrakeRearGrip:Float;
    var driftSlipThreshold:Float;
}

/**
 * Nitrous oxide fuel reserve and thrust boost profile.
 *
 * @typedef {Object} BoostConfig
 */
typedef BoostConfig = {
    var maxFuel:Float;
    var burnRate:Float;
    var regenRate:Float;
    var thrustForce:Float;
    var speedBonus:Float;
}

/**
 * Complete serialized vehicle tuning specification consumed by CarPhysics solvers.
 *
 * @typedef {Object} VehicleConfigData
 */
typedef VehicleConfigData = {
    var chassis:ChassisConfig;
    var suspension:SuspensionConfig;
    var drivetrain:DrivetrainConfig;
    var tires:TireConfig;
    var boost:BoostConfig;
}

/**
 * Central vehicle geometry constants, default tuning factory, safe parameter clamping,
 * and JSON serialization helpers for the 4-wheel raycast physics engine.
 *
 * @class CarConfig
 * @module physics/CarConfig
 */
class CarConfig {
    /** Outer tire radius in meters (aligned 1:1 with visual CarMesh cylinder). */
    public static inline var TIRE_RADIUS:Float = 0.36;

    /** Tire tread section width in meters. */
    public static inline var TIRE_WIDTH:Float = 0.30;

    /** Physical and visual chassis body width in meters. */
    public static inline var CHASSIS_WIDTH:Float = 1.88;

    /** Physical and visual chassis bumper-to-bumper length in meters. */
    public static inline var CHASSIS_LENGTH:Float = 4.30;

    /** Center of gravity height above wheel contact plane in meters. */
    public static inline var COG_HEIGHT:Float = 0.48;

    /** Nominal axle-to-axle wheelbase matching CarMesh front/rear offsets (+/- 1.35 m). */
    public static inline var WHEELBASE:Float = 2.70;

    /** Nominal left-to-right track width matching CarMesh wheel offsets (+/- 0.98 m). */
    public static inline var TRACK_WIDTH:Float = 1.96;

    /**
     * Returns a freshly allocated default sports-coupe vehicle configuration.
     *
     * @returns {VehicleConfigData} Validated default tuning profile.
     */
    public static function getDefault():VehicleConfigData {
        return {
            chassis: {
                massKg: 1450.0,
                wheelbase: WHEELBASE,
                trackWidth: TRACK_WIDTH,
                cogHeight: COG_HEIGHT,
                pitchInertia: 2200.0,
                rollInertia: 780.0,
                yawInertia: 2450.0,
                aeroDragArea: 0.36,
                aeroDownforce: 1.85,
                rollingResistance: 0.014
            },
            suspension: {
                restLength: 0.36,
                unloadedLength: 0.50,
                minLength: 0.14,
                springStiffness: 25400.0,
                bumpDamping: 3950.0,
                reboundDamping: 5450.0,
                antiRollStiffness: 14500.0,
                maxWheelForce: 13500.0
            },
            drivetrain: {
                idleRPM: 950.0,
                redlineRPM: 7600.0,
                peakTorqueNm: 560.0,
                finalDrive: 3.75,
                gearRatios: [3.42, 2.28, 1.65, 1.28, 1.02, 0.84],
                reverseRatio: -3.15,
                shiftUpRPM: 6900.0,
                shiftDownRPM: 2850.0,
                maxForwardSpeed: 72.0,
                maxReverseSpeed: 19.0,
                brakeForce: 19500.0,
                engineBrakeTorque: 95.0
            },
            tires: {
                pacejkaB: 9.2,
                pacejkaC: 1.52,
                pacejkaD: 1.08,
                pacejkaE: -0.35,
                relaxationLength: 0.34,
                minSlipSpeed: 1.2,
                stictionSpeed: 0.65,
                maxSteerAngle: 0.54,
                highSpeedSteerDamp: 0.026,
                ackermannFactor: 0.65,
                handbrakeRearGrip: 0.28,
                driftSlipThreshold: 0.14
            },
            boost: {
                maxFuel: 1.0,
                burnRate: 0.28,
                regenRate: 0.12,
                thrustForce: 7800.0,
                speedBonus: 14.0
            }
        };
    }

    /**
     * Deep-copies and clamps a VehicleConfigData structure so invalid values or zero divisors
     * can never destabilize suspension or tire integration.
     *
     * @param {VehicleConfigData} cfg Input vehicle configuration (defaults used if null).
     * @returns {VehicleConfigData} Safe clamped configuration clone.
     */
    public static function clamp(?cfg:VehicleConfigData):VehicleConfigData {
        var def = getDefault();
        if (cfg == null) return def;

        var c = cfg.chassis != null ? cfg.chassis : def.chassis;
        var s = cfg.suspension != null ? cfg.suspension : def.suspension;
        var d = cfg.drivetrain != null ? cfg.drivetrain : def.drivetrain;
        var t = cfg.tires != null ? cfg.tires : def.tires;
        var b = cfg.boost != null ? cfg.boost : def.boost;

        var ratios = (d.gearRatios != null && d.gearRatios.length > 0)
            ? d.gearRatios.copy()
            : def.drivetrain.gearRatios.copy();
        for (i in 0...ratios.length) {
            ratios[i] = clampVal(ratios[i], 0.3, 6.0, def.drivetrain.gearRatios[0]);
        }

        var minLen = clampVal(s.minLength, 0.04, 0.30, def.suspension.minLength);
        var restLen = clampVal(s.restLength, minLen + 0.06, 0.65, def.suspension.restLength);
        var unloadedLen = clampVal(s.unloadedLength, restLen + 0.04, 0.90, def.suspension.unloadedLength);

        var idle = clampVal(d.idleRPM, 500.0, 2500.0, def.drivetrain.idleRPM);
        var redline = clampVal(d.redlineRPM, idle + 1500.0, 12000.0, def.drivetrain.redlineRPM);

        return {
            chassis: {
                massKg: clampVal(c.massKg, 400.0, 5000.0, def.chassis.massKg),
                wheelbase: clampVal(c.wheelbase, 1.2, 5.0, def.chassis.wheelbase),
                trackWidth: clampVal(c.trackWidth, 0.8, 3.0, def.chassis.trackWidth),
                cogHeight: clampVal(c.cogHeight, 0.20, 1.20, def.chassis.cogHeight),
                pitchInertia: clampVal(c.pitchInertia, 300.0, 12000.0, def.chassis.pitchInertia),
                rollInertia: clampVal(c.rollInertia, 150.0, 6000.0, def.chassis.rollInertia),
                yawInertia: clampVal(c.yawInertia, 300.0, 12000.0, def.chassis.yawInertia),
                aeroDragArea: clampVal(c.aeroDragArea, 0.0, 3.0, def.chassis.aeroDragArea),
                aeroDownforce: clampVal(c.aeroDownforce, 0.0, 10.0, def.chassis.aeroDownforce),
                rollingResistance: clampVal(c.rollingResistance, 0.001, 0.25, def.chassis.rollingResistance)
            },
            suspension: {
                restLength: restLen,
                unloadedLength: unloadedLen,
                minLength: minLen,
                springStiffness: clampVal(s.springStiffness, 5000.0, 180000.0, def.suspension.springStiffness),
                bumpDamping: clampVal(s.bumpDamping, 500.0, 40000.0, def.suspension.bumpDamping),
                reboundDamping: clampVal(s.reboundDamping, 500.0, 40000.0, def.suspension.reboundDamping),
                antiRollStiffness: clampVal(s.antiRollStiffness, 0.0, 80000.0, def.suspension.antiRollStiffness),
                maxWheelForce: clampVal(s.maxWheelForce, 2000.0, 60000.0, def.suspension.maxWheelForce)
            },
            drivetrain: {
                idleRPM: idle,
                redlineRPM: redline,
                peakTorqueNm: clampVal(d.peakTorqueNm, 50.0, 3000.0, def.drivetrain.peakTorqueNm),
                finalDrive: clampVal(d.finalDrive, 1.0, 8.0, def.drivetrain.finalDrive),
                gearRatios: ratios,
                reverseRatio: clampVal(d.reverseRatio, -6.0, -0.5, def.drivetrain.reverseRatio),
                shiftUpRPM: clampVal(d.shiftUpRPM, idle + 500.0, redline - 100.0, def.drivetrain.shiftUpRPM),
                shiftDownRPM: clampVal(d.shiftDownRPM, idle + 100.0, redline - 600.0, def.drivetrain.shiftDownRPM),
                maxForwardSpeed: clampVal(d.maxForwardSpeed, 10.0, 150.0, def.drivetrain.maxForwardSpeed),
                maxReverseSpeed: clampVal(d.maxReverseSpeed, 5.0, 50.0, def.drivetrain.maxReverseSpeed),
                brakeForce: clampVal(d.brakeForce, 1000.0, 80000.0, def.drivetrain.brakeForce),
                engineBrakeTorque: clampVal(d.engineBrakeTorque, 0.0, 1000.0, def.drivetrain.engineBrakeTorque)
            },
            tires: {
                pacejkaB: clampVal(t.pacejkaB, 2.0, 25.0, def.tires.pacejkaB),
                pacejkaC: clampVal(t.pacejkaC, 0.5, 2.5, def.tires.pacejkaC),
                pacejkaD: clampVal(t.pacejkaD, 0.3, 2.5, def.tires.pacejkaD),
                pacejkaE: clampVal(t.pacejkaE, -2.0, 1.0, def.tires.pacejkaE),
                relaxationLength: clampVal(t.relaxationLength, 0.05, 2.0, def.tires.relaxationLength),
                minSlipSpeed: clampVal(t.minSlipSpeed, 0.25, 5.0, def.tires.minSlipSpeed),
                stictionSpeed: clampVal(t.stictionSpeed, 0.05, 2.5, def.tires.stictionSpeed),
                maxSteerAngle: clampVal(t.maxSteerAngle, 0.10, 0.85, def.tires.maxSteerAngle),
                highSpeedSteerDamp: clampVal(t.highSpeedSteerDamp, 0.0, 0.15, def.tires.highSpeedSteerDamp),
                ackermannFactor: clampVal(t.ackermannFactor, 0.0, 1.0, def.tires.ackermannFactor),
                handbrakeRearGrip: clampVal(t.handbrakeRearGrip, 0.05, 1.0, def.tires.handbrakeRearGrip),
                driftSlipThreshold: clampVal(t.driftSlipThreshold, 0.05, 0.60, def.tires.driftSlipThreshold)
            },
            boost: {
                maxFuel: clampVal(b.maxFuel, 0.1, 10.0, def.boost.maxFuel),
                burnRate: clampVal(b.burnRate, 0.01, 2.0, def.boost.burnRate),
                regenRate: clampVal(b.regenRate, 0.0, 2.0, def.boost.regenRate),
                thrustForce: clampVal(b.thrustForce, 0.0, 30000.0, def.boost.thrustForce),
                speedBonus: clampVal(b.speedBonus, 0.0, 50.0, def.boost.speedBonus)
            }
        };
    }

    /**
     * Serializes a vehicle config struct into formatted JSON.
     *
     * @param {VehicleConfigData} cfg Vehicle config to serialize.
     * @returns {String} JSON representation.
     */
    public static function toJson(cfg:VehicleConfigData):String {
        return Json.stringify(clamp(cfg), null, "  ");
    }

    /**
     * Parses JSON into a safely validated VehicleConfigData profile (falls back on defaults on error).
     *
     * @param {String} jsonText Input JSON string.
     * @returns {VehicleConfigData} Clamped configuration profile.
     */
    public static function fromJson(jsonText:String):VehicleConfigData {
        if (jsonText == null || StringTools.trim(jsonText).length == 0) {
            return getDefault();
        }
        try {
            var parsed:Dynamic = Json.parse(jsonText);
            return clamp(parsed);
        } catch (_:Dynamic) {
            return getDefault();
        }
    }

    static inline function clampVal(v:Float, minV:Float, maxV:Float, fallback:Float):Float {
        if (Math.isNaN(v) || !Math.isFinite(v)) return fallback;
        return v < minV ? minV : (v > maxV ? maxV : v);
    }
}
