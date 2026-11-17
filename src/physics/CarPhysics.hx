package physics;

import oimo.common.Vec3 as OimoVec3;
import math.Vec3;
import oimo.collision.geometry.BoxGeometry;
import oimo.dynamics.World;
import oimo.dynamics.rigidbody.RigidBody;
import oimo.dynamics.rigidbody.RigidBodyConfig;
import oimo.dynamics.rigidbody.RigidBodyType;
import oimo.dynamics.rigidbody.Shape;
import oimo.dynamics.rigidbody.ShapeConfig;
import config.GameConfig.PhysicsWorldConfig;
import input.InputController;
import physics.CarConfig;
import physics.SuspensionSolver;
import physics.DrivetrainSolver;
import physics.TireSlipSolver;
import world.IGroundProvider;

/**
 * Modular 4-wheel raycast vehicle controller integrated with OimoPhysics rigid-body collision boundaries.
 * Executes fixed 240Hz micro-stepping across asymmetric suspension struts, axle anti-roll bars,
 * longitudinal weight transfer, speed-blended Ackermann geometry, Pacejka tire curves with combined
 * Friction Circle clamping, multi-gear drivetrain curves, and low-speed stiction holding.
 *
 * World Coordinate Convention (Heaps Z-Up):
 * - +X: World Right
 * - +Y: World Forward (yaw = 0)
 * - +Z: World Up
 * - Steering Left  (input.steer < 0) -> negative yawRate, yaw decreases, vehicle moves toward -X
 * - Steering Right (input.steer > 0) -> positive yawRate, yaw increases, vehicle moves toward +X
 *
 * @class CarPhysics
 * @module physics/CarPhysics
 */
class CarPhysics {
    static inline var FIXED_SUBSTEP:Float = 1.0 / 240.0;
    static inline var MAX_FRAME_DT:Float = 0.05;

    /** Underlying OimoPhysics world hosting static arena walls and dynamic rigid bodies. */
    public var physicsWorld:World;

    /** Dynamic Oimo rigid body aligned with the vehicle chassis center of gravity. */
    public var chassisBody:RigidBody;

    /** Active validated vehicle configuration profile. */
    public var config:VehicleConfigData;

    /** Last queried ground provider (exposed read-only for terrain-aware camera clearance). */
    public var groundProvider:IGroundProvider = null;

    /** Vehicle world position anchored at wheel-bottom contact elevation (m). */
    public var pos:Vec3;

    /** Vehicle heading angle in radians (0 = +Y, negative = Left/-X, positive = Right/+X). */
    public var yaw:Float = 0.0;

    /** Chassis pitch angle in radians (+ = Nose Up). */
    public var pitch:Float = 0.0;

    /** Chassis roll angle in radians (+ = Lean Right). */
    public var roll:Float = 0.0;

    /** Visual slip offset angle in radians (kept 0 so mesh matches exact physical yaw). */
    public var driftAngle:Float = 0.0;

    /** Longitudinal velocity projected along vehicle horizontal forward vector (m/s). */
    public var forwardSpeed:Float = 0.0;

    /** Lateral velocity projected along vehicle horizontal right vector (m/s). */
    public var lateralVelocity:Float = 0.0;

    /** World vertical velocity along +Z (m/s). */
    public var verticalVelocity:Float = 0.0;

    /** Current heading angular velocity in rad/s (+ = turning Right). */
    public var yawRate:Float = 0.0;

    /** Current pitch angular velocity in rad/s (+ = pitching Nose Up). */
    public var pitchRate:Float = 0.0;

    /** Current roll angular velocity in rad/s (+ = leaning Right). */
    public var rollRate:Float = 0.0;

    /** True when at least one wheel strut maintains surface contact. */
    public var isGrounded:Bool = true;

    /** Number of currently grounded wheels [0..4]. */
    public var groundedWheelCount:Int = 4;

    /** True when rear tire slip angle or handbrake slide crosses drifting threshold. */
    public var isDrifting:Bool = false;

    /** True while nitrous boost injection is actively firing. */
    public var isBoosting:Bool = false;

    /** Active automatic gearbox gear (-1 = Reverse, 1..6 = Forward). */
    public var currentGear:Int = 1;

