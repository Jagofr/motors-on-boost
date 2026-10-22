package physics;

import h3d.Vector;
import input.InputController;
import physics.CarConfig.VehicleConfigData;

/**
 * Zero-overhead strongly typed enum abstract for four-wheel suspension and contact indexing.
 */
enum abstract WheelIndex(Int) from Int to Int {
    /** Front-left wheel index (0). */
    var FrontLeft = 0;

    /** Front-right wheel index (1). */
    var FrontRight = 1;

    /** Rear-left wheel index (2). */
    var RearLeft = 2;

    /** Rear-right wheel index (3). */
    var RearRight = 3;
}

/**
 * Zero-overhead strongly typed enum abstract for transmission gear ratios.
 */
enum abstract Gear(Int) from Int to Int {
    /** Reverse transmission gear (-1). */
    var Reverse = -1;

    /** Neutral transmission idle (0). */
    var Neutral = 0;

    /** First forward transmission gear (1). */
    var First = 1;

    /** Second forward transmission gear (2). */
    var Second = 2;

    /** Third forward transmission gear (3). */
    var Third = 3;

    /** Fourth forward transmission gear (4). */
    var Fourth = 4;

    /** Fifth forward transmission gear (5). */
    var Fifth = 5;

    /** Sixth forward transmission gear (6). */
    var Sixth = 6;
}

/**
 * First-principles arcade vehicle dynamics, multi-link raycast suspension simulation,
 * slip-angle tire friction modeling, and arcade drift mechanics.
 * Designed with zero runtime allocations in update loops.
 */
class CarPhysics {
    /** World position of the vehicle chassis center point. */
    public var pos:Vector = new Vector();

    /** Yaw orientation in radians (rotation about world Z-axis). */
    public var yaw:Float = 1.5707963;

    /** Dynamic chassis pitch in radians (squat on acceleration, dive on braking). */
    public var pitch:Float = 0.0;

    /** Dynamic chassis roll in radians (lateral centrifugal roll dampened by anti-roll bars). */
    public var roll:Float = 0.0;

    /** Forward longitudinal velocity along vehicle heading vector in m/s. */
    public var forwardSpeed:Float = 0.0;

    /** Lateral slip velocity perpendicular to vehicle forward heading in m/s. */
    public var lateralVelocity:Float = 0.0;

    /** Vertical chassis velocity in m/s. */
    public var verticalVelocity:Float = 0.0;

    /** Flag indicating whether the rear tires have broken traction into an active drift slide. */
    public var isDrifting:Bool = false;

    /** Sign multiplier of active drift direction (-1.0 for leftward yaw bias, +1.0 for rightward yaw bias). */
    public var driftDirection:Float = 0.0;

    /** Visual vehicle body slip angle offset relative to velocity direction in radians. */
    public var driftAngle:Float = 0.0;

    /** Current transmission gear index (-1 = Reverse, 0 = Neutral, 1..6 = Forward gears). */
    public var currentGear:Int = 1;

    /** Current engine rotational speed in revolutions per minute. */
    public var engineRPM:Float = 1000.0;

    /** Active shift disengagement timer in seconds. */
    public var shiftTimer:Float = 0.0;

    /** Whether transmission is currently disengaged during a gear transition. */
    public var isShifting:Bool = false;

    /** Remaining nitrous boost fuel capacity in range [0.0, 1.0]. */
    public var boostFuel:Float = 1.0;

    /** Nitrous fuel burn consumption rate per second while boosting (4.0s full duration). */
    public static inline var BOOST_DRAIN_RATE:Float = 0.25;

    /** Nitrous fuel automatic regeneration recovery rate per second (10.0s to full tank). */
    public static inline var BOOST_RECHARGE_RATE:Float = 0.10;

    /** Whether the vehicle is actively consuming nitrous oxide thrust this frame. */
    public var isBoosting:Bool = false;

    /** Active vehicle performance and dynamics tuning configuration. */
    public var config:VehicleConfigData;

    // =========================================================================
    // FOUR-WHEEL SUSPENSION STATE & CONTACT ARRAYS
    // Wheel order: 0 = Front-Left (FL), 1 = Front-Right (FR), 2 = Rear-Left (RL), 3 = Rear-Right (RR)
    // =========================================================================

