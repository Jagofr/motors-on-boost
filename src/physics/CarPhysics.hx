package physics;

import h3d.Vector;
import input.InputController;
import physics.CarConfig.VehicleConfigData;
import oimo.dynamics.World;
import oimo.dynamics.rigidbody.RigidBody;
import oimo.dynamics.rigidbody.RigidBodyConfig;
import oimo.dynamics.rigidbody.RigidBodyType;
import oimo.dynamics.rigidbody.Shape;
import oimo.dynamics.rigidbody.ShapeConfig;
import oimo.collision.geometry.BoxGeometry;
import oimo.common.Vec3;
import oimo.common.Mat3;
import oimo.common.Quat;

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
 * High-performance hybrid vehicle dynamics simulator combining an OimoPhysics 3D rigid body
 * backbone for mass, inertia, world collisions, and restitution, driven by analytical multi-link
 * raycast suspension, Pacejka slip-angle tire adhesion, and Criterion-style brake-to-drift mechanics.
 * Designed with zero runtime allocations in frame update loops.
 */
class CarPhysics {
    /** Underlying OimoPhysics rigid body simulation world. */
    public var physicsWorld:World;

    /** 3D inertial rigid body representing vehicle chassis and collision hull. */
    public var chassisBody:RigidBody;

    /** World position of the vehicle chassis contact center point. */
    public var pos:Vector = new Vector();

    /** Yaw orientation in radians (rotation about world Z-axis; 0.0 = facing +Y Forward). */
    public var yaw(default, set):Float = 0.0;
    function set_yaw(v:Float):Float {
        yaw = v;
        if (chassisBody != null) {
            var m = new Mat3().fromEulerXyz(new Vec3(pitch, roll, -v));
            chassisBody.setOrientation(m.toQuat());
        }
        return v;
    }

    /** Dynamic chassis pitch in radians (squat on acceleration, dive on braking). */
    public var pitch:Float = 0.0;

    /** Dynamic chassis roll in radians (lateral centrifugal roll dampened by anti-roll bars). */
    public var roll:Float = 0.0;

    /** Forward longitudinal velocity along vehicle heading vector in m/s. */
    public var forwardSpeed(default, set):Float = 0.0;
    function set_forwardSpeed(v:Float):Float {
        forwardSpeed = v;
        if (chassisBody != null) {
            var cosY = Math.cos(yaw);
            var sinY = Math.sin(yaw);
            var curVel = chassisBody.getLinearVelocity();
            chassisBody.setLinearVelocity(new Vec3(sinY * v, cosY * v, curVel.z));
        }
        return v;
    }

    /** Lateral slip velocity perpendicular to vehicle forward heading in m/s. */
    public var lateralVelocity:Float = 0.0;

    /** Vertical chassis velocity in m/s. */
    public var verticalVelocity:Float = 0.0;

    /** Flag indicating whether the vehicle has ground contact on at least 2 wheels. */
    public var isGrounded:Bool = true;

    /** Ground contact state in the previous physics frame for transition buffering. */
    public var wasGrounded:Bool = true;

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
    // HYBRID SIM-CADE HANDLING CONSTANTS (SKLL.md)
    // =========================================================================
    public static inline var FAKE_DOWNFORCE_COEFF:Float = 0.45;
    public static inline var LATERAL_GRIP_COEFF:Float = 12.0;
    public static inline var YAW_DAMPING:Float = 8.5;
    public static inline var SIGMA_REDIRECT:Float = 0.25;
    public static inline var AIR_LEVELING_STIFFNESS:Float = 40.0;
    public static inline var AIR_DAMPING:Float = 5.0;
    public static inline var AFTERTOUCH_STIFFNESS:Float = 15.0;
    public static inline var LANDING_ABSORB_RATIO:Float = 0.30;

    // Pre-allocated scratch objects for zero GC churn in frame loops
    var scratchVec3A:Vec3 = new Vec3();
    var scratchVec3B:Vec3 = new Vec3();
    var scratchVec3C:Vec3 = new Vec3();
    var scratchMat3:Mat3 = new Mat3();
    var scratchWheelWorld:Vector = new Vector();