    /** Current simulated engine crankshaft speed (RPM). */
    public var engineRPM:Float = 950.0;

    /** Normalized remaining nitrous boost reserve [0.0, maxFuel]. */
    public var boostFuel:Float = 1.0;

    /** Live compressed suspension strut lengths [FL, FR, RL, RR] in meters. */
    public var suspLength:Array<Float>;

    /** Live vertical normal load per wheel [FL, FR, RL, RR] in Newtons. */
    public var wheelNormalLoads:Array<Float>;

    /** Surface friction coefficient sampled at each wheel [FL, FR, RL, RR]. */
    public var wheelFriction:Array<Float>;

    /** Visual rear wheel slip angular velocity offset [FL, FR, RL, RR] in rad/s. */
    public var wheelSpinVelocity:Array<Float>;

    /** Effective inner/center front wheel steer angle in radians (- = Left, + = Right). */
    public var frontSteerAngle:Float = 0.0;

    var gravityZ:Float = -9.81;
    var maxDt:Float = MAX_FRAME_DT;
    var worldVx:Float = 0.0;
    var worldVy:Float = 0.0;
    var worldVz:Float = 0.0;
    var lastLongAccel:Float = 0.0;
    var prevSteerInput:Float = 0.0;

    var suspensionSolver:SuspensionSolver;
    var drivetrainSolver:DrivetrainSolver;
    var tireSlipSolver:TireSlipSolver;
    var oimoPosScratch:OimoVec3;
    var oimoVelScratch:OimoVec3;

    /**
     * Initializes a new 4-wheel raycast vehicle physics instance and Oimo collision world.
     *
     * @param {Float} x Initial world X position (m).
     * @param {Float} y Initial world Y position (m).
     * @param {Float} z Initial world Z ground contact elevation (m).
     * @param {VehicleConfigData} initialConfig Optional vehicle tuning override (uses CarConfig default if null).
     * @param {PhysicsWorldConfig} worldConfig Optional world gravity/dt bounds.
     */
    public function new(
        x:Float = 0.0,
        y:Float = 0.0,
        z:Float = 0.0,
        ?initialConfig:VehicleConfigData,
        ?worldConfig:PhysicsWorldConfig
    ) {
        config = CarConfig.clamp(initialConfig);
        if (worldConfig != null) {
            gravityZ = worldConfig.gravityZ < -1.0 ? worldConfig.gravityZ : -9.81;
            maxDt = worldConfig.maxDt > 0.005 ? worldConfig.maxDt : MAX_FRAME_DT;
        }

        pos = new Vec3(x, y, z);
        suspLength = [config.suspension.restLength, config.suspension.restLength, config.suspension.restLength, config.suspension.restLength];
        wheelNormalLoads = [0.0, 0.0, 0.0, 0.0];
        wheelFriction = [1.0, 1.0, 1.0, 1.0];
        wheelSpinVelocity = [0.0, 0.0, 0.0, 0.0];
        boostFuel = config.boost.maxFuel;
        engineRPM = config.drivetrain.idleRPM;

        suspensionSolver = new SuspensionSolver();
        drivetrainSolver = new DrivetrainSolver();
        tireSlipSolver = new TireSlipSolver();
        oimoPosScratch = new OimoVec3();
        oimoVelScratch = new OimoVec3();

        physicsWorld = new World();
        physicsWorld.setGravity(new OimoVec3(0.0, 0.0, gravityZ));

        // Create dynamic chassis rigid body with collider raised clear of tire ground contact
        var rbCfg = new RigidBodyConfig();
        rbCfg.type = RigidBodyType.DYNAMIC;
        rbCfg.position = new OimoVec3(x, y, z + config.chassis.cogHeight);
        chassisBody = new RigidBody(rbCfg);

        var shapeCfg = new ShapeConfig();
        shapeCfg.geometry = new BoxGeometry(new OimoVec3(
            CarConfig.CHASSIS_WIDTH * 0.46,
            CarConfig.CHASSIS_LENGTH * 0.46,
            0.34
        ));
        // Bottom of Oimo hull stays safely above TIRE_RADIUS so hills/ramps never snag the belly
        shapeCfg.position = new OimoVec3(0.0, 0.0, 0.24);
        shapeCfg.restitution = 0.2;
        shapeCfg.friction = 0.2;
        chassisBody.addShape(new Shape(shapeCfg));
        physicsWorld.addRigidBody(chassisBody);

        resetState(x, y, z, 0.0);
    }

