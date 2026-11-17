package physics;

import oimo.common.Vec3 as OimoVec3;
import math.Vec3;
import oimo.collision.geometry.RayCastHit;
import oimo.dynamics.World;
import oimo.dynamics.callback.RayCastCallback;
import oimo.dynamics.rigidbody.RigidBody;
import oimo.dynamics.rigidbody.Shape;
import world.IGroundProvider;
import entities.CarMesh;
import physics.CarConfig;

/**
 * Contact state and normal load computed for an individual wheel raycast strut.
 *
 * @typedef {Object} WheelContact
 */
typedef WheelContact = {
    var grounded:Bool;
    var groundZ:Float;
    var suspLength:Float;
    var compression:Float;
    var compressionVel:Float;
    var normalLoad:Float;
    var mu:Float;
    var normalX:Float;
    var normalY:Float;
    var normalZ:Float;
    var worldX:Float;
    var worldY:Float;
    var worldZ:Float;
}

/**
 * Aggregate 4-wheel suspension force, axle anti-roll torque, and surface contact result.
 *
 * @typedef {Object} SuspensionResult
 */
typedef SuspensionResult = {
    var wheels:Array<WheelContact>;
    var groundedCount:Int;
    var avgNormalX:Float;
    var avgNormalY:Float;
    var avgNormalZ:Float;
    var totalNormalZForce:Float;
    var pitchTorque:Float;
    var rollTorque:Float;
    var maxBottomOutPenetration:Float;
}

/**
 * Internal Oimo raycast callback filtering out the player's own chassis colliders and
 * vertical perimeter walls so struts only land on genuine drivable surfaces.
 */
class WheelRayCallback extends RayCastCallback {
    public var ignoreBody:RigidBody;
    public var hit:Bool = false;
    public var fraction:Float = 1.0;
    public var hitZ:Float = 0.0;
    public var normalX:Float = 0.0;
    public var normalY:Float = 0.0;
    public var normalZ:Float = 1.0;

    public function new(?ignoreBody:RigidBody) {
        super();
        this.ignoreBody = ignoreBody;
    }

    public inline function reset(?ignoreBody:RigidBody):Void {
        this.ignoreBody = ignoreBody;
        this.hit = false;
        this.fraction = 1.0;
        this.hitZ = 0.0;
        this.normalX = 0.0;
        this.normalY = 0.0;
        this.normalZ = 1.0;
    }

    override public function process(shape:Shape, rhit:RayCastHit):Void {
        if (ignoreBody != null && shape.getRigidBody() == ignoreBody) return;
        // Require mostly-upward support normal so vertical guardrails/walls are ignored by suspension struts
        if (rhit.normal.z <= 0.65) return;
        if (rhit.fraction < fraction) {
            fraction = rhit.fraction;
            hit = true;
            hitZ = rhit.position.z;
            normalX = rhit.normal.x;
            normalY = rhit.normal.y;
            normalZ = rhit.normal.z;
        }
    }
}

/**
 * Evaluates four independent raycast wheel struts against both IGroundProvider terrain fields
 * and Oimo static colliders, applying asymmetric bump/rebound damping and axle Anti-Roll Bars.
 *
 * @class SuspensionSolver
 * @module physics/SuspensionSolver
 */
class SuspensionSolver {
    var prevCompressions:Array<Float>;
    var prevGrounded:Array<Bool>;
    var rayCallback:WheelRayCallback;
    var rayStart:OimoVec3;
    var rayEnd:OimoVec3;
    var scratchNormal:Vec3;

    /**
     * Constructs a reusable 4-wheel suspension solver with persistent bump/rebound history.
     */
    public function new() {
        prevCompressions = [0.14, 0.14, 0.14, 0.14];
        prevGrounded = [true, true, true, true];
        rayCallback = new WheelRayCallback(null);
        rayStart = new OimoVec3();
        rayEnd = new OimoVec3();
        scratchNormal = new Vec3(0.0, 0.0, 1.0);
    }