    /** Local chassis offset coordinates for each wheel attachment point [X, Y]. */
    public static var WHEEL_OFFSETS(default, never):Array<{x:Float, y:Float}> = [
        { x: -0.98, y:  1.35 }, // 0: FL
        { x:  0.98, y:  1.35 }, // 1: FR
        { x: -0.98, y: -1.35 }, // 2: RL
        { x:  0.98, y: -1.35 }  // 3: RR
    ];

    /** Current suspension spring extension length in meters for each wheel. */
    public var suspLength:Array<Float> = [0.45, 0.45, 0.45, 0.45];

    /** Previous frame suspension spring length for velocity differentiation. */
    public var prevSuspLength:Array<Float> = [0.45, 0.45, 0.45, 0.45];

    /** Normalized suspension compression ratio [0.0 = full droop, 1.0 = bottomed out]. */
    public var suspCompression:Array<Float> = [0.0, 0.0, 0.0, 0.0];

    /** Ground contact flag for each wheel. */
    public var wheelOnGround:Array<Bool> = [true, true, true, true];

    /** Wheel surface contact normal vectors in world coordinates. */
    public var wheelNormals:Array<Vector> = [
        new Vector(0, 0, 1),
        new Vector(0, 0, 1),
        new Vector(0, 0, 1),
        new Vector(0, 0, 1)
    ];

    /** Tire slip angle in radians for each wheel. */
    public var wheelSlipAngles:Array<Float> = [0.0, 0.0, 0.0, 0.0];

    /** Rotational angular velocity in rad/s for each wheel. */
    public var wheelSpinVelocity:Array<Float> = [0.0, 0.0, 0.0, 0.0];

    /** Ground contact elevation in meters beneath each wheel. */
    public var wheelGroundZ:Array<Float> = [0.0, 0.0, 0.0, 0.0];

    var scratchGroundNormal:Vector = new Vector(0, 0, 1);

    // =========================================================================
    // EASILY TUNABLE DRIVING PHYSICS RUNTIME PROPERTIES
    // =========================================================================

    /** Front vs rear tire slip bias [-1.0 .. 1.0]. Negative = rear bias / oversteer, Positive = front bias / understeer, 0.0 = neutral. */
    public var tireSlipBias(get, set):Float;
    inline function get_tireSlipBias():Float return config.tires.tireSlipBias;
    inline function set_tireSlipBias(v:Float):Float return config.tires.tireSlipBias = Math.max(-1.0, Math.min(1.0, v));

    /** Vehicle body slip angle threshold in radians required to trigger active drift physics. */
    public var driftTriggerAngle(get, set):Float;
    inline function get_driftTriggerAngle():Float return config.drift.driftTriggerAngle;
    inline function set_driftTriggerAngle(v:Float):Float return config.drift.driftTriggerAngle = Math.max(0.05, v);

    /** Dynamic chassis roll multiplier affecting suspension lean and spring compression. */
    public var bodyRollScale(get, set):Float;
    inline function get_bodyRollScale():Float return config.suspension.bodyRollScale;
    inline function set_bodyRollScale(v:Float):Float return config.suspension.bodyRollScale = Math.max(0.0, v);

    /** Global ground contact friction scalar multiplying tire adhesion and braking. */
    public var groundFriction(get, set):Float;
    inline function get_groundFriction():Float return config.tires.groundFriction;
    inline function set_groundFriction(v:Float):Float return config.tires.groundFriction = Math.max(0.1, v);

    /** Burnout wheelspin multiplier during standstill launches or full-throttle power corners. */
    public var wheelspinAmount(get, set):Float;
    inline function get_wheelspinAmount():Float return config.tires.wheelspinAmount;
    inline function set_wheelspinAmount(v:Float):Float return config.tires.wheelspinAmount = Math.max(0.0, v);

    /** Standard engine acceleration rate in m/s². */
    public var baseAcceleration(get, set):Float;
    inline function get_baseAcceleration():Float return config.baseAcceleration;
    inline function set_baseAcceleration(v:Float):Float return config.baseAcceleration = v;

    /** Nitrous oxide augmented acceleration rate in m/s². */
    public var boostAcceleration(get, set):Float;
    inline function get_boostAcceleration():Float return config.boostAcceleration;
    inline function set_boostAcceleration(v:Float):Float return config.boostAcceleration = v;

