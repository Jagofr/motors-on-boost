package tests.physics;

import utest.Test;
import utest.Assert;
import h3d.Vector;
import oimo.dynamics.World;
import input.InputController;
import physics.CarConfig;
import physics.CarPhysics;
import world.IGroundProvider;

/**
 * Deterministic mock terrain provider supporting flat ground, sloped ramps,
 * and configurable tire surface friction for isolated physics validation.
 */
class MockGroundProvider implements IGroundProvider {
    public var mode:String = "flat";
    public var friction:Float = 1.0;
    public var slopeRadians:Float = 0.22; // ~12.6 deg
    public var rampStartY:Float = 15.0;

    public function new(?mode:String = "flat", friction:Float = 1.0) {
        this.mode = mode;
        this.friction = friction;
    }

    public function getGroundElevation(x:Float, y:Float):Float {
        if (mode == "ramp") {
            if (y <= rampStartY) return 0.0;
            return (y - rampStartY) * Math.tan(slopeRadians);
        } else if (mode == "hill") {
            return y * Math.tan(slopeRadians);
        }
        return 0.0;
    }

    public function getGroundNormal(x:Float, y:Float, out:Vector):Void {
        var active = (mode == "hill") || (mode == "ramp" && y > rampStartY);
        if (active) {
            out.set(0.0, -Math.sin(slopeRadians), Math.cos(slopeRadians));
        } else {
            out.set(0.0, 0.0, 1.0);
        }
    }

    public function getGroundFriction(x:Float, y:Float):Float {
        return friction;
    }

    public function enforceBoundaries(pos:Vector, forwardSpeed:Float, lateralVelocity:Float):{ hitWall:Bool, speedMult:Float, latMult:Float } {
        return { hitWall: false, speedMult: 1.0, latMult: 1.0 };
    }

    public function registerPhysicsColliders(world:World):Void {}
    public function unregisterPhysicsColliders(world:World):Void {}
}

/**
 * Comprehensive verification suite for the 4-wheel raycast CarPhysics engine:
 * equilibrium stability, standstill slope stiction, acceleration/gears, reverse interlock,
 * left/right steering sign correctness, smooth slope climbing, surface friction, boost, and Oimo sync.
 */
class TestCarPhysics extends Test {
    var car:CarPhysics;
    var input:InputController;
    var dt:Float = 1.0 / 60.0;

    public function setup() {
        car = new CarPhysics(0.0, 0.0, 0.0);
        input = new InputController();
    }

    function stepSimulation(seconds:Float, steer:Float, throttle:Float, brake:Float, ?ground:IGroundProvider, handbrake:Bool = false, boost:Bool = false) {
        var frames = Math.round(seconds / dt);
        for (_ in 0...frames) {
            input.steer = steer;
            input.throttle = throttle;
            input.brake = brake;
            input.handbrake = handbrake;
            input.boost = boost;
            car.update(dt, input, null, ground);
        }
    }

    public function testFlatStandstillNoWobbleOrBounce() {
        var ground = new MockGroundProvider("flat", 1.0);
        car.resetState(0.0, 0.0, 0.0, 0.0);

        stepSimulation(2.0, 0.0, 0.0, 0.0, ground);

        Assert.floatEquals(0.0, car.pos.x, 0.005);
        Assert.floatEquals(0.0, car.pos.y, 0.005);
        Assert.floatEquals(0.0, car.pos.z, 0.025);
        Assert.floatEquals(0.0, car.forwardSpeed, 0.02);
        Assert.floatEquals(0.0, car.yaw, 0.005);
        Assert.floatEquals(0.0, car.pitch, 0.02);
        Assert.floatEquals(0.0, car.roll, 0.02);
        Assert.equals(4, car.groundedWheelCount);
        Assert.floatEquals(car.config.suspension.restLength, car.suspLength[0], 0.03);
    }

    public function testSlopeStandstillStictionHoldsWithoutCreep() {
        var ground = new MockGroundProvider("hill", 1.0);
        ground.slopeRadians = 0.18; // ~10.3 deg grade
        car.resetState(0.0, 0.0, 0.0, 0.0);
        car.pitch = 0.18;

        stepSimulation(2.0, 0.0, 0.0, 0.0, ground);

        // Static friction holds car steady without rolling down the slope
        Assert.isTrue(Math.abs(car.forwardSpeed) < 0.10, "Parked car crept down moderate slope: " + car.forwardSpeed);
        Assert.isTrue(Math.abs(car.pos.y) < 0.10, "Parked car shifted Y on slope: " + car.pos.y);
    }