    /**
     * Replaces active vehicle configuration at runtime and clamps parameters safely.
     *
     * @param {VehicleConfigData} newConfig Updated vehicle config struct.
     */
    public function setConfig(newConfig:VehicleConfigData):Void {
        config = CarConfig.clamp(newConfig);
        boostFuel = Math.min(boostFuel, config.boost.maxFuel);
    }

    /**
     * Teleports the vehicle to a clean stationary state at the specified world coordinates and heading.
     *
     * @param {Float} x Target world X coordinate (m).
     * @param {Float} y Target world Y coordinate (m).
     * @param {Float} z Target wheel-bottom ground elevation (m).
     * @param {Float} yawAngle Initial heading angle in radians (0 = +Y).
     */
    public function resetState(x:Float, y:Float, z:Float, yawAngle:Float = 0.0):Void {
        pos.set(x, y, z);
        yaw = yawAngle;
        pitch = 0.0;
        roll = 0.0;
        driftAngle = 0.0;

        forwardSpeed = 0.0;
        lateralVelocity = 0.0;
        verticalVelocity = 0.0;
        worldVx = 0.0;
        worldVy = 0.0;
        worldVz = 0.0;
        yawRate = 0.0;
        pitchRate = 0.0;
        rollRate = 0.0;
        lastLongAccel = 0.0;

        isGrounded = true;
        groundedWheelCount = 4;
        isDrifting = false;
        isBoosting = false;
        currentGear = 1;
        engineRPM = config.drivetrain.idleRPM;
        boostFuel = config.boost.maxFuel;
        frontSteerAngle = 0.0;
        prevSteerInput = 0.0;

        var staticComp = config.suspension.unloadedLength - config.suspension.restLength;
        suspensionSolver.resetHistory(staticComp);
        drivetrainSolver.reset();
        tireSlipSolver.reset();

        var staticWheelLoad = (config.chassis.massKg * Math.abs(gravityZ)) * 0.25;
        for (i in 0...4) {
            suspLength[i] = config.suspension.restLength;
            wheelNormalLoads[i] = staticWheelLoad;
            wheelFriction[i] = 1.0;
            wheelSpinVelocity[i] = 0.0;
        }

        syncToOimoBody();
    }

    /**
     * Synchronizes current pos, heading, and velocity state directly into Oimo's RigidBody transform.
     */
    public function syncToOimoBody():Void {
        var sy = Math.sin(yaw);
        var cy = Math.cos(yaw);
        worldVx = forwardSpeed * sy + lateralVelocity * cy;
        worldVy = forwardSpeed * cy - lateralVelocity * sy;
        worldVz = verticalVelocity;

        if (chassisBody == null) return;
        oimoPosScratch.init(pos.x, pos.y, pos.z + config.chassis.cogHeight);
        chassisBody.setPosition(oimoPosScratch);
        oimoVelScratch.init(worldVx, worldVy, worldVz);
        chassisBody.setLinearVelocity(oimoVelScratch);
        oimoVelScratch.init(0.0, 0.0, 0.0);
        chassisBody.setAngularVelocity(oimoVelScratch);
    }

    /**
     * Reads back world position and linear velocity from Oimo's RigidBody after world steps/contacts.
     */
    public function syncFromOimoBody():Void {
        if (chassisBody == null) return;
        var p = chassisBody.getPosition();
        var v = chassisBody.getLinearVelocity();
        pos.x = p.x;
        pos.y = p.y;
        pos.z = p.z - config.chassis.cogHeight;
        worldVx = v.x;
        worldVy = v.y;
        worldVz = v.z;
        projectHorizontalVelocities();
        verticalVelocity = worldVz;
    }