    // Static fallback constants matching configuration defaults for backwards compatibility
    public static inline var TOP_SPEED:Float = 68.0;
    public static inline var BOOST_TOP_SPEED:Float = 88.0;
    public static inline var ACCELERATION:Float = 28.0;
    public static inline var BOOST_ACCEL:Float = 48.0;
    public static inline var BRAKING:Float = 38.0;
    public static inline var REVERSE_TOP_SPEED:Float = 18.0;
    public static inline var DRAG_COEFF:Float = 0.0032;
    public static inline var ROLLING_RESISTANCE:Float = 2.0;

    // =========================================================================
    // PRE-ALLOCATED SCRATCH MATH VECTORS (ZERO GC ALLOCATIONS IN FRAME LOOPS)
    // =========================================================================
    var scratchFwd:Vector = new Vector();
    var scratchRight:Vector = new Vector();
    var scratchWheelWorld:Vector = new Vector();
    var scratchWheelPos3D:Vector = new Vector();
    var scratchSurfaceNormal:Vector = new Vector();

    /**
     * Constructs a new vehicle dynamics simulation instance.
     *
     * @param startX Initial world X position coordinate.
     * @param startY Initial world Y position coordinate.
     * @param startZ Initial world Z position coordinate.
     * @param initialConfig Optional vehicle performance configuration (defaults to `CarConfig.getDefault()`).
     */
    public function new(startX:Float = 0.0, startY:Float = 0.0, startZ:Float = 0.0, ?initialConfig:VehicleConfigData) {
        pos.set(startX, startY, startZ);
        this.config = (initialConfig != null) ? initialConfig : CarConfig.getDefault();
        engineRPM = config.drivetrain.idleRPM;

        var rest = config.suspension.restLength;
        for (i in 0...4) {
            suspLength[i] = rest;
            prevSuspLength[i] = rest;
        }
    }

    /**
     * Replaces the active vehicle configuration profile dynamically at runtime.
     *
     * @param newConfig Updated vehicle configuration data structure.
     */
    public function setConfig(newConfig:VehicleConfigData) {
        if (newConfig == null) return;
        this.config = newConfig;
    }

    /**
     * Advances the vehicle dynamics simulation by a delta time step.
     * Integrates raycast suspension, anti-roll bars, slip-angle tire forces,
     * arcade drift dynamics, powertrain RPM simulation, and chassis orientation.
     *
     * @param dt Delta time elapsed since last frame in seconds.
     * @param input Controller or touch input readings.
     * @param waypoints Optional track spline waypoints for raycast ground sampling.
     * @param groundProvider Optional IGroundProvider implementing terrain elevation and boundaries.
     */
    public function update(dt:Float, input:InputController, ?waypoints:Array<Vector>, ?groundProvider:world.IGroundProvider) {
        if (dt <= 0.0) return;
        // Clamp large frame hitch dt to avoid physics explosion
        var clampedDt = Math.min(dt, 0.05);

        // Calculate heading basis vectors in world horizontal plane
        var cosYaw = Math.cos(yaw);
        var sinYaw = Math.sin(yaw);
        var fwdX = -sinYaw;
        var fwdY =  cosYaw;
        var rightX =  cosYaw;
        var rightY =  sinYaw;

        scratchFwd.set(fwdX, fwdY, 0);
        scratchRight.set(rightX, rightY, 0);

        // 1. Raycast Suspension & Anti-Roll Bar Force Simulation
        updateSuspension(clampedDt, fwdX, fwdY, rightX, rightY, waypoints, groundProvider);

        // 2. Nitrous Oxide Fuel Depletion & Regeneration Simulation
        if (input.boost && boostFuel > 0.0) {
            boostFuel = Math.max(0.0, boostFuel - BOOST_DRAIN_RATE * clampedDt);
            isBoosting = (boostFuel > 0.0);
        } else {
            isBoosting = false;
            if (boostFuel < 1.0) {
                boostFuel = Math.min(1.0, boostFuel + BOOST_RECHARGE_RATE * clampedDt);
            }
        }

        // 3. Drivetrain, Engine RPM & Automatic Transmission Shifting
        updateDrivetrain(clampedDt, input);

        // 4. Longitudinal Acceleration & Braking Simulation
        updateLongitudinal(clampedDt, input);

        // 4. Lateral Tire Adhesion, Slip Angles & Cornering Grip
        updateLateralAndDrift(clampedDt, input, fwdX, fwdY, rightX, rightY);

        // 5. World Coordinate Position & Velocity Integration
        pos.x += (fwdX * forwardSpeed + rightX * lateralVelocity) * clampedDt;
        pos.y += (fwdY * forwardSpeed + rightY * lateralVelocity) * clampedDt;

        if (groundProvider != null) {
            var bRes = groundProvider.enforceBoundaries(pos, forwardSpeed, lateralVelocity);
            if (bRes.hitWall) {
                forwardSpeed *= bRes.speedMult;
                lateralVelocity *= bRes.latMult;
            }
        }

        // 6. Dynamic Chassis Roll & Pitch Suspension Settling
        updateChassisAttitude(clampedDt, input);
    }