    public function testAccelerationShiftsThroughGears() {
        var ground = new MockGroundProvider("flat", 1.0);
        car.resetState(0.0, 0.0, 0.0, 0.0);

        stepSimulation(4.5, 0.0, 1.0, 0.0, ground);

        Assert.isTrue(car.forwardSpeed > 28.0, "Expected strong acceleration > 28 m/s, got " + car.forwardSpeed);
        Assert.isTrue(car.currentGear >= 2, "Expected automatic upshift >= 2nd gear, got " + car.currentGear);
        Assert.isTrue(car.engineRPM > car.config.drivetrain.idleRPM);
        Assert.isTrue(car.pos.y > 60.0);
    }

    public function testBrakingStopsAndEngagesReverse() {
        var ground = new MockGroundProvider("flat", 1.0);
        car.resetState(0.0, 0.0, 0.0, 0.0);

        stepSimulation(2.0, 0.0, 1.0, 0.0, ground);
        var speedBeforeBrake = car.forwardSpeed;
        Assert.isTrue(speedBeforeBrake > 12.0);

        stepSimulation(3.5, 0.0, 0.0, 1.0, ground);
        Assert.equals(-1, car.currentGear);
        Assert.isTrue(car.forwardSpeed < -3.0, "Expected vehicle reversing when holding brake past stop, got " + car.forwardSpeed);
    }

    public function testSteeringLeftTurnsNegativeXAndRightTurnsPositiveX() {
        var ground = new MockGroundProvider("flat", 1.0);

        // Left steering test (input.steer < 0)
        car.resetState(0.0, 0.0, 0.0, 0.0);
        stepSimulation(0.8, 0.0, 1.0, 0.0, ground);
        stepSimulation(1.4, -1.0, 1.0, 0.0, ground);
        var leftPosX = car.pos.x;
        var leftYaw = car.yaw;
        Assert.isTrue(leftYaw < -0.25, "Steer Left must yield negative yaw, got " + leftYaw);
        Assert.isTrue(leftPosX < -1.5, "Steer Left must translate vehicle toward -X, got " + leftPosX);

        // Right steering test (input.steer > 0)
        car.resetState(0.0, 0.0, 0.0, 0.0);
        stepSimulation(0.8, 0.0, 1.0, 0.0, ground);
        stepSimulation(1.4, 1.0, 1.0, 0.0, ground);
        var rightPosX = car.pos.x;
        var rightYaw = car.yaw;
        Assert.isTrue(rightYaw > 0.25, "Steer Right must yield positive yaw, got " + rightYaw);
        Assert.isTrue(rightPosX > 1.5, "Steer Right must translate vehicle toward +X, got " + rightPosX);

        // Symmetric handling left vs right
        Assert.floatEquals(-leftPosX, rightPosX, 0.25);
        Assert.floatEquals(-leftYaw, rightYaw, 0.08);
    }

    public function testPartialAnalogSteerProducesProportionateArc() {
        var ground = new MockGroundProvider("flat", 1.0);

        car.resetState(0.0, 0.0, 0.0, 0.0);
        stepSimulation(0.8, 0.0, 1.0, 0.0, ground);
        stepSimulation(1.0, -0.45, 1.0, 0.0, ground);
        var mildYaw = car.yaw;

        car.resetState(0.0, 0.0, 0.0, 0.0);
        stepSimulation(0.8, 0.0, 1.0, 0.0, ground);
        stepSimulation(1.0, -1.0, 1.0, 0.0, ground);
        var fullYaw = car.yaw;

        Assert.isTrue(mildYaw < -0.05 && mildYaw > fullYaw, "Partial left stick should turn less sharply than full stick");
    }