    /**
     * Constructs a new vehicle dynamics simulation instance backed by OimoPhysics.
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

        initOimoPhysics(startX, startY, startZ);
    }

    /**
     * Allocates and initializes the OimoPhysics rigid body world, inertia tensor, and chassis collision box.
     */
    function initOimoPhysics(startX:Float, startY:Float, startZ:Float) {
        physicsWorld = new World();
        physicsWorld.setGravity(new Vec3(0, 0, -9.81));

        var rbConfig = new RigidBodyConfig();
        rbConfig.type = RigidBodyType.DYNAMIC;
        rbConfig.position = new Vec3(startX, startY, startZ + 0.35);
        chassisBody = new RigidBody(rbConfig);

        var shapeConfig = new ShapeConfig();
        // Half-extents: 0.94m width, 2.15m length, 0.22m height (Total: 1.88 x 4.30 x 0.44m matching full CarMesh bounds)
        shapeConfig.geometry = new BoxGeometry(new Vec3(0.94, 2.15, 0.22));
        shapeConfig.density = config.mass / (1.88 * 4.30 * 0.44);
        // Zero-Friction Rule (SKLL.md): Decouple rigid body friction from custom sim-cade mechanics
        shapeConfig.friction = 0.0;
        shapeConfig.restitution = 0.0;
        chassisBody.addShape(new Shape(shapeConfig));

        var initialRot = new Mat3().fromEulerXyz(new Vec3(0, 0, -yaw));
        chassisBody.setOrientation(initialRot.toQuat());

        physicsWorld.addRigidBody(chassisBody);
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
     * Resets the vehicle transform, velocities, transmission, and Oimo rigid body.
     */
    public function resetState(startX:Float, startY:Float, startZ:Float, newYaw:Float = 0.0):Void {
        pos.set(startX, startY, startZ);
        yaw = newYaw;
        pitch = 0.0;
        roll = 0.0;
        forwardSpeed = 0.0;
        lateralVelocity = 0.0;
        verticalVelocity = 0.0;
        isGrounded = true;
        wasGrounded = true;
        isDrifting = false;
        driftDirection = 0.0;
        driftAngle = 0.0;
        currentGear = 1;
        engineRPM = config.drivetrain.idleRPM;
        boostFuel = 1.0;
        isBoosting = false;

        var rest = config.suspension.restLength;
        for (i in 0...4) {
            suspLength[i] = rest;
            prevSuspLength[i] = rest;
            suspCompression[i] = 0.0;
            wheelOnGround[i] = true;
            wheelSpinVelocity[i] = 0.0;
        }

        if (chassisBody != null) {
            chassisBody.setPosition(new Vec3(startX, startY, startZ + 0.35));
            var m = new Mat3().fromEulerXyz(new Vec3(0, 0, -newYaw));
            chassisBody.setOrientation(m.toQuat());
            chassisBody.setLinearVelocity(new Vec3(0, 0, 0));
            chassisBody.setAngularVelocity(new Vec3(0, 0, 0));
        }
    }

    /**
     * Synchronizes the OimoPhysics chassis rigid body directly from external position/velocity mutations
     * (such as traffic collisions or guardrail clamping).
     */
    public function syncToOimoBody():Void {
        if (chassisBody == null) return;
        chassisBody.setPosition(new Vec3(pos.x, pos.y, pos.z + 0.35));
        var m = new Mat3().fromEulerXyz(new Vec3(pitch, roll, -yaw));
        chassisBody.setOrientation(m.toQuat());
        var fwdX = Math.sin(yaw);
        var fwdY = Math.cos(yaw);
        var rightX = Math.cos(yaw);
        var rightY = -Math.sin(yaw);
        chassisBody.setLinearVelocity(new Vec3(
            fwdX * forwardSpeed + rightX * lateralVelocity,
            fwdY * forwardSpeed + rightY * lateralVelocity,
            verticalVelocity
        ));
    }

    /**
     * Populates out vector with vehicle unit forward heading (+Y is forward at yaw = 0).
     */
    public function getForwardVector(?out:Vector):Vector {
        if (out == null) out = new Vector();
        out.set(Math.sin(yaw), Math.cos(yaw), 0);
        return out;
    }

    /**
     * Populates out vector with vehicle unit rightward vector (+X is right at yaw = 0).
     */
    public function getRightVector(?out:Vector):Vector {
        if (out == null) out = new Vector();
        out.set(Math.cos(yaw), -Math.sin(yaw), 0);
        return out;
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
        var clampedDt = Math.min(dt, 0.05);

        // Extract orientation matrix and basis vectors from Oimo chassis body
        var bRot = chassisBody.getRotation();
        var bPos = chassisBody.getPosition();
        var bLinVel = chassisBody.getLinearVelocity();

        // Column 1 is vehicle local forward (+Y): (e01, e11, e21)
        var fwdX = bRot.e01;
        var fwdY = bRot.e11;
        var fwdZ = bRot.e21;

        // Column 0 is vehicle local right (+X): (e00, e10, e20)
        var rightX = bRot.e00;
        var rightY = bRot.e10;
        var rightZ = bRot.e20;

        // Column 2 is vehicle local up (+Z): (e02, e12, e22)
        var upX = bRot.e02;
        var upY = bRot.e12;
        var upZ = bRot.e22;

        // Project linear velocity onto chassis local axes
        forwardSpeed = bLinVel.x * fwdX + bLinVel.y * fwdY + bLinVel.z * fwdZ;
        lateralVelocity = bLinVel.x * rightX + bLinVel.y * rightY + bLinVel.z * rightZ;
        verticalVelocity = bLinVel.z;

        // 1. Raycast Suspension & Anti-Roll Bar Force Simulation
        updateSuspension(clampedDt, bPos, bRot, bLinVel, fwdX, fwdY, rightX, rightY, upX, upY, upZ, waypoints, groundProvider);

        // Landing Transition Check (CRASH / LANDING BUFFER pipeline per SKLL.md)
        if (!wasGrounded && isGrounded) {
            var curVel = chassisBody.getLinearVelocity();
            if (curVel.z < -1.0) {
                var downwardSpeed = Math.min(10.0, Math.abs(curVel.z));
                var forwardBoost = downwardSpeed * LANDING_ABSORB_RATIO;
                forwardSpeed += forwardBoost;
                scratchVec3A.init(
                    curVel.x + fwdX * forwardBoost,
                    curVel.y + fwdY * forwardBoost,
                    curVel.z * 0.25
                );
                chassisBody.setLinearVelocity(scratchVec3A);
            }
        }
        wasGrounded = isGrounded;

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

        if (isGrounded) {
            // =================================================================
            // GROUND STATE: MID-GEN NEED FOR SPEED "GLUED TO GROUND" STYLE
            // =================================================================

            // A. Aerodynamic Downforce: (mass * gNormal * 0.15) + (cFakeDownforce * speedForward^2) + aero downforce
            var speedFwdSq = forwardSpeed * forwardSpeed;
            var downforceMag = (config.mass * 9.81 * 0.15) + (FAKE_DOWNFORCE_COEFF * speedFwdSq) + (0.5 * 1.225 * speedFwdSq * config.aero.downforceCoeff);
            scratchVec3A.init(-upX * downforceMag, -upY * downforceMag, -upZ * downforceMag);
            chassisBody.applyForceToCenter(scratchVec3A);

            // B. Longitudinal Acceleration, Service Braking & Drag Force
            var netLongForce = computeLongitudinalForce(clampedDt, input, groundProvider);
            scratchVec3A.init(fwdX * netLongForce, fwdY * netLongForce, fwdZ * netLongForce);
            chassisBody.applyForceToCenter(scratchVec3A);

            // C. Lateral Tire Cornering, Pacejka Slip Curves, Handbrake & Drift Moments
            updateLateralAndDrift(clampedDt, input, fwdX, fwdY, rightX, rightY, rightZ, upX, upY, upZ, downforceMag, groundProvider);

            // D. Rigid Yaw Gyroscopic Stabilization
            // Damps uncommanded yaw spin while steering is controlled by Ackermann rack authority
            var curAngVel = chassisBody.getAngularVelocity();
            var wYaw = curAngVel.x * upX + curAngVel.y * upY + curAngVel.z * upZ;
            var gyroscopicDamping = -wYaw * YAW_DAMPING * config.yawInertia * 0.006;
            scratchVec3A.init(upX * gyroscopicDamping, upY * gyroscopicDamping, upZ * gyroscopicDamping);
            chassisBody.applyTorque(scratchVec3A);

            // Slope terrain conformity: align chassis local up with average contact normal
            // Evaluated in vehicle local pitch/roll axes to ensure consistent behavior across all yaw angles
            var avgNx = (wheelNormals[0].x + wheelNormals[1].x + wheelNormals[2].x + wheelNormals[3].x) * 0.25;
            var avgNy = (wheelNormals[0].y + wheelNormals[1].y + wheelNormals[2].y + wheelNormals[3].y) * 0.25;
            var avgNz = (wheelNormals[0].z + wheelNormals[1].z + wheelNormals[2].z + wheelNormals[3].z) * 0.25;
            var errX = upY * avgNz - upZ * avgNy;
            var errY = upZ * avgNx - upX * avgNz;
            var errZ = upX * avgNy - upY * avgNx;
            var pitchErr = errX * rightX + errY * rightY + errZ * rightZ;
            var rollErr = errX * fwdX + errY * fwdY + errZ * fwdZ;
            var pitchAngVel = curAngVel.x * rightX + curAngVel.y * rightY + curAngVel.z * rightZ;
            var rollAngVel = curAngVel.x * fwdX + curAngVel.y * fwdY + curAngVel.z * fwdZ;
            var tPitch = (pitchErr * 12.0 * config.pitchInertia) - (pitchAngVel * 2.0 * config.pitchInertia);
            var tRoll = (rollErr * 12.0 * config.rollInertia) - (rollAngVel * 2.0 * config.rollInertia);
            scratchVec3A.init(
                rightX * tPitch + fwdX * tRoll,
                rightY * tPitch + fwdY * tRoll,
                rightZ * tPitch + fwdZ * tRoll
            );
            chassisBody.applyTorque(scratchVec3A);

            // E. Energy Redirection (SKLL.md):
            // Redirect fraction of lateral slide speed back into forward acceleration force
            var absVLateral = Math.abs(lateralVelocity);
            var speedAbs = Math.abs(forwardSpeed);
            if (speedAbs > 2.0 && absVLateral > 0.25) {
                var redirectMag = absVLateral * SIGMA_REDIRECT * config.mass * 2.0;
                scratchVec3A.init(fwdX * redirectMag, fwdY * redirectMag, 0.0);
                chassisBody.applyForceToCenter(scratchVec3A);
            }

            // F. Standstill clamping and pitch/roll damping to eliminate stopped chatter
            if (speedAbs < 0.25 && absVLateral < 0.25 && input.throttle == 0.0 && input.brake == 0.0) {
                var curLinV = chassisBody.getLinearVelocity();
                scratchVec3A.init(curLinV.x * 0.85, curLinV.y * 0.85, curLinV.z);
                chassisBody.setLinearVelocity(scratchVec3A);
                forwardSpeed = 0.0;
                lateralVelocity = 0.0;
                scratchVec3B.init(curAngVel.x * 0.50, curAngVel.y * 0.50, curAngVel.z * 0.50);
                chassisBody.setAngularVelocity(scratchVec3B);
            } else {
                scratchVec3B.init(curAngVel.x * 0.85, curAngVel.y * 0.85, curAngVel.z);
                chassisBody.setAngularVelocity(scratchVec3B);
            }

        } else {
            // =================================================================
            // AIRTIME STATE: BURNOUT "CINEMATIC ARC" STYLE
            // =================================================================

            // A. Dynamic Gravity Scaling: natural fall rate on ascent, crisp landing settling on descent
            var vVertical = bLinVel.z;
            var gravityMod = (vVertical > 0.0) ? 1.05 : 1.45;
            var deltaGravityZ = -config.mass * 9.81 * (gravityMod - 1.0);
            scratchVec3A.init(0, 0, deltaGravityZ);
            chassisBody.applyForceToCenter(scratchVec3A);

            // B. Automatic Gyroscopic Wheel Leveler:
            var curAngVel = chassisBody.getAngularVelocity();
            var tStabilizeX = upY * (config.pitchInertia * 0.015 * AIR_LEVELING_STIFFNESS) - curAngVel.x * (config.pitchInertia * 0.02 * AIR_DAMPING);
            var tStabilizeY = -upX * (config.rollInertia * 0.015 * AIR_LEVELING_STIFFNESS) - curAngVel.y * (config.rollInertia * 0.02 * AIR_DAMPING);
            scratchVec3A.init(tStabilizeX, tStabilizeY, 0);
            chassisBody.applyTorque(scratchVec3A);

            // C. Burnout Airborne Aftertouch Control:
            if (input.steer != 0.0) {
                var tAftertouch = -input.steer * config.yawInertia * AFTERTOUCH_STIFFNESS * 0.35;
                scratchVec3A.init(upX * tAftertouch, upY * tAftertouch, upZ * tAftertouch);
                chassisBody.applyTorque(scratchVec3A);
            }

            driftAngle += (0.0 - driftAngle) * 4.0 * clampedDt;
        }

        // 7. Advance OimoPhysics Rigid Body Dynamics
        physicsWorld.step(clampedDt);

        // 8. Synchronize State Back from Simulated Rigid Body
        bPos = chassisBody.getPosition();
        bRot = chassisBody.getRotation();
        bLinVel = chassisBody.getLinearVelocity();

        pos.x = bPos.x;
        pos.y = bPos.y;
        pos.z = bPos.z - 0.35;

        fwdX = bRot.e01; fwdY = bRot.e11; fwdZ = bRot.e21;
        rightX = bRot.e00; rightY = bRot.e10; rightZ = bRot.e20;

        forwardSpeed = bLinVel.x * fwdX + bLinVel.y * fwdY + bLinVel.z * fwdZ;
        lateralVelocity = bLinVel.x * rightX + bLinVel.y * rightY + bLinVel.z * rightZ;
        verticalVelocity = bLinVel.z;

        var euler = bRot.toEulerXyz();
        pitch = Math.max(-1.15, Math.min(1.15, euler.x));
        roll = Math.max(-0.85, Math.min(0.85, euler.y));
        yaw = -euler.z;

        // Dampen excessive roll angular velocity while preserving natural hill climb pitch
        var angVel = chassisBody.getAngularVelocity();
        chassisBody.setAngularVelocity(new Vec3(angVel.x * 0.94, angVel.y * 0.88, angVel.z));

        // 9. Boundary Constraints and Physical Floor Penetration Guard
        if (groundProvider != null) {
            var prevX = pos.x;
            var prevY = pos.y;
            var bRes = groundProvider.enforceBoundaries(pos, forwardSpeed, lateralVelocity);
            if (bRes.hitWall) {
                var dispX = pos.x - prevX;
                var dispY = pos.y - prevY;
                var dispLen = Math.sqrt(dispX * dispX + dispY * dispY);

                if (dispLen > 0.0001) {
                    var inNormX = dispX / dispLen;
                    var inNormY = dispY / dispLen;
                    var wallNormX = -inNormX;
                    var wallNormY = -inNormY;
                    var wallTangX = -wallNormY;
                    var wallTangY = wallNormX;

                    var curLinV = chassisBody.getLinearVelocity();
                    var vIntoWall = curLinV.x * wallNormX + curLinV.y * wallNormY;
                    var vTang = curLinV.x * wallTangX + curLinV.y * wallTangY;

                    var reboundV = (vIntoWall > 0.0) ? -0.30 * vIntoWall : 0.0;
                    var newTangV = vTang * 0.985;

                    var newVx = wallTangX * newTangV + inNormX * Math.abs(reboundV);
                    var newVy = wallTangY * newTangV + inNormY * Math.abs(reboundV);

                    var dotFwdIntoWall = fwdX * wallNormX + fwdY * wallNormY;
                    if (dotFwdIntoWall > 0.05) {
                        var alignSign = (newTangV >= 0.0) ? 1.0 : -1.0;
                        var targetTangYaw = Math.atan2(wallTangX * alignSign, wallTangY * alignSign);
                        var yawDiff = targetTangYaw - yaw;
                        while (yawDiff > Math.PI) yawDiff -= Math.PI * 2.0;
                        while (yawDiff < -Math.PI) yawDiff += Math.PI * 2.0;
                        yaw += yawDiff * Math.min(1.0, 6.0 * clampedDt);
                        var newRot = new Mat3().fromEulerXyz(new Vec3(pitch, roll, -yaw));
                        chassisBody.setOrientation(newRot.toQuat());
                        fwdX = newRot.e01; fwdY = newRot.e11; fwdZ = newRot.e21;
                        rightX = newRot.e00; rightY = newRot.e10; rightZ = newRot.e20;
                    }

                    forwardSpeed = newVx * fwdX + newVy * fwdY;
                    lateralVelocity = newVx * rightX + newVy * rightY;
                    chassisBody.setPosition(new Vec3(pos.x, pos.y, bPos.z));
                    scratchVec3A.init(newVx, newVy, curLinV.z * 0.5);
                    chassisBody.setLinearVelocity(scratchVec3A);
                } else {
                    forwardSpeed *= bRes.speedMult;
                    lateralVelocity *= bRes.latMult;
                    chassisBody.setPosition(new Vec3(pos.x, pos.y, bPos.z));
                    scratchVec3A.init(fwdX * forwardSpeed + rightX * lateralVelocity, fwdY * forwardSpeed + rightY * lateralVelocity, verticalVelocity * 0.5);
                    chassisBody.setLinearVelocity(scratchVec3A);
                }
            }

            // Physical Chassis Belly Contact Guard:
            // Prevents subterranean chassis penetration on steep impacts or bottoming out
            var groundZ = groundProvider.getGroundElevation(bPos.x, bPos.y);
            var minChassisZ = groundZ + 0.22 * Math.max(0.2, upZ);
            if (bPos.z < minChassisZ) {
                var pen = minChassisZ - bPos.z;
                bPos.z = minChassisZ;
                chassisBody.setPosition(bPos);
                pos.z = bPos.z;

                var curV = chassisBody.getLinearVelocity();
                if (curV.z < 0.0) {
                    curV.z = 0.0;
                    chassisBody.setLinearVelocity(curV);
                }

                groundProvider.getGroundNormal(bPos.x, bPos.y, scratchGroundNormal);
                var bounceForce = pen * config.mass * 250.0;
                scratchVec3A.init(scratchGroundNormal.x * bounceForce, scratchGroundNormal.y * bounceForce, scratchGroundNormal.z * bounceForce);
                chassisBody.applyForceToCenter(scratchVec3A);
            }
        }
    }

    /**
     * Evaluates independent raycast spring-damper suspension for all 4 wheels.
     * Calculates contact normals and applies upward spring-damper reaction forces to the Oimo chassis.
     */
    function updateSuspension(
        dt:Float,
        bPos:Vec3,
        bRot:Mat3,
        bLinVel:Vec3,
        fwdX:Float,
        fwdY:Float,
        rightX:Float,
        rightY:Float,
        upX:Float,
        upY:Float,
        upZ:Float,
        waypoints:Array<Vector>,
        ?groundProvider:world.IGroundProvider
    ) {
        var susp = config.suspension;
        var restLen = susp.restLength;
        var k = susp.springRate;
        var c = susp.damping;
        var arbK = susp.antiRollStiffness;

        var groundContacts = 0;

        for (i in 0...4) {
            var offset = WHEEL_OFFSETS[i];

            // Transform suspension mount point into world 3D space using full chassis orientation
            var relX = rightX * offset.x + fwdX * offset.y;
            var relY = rightY * offset.x + fwdY * offset.y;
            var relZ = bRot.e20 * offset.x + bRot.e21 * offset.y;
            var attachX = bPos.x + relX;
            var attachY = bPos.y + relY;
            var attachZ = bPos.z + relZ;

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
                groundZ = proj.z + world.Track.ROAD_LIFT;
                nx = -proj.segDirY * 0.04;
                ny =  proj.segDirX * 0.04;
                nz = Math.sqrt(Math.max(0.01, 1.0 - (nx * nx + ny * ny)));
            } else {
                groundZ = 0.0;
            }

            wheelGroundZ[i] = groundZ;
            wheelNormals[i].set(nx, ny, nz);

            // Raycast distance along vehicle local down axis
            var currentLen = (attachZ - groundZ) / Math.max(0.3, upZ);
            prevSuspLength[i] = suspLength[i];

            if (currentLen <= restLen) {
                wheelOnGround[i] = true;
                groundContacts++;
                suspLength[i] = Math.max(susp.minTravel, Math.min(restLen, currentLen));
                suspCompression[i] = Math.max(0.0, (restLen - suspLength[i]) / (restLen - susp.minTravel));

                // Linear spring-damper: compression velocity is positive when compressing
                var compressionDelta = restLen - currentLen;
                var suspVelocity = (prevSuspLength[i] - currentLen) / dt;
                var springForce = (k * compressionDelta + c * suspVelocity);

                // Progressive bump-stop elastomer when compressed beyond minTravel
                if (currentLen < susp.minTravel) {
                    var bumpDelta = susp.minTravel - currentLen;
                    springForce += bumpDelta * k * 0.5;
                }
                if (springForce < 0.0) springForce = 0.0;
                var maxWheelForce = (config.mass * 9.81 * 0.25) * 2.5;
                if (springForce > maxWheelForce) springForce = maxWheelForce;

                // Apply upward physical suspension force to Oimo rigid body along contact normal
                scratchVec3A.init(nx * springForce, ny * springForce, nz * springForce);
                scratchVec3B.init(attachX, attachY, attachZ);
                chassisBody.applyForce(scratchVec3A, scratchVec3B);
            } else {
                // Wheel is airborne in full droop
                wheelOnGround[i] = false;
                suspLength[i] = Math.min(susp.maxTravel, currentLen);
                suspCompression[i] = 0.0;
            }
        }

        // Vehicle is grounded if at least 2 wheels maintain contact
        isGrounded = (groundContacts >= 2);

        // Anti-roll bar torque across opposing wheel pairs:
        // Front axle: FL (0) vs FR (1)
        var frontTravelDiff = (restLen - suspLength[0]) - (restLen - suspLength[1]);
        var frontArbForce = frontTravelDiff * arbK;

        // Rear axle: RL (2) vs RR (3)
        var rearTravelDiff = (restLen - suspLength[2]) - (restLen - suspLength[3]);
        var rearArbForce = rearTravelDiff * arbK;

        // Apply opposing anti-roll moments to chassis
        var arbRollMoment = (frontArbForce + rearArbForce) * 0.5;
        scratchVec3A.init(0, -arbRollMoment * 0.1, 0);
        chassisBody.applyTorque(scratchVec3A);
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
     * Calculates net longitudinal force in Newtons from engine throttle, braking, rolling resistance, and aerodynamic drag.
     */
    function computeLongitudinalForce(dt:Float, input:InputController, ?groundProvider:world.IGroundProvider):Float {
        var surfaceFriction = (groundProvider != null) ? groundProvider.getGroundFriction(pos.x, pos.y) : 1.0;
        var mu = config.tires.groundFriction * surfaceFriction;
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
            accelRate *= Math.max(0.65, 1.0 - burnoutRatio * 0.35);
        }

        var netForce = 0.0;
        if (throttleEff > 0.0) {
            if (forwardSpeed < maxSpeed) {
                netForce = accelRate * throttleEff * config.mass;
            }
        } else if (input.brake > 0.0) {
            if (forwardSpeed > 0.5) {
                netForce = -config.brakeDecel * mu * input.brake * config.mass;
            } else {
                netForce = -(config.baseAcceleration * 0.5) * mu * input.brake * config.mass;
            }
        } else {
            if (speedAbs < 0.35) {
                // Smoothly damp creeping velocity to a clean standstill without sign-flip chatter
                netForce = 0.0;
                forwardSpeed *= Math.max(0.0, 1.0 - 20.0 * dt);
                if (Math.abs(forwardSpeed) < 0.01) forwardSpeed = 0.0;
            } else {
                var sign = forwardSpeed > 0 ? 1.0 : -1.0;
                var decelForce = (config.tires.rollingResistance * mu + (forwardSpeed * forwardSpeed * config.aero.dragCoeff)) * config.mass;
                netForce = -sign * decelForce;
            }
        }

        return netForce;
    }