    /**
     * Evaluates independent raycast spring-damper suspension for all 4 wheels.
     * Calculates contact normals and anti-roll bar forces across front and rear wheel pairs.
     */
    function updateSuspension(dt:Float, fwdX:Float, fwdY:Float, rightX:Float, rightY:Float, waypoints:Array<Vector>, ?groundProvider:world.IGroundProvider) {
        var susp = config.suspension;
        var restLen = susp.restLength;
        var k = susp.springRate;
        var c = susp.damping;
        var arbK = susp.antiRollStiffness;

        var totalSuspensionForceZ = 0.0;
        var groundContacts = 0;

        for (i in 0...4) {
            var offset = WHEEL_OFFSETS[i];

            // Transform wheel attachment point into world horizontal space
            var attachX = pos.x + (rightX * offset.x + fwdX * offset.y);
            var attachY = pos.y + (rightY * offset.x + fwdY * offset.y);
            var attachZ = pos.z;

            scratchWheelWorld.set(attachX, attachY, attachZ);

            var groundZ = 0.0;
            var nx = 0.0;
            var ny = 0.0;
            var nz = 1.0;

            if (groundProvider != null) {
                groundZ = groundProvider.getGroundElevation(attachX, attachY);
                groundProvider.getGroundNormal(attachX, attachY, scratchGroundNormal);
                nx = scratchGroundNormal.x;
                ny = scratchGroundNormal.y;
                nz = scratchGroundNormal.z;
            } else if (waypoints != null && waypoints.length > 0) {
                var proj = SplineMath.getClosestSegment(scratchWheelWorld, waypoints);
                groundZ = proj.z;
                // Approximate track slope normal along segment
                nx = -proj.segDirY * 0.04;
                ny =  proj.segDirX * 0.04;
                nz = Math.sqrt(Math.max(0.01, 1.0 - (nx * nx + ny * ny)));
            } else {
                groundZ = 0.0;
            }

            wheelGroundZ[i] = groundZ;
            wheelNormals[i].set(nx, ny, nz);

            // Distance from wheel chassis mount to road contact plane
            // Incorporate dynamic body roll lean: outer wheels compress and inner wheels extend
            var rollTravelDelta = offset.x * Math.sin(roll) * config.suspension.bodyRollScale;
            var currentLen = (attachZ - groundZ) + rollTravelDelta;
            prevSuspLength[i] = suspLength[i];

            if (currentLen <= restLen) {
                wheelOnGround[i] = true;
                groundContacts++;
                suspLength[i] = Math.max(susp.minTravel, Math.min(restLen, currentLen));
                suspCompression[i] = Math.max(0.0, (restLen - suspLength[i]) / (restLen - susp.minTravel));

                // Spring-damper force calculation: F = (k * (restLength - currentLength) - c * suspVelocity)
                var compressionDelta = restLen - suspLength[i];
                var suspVelocity = (prevSuspLength[i] - suspLength[i]) / dt;
                var springForce = (k * compressionDelta - c * suspVelocity);
                if (springForce < 0.0) springForce = 0.0;

                totalSuspensionForceZ += springForce * nz;
            } else {
                // Wheel is airborne in full droop
                wheelOnGround[i] = false;
                suspLength[i] = Math.min(susp.maxTravel, currentLen);
                suspCompression[i] = 0.0;
            }
        }

        // Anti-roll bar torque across opposing wheel pairs:
        // Front axle: FL (0) vs FR (1)
        var frontTravelDiff = (restLen - suspLength[0]) - (restLen - suspLength[1]);
        var frontArbForce = frontTravelDiff * arbK;

        // Rear axle: RL (2) vs RR (3)
        var rearTravelDiff = (restLen - suspLength[2]) - (restLen - suspLength[3]);
        var rearArbForce = rearTravelDiff * arbK;

        // Apply opposing anti-roll moments to chassis roll angle
        var arbRollMoment = (frontArbForce + rearArbForce) / config.mass;
        roll -= arbRollMoment * 0.0004 * dt;

        // Vertical elevation equilibrium integration
        if (groundContacts > 0) {
            // Target equilibrium elevation: chassis rests at spring rest height above average ground contact
            var targetZ = 0.0;
            if (groundProvider != null) {
                targetZ = groundProvider.getGroundElevation(pos.x, pos.y);
            } else if (waypoints != null && waypoints.length > 0) {
                var centerProj = SplineMath.getClosestSegment(pos, waypoints);
                targetZ = centerProj.z;
            }
            // Smoothly track elevation with spring-damper absorption
            pos.z += (targetZ - pos.z) * Math.min(1.0, 16.0 * dt);
            verticalVelocity = 0.0;
        } else {
            // Freefall ballistic gravity
            verticalVelocity -= 9.81 * dt;
            pos.z += verticalVelocity * dt;
        }
    }