    public function testSmoothSlopeClimbWithoutCatapultLaunch() {
        var rampGround = new MockGroundProvider("ramp", 1.0);
        rampGround.slopeRadians = 0.24; // ~13.7 deg continuous ramp starting at y = 15
        rampGround.rampStartY = 15.0;
        car.resetState(0.0, 0.0, 0.0, 0.0);

        var maxVerticalSpeed = 0.0;
        var maxClearanceGap = 0.0;

        var totalFrames = Math.round(3.5 / dt);
        for (f in 0...totalFrames) {
            input.steer = 0.0;
            input.throttle = 1.0;
            input.brake = 0.0;
            input.handbrake = false;
            input.boost = false;
            car.update(dt, input, null, rampGround);

            if (car.verticalVelocity > maxVerticalSpeed) maxVerticalSpeed = car.verticalVelocity;
            var terrainZ = rampGround.getGroundElevation(car.pos.x, car.pos.y);
            var gap = car.pos.z - terrainZ;
            if (gap > maxClearanceGap) maxClearanceGap = gap;
        }

        var finalTerrainZ = rampGround.getGroundElevation(car.pos.x, car.pos.y);
        Assert.isTrue(car.pos.y > 40.0, "Car must climb onto ramp cleanly, y=" + car.pos.y);
        Assert.isTrue(car.pos.z > 4.0, "Car must climb vertically up ramp, z=" + car.pos.z);
        Assert.isTrue(car.pitch > 0.05, "Chassis nose must pitch up smoothly on ramp, pitch=" + car.pitch);
        Assert.isTrue(maxClearanceGap < 0.75, "Ramp transition must NOT catapult car into the sky: maxGap=" + maxClearanceGap);
        Assert.isTrue(car.pos.z >= finalTerrainZ - 0.35, "Car must not fall through ramp surface");
    }

    public function testSurfaceMaterialFrictionGovernsGrip() {
        var dryAsphalt = new MockGroundProvider("flat", 1.05);
        var slickIce = new MockGroundProvider("flat", 0.22);

        // Corner at speed on dry asphalt
        car.resetState(0.0, 0.0, 0.0, 0.0);
        stepSimulation(1.0, 0.0, 1.0, 0.0, dryAsphalt);
        stepSimulation(1.2, 0.9, 0.6, 0.0, dryAsphalt);
        var dryYaw = car.yaw;

        // Same cornering maneuver on slick ice
        car.resetState(0.0, 0.0, 0.0, 0.0);
        stepSimulation(1.0, 0.0, 1.0, 0.0, dryAsphalt);
        stepSimulation(1.2, 0.9, 0.6, 0.0, slickIce);
        var iceYaw = car.yaw;

        Assert.isTrue(dryYaw > iceYaw + 0.15, "Higher surface friction must provide sharper turn-in rate (" + dryYaw + " vs " + iceYaw + ")");
    }

    public function testNitrousBoostAndRegeneration() {
        var ground = new MockGroundProvider("flat", 1.0);

        car.resetState(0.0, 0.0, 0.0, 0.0);
        stepSimulation(2.0, 0.0, 1.0, 0.0, ground, false, false);
        var normalSpeed = car.forwardSpeed;

        car.resetState(0.0, 0.0, 0.0, 0.0);
        stepSimulation(2.0, 0.0, 1.0, 0.0, ground, false, true);
        var boostSpeed = car.forwardSpeed;
        var fuelAfterBurn = car.boostFuel;

        Assert.isTrue(boostSpeed > normalSpeed + 2.0, "Nitrous boost must increase speed significantly");
        Assert.isTrue(fuelAfterBurn < car.config.boost.maxFuel - 0.2);

        stepSimulation(2.0, 0.0, 0.0, 0.0, ground, false, false);
        Assert.isTrue(car.boostFuel > fuelAfterBurn, "Nitrous fuel must regenerate after releasing boost");
    }

    public function testOimoRigidBodySync() {
        car.resetState(12.5, -45.0, 2.0, 0.0);
        car.forwardSpeed = 24.0;
        car.syncToOimoBody();

        Assert.floatEquals(12.5, car.chassisBody.getPosition().x, 0.001);
        Assert.floatEquals(-45.0, car.chassisBody.getPosition().y, 0.001);
        Assert.floatEquals(2.0 + car.config.chassis.cogHeight, car.chassisBody.getPosition().z, 0.001);
        Assert.floatEquals(24.0, car.chassisBody.getLinearVelocity().y, 0.01);
    }
}