    /**
     * Resets stored compression history cleanly after teleporting or spawning the car.
     *
     * @param {Float} initialCompression Equilibrium compression in meters.
     */
    public function resetHistory(initialCompression:Float = 0.14):Void {
        for (i in 0...4) {
            prevCompressions[i] = initialCompression;
            prevGrounded[i] = true;
        }
    }

    /**
     * Solves 4-wheel raycast contact geometry, spring-damper forces, Anti-Roll Bar load transfer,
     * and resulting chassis pitch/roll restoring torques in world coordinates.
     *
     * @param {Float} dt Fixed physics sub-step in seconds.
     * @param {VehicleConfigData} cfg Validated vehicle tuning configuration.
     * @param {Vector} pos Current wheel-bottom reference position (m).
     * @param {Float} vz Current chassis vertical velocity (m/s).
     * @param {Float} yaw Heading yaw in radians (0 = +Y, - = Left, + = Right).
     * @param {Float} pitch Chassis pitch angle in radians (+ = Nose Up).
     * @param {Float} roll Chassis roll angle in radians (+ = Lean Right).
     * @param {Float} pitchRate Angular velocity about local right axis (rad/s).
     * @param {Float} rollRate Angular velocity about local forward axis (rad/s).
     * @param {IGroundProvider} ground Optional world terrain height/normal/friction provider.
     * @param {World} physicsWorld Optional Oimo world for raycasting solid props/decks.
     * @param {RigidBody} chassisBody Own rigid body to exclude from self-raycast hits.
     * @returns {SuspensionResult} Computed per-wheel contact states and net suspension forces/torques.
     */
    public function solve(
        dt:Float,
        cfg:VehicleConfigData,
        pos:Vec3,
        vz:Float,
        yaw:Float,
        pitch:Float,
        roll:Float,
        pitchRate:Float,
        rollRate:Float,
        ?ground:IGroundProvider,
        ?physicsWorld:World,
        ?chassisBody:RigidBody
    ):SuspensionResult {
        var safeDt = dt > 0.0001 ? dt : 0.0001;
        var suspCfg = cfg.suspension;
        var restLen = suspCfg.restLength;
        var unloadedLen = suspCfg.unloadedLength;
        var minLen = suspCfg.minLength;
        var tireRadius = CarConfig.TIRE_RADIUS;

        // Build full 3D chassis basis vectors matching WorldManager + CarMesh rotation convention:
        // World basis is R_z(-yaw) * R_x(pitch) * R_y(roll).
        var sy = Math.sin(yaw);
        var cy = Math.cos(yaw);
        var sp = Math.sin(pitch);
        var cp = Math.cos(pitch);
        var sr = Math.sin(roll);
        var cr = Math.cos(roll);

        // Local +X (Right) rotated by R_x(pitch) * R_y(roll) then R_z(-yaw):
        // R_y(roll)*(1,0,0) = (cr, 0, -sr); R_x(pitch)*(cr, 0, -sr) = (cr, sr*sp, -sr*cp)
        var rxL = cr;
        var ryL = sr * sp;
        var rzL = -sr * cp;
        var rightX = cy * rxL + sy * ryL;
        var rightY = -sy * rxL + cy * ryL;
        var rightZ = rzL;

        // Local +Y (Forward): R_y*(0,1,0) = (0,1,0); R_x*(0,1,0) = (0, cp, sp)
        var fwdX = sy * cp;
        var fwdY = cy * cp;
        var fwdZ = sp;

        // Local +Z (Up): R_y*(0,0,1) = (sr, 0, cr); R_x*(sr, 0, cr) = (sr, -sp*cr, cp*cr)
        var uxL = sr;
        var uyL = -sp * cr;
        var uzL = cp * cr;
        var upX = cy * uxL + sy * uyL;
        var upY = -sy * uxL + cy * uyL;
        var upZ = uzL;

        // Strut top mount lies directly above tire contact center at equilibrium ride height
        var mountLocalZ = tireRadius + restLen;
        var maxRayDist = tireRadius + unloadedLen;
        var upProjection = upZ > 0.45 ? upZ : 0.45;

        var wheelContacts:Array<WheelContact> = [];
        var groundedCount = 0;
        var sumNormX = 0.0;
        var sumNormY = 0.0;
        var sumNormZ = 0.0;
        var maxBottomOut = 0.0;

        for (i in 0...4) {
            var offset = CarMesh.WHEEL_OFFSETS[i];
            var wxOffset = offset.x;
            var wyOffset = offset.y;

            // Compute strut hardpoint in world space relative to pos (where pos is bottom-of-wheels plane)
            var mountX = pos.x + rightX * wxOffset + fwdX * wyOffset + upX * mountLocalZ;
            var mountY = pos.y + rightY * wxOffset + fwdY * wyOffset + upY * mountLocalZ;
            var mountZ = pos.z + rightZ * wxOffset + fwdZ * wyOffset + upZ * mountLocalZ;

            // Sample continuous terrain field at wheel XY footprint directly under strut projection
            var rayBottomX = mountX - upX * maxRayDist;
            var rayBottomY = mountY - upY * maxRayDist;
            var queryX = (mountX + rayBottomX) * 0.5;
            var queryY = (mountY + rayBottomY) * 0.5;

            var surfaceZ = 0.0;
            var mu = 1.0;
            var nx = 0.0;
            var ny = 0.0;
            var nz = 1.0;

            if (ground != null) {
                surfaceZ = ground.getGroundElevation(queryX, queryY);
                mu = ground.getGroundFriction(queryX, queryY);
                ground.getGroundNormal(queryX, queryY, scratchNormal);
                nx = scratchNormal.x;
                ny = scratchNormal.y;
                nz = scratchNormal.z;
                if (nz < 0.2) {
                    nx = 0.0;
                    ny = 0.0;
                    nz = 1.0;
                }
            }

            // Cast physical Oimo ray downward to pick up drivable static colliders (decks/ramps) if present
            if (physicsWorld != null) {
                rayStart.init(mountX, mountY, mountZ);
                rayEnd.init(mountX - upX * maxRayDist, mountY - upY * maxRayDist, mountZ - upZ * maxRayDist);
                rayCallback.reset(chassisBody);
                physicsWorld.rayCast(rayStart, rayEnd, rayCallback);
                if (rayCallback.hit && rayCallback.hitZ >= surfaceZ - 0.05 && rayCallback.hitZ <= surfaceZ + 6.0) {
                    surfaceZ = rayCallback.hitZ;
                    nx = rayCallback.normalX;
                    ny = rayCallback.normalY;
                    nz = rayCallback.normalZ;
                }
            }

            // Distance from upper strut mount along -chassisUp to ground surface
            var hitDist = (mountZ - surfaceZ) / upProjection;
            var rawStrutLen = hitDist - tireRadius;
            var hardStopLen = minLen - 0.04;
            if (rawStrutLen < hardStopLen) {
                var pen = hardStopLen - rawStrutLen;
                if (pen > maxBottomOut) maxBottomOut = pen;
            }

            if (rawStrutLen <= unloadedLen) {
                groundedCount++;
                sumNormX += nx;
                sumNormY += ny;
                sumNormZ += nz;

                var clampedLen = rawStrutLen < minLen ? minLen : rawStrutLen;
                var compression = unloadedLen - clampedLen;

                // Strut compression velocity combining corner pitch/roll rate with chassis vertical rate
                var mountWorldVz = vz + wyOffset * pitchRate - wxOffset * rollRate;
                var compVel = prevGrounded[i]
                    ? (compression - prevCompressions[i]) / safeDt
                    : -mountWorldVz;

                // Clamp transient derivative spikes across frame boundaries
                if (compVel > 8.0) compVel = 8.0;
                else if (compVel < -8.0) compVel = -8.0;

                var dampRate = compVel >= 0.0 ? suspCfg.bumpDamping : suspCfg.reboundDamping;
                var springForce = suspCfg.springStiffness * compression + dampRate * compVel;

                // Soft progressive hydraulic bump-stop near full compression (never teleports or spikes)
                if (rawStrutLen < minLen) {
                    var penetration = minLen - rawStrutLen;
                    springForce += penetration * suspCfg.springStiffness * 1.45;
                }

                if (springForce < 0.0) springForce = 0.0;
                if (springForce > suspCfg.maxWheelForce) springForce = suspCfg.maxWheelForce;

                prevCompressions[i] = compression;
                prevGrounded[i] = true;

                wheelContacts.push({
                    grounded: true,
                    groundZ: surfaceZ,
                    suspLength: clampedLen,
                    compression: compression,
                    compressionVel: compVel,
                    normalLoad: springForce,
                    mu: mu,
                    normalX: nx,
                    normalY: ny,
                    normalZ: nz,
                    worldX: queryX,
                    worldY: queryY,
                    worldZ: surfaceZ
                });
            } else {
                prevCompressions[i] = 0.0;
                prevGrounded[i] = false;

                wheelContacts.push({
                    grounded: false,
                    groundZ: surfaceZ,
                    suspLength: unloadedLen,
                    compression: 0.0,
                    compressionVel: 0.0,
                    normalLoad: 0.0,
                    mu: mu,
                    normalX: nx,
                    normalY: ny,
                    normalZ: nz,
                    worldX: queryX,
                    worldY: queryY,
                    worldZ: surfaceZ
                });
            }
        }

        // Apply axle Anti-Roll Bar load transfer across left/right pairs: (FL, FR) and (RL, RR)
        var arbStiffness = suspCfg.antiRollStiffness;
        applyAntiRoll(wheelContacts[0], wheelContacts[1], arbStiffness, suspCfg.maxWheelForce);
        applyAntiRoll(wheelContacts[2], wheelContacts[3], arbStiffness, suspCfg.maxWheelForce);

        var totalZForce = 0.0;
        var pitchTorque = 0.0;
        var rollTorque = 0.0;

        for (i in 0...4) {
            var wc = wheelContacts[i];
            if (!wc.grounded || wc.normalLoad <= 0.0) continue;

            var off = CarMesh.WHEEL_OFFSETS[i];
            totalZForce += wc.normalLoad * wc.normalZ;

            // Pitch torque (+ = front force pushes nose UP around local +X)
            pitchTorque += wc.normalLoad * off.y;
            // Roll torque (+ = left force pushes left side UP -> chassis leans RIGHT around local +Y)
            rollTorque += wc.normalLoad * (-off.x);
        }

        var avgNX = 0.0;
        var avgNY = 0.0;
        var avgNZ = 1.0;
        if (groundedCount > 0) {
            var len = Math.sqrt(sumNormX * sumNormX + sumNormY * sumNormY + sumNormZ * sumNormZ);
            if (len > 0.001) {
                avgNX = sumNormX / len;
                avgNY = sumNormY / len;
                avgNZ = sumNormZ / len;
            }
        }

        return {
            wheels: wheelContacts,
            groundedCount: groundedCount,
            avgNormalX: avgNX,
            avgNormalY: avgNY,
            avgNormalZ: avgNZ,
            totalNormalZForce: totalZForce,
            pitchTorque: pitchTorque,
            rollTorque: rollTorque,
            maxBottomOutPenetration: maxBottomOut
        };
    }

    static inline function applyAntiRoll(leftWheel:WheelContact, rightWheel:WheelContact, stiffness:Float, maxForce:Float):Void {
        if (!leftWheel.grounded && !rightWheel.grounded) return;
        var diff = leftWheel.compression - rightWheel.compression;
        var arbForce = diff * stiffness;

        if (leftWheel.grounded) {
            leftWheel.normalLoad = clampF(leftWheel.normalLoad + arbForce, 0.0, maxForce);
        }
        if (rightWheel.grounded) {
            rightWheel.normalLoad = clampF(rightWheel.normalLoad - arbForce, 0.0, maxForce);
        }
    }

    static inline function clampF(v:Float, lo:Float, hi:Float):Float {
        return v < lo ? lo : (v > hi ? hi : v);
    }
}
