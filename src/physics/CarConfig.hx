package physics;

import haxe.Json;

/**
 * Tunable suspension configuration parameters.
 */
typedef SuspensionConfig = {
    /** Unloaded spring rest length from chassis mount to wheel contact in meters. */
    var restLength:Float;

    /** Linear spring stiffness rate in N/m. */
    var springRate:Float;

    /** Shock absorber viscous damping coefficient in Ns/m. */
    var damping:Float;

    /** Transverse anti-roll bar torsional stiffness rate in N/m. */
    var antiRollStiffness:Float;

    /** Minimum allowable spring compression travel in meters before bump-stop contact. */
    var minTravel:Float;

    /** Maximum allowable spring extension travel in meters before full droop. */
    var maxTravel:Float;

    /** Dynamic chassis roll multiplier affecting suspension lean and spring compression. */
    var bodyRollScale:Float;
}

/**
 * Mechanical and pneumatic tire adhesion parameters.
 */
typedef TireConfig = {
    /** Tire slip angle at which lateral grip reaches peak adhesion in radians. */
    var peakSlipAngle:Float;

    /** Base lateral cornering stiffness coefficient along the linear slip region. */
    var baseLateralStiffness:Float;

    /** Longitudinal friction coefficient during acceleration and threshold braking. */
    var longitudinalGrip:Float;

    /** Rolling resistance deceleration coefficient in m/s². */
    var rollingResistance:Float;

    /** Front vs rear tire slip bias [-1.0 .. 1.0]. Negative = rear bias / oversteer, Positive = front bias / understeer, 0.0 = neutral. */
    var tireSlipBias:Float;

    /** Global ground contact friction scalar multiplying tire adhesion and braking. */
    var groundFriction:Float;

    /** Burnout wheelspin multiplier during standstill launches or full-throttle power corners. */
    var wheelspinAmount:Float;
}

/**
 * Arcade drift handling and momentum assist multipliers.
 */
typedef DriftConfig = {
    /** Lateral tire stiffness scaling multiplier during active slide (30-40% baseline). */
    var lateralStiffnessScale:Float;

    /** Counter-steer rotational torque assist multiplier stabilizing slide angle. */
    var counterSteerTorque:Float;

    /** Blending rate at which linear velocity vector aligns with vehicle forward heading. */
    var forwardBiasRate:Float;

    /** Minimum longitudinal velocity in m/s required to initiate an intentional drift slide. */
    var minDriftSpeed:Float;

    /** Base rotational yaw rate during active drift slide in rad/s. */
    var driftYawRate:Float;

    /** Threshold speed in m/s below which an active drift automatically terminates. */
    var driftExitSpeed:Float;

    /** Vehicle body slip angle threshold in radians required to trigger active drift physics. */
    var driftTriggerAngle:Float;
}

/**
 * Internal combustion powertrain, transmission ratios, and differential settings.
 */
typedef DrivetrainConfig = {
    /** Forward progressive gear reduction ratios (1st through 6th). */
    var gearRatios:Array<Float>;

    /** Reverse gear reduction ratio (negative). */
    var reverseRatio:Float;

    /** Final drive differential axle reduction ratio. */
    var finalDrive:Float;

    /** Engine baseline idle rotational speed in revolutions per minute. */
    var idleRPM:Float;

    /** Engine maximum redline rotational cutoff in revolutions per minute. */
    var redlineRPM:Float;

    /** Automatic transmission up-shift threshold RPM. */
    var shiftUpRPM:Float;

    /** Automatic transmission down-shift threshold RPM. */
    var shiftDownRPM:Float;

    /** Shifting disengagement latency duration in seconds. */
    var shiftDelay:Float;

    /** Simulated limited-slip differential torque transfer lockup ratio [0.0 - 1.0]. */
    var lsdLockRatio:Float;

    /** Peak flywheel torque delivery in Newton-meters. */
    var maxEngineTorque:Float;
}