    /**
     * Simulates engine flywheel RPM, progressive gear ratios, automatic shifting,
     * and simulated limited-slip differential power distribution.
     */
    function updateDrivetrain(dt:Float, input:InputController) {
        var dtCfg = config.drivetrain;

        // Shifting disengagement latency cooldown
        if (shiftTimer > 0.0) {
            shiftTimer -= dt;
            if (shiftTimer <= 0.0) {
                isShifting = false;
            }
        }

        var speedAbs = Math.abs(forwardSpeed);
        var tireRadius = 0.36; // 36cm sports tire radius
        var wheelCircumference = 2.0 * Math.PI * tireRadius;
        var wheelRPM = (speedAbs / wheelCircumference) * 60.0;

        // Select current effective gear ratio
        var gearRatio = 1.0;
        if (forwardSpeed < -0.5) {
            currentGear = -1;
            gearRatio = Math.abs(dtCfg.reverseRatio);
        } else {
            if (currentGear < 1) currentGear = 1;
            var gearIdx = Math.min(currentGear - 1, dtCfg.gearRatios.length - 1);
            gearRatio = dtCfg.gearRatios[Math.floor(gearIdx)];
        }

        // Calculate theoretical engine RPM connected through transmission and final drive
        var targetRPM = dtCfg.idleRPM + (wheelRPM * gearRatio * dtCfg.finalDrive * 0.42);

        // Add throttle flare when clutching / shifting or revving at low wheel speed
        if (isShifting || (speedAbs < 1.0 && input.throttle > 0.0)) {
            targetRPM = Math.max(targetRPM, dtCfg.idleRPM + (input.throttle * 4500.0));
        }

        targetRPM = Math.max(dtCfg.idleRPM, Math.min(dtCfg.redlineRPM, targetRPM));

        // Smooth RPM needle response
        engineRPM += (targetRPM - engineRPM) * Math.min(1.0, 14.0 * dt);

        // Automatic Transmission Shift Logic
        if (currentGear > 0 && !isShifting) {
            var numGears = dtCfg.gearRatios.length;
            if (engineRPM > dtCfg.shiftUpRPM && currentGear < numGears && speedAbs > 8.0) {
                // Shift Up
                currentGear++;
                isShifting = true;
                shiftTimer = dtCfg.shiftDelay;
                engineRPM *= 0.72; // RPM drop on upshift
            } else if (engineRPM < dtCfg.shiftDownRPM && currentGear > 1 && speedAbs < (TOP_SPEED * (currentGear / numGears) * 0.75)) {
                // Shift Down
                currentGear--;
                isShifting = true;
                shiftTimer = dtCfg.shiftDelay;
                engineRPM = Math.min(dtCfg.redlineRPM, engineRPM * 1.35); // RPM blip on downshift
            }
        }

        // Simulated Limited-Slip Differential (LSD):
        // Balances wheel spin velocities between driven rear wheels (index 2 = RL, 3 = RR)
        var rearAvgSpin = (wheelSpinVelocity[2] + wheelSpinVelocity[3]) * 0.5;
        var lsdLock = dtCfg.lsdLockRatio;
        wheelSpinVelocity[2] += (rearAvgSpin - wheelSpinVelocity[2]) * lsdLock * Math.min(1.0, 15.0 * dt);
        wheelSpinVelocity[3] += (rearAvgSpin - wheelSpinVelocity[3]) * lsdLock * Math.min(1.0, 15.0 * dt);
    }