    /**
     * Simulates tire slip angle adhesion curves, lateral cornering grip, front/rear slip bias,
     * handbrake traction breakaway, drift state transitions, counter-steer torque injection,
     * cornering wheelspin, and forward momentum biasing with zero heap allocations.
     */
    function updateLateralAndDrift(dt:Float, input:InputController, fwdX:Float, fwdY:Float, rightX:Float, rightY:Float, rightZ:Float, upX:Float, upY:Float, upZ:Float, downforceMag:Float, ?groundProvider:world.IGroundProvider) {
        var driftCfg = config.drift;
        var tireCfg = config.tires;
        var surfaceFriction = (groundProvider != null) ? groundProvider.getGroundFriction(pos.x, pos.y) : 1.0;
        var effectiveFriction = tireCfg.groundFriction * surfaceFriction;
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
        var bias = tireCfg.tireSlipBias;
        var frontGripMult = (1.0 - bias * 0.40) * effectiveFriction;
        var rearGripMult = (1.0 + bias * 0.40) * effectiveFriction;

        // 3. Proper Handbrake Function (SKLL.md De-grip rear end dynamically):
        if (input.handbrake) {
            rearGripMult *= 0.15; // De-grip rear end dynamically per SKLL.md

            // Handbrake drag on longitudinal forward motion
            if (speedAbs > 0.5) {
                var hbForce = 14.0 * effectiveFriction * config.mass * (forwardSpeed > 0 ? -1.0 : 1.0);
                scratchVec3A.init(fwdX * hbForce, fwdY * hbForce, 0);
                chassisBody.applyForceToCenter(scratchVec3A);
            }

            // Induce yaw rotation into the turn if steering or sliding
            if (speedAbs > 2.0) {
                var yawSteer = input.steer != 0.0 ? -input.steer : (lateralVelocity < 0 ? 0.8 : -0.8);
                var hbTorque = yawSteer * 3.2 * config.yawInertia * 4.0;
                scratchVec3A.init(0, 0, hbTorque);
                chassisBody.applyTorque(scratchVec3A);
            }
        }

        // 4. Power Oversteer & Wheelspin:
        var isPowerTurn = (Math.abs(input.steer) > 0.25 && input.throttle > 0.75 && speedAbs > 4.0);
        if (isPowerTurn) {
            var spinKick = input.throttle * tireCfg.wheelspinAmount;
            wheelSpinVelocity[2] += spinKick * 60.0 * dt;
            wheelSpinVelocity[3] += spinKick * 60.0 * dt;
            rearGripMult *= Math.max(0.25, 1.0 - (tireCfg.wheelspinAmount * 0.35));
            var pwrTorque = -input.steer * 1.8 * tireCfg.wheelspinAmount * config.yawInertia * 3.0;
            scratchVec3A.init(0, 0, pwrTorque);
            chassisBody.applyTorque(scratchVec3A);
        }

        // 5. Vehicle Chassis Slip Angle & Drift Trigger Evaluation:
        var carSlipAngle = Math.atan2(Math.abs(lateralVelocity), Math.max(1.0, speedAbs));
        var triggerAngle = driftCfg.driftTriggerAngle;

        var driftInitiatedByHandbrake = input.handbrake && Math.abs(input.steer) > 0.15;
        var driftInitiatedByAngle = (carSlipAngle >= triggerAngle && Math.abs(input.steer) > 0.18);
        var driftInitiatedByBrakeFlick = (input.brake > 0.2 && input.throttle > 0.1 && Math.abs(input.steer) > 0.22);

        if (!isDrifting && (driftInitiatedByHandbrake || driftInitiatedByAngle || driftInitiatedByBrakeFlick) && speedAbs > driftCfg.minDriftSpeed) {
            isDrifting = true;
            driftDirection = (input.steer != 0.0) ? (input.steer > 0.0 ? 1.0 : -1.0) : (lateralVelocity > 0.0 ? 1.0 : -1.0);
        }

        if (isDrifting) {
            var counterSteeringOut = (driftDirection > 0 && input.steer < -0.70) || (driftDirection < 0 && input.steer > 0.70);
            var isStraightenedOut = (carSlipAngle < (triggerAngle * 0.35) && !input.handbrake && Math.abs(input.steer) < 0.10);
            if (speedAbs < driftCfg.driftExitSpeed || counterSteeringOut || isStraightenedOut) {
                isDrifting = false;
            }
        }

        // 6. Lateral Cornering & Drift Yaw Simulation
        var fLateralMax = effectiveFriction * downforceMag;

        if (isDrifting) {
            var targetAngle = driftDirection * 0.45;
            driftAngle += (targetAngle - driftAngle) * 5.5 * dt;

            // Lateral tire stiffness is scaled down during drift (scaled with rear grip)
            var latGripScale = driftCfg.lateralStiffnessScale * rearGripMult;
            var latForceRaw = -lateralVelocity * tireCfg.baseLateralStiffness * latGripScale * config.mass * 0.15;
            var latForce = Math.max(-fLateralMax, Math.min(fLateralMax, latForceRaw));
            scratchVec3A.init(rightX * latForce, rightY * latForce, rightZ * latForce);
            chassisBody.applyForceToCenter(scratchVec3A);

            // Counter-steering stabilizes slide angle, steering with slide tightens yaw
            var counterSteerFactor = (input.steer * driftDirection < 0) ? driftCfg.counterSteerTorque : 1.5;
            var targetYawRate = (-driftDirection * driftCfg.driftYawRate * 0.35 - input.steer * counterSteerFactor * 0.35);
            var curAngVel = chassisBody.getAngularVelocity();
            var curYawVel = curAngVel.x * upX + curAngVel.y * upY + curAngVel.z * upZ;
            var yawTorque = (targetYawRate - curYawVel) * config.yawInertia * 10.0;
            scratchVec3A.init(upX * yawTorque, upY * yawTorque, upZ * yawTorque);
            chassisBody.applyTorque(scratchVec3A);

            // Forward Velocity Biasing: Criterion-style momentum assist aligning velocity vector with forward heading
            var biasFactor = Math.min(1.0, driftCfg.forwardBiasRate * dt);
            var linV = chassisBody.getLinearVelocity();
            var currentHorizSpeed = Math.sqrt(linV.x * linV.x + linV.y * linV.y);
            var targetVx = fwdX * currentHorizSpeed;
            var targetVy = fwdY * currentHorizSpeed;
            var fwdBiasForceX = (targetVx - linV.x) * config.mass * biasFactor * 2.5;
            var fwdBiasForceY = (targetVy - linV.y) * config.mass * biasFactor * 2.5;
            scratchVec3A.init(fwdBiasForceX, fwdBiasForceY, 0.0);
            chassisBody.applyForceToCenter(scratchVec3A);
        } else {
            driftAngle += (0.0 - driftAngle) * 10.0 * dt;

            // Normal cornering: standard lateral grip restoring velocity towards zero clamped by normal load
            if (speedAbs < 0.35 && Math.abs(lateralVelocity) < 0.35) {
                lateralVelocity *= Math.max(0.0, 1.0 - 20.0 * dt);
                if (Math.abs(lateralVelocity) < 0.01) lateralVelocity = 0.0;
            } else {
                var latForceRaw = -lateralVelocity * tireCfg.baseLateralStiffness * frontGripMult * config.mass * 0.25;
                var latForce = Math.max(-fLateralMax, Math.min(fLateralMax, latForceRaw));
                scratchVec3A.init(rightX * latForce, rightY * latForce, rightZ * latForce);
                chassisBody.applyForceToCenter(scratchVec3A);
            }

            // Standard Ackermann steering rack cornering authority scaled with speed & front grip
            // Steering authority applied around vehicle local UP axis to prevent roll cross-coupling on slopes
            if (speedAbs > 0.25) {
                var steerAuthority = 2.4 * Math.min(1.0, speedRatio + 0.35) * frontGripMult;
                var fwdSign = forwardSpeed >= 0 ? 1.0 : -1.0;
                var targetYawRate = -input.steer * steerAuthority * fwdSign * 0.70;
                var curAngVel = chassisBody.getAngularVelocity();
                var curYawVel = curAngVel.x * upX + curAngVel.y * upY + curAngVel.z * upZ;
                var steerTorque = (targetYawRate - curYawVel) * config.yawInertia * 8.0;
                scratchVec3A.init(upX * steerTorque, upY * steerTorque, upZ * steerTorque);
                chassisBody.applyTorque(scratchVec3A);
            } else {
                var curAngVel = chassisBody.getAngularVelocity();
                scratchVec3A.init(curAngVel.x * 0.8, curAngVel.y * 0.8, curAngVel.z * 0.5);
                chassisBody.setAngularVelocity(scratchVec3A);
            }
        }
    }
}