/**
 * Aerodynamic quadratic drag and ground-effect downforce coefficients.
 */
typedef AeroConfig = {
    /** Longitudinal quadratic aerodynamic drag coefficient (Fd = 0.5 * rho * Cd * A * v²). */
    var dragCoeff:Float;

    /** Aerodynamic downforce coefficient generating normal load at high velocities. */
    var downforceCoeff:Float;
}

/**
 * Complete vehicle dynamics and performance configuration schema.
 * Represents a fully serializable, runtime-swappable vehicle tuning profile.
 */
typedef VehicleConfigData = {
    /** Human-readable vehicle model designation. */
    var name:String;

    /** Vehicle curb weight mass in kilograms. */
    var mass:Float;

    /** Rotational yaw moment of inertia about vertical Z-axis in kg·m². */
    var yawInertia:Float;

    /** Rotational pitch moment of inertia about transverse Y-axis in kg·m². */
    var pitchInertia:Float;

    /** Rotational roll moment of inertia about longitudinal X-axis in kg·m². */
    var rollInertia:Float;

    /** Baseline top speed under standard atmospheric propulsion in m/s (~245 km/h). */
    var baseTopSpeed:Float;

    /** Absolute terminal velocity while nitrous oxide injection is active in m/s (~316 km/h). */
    var boostTopSpeed:Float;

    /** Standard engine acceleration rate in m/s². */
    var baseAcceleration:Float;

    /** Nitrous oxide augmented acceleration rate in m/s². */
    var boostAcceleration:Float;

    /** Primary service brake deceleration rate in m/s². */
    var brakeDecel:Float;

    /** Reverse gear terminal velocity limit in m/s (~65 km/h). */
    var reverseTopSpeed:Float;

    /** Four-wheel independent suspension configuration. */
    var suspension:SuspensionConfig;

    /** Tire contact patch and slip friction parameters. */
    var tires:TireConfig;

    /** Arcade drift mechanics and momentum assist tuning. */
    var drift:DriftConfig;

    /** Powertrain, transmission, and differential configuration. */
    var drivetrain:DrivetrainConfig;

    /** Aerodynamic drag and downforce characteristics. */
    var aero:AeroConfig;
}

/**
 * Factory and serialization utilities for vehicle dynamics configurations.
 * Supports loading and dumping vehicle tuning profiles via JSON for runtime balancing.
 */
class CarConfig {
    /**
     * Constructs and returns the default high-performance arcade vehicle configuration.
     * Tuned for responsive arcade-sim dynamics inspired by classic high-speed street racers.
     *
     * @return Fully populated `VehicleConfigData` structure.
     */
    public static function getDefault():VehicleConfigData {
        return {
            name: "Apex GT-R Prototype",
            mass: 1350.0,
            yawInertia: 1750.0,
            pitchInertia: 1350.0,
            rollInertia: 620.0,
            baseTopSpeed: 68.0,
            boostTopSpeed: 88.0,
            baseAcceleration: 28.0,
            boostAcceleration: 48.0,
            brakeDecel: 38.0,
            reverseTopSpeed: 18.0,
            suspension: {
                restLength: 0.45,
                springRate: 32000.0,
                damping: 2600.0,
                antiRollStiffness: 9500.0,
                minTravel: 0.08,
                maxTravel: 0.52,
                bodyRollScale: 1.0
            },
            tires: {
                peakSlipAngle: 0.16,
                baseLateralStiffness: 34.0,
                longitudinalGrip: 1.15,
                rollingResistance: 2.0,
                tireSlipBias: -0.45,
                groundFriction: 1.0,
                wheelspinAmount: 1.2
            },
            drift: {
                lateralStiffnessScale: 0.35,
                counterSteerTorque: 3.4,
                forwardBiasRate: 3.8,
                minDriftSpeed: 12.0,
                driftYawRate: 2.8,
                driftExitSpeed: 8.0,
                driftTriggerAngle: 0.22
            },
            drivetrain: {
                gearRatios: [3.40, 2.20, 1.55, 1.18, 0.92, 0.76],
                reverseRatio: -3.10,
                finalDrive: 3.73,
                idleRPM: 1000.0,
                redlineRPM: 8000.0,
                shiftUpRPM: 7200.0,
                shiftDownRPM: 3400.0,
                shiftDelay: 0.20,
                lsdLockRatio: 0.72,
                maxEngineTorque: 540.0
            },
            aero: {
                dragCoeff: 0.0032,
                downforceCoeff: 0.0045
            }
        };
    }