    /**
     * Integrates longitudinal throttle propulsion, threshold braking, burnout wheelspin, and aerodynamic drag.
     */
    function updateLongitudinal(dt:Float, input:InputController) {
        var mu = config.tires.groundFriction;
        var maxSpeed = isBoosting ? config.boostTopSpeed : config.baseTopSpeed;
        var accelRate = (isBoosting ? config.boostAcceleration : config.baseAcceleration) * mu;

        // Drivetrain torque delivery scaled by shift disengagement
        var throttleEff = isShifting ? (input.throttle * 0.25) : input.throttle;

        var speedAbs = Math.abs(forwardSpeed);

        // Standstill or low-speed launch burnout wheelspin
        var isBurnoutLaunch = (speedAbs < 8.0 && throttleEff > 0.75);
        if (isBurnoutLaunch) {
            var burnoutRatio = (1.0 - speedAbs / 8.0) * throttleEff * config.tires.wheelspinAmount;
            wheelSpinVelocity[2] += burnoutRatio * 140.0 * dt;
            wheelSpinVelocity[3] += burnoutRatio * 140.0 * dt;
            // Slight initial slip reduction during heavy burnout
            accelRate *= Math.max(0.65, 1.0 - burnoutRatio * 0.35);
        }

        if (throttleEff > 0.0) {
            if (forwardSpeed < maxSpeed) {
                // Forward engine acceleration clamped to terminal speed
                forwardSpeed += accelRate * throttleEff * dt;
            }
        } else if (input.brake > 0.0) {
            if (forwardSpeed > 0.5) {
                // Progressive service braking
                forwardSpeed = Math.max(0.0, forwardSpeed - config.brakeDecel * mu * input.brake * dt);
            } else {
                // Reverse propulsion once stopped
                forwardSpeed = Math.max(-config.reverseTopSpeed, forwardSpeed - (config.baseAcceleration * 0.5) * mu * input.brake * dt);
            }
        } else {
            // Coasting deceleration: rolling resistance + quadratic aerodynamic drag
            var sign = forwardSpeed > 0 ? 1.0 : -1.0;
            var decel = (config.tires.rollingResistance * mu + (forwardSpeed * forwardSpeed * config.aero.dragCoeff)) * dt;
            if (Math.abs(forwardSpeed) <= decel) {
                forwardSpeed = 0.0;
            } else {
                forwardSpeed -= sign * decel;
            }
        }
    }