    /**
     * Advances vehicle simulation over variable frame delta dt using deterministic 240Hz sub-stepping.
     *
     * @param {Float} dt Elapsed frame time in seconds.
     * @param {InputController} input Conditioned multi-device input state.
     * @param {Array<Vec3>} waypoints Optional spline waypoints (passed by circuit world mode).
     * @param {IGroundProvider} ground Terrain height, normal, material friction, and boundary provider.
     */
    public function update(
        dt:Float,
        input:InputController,
        ?waypoints:Array<Vec3>,
        ?ground:IGroundProvider
    ):Void {
        if (dt <= 0.0 || Math.isNaN(dt)) return;
        groundProvider = ground;

        var frameDt = dt > maxDt ? maxDt : dt;
        var steps = Math.ceil(frameDt / FIXED_SUBSTEP);
        if (steps < 1) steps = 1;
        var subDt = frameDt / steps;

        var steerIn = input != null ? clampF(input.steer, -1.0, 1.0) : 0.0;
        var throttleIn = input != null ? clampF(input.throttle, 0.0, 1.0) : 0.0;
        var brakeIn = input != null ? clampF(input.brake, 0.0, 1.0) : 0.0;
        var handbrakeIn = input != null ? input.handbrake : false;
        var boostIn = input != null ? input.boost : false;

        for (step in 0...steps) {
            stepSubstep(subDt, steerIn, throttleIn, brakeIn, handbrakeIn, boostIn, ground);
        }

        // Sync canonical 1D/local velocity scalars immediately after sub-step integration
        projectHorizontalVelocities();
        verticalVelocity = worldVz;

        // Resolve any static Oimo obstacle overlap without double-integrating linear velocity
        if (physicsWorld != null && ground != null && chassisBody != null) {
            oimoPosScratch.init(pos.x, pos.y, pos.z + config.chassis.cogHeight);
            chassisBody.setPosition(oimoPosScratch);
            oimoVelScratch.init(0.0, 0.0, 0.0);
            chassisBody.setLinearVelocity(oimoVelScratch);
            chassisBody.setAngularVelocity(oimoVelScratch);
            chassisBody.setGravityScale(0.0);
            physicsWorld.step(frameDt);
            var oimoPos = chassisBody.getPosition();
            pos.x = oimoPos.x;
            pos.y = oimoPos.y;
        }

        // Enforce IGroundProvider track barriers / arena bounds on final position & velocity
        if (ground != null) {
            var hit = ground.enforceBoundaries(pos, forwardSpeed, lateralVelocity);
            if (hit.hitWall) {
                forwardSpeed *= hit.speedMult;
                lateralVelocity *= hit.latMult;
                yawRate *= 0.35;
            }
        }

        syncToOimoBody();
        prevSteerInput = steerIn;
    }

