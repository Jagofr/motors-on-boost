package tests.physics;

import utest.Test;
import utest.Assert;
import h3d.Vector;
import input.InputController;
import physics.CarPhysics;
import physics.CarConfig;

/**
 * Unit test suite validating raycast suspension dynamics, Pacejka slip curves,
 * drift state machine transitions, and nitro capacity drain/recharge.
 */
class TestCarPhysics extends Test {
    var car:CarPhysics;
    var input:InputController;

    public function setup() {
        car = new CarPhysics();
        input = new InputController();
    }

    public function testInitialState() {
        Assert.floatEquals(0.0, car.forwardSpeed, 0.001);
        Assert.floatEquals(1.0, car.boostFuel, 0.001);
        Assert.isFalse(car.isDrifting);
        Assert.isFalse(car.isBoosting);
        Assert.equals(4, car.suspLength.length);
        Assert.equals(4, car.wheelOnGround.length);
    }

    public function testTunablePropertiesClamping() {
        // tireSlipBias clamped [-1.0 .. 1.0]
        car.tireSlipBias = -1.5;
        Assert.floatEquals(-1.0, car.tireSlipBias, 0.001);
        car.tireSlipBias = 2.0;
        Assert.floatEquals(1.0, car.tireSlipBias, 0.001);
        car.tireSlipBias = -0.3;
        Assert.floatEquals(-0.3, car.tireSlipBias, 0.001);

        // groundFriction
        car.groundFriction = 1.25;
        Assert.floatEquals(1.25, car.groundFriction, 0.001);

        // driftTriggerAngle
        car.driftTriggerAngle = 0.28;
        Assert.floatEquals(0.28, car.driftTriggerAngle, 0.001);

        // bodyRollScale
        car.bodyRollScale = 0.85;
        Assert.floatEquals(0.85, car.bodyRollScale, 0.001);
    }

    public function testThrottleAcceleration() {
        input.throttle = 1.0;
        input.brake = 0.0;
        input.steer = 0.0;

        // Simulate 1 second of forward driving
        for (i in 0...60) {
            car.update(1.0 / 60.0, input);
        }

        Assert.isTrue(car.forwardSpeed > 5.0, "Car should accelerate forward under full throttle");
        Assert.isTrue(car.engineRPM > 1000.0, "Engine RPM should rise above idle during acceleration");
    }

    public function testBrakingDeceleration() {
        car.forwardSpeed = 30.0;
        input.throttle = 0.0;
        input.brake = 1.0;

        for (i in 0...30) {
            car.update(1.0 / 60.0, input);
        }

        Assert.isTrue(car.forwardSpeed < 30.0, "Car should decelerate under braking");
    }

    public function testNitroDrainAndRecharge() {
        car.forwardSpeed = 20.0;
        input.throttle = 1.0;
        input.boost = true;

        // Drain for 1 second
        for (i in 0...60) {
            car.update(1.0 / 60.0, input);
        }

        Assert.isTrue(car.isBoosting, "Car should be actively boosting");
        Assert.isTrue(car.boostFuel < 1.0, "Boost fuel should drain while boosting");
        var fuelAfterDrain = car.boostFuel;

        // Stop boosting, let recharge for 1 second
        input.boost = false;
        for (i in 0...60) {
            car.update(1.0 / 60.0, input);
        }

        Assert.isFalse(car.isBoosting, "Boosting should be inactive");
        Assert.isTrue(car.boostFuel > fuelAfterDrain, "Boost fuel should recover over time");
        Assert.isTrue(car.boostFuel <= 1.0, "Boost fuel should not exceed 100%");
    }

    public function testNitroDepletionStopsBoost() {
        car.forwardSpeed = 20.0;
        car.boostFuel = 0.02; // Nearly empty
        input.throttle = 1.0;
        input.boost = true;

        for (i in 0...30) {
            car.update(1.0 / 60.0, input);
        }

        Assert.isFalse(car.isBoosting, "Boosting must shut off once nitro fuel is exhausted");
        Assert.floatEquals(0.0, car.boostFuel, 0.01);
    }

    public function testDriftInitiationViaHandbrake() {
        car.forwardSpeed = 25.0; // Above minDriftSpeed
        input.throttle = 1.0;
        input.steer = 0.8; // Sharp steering
        input.handbrake = true; // Trigger drift

        for (i in 0...15) {
            car.update(1.0 / 60.0, input);
        }

        Assert.isTrue(car.isDrifting, "Car should initiate drift when handbrake is engaged with steering");
        Assert.isTrue(car.driftDirection != 0.0, "Drift direction should indicate left or right bias");
    }

    public function testDriftExitOnLowSpeed() {
        car.forwardSpeed = 20.0;
        car.isDrifting = true;
        car.driftDirection = 1.0;

        // Drop speed below exit threshold
        car.forwardSpeed = 1.0;
        input.handbrake = false;
        input.steer = 0.0;

        car.update(1.0 / 60.0, input);
        Assert.isFalse(car.isDrifting, "Drift should terminate when speed drops below threshold");
    }

    public function testOimoRigidBodyBackbone() {
        Assert.notNull(car.physicsWorld, "Oimo physics world must be initialized");
        Assert.notNull(car.chassisBody, "Oimo chassis rigid body must be instantiated");

        // Verify gravity along -Z
        var g = car.physicsWorld.getGravity();
        Assert.floatEquals(0.0, g.x, 0.001);
        Assert.floatEquals(0.0, g.y, 0.001);
        Assert.floatEquals(-9.81, g.z, 0.001);

        // Verify chassis position
        var pos = car.chassisBody.getPosition();
        Assert.floatEquals(car.pos.x, pos.x, 0.001);
        Assert.floatEquals(car.pos.y, pos.y, 0.001);
        Assert.floatEquals(car.pos.z + 0.35, pos.z, 0.001);
    }

    public function testResetStateOimoSync() {
        car.resetState(50.0, -120.0, 5.0, 3.14159);
        Assert.floatEquals(50.0, car.pos.x, 0.001);
        Assert.floatEquals(-120.0, car.pos.y, 0.001);
        Assert.floatEquals(5.0, car.pos.z, 0.001);

        var bPos = car.chassisBody.getPosition();
        Assert.floatEquals(50.0, bPos.x, 0.001);
        Assert.floatEquals(-120.0, bPos.y, 0.001);
        Assert.floatEquals(5.35, bPos.z, 0.001);

        var bVel = car.chassisBody.getLinearVelocity();
        Assert.floatEquals(0.0, bVel.length(), 0.001);
    }
}