    /**
     * Parses a vehicle configuration from a serialized JSON string.
     * Falls back cleanly to default configuration on syntax or structure error.
     *
     * @param jsonString Raw JSON encoded configuration string.
     * @return Deserialized `VehicleConfigData` instance.
     */
    public static function fromJson(jsonString:String):VehicleConfigData {
        if (jsonString == null || jsonString.length == 0) {
            return getDefault();
        }
        try {
            var raw:Dynamic = Json.parse(jsonString);
            var def = getDefault();

            // Safely merge fields with fallback defaults
            var cfg:VehicleConfigData = {
                name: raw.name != null ? raw.name : def.name,
                mass: raw.mass != null ? raw.mass : def.mass,
                yawInertia: raw.yawInertia != null ? raw.yawInertia : def.yawInertia,
                pitchInertia: raw.pitchInertia != null ? raw.pitchInertia : def.pitchInertia,
                rollInertia: raw.rollInertia != null ? raw.rollInertia : def.rollInertia,
                baseTopSpeed: raw.baseTopSpeed != null ? raw.baseTopSpeed : def.baseTopSpeed,
                boostTopSpeed: raw.boostTopSpeed != null ? raw.boostTopSpeed : def.boostTopSpeed,
                baseAcceleration: raw.baseAcceleration != null ? raw.baseAcceleration : def.baseAcceleration,
                boostAcceleration: raw.boostAcceleration != null ? raw.boostAcceleration : def.boostAcceleration,
                brakeDecel: raw.brakeDecel != null ? raw.brakeDecel : def.brakeDecel,
                reverseTopSpeed: raw.reverseTopSpeed != null ? raw.reverseTopSpeed : def.reverseTopSpeed,
                suspension: raw.suspension != null ? {
                    restLength: raw.suspension.restLength != null ? raw.suspension.restLength : def.suspension.restLength,
                    springRate: raw.suspension.springRate != null ? raw.suspension.springRate : def.suspension.springRate,
                    damping: raw.suspension.damping != null ? raw.suspension.damping : def.suspension.damping,
                    antiRollStiffness: raw.suspension.antiRollStiffness != null ? raw.suspension.antiRollStiffness : def.suspension.antiRollStiffness,
                    minTravel: raw.suspension.minTravel != null ? raw.suspension.minTravel : def.suspension.minTravel,
                    maxTravel: raw.suspension.maxTravel != null ? raw.suspension.maxTravel : def.suspension.maxTravel,
                    bodyRollScale: raw.suspension.bodyRollScale != null ? raw.suspension.bodyRollScale : def.suspension.bodyRollScale
                } : def.suspension,
                tires: raw.tires != null ? {
                    peakSlipAngle: raw.tires.peakSlipAngle != null ? raw.tires.peakSlipAngle : def.tires.peakSlipAngle,
                    baseLateralStiffness: raw.tires.baseLateralStiffness != null ? raw.tires.baseLateralStiffness : def.tires.baseLateralStiffness,
                    longitudinalGrip: raw.tires.longitudinalGrip != null ? raw.tires.longitudinalGrip : def.tires.longitudinalGrip,
                    rollingResistance: raw.tires.rollingResistance != null ? raw.tires.rollingResistance : def.tires.rollingResistance,
                    tireSlipBias: raw.tires.tireSlipBias != null ? raw.tires.tireSlipBias : def.tires.tireSlipBias,
                    groundFriction: raw.tires.groundFriction != null ? raw.tires.groundFriction : def.tires.groundFriction,
                    wheelspinAmount: raw.tires.wheelspinAmount != null ? raw.tires.wheelspinAmount : def.tires.wheelspinAmount
                } : def.tires,
                drift: raw.drift != null ? {
                    lateralStiffnessScale: raw.drift.lateralStiffnessScale != null ? raw.drift.lateralStiffnessScale : def.drift.lateralStiffnessScale,
                    counterSteerTorque: raw.drift.counterSteerTorque != null ? raw.drift.counterSteerTorque : def.drift.counterSteerTorque,
                    forwardBiasRate: raw.drift.forwardBiasRate != null ? raw.drift.forwardBiasRate : def.drift.forwardBiasRate,
                    minDriftSpeed: raw.drift.minDriftSpeed != null ? raw.drift.minDriftSpeed : def.drift.minDriftSpeed,
                    driftYawRate: raw.drift.driftYawRate != null ? raw.drift.driftYawRate : def.drift.driftYawRate,
                    driftExitSpeed: raw.drift.driftExitSpeed != null ? raw.drift.driftExitSpeed : def.drift.driftExitSpeed,
                    driftTriggerAngle: raw.drift.driftTriggerAngle != null ? raw.drift.driftTriggerAngle : def.drift.driftTriggerAngle
                } : def.drift,
                drivetrain: raw.drivetrain != null ? {
                    gearRatios: raw.drivetrain.gearRatios != null ? raw.drivetrain.gearRatios : def.drivetrain.gearRatios,
                    reverseRatio: raw.drivetrain.reverseRatio != null ? raw.drivetrain.reverseRatio : def.drivetrain.reverseRatio,
                    finalDrive: raw.drivetrain.finalDrive != null ? raw.drivetrain.finalDrive : def.drivetrain.finalDrive,
                    idleRPM: raw.drivetrain.idleRPM != null ? raw.drivetrain.idleRPM : def.drivetrain.idleRPM,
                    redlineRPM: raw.drivetrain.redlineRPM != null ? raw.drivetrain.redlineRPM : def.drivetrain.redlineRPM,
                    shiftUpRPM: raw.drivetrain.shiftUpRPM != null ? raw.drivetrain.shiftUpRPM : def.drivetrain.shiftUpRPM,
                    shiftDownRPM: raw.drivetrain.shiftDownRPM != null ? raw.drivetrain.shiftDownRPM : def.drivetrain.shiftDownRPM,
                    shiftDelay: raw.drivetrain.shiftDelay != null ? raw.drivetrain.shiftDelay : def.drivetrain.shiftDelay,
                    lsdLockRatio: raw.drivetrain.lsdLockRatio != null ? raw.drivetrain.lsdLockRatio : def.drivetrain.lsdLockRatio,
                    maxEngineTorque: raw.drivetrain.maxEngineTorque != null ? raw.drivetrain.maxEngineTorque : def.drivetrain.maxEngineTorque
                } : def.drivetrain,
                aero: raw.aero != null ? {
                    dragCoeff: raw.aero.dragCoeff != null ? raw.aero.dragCoeff : def.aero.dragCoeff,
                    downforceCoeff: raw.aero.downforceCoeff != null ? raw.aero.downforceCoeff : def.aero.downforceCoeff
                } : def.aero
            };
            return cfg;
        } catch (e:haxe.Exception) {
            trace("CarConfig parse error: " + e.message);
            return getDefault();
        }
    }

    /**
     * Serializes a vehicle configuration data structure into a formatted JSON string.
     *
     * @param config Target vehicle configuration.
     * @param pretty Whether to apply indentation formatting.
     * @return JSON encoded string.
     */
    public static function toJson(config:VehicleConfigData, pretty:Bool = true):String {
        return Json.stringify(config, pretty ? "  " : null);
    }
}