    /**
     * Simulates tire slip angle adhesion curves, lateral cornering grip, front/rear slip bias,
     * handbrake traction breakaway, drift state transitions, counter-steer torque injection,
     * cornering wheelspin, and forward momentum biasing.
     */
    function updateLateralAndDrift(dt:Float, input:InputController, fwdX:Float, fwdY:Float, rightX:Float, rightY:Float) {
        var driftCfg = config.drift;
        var tireCfg = config.tires;
        var speedAbs = Math.abs(forwardSpeed);
        var speedRatio = Math.min(1.0, speedAbs / config.baseTopSpeed);

        // 1. Slip Angle Calculation: alpha = atan2(vLateral, |vForward|)
        var slipAngle = Math.atan2(lateralVelocity, Math.max(0.5, speedAbs));

        // Evaluate normalized lateral grip curve
        var normalizedAlpha = slipAngle / tireCfg.peakSlipAngle;
        // Arcade Pacejka-like grip saturation curve: 2 * x / (1 + x^2)
        var gripFactor = (2.0 * normalizedAlpha) / (1.0 + (normalizedAlpha * normalizedAlpha));
        gripFactor = Math.max(-1.0, Math.min(1.0, gripFactor));

        // 2. Front vs Rear Tire Slip Bias:
        // tireSlipBias [-1.0 .. 1.0]:
        // Negative = rear bias / oversteer (rear slips more, tail kicks out easily)
        // Positive = front bias / understeer (front slips more, car pushes wide)
        // 0.0 = neutral / balanced slip
        var bias = tireCfg.tireSlipBias;
        var frontGripMult = (1.0 - bias * 0.40) * tireCfg.groundFriction;
        var rearGripMult = (1.0 + bias * 0.40) * tireCfg.groundFriction;

        // 3. Proper Handbrake Function:
        // Immediately breaks rear tire traction, locks rear wheels, and allows tail to swing out
        if (input.handbrake) {
            // Cut rear lateral grip dramatically (scaled with rear bias)
            rearGripMult *= (0.20 + (bias + 1.0) * 0.08);

            // Handbrake drag on longitudinal forward motion
            if (speedAbs > 0.5) {
                var hbDecel = 14.0 * tireCfg.groundFriction * dt;
                if (forwardSpeed > 0) forwardSpeed = Math.max(0.0, forwardSpeed - hbDecel);
                else forwardSpeed = Math.min(0.0, forwardSpeed + hbDecel);
            }

            // Induce yaw rotation into the turn if steering or sliding
            if (speedAbs > 2.0) {
                var yawSteer = input.steer != 0.0 ? input.steer : (lateralVelocity < 0 ? -0.8 : 0.8);
                yaw += yawSteer * 3.2 * dt;
                lateralVelocity += yawSteer * 20.0 * dt;
            }
        }

        // 4. Punching Throttle at Harsh Corners (Power Oversteer & Wheelspin):
        var isPowerTurn = (Math.abs(input.steer) > 0.25 && input.throttle > 0.75 && speedAbs > 4.0);
        if (isPowerTurn) {
            var spinKick = input.throttle * tireCfg.wheelspinAmount;
            wheelSpinVelocity[2] += spinKick * 60.0 * dt;
            wheelSpinVelocity[3] += spinKick * 60.0 * dt;
            // Power oversteer loosens rear grip and rotates car into apex
            rearGripMult *= Math.max(0.25, 1.0 - (tireCfg.wheelspinAmount * 0.35));
            yaw += input.steer * 1.8 * tireCfg.wheelspinAmount * dt;
        }

        // 5. Vehicle Chassis Slip Angle & Drift Trigger Evaluation:
        // carSlipAngle: angle between chassis forward heading and velocity vector
        var carSlipAngle = Math.atan2(Math.abs(lateralVelocity), Math.max(1.0, speedAbs));
        var triggerAngle = driftCfg.driftTriggerAngle;

        // Drift Initiation:
        // Triggers if handbrake is pulled OR if vehicle slip angle reaches or exceeds driftTriggerAngle
        var driftInitiatedByHandbrake = input.handbrake && Math.abs(input.steer) > 0.15;
        var driftInitiatedByAngle = (carSlipAngle >= triggerAngle && Math.abs(input.steer) > 0.18);
        var driftInitiatedByBrakeFlick = (input.brake > 0.2 && input.throttle > 0.1 && Math.abs(input.steer) > 0.22);

        if (!isDrifting && (driftInitiatedByHandbrake || driftInitiatedByAngle || driftInitiatedByBrakeFlick) && speedAbs > driftCfg.minDriftSpeed) {
            isDrifting = true;
            driftDirection = (lateralVelocity != 0.0) ? (lateralVelocity < 0.0 ? -1.0 : 1.0) : (input.steer < 0.0 ? -1.0 : 1.0);
        }

        // Exit drift if vehicle drops below exit speed or aligns back within threshold
        if (isDrifting) {
            var counterSteeringOut = (driftDirection > 0 && input.steer < -0.70) || (driftDirection < 0 && input.steer > 0.70);
            var isStraightenedOut = (carSlipAngle < (triggerAngle * 0.35) && !input.handbrake && Math.abs(input.steer) < 0.10);
            if (speedAbs < driftCfg.driftExitSpeed || counterSteeringOut || isStraightenedOut) {
                isDrifting = false;
            }
        }

        // 6. Lateral Cornering & Drift Yaw Simulation
        if (isDrifting) {
            // Target slip angle orientation biased towards slide direction
            var targetAngle = driftDirection * 0.65;
            driftAngle += (targetAngle - driftAngle) * 5.5 * dt;

            // Lateral tire stiffness is scaled down during drift (scaled with rear grip)
            var lateralStiffness = tireCfg.baseLateralStiffness * driftCfg.lateralStiffnessScale * rearGripMult;

            // Inject artificial counter-steer-assisted yaw torque:
            // Counter-steering stabilizes slide angle, steering with slide tightens yaw
            var counterSteerFactor = (input.steer * driftDirection < 0) ? driftCfg.counterSteerTorque : 1.5;
            var yawImpulse = (driftDirection * driftCfg.driftYawRate + input.steer * counterSteerFactor) * dt;
            yaw += yawImpulse;

            // Lateral slide injection damped by stickiness
            lateralVelocity += driftDirection * (16.0 * (1.0 - bias * 0.25)) * dt;
            lateralVelocity *= Math.pow(0.88, dt * 60.0);

            // Forward Velocity Biasing:
            // Blends linear velocity vector toward forward heading orientation to prevent spinout
            var biasFactor = Math.min(1.0, driftCfg.forwardBiasRate * dt);
            lateralVelocity *= (1.0 - biasFactor * 0.45);
        } else {
            // Re-align visual chassis slip angle back towards vehicle centerline
            driftAngle += (0.0 - driftAngle) * 10.0 * dt;

            // Normal cornering: standard lateral grip restoring velocity towards zero
            var gripDecay = Math.pow(Math.max(0.1, 0.50 / frontGripMult), dt * 60.0);
            lateralVelocity *= gripDecay;

            // Standard Ackermann steering rack cornering authority scaled with speed & front grip
            if (speedAbs > 0.2) {
                var steerAuthority = 2.2 * Math.min(1.0, speedRatio + 0.35) * frontGripMult;
                var fwdSign = forwardSpeed >= 0 ? 1.0 : -1.0;
                yaw += (input.steer * steerAuthority * fwdSign) * dt;
            }
        }
    }