    function stepSubstep(
        dt:Float,
        steerIn:Float,
        throttleIn:Float,
        brakeIn:Float,
        handbrakeIn:Bool,
        boostIn:Bool,
        ground:IGroundProvider
    ):Void {
        var mass = config.chassis.massKg;
        var gMag = Math.abs(gravityZ);
        var sy = Math.sin(yaw);
        var cy = Math.cos(yaw);

        // Project world horizontal velocity onto current vehicle heading axes
        var vLong = worldVx * sy + worldVy * cy;
        var vLat = worldVx * cy - worldVy * sy;

        // 1. Evaluate 4-wheel raycast struts + spring-damper + axle Anti-Roll Bars
        var susp = suspensionSolver.solve(
            dt,
            config,
            pos,
            worldVz,
            yaw,
            pitch,
            roll,
            pitchRate,
            rollRate,
            ground,
            physicsWorld,
            chassisBody
        );

        groundedWheelCount = susp.groundedCount;
        isGrounded = susp.groundedCount > 0;
        for (i in 0...4) {
            var w = susp.wheels[i];
            suspLength[i] = w.suspLength;
            wheelNormalLoads[i] = w.normalLoad;
            wheelFriction[i] = w.mu;
        }

        // Build orthonormal terrain-tangent forward & right vectors from average ground normal
        var nx = susp.avgNormalX;
        var ny = susp.avgNormalY;
        var nz = susp.avgNormalZ;

        // Horizontal forward dot normal = slope sine along forward direction (negative = facing uphill)
        var fwdDotN = sy * nx + cy * ny;
        var rightDotN = cy * nx - sy * ny;

        var tFwdX = sy - fwdDotN * nx;
        var tFwdY = cy - fwdDotN * ny;
        var tFwdZ = -fwdDotN * nz;
        var tfLen = Math.sqrt(tFwdX * tFwdX + tFwdY * tFwdY + tFwdZ * tFwdZ);
        if (tfLen > 0.001) {
            tFwdX /= tfLen;
            tFwdY /= tfLen;
            tFwdZ /= tfLen;
        } else {
            tFwdX = sy;
            tFwdY = cy;
            tFwdZ = 0.0;
        }

        var tRightX = cy - rightDotN * nx;
        var tRightY = -sy - rightDotN * ny;
        var tRightZ = -rightDotN * nz;
        var trLen = Math.sqrt(tRightX * tRightX + tRightY * tRightY + tRightZ * tRightZ);
        if (trLen > 0.001) {
            tRightX /= trLen;
            tRightY /= trLen;
            tRightZ /= trLen;
        } else {
            tRightX = cy;
            tRightY = -sy;
            tRightZ = 0.0;
        }

        // 2. Evaluate drivetrain gearbox, torque delivery, brakes, and nitrous boost
        var driveRes = drivetrainSolver.solve(
            dt,
            config,
            throttleIn,
            brakeIn,
            handbrakeIn,
            boostIn,
            vLong,
            currentGear,
            boostFuel,
            susp.groundedCount
        );

        currentGear = driveRes.currentGear;
        engineRPM = driveRes.engineRPM;
        boostFuel = driveRes.boostFuel;
        isBoosting = driveRes.isBoosting;
        for (i in 0...4) {
            wheelSpinVelocity[i] = (i >= 2) ? driveRes.rearWheelSpinDelta : 0.0;
        }

        // 3. Evaluate tire slip angles, Pacejka lateral curves, Friction Circle, and stiction
        // Uphill slope sine > 0 when facing uphill (-fwdDotN)
        var slopeFwdSin = -fwdDotN;
        var slopeRightSin = -rightDotN;

        var tireRes = tireSlipSolver.solve(
            dt,
            config,
            susp.wheels,
            vLong,
            vLat,
            yawRate,
            steerIn,
            driveRes.driveForce,
            driveRes.brakeForce,
            handbrakeIn,
            lastLongAccel,
            slopeFwdSin,
            slopeRightSin,
            gMag
        );

        frontSteerAngle = tireRes.frontSteerAngle;

        // 4. Sum 3D world Newtonian forces (Gravity + Normal Suspension + Tangential Tire Forces + Downforce)
        var speedSq = worldVx * worldVx + worldVy * worldVy;
        var aeroDown = susp.groundedCount > 0 ? config.chassis.aeroDownforce * speedSq : 0.0;

        var totalFx = susp.totalNormalZForce > 0.0 ? (susp.avgNormalX * (susp.totalNormalZForce / Math.max(0.35, susp.avgNormalZ))) : 0.0;
        var totalFy = susp.totalNormalZForce > 0.0 ? (susp.avgNormalY * (susp.totalNormalZForce / Math.max(0.35, susp.avgNormalZ))) : 0.0;
        var totalFz = susp.totalNormalZForce + mass * gravityZ - aeroDown;

        // Add tire drive/cornering forces projected cleanly along sloped terrain tangent axes
        if (susp.groundedCount > 0) {
            var netFwd = tireRes.forceFwd + driveRes.nitroThrust;
            totalFx += netFwd * tFwdX + tireRes.forceRight * tRightX;
            totalFy += netFwd * tFwdY + tireRes.forceRight * tRightY;
            totalFz += netFwd * tFwdZ + tireRes.forceRight * tRightZ;
        } else if (driveRes.nitroThrust > 0.0) {
            totalFx += driveRes.nitroThrust * tFwdX;
            totalFy += driveRes.nitroThrust * tFwdY;
        }

        var prevVLong = vLong;
        worldVx += (totalFx / mass) * dt;
        worldVy += (totalFy / mass) * dt;
        worldVz += (totalFz / mass) * dt;

        // Clamp residual creep velocities cleanly while static friction holds the parked vehicle
        if (tireRes.isStictionActive) {
            var vDecay = Math.exp(-20.0 * dt);
            worldVx *= vDecay;
            worldVy *= vDecay;
            if (Math.abs(worldVx) < 0.005) worldVx = 0.0;
            if (Math.abs(worldVy) < 0.005) worldVy = 0.0;
            yawRate *= vDecay;
            if (Math.abs(yawRate) < 0.002) yawRate = 0.0;
        }

        // Track longitudinal acceleration smoothed gently for weight transfer on next sub-step
        var newVLong = worldVx * sy + worldVy * cy;
        var instAccel = (newVLong - prevVLong) / dt;
        if (instAccel > 25.0) instAccel = 25.0;
        else if (instAccel < -30.0) instAccel = -30.0;
        lastLongAccel += (instAccel - lastLongAccel) * Math.min(1.0, dt * 18.0);

        // Integrate linear world position
        pos.x += worldVx * dt;
        pos.y += worldVy * dt;
        pos.z += worldVz * dt;

        // Hard bump-stop floor guard only if an individual wheel crushes past its hardstop limit
        // (lifts vertically out of ground crush and removes inward normal speed without catapult bounce)
        if (susp.groundedCount > 0 && susp.maxBottomOutPenetration > 0.0) {
            pos.z += susp.maxBottomOutPenetration / Math.max(0.5, nz);
            var vn = worldVx * nx + worldVy * ny + worldVz * nz;
            if (vn < 0.0) {
                worldVx -= vn * nx;
                worldVy -= vn * ny;
                worldVz -= vn * nz;
            }
        }

        // 5. Integrate yaw angular dynamics
        var yawAccel = tireRes.yawTorque / config.chassis.yawInertia;
        // Subtle natural yaw-rate self-aligning stabilization at speed (prevents tank-slapper instability)
        var yawDamp = Math.exp(-(handbrakeIn ? 2.2 : 3.6) * dt);
        yawRate = yawRate * yawDamp + yawAccel * dt;
        if (Math.abs(yawRate) > 4.2) yawRate = yawRate > 0 ? 4.2 : -4.2;
        yaw += yawRate * dt;

        // Wrap yaw cleanly to [-PI, +PI] without discontinuities near 0
        if (yaw > Math.PI * 2.0) yaw -= Math.PI * 2.0;
        else if (yaw < -Math.PI * 2.0) yaw += Math.PI * 2.0;

        // 6. Integrate real 6-DOF pitch and roll dynamics (suspension restoring + dynamic weight shift)
        var cog = config.chassis.cogHeight;
        var dynamicPitchMoment = tireRes.forceFwd * cog * 0.42;
        var dynamicRollMoment = -tireRes.forceRight * cog * 0.55;

        if (susp.groundedCount > 0) {
            var pitchAccel = (susp.pitchTorque + dynamicPitchMoment) / config.chassis.pitchInertia;
            var rollAccel = (susp.rollTorque + dynamicRollMoment) / config.chassis.rollInertia;
            pitchRate = pitchRate * Math.exp(-3.2 * dt) + pitchAccel * dt;
            rollRate = rollRate * Math.exp(-3.8 * dt) + rollAccel * dt;
        } else {
            // Subtle mid-air aerodynamic attitude settling prevents wild pitch/roll spinning on jumps
            pitchRate = pitchRate * Math.exp(-2.4 * dt) - pitch * 1.4 * dt;
            rollRate = rollRate * Math.exp(-2.8 * dt) - roll * 1.8 * dt;
        }

        pitch = clampF(pitch + pitchRate * dt, -0.65, 0.65);
        roll = clampF(roll + rollRate * dt, -0.60, 0.60);
        driftAngle = 0.0;

        // Update drifting telemetry flag cleanly
        var newVLat = worldVx * cosY(yaw) - worldVy * sinY(yaw);
        isDrifting = isGrounded
            && Math.abs(newVLong) > 6.5
            && (tireRes.lateralSlipAngle > config.tires.driftSlipThreshold || (handbrakeIn && Math.abs(newVLat) > 2.2));
    }

    inline function projectHorizontalVelocities():Void {
        var sy = Math.sin(yaw);
        var cy = Math.cos(yaw);
        forwardSpeed = worldVx * sy + worldVy * cy;
        lateralVelocity = worldVx * cy - worldVy * sy;
    }

    static inline function sinY(a:Float):Float return Math.sin(a);
    static inline function cosY(a:Float):Float return Math.cos(a);

    static inline function clampF(v:Float, lo:Float, hi:Float):Float {
        return v < lo ? lo : (v > hi ? hi : v);
    }
}