    /**
     * Calculates dynamic chassis body roll and pitch based on weight transfer and anti-roll bars.
     * Clamps roll on flat road to prevent full overturn without a track bump or ramp causing it.
     */
    function updateChassisAttitude(dt:Float, input:InputController) {
        var speedRatio = Math.min(1.0, Math.abs(forwardSpeed) / config.baseTopSpeed);

        // Body Roll: Centrifugal lateral weight transfer scaled by bodyRollScale
        var targetRoll = -input.steer * speedRatio * 0.14 * config.suspension.bodyRollScale;
        if (isDrifting) targetRoll *= 1.7;

        // Dynamic terrain slope conforming: pitch and roll from 4-wheel contact elevation differences
        var frontAvgZ = (wheelGroundZ[0] + wheelGroundZ[1]) * 0.5;
        var rearAvgZ  = (wheelGroundZ[2] + wheelGroundZ[3]) * 0.5;
        var terrainPitch = Math.atan2(frontAvgZ - rearAvgZ, 2.7);

        var leftAvgZ  = (wheelGroundZ[0] + wheelGroundZ[2]) * 0.5;
        var rightAvgZ = (wheelGroundZ[1] + wheelGroundZ[3]) * 0.5;
        var terrainRoll = Math.atan2(rightAvgZ - leftAvgZ, 1.96);

        // Clamp dynamic suspension lean
        var maxRoll = 0.25 * Math.min(1.5, Math.max(0.5, config.suspension.bodyRollScale));
        targetRoll = Math.max(-maxRoll, Math.min(maxRoll, targetRoll));

        roll += (targetRoll + terrainRoll - roll) * 8.0 * dt;

        // Pitch: Longitudinal acceleration squat, braking dive, and terrain slope pitch
        var targetPitch = (input.throttle - input.brake) * 0.06;
        pitch += (targetPitch + terrainPitch - pitch) * 8.0 * dt;
    }
}