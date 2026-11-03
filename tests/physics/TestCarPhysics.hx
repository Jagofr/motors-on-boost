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

    public function testSteeringDirectionRightAndLeft() {
        // Facing +Y (yaw = 0): steering right (+1.0) turns car rightward on screen toward +X
        car.resetState(0.0, 0.0, 0.0, 0.0);
        car.forwardSpeed = 20.0;
        input.throttle = 1.0;
        input.steer = 1.0; // Steer Right (D)

        for (i in 0...30) {
            car.update(1.0 / 60.0, input);
        }

        Assert.isTrue(car.yaw > 0.05, "Steering right (+1.0) must turn car rightward on screen");
        Assert.isTrue(car.pos.x > 0.2, "Steering right (+1.0) while moving +Y must move vehicle rightward (+X)");
        Assert.isTrue(car.pos.y > 5.0, "Vehicle must advance along +Y (Forward)");

        // Facing +Y (yaw = 0): steering left (-1.0) turns car leftward on screen toward -X
        car.resetState(0.0, 0.0, 0.0, 0.0);
        car.forwardSpeed = 20.0;
        input.throttle = 1.0;
        input.steer = -1.0; // Steer Left (A)

        for (i in 0...30) {
            car.update(1.0 / 60.0, input);
        }

        Assert.isTrue(car.yaw < -0.05, "Steering left (-1.0) must turn car leftward on screen");
        Assert.isTrue(car.pos.x < -0.2, "Steering left (-1.0) while moving +Y must move vehicle leftward (-X)");
    }

    public function testCarMeshAndWheelRimAlignment() {
        var mesh = new entities.CarMesh();
        Assert.equals(4, mesh.wheels.length);
        Assert.equals(4, mesh.rimCaps.length);

        // Body mesh centered at Y = 0.0
        Assert.floatEquals(0.0, mesh.bodyMesh.y, 0.001);

        // Left wheels (0: FL, 2: RL) are at x = -0.98 and rimCaps at z < 0 (pointing outward along -X)
        Assert.floatEquals(-0.98, mesh.wheels[0].x, 0.001);
        Assert.isTrue(mesh.rimCaps[0].z < 0.0, "Front-left rim cap must be on outer left face (-X)");
        Assert.floatEquals(-0.98, mesh.wheels[2].x, 0.001);
        Assert.isTrue(mesh.rimCaps[2].z < 0.0, "Rear-left rim cap must be on outer left face (-X)");

        // Right wheels (1: FR, 3: RR) are at x = +0.98 and rimCaps at z > 0 (pointing outward along +X)
        Assert.floatEquals(0.98, mesh.wheels[1].x, 0.001);
        Assert.isTrue(mesh.rimCaps[1].z > 0.0, "Front-right rim cap must be on outer right face (+X)");
        Assert.floatEquals(0.98, mesh.wheels[3].x, 0.001);
        Assert.isTrue(mesh.rimCaps[3].z > 0.0, "Rear-right rim cap must be on outer right face (+X)");
    }

    public function testZeroFrictionAndRestitutionRule() {
        var shape = car.chassisBody.getShapeList();
        Assert.notNull(shape, "Chassis body shape must be present");
        Assert.floatEquals(0.0, shape.getFriction(), 0.001);
        Assert.floatEquals(0.0, shape.getRestitution(), 0.001);
    }

    public function testIsGroundedStateDetection() {
        // When dropped from 15.0m elevation (in mid-air)
        car.resetState(0.0, 0.0, 15.0, 0.0);
        car.update(1.0 / 60.0, input);
        Assert.isFalse(car.isGrounded, "Car at 15.0m elevation with ground at 0.0m must be airborne (isGrounded == false)");

        // When positioned on the road (Z = 0.06m)
        car.resetState(0.0, 0.0, 0.06, 0.0);
        car.update(1.0 / 60.0, input);
        Assert.isTrue(car.isGrounded, "Car positioned at road surface must be grounded (isGrounded == true)");
    }

    public function testLandingBufferEnergyTranslation() {
        // Place car airborne falling at -10 m/s
        car.resetState(0.0, 0.0, 2.0, 0.0);
        car.forwardSpeed = 20.0;
        car.verticalVelocity = -10.0;
        car.syncToOimoBody();
        car.update(1.0 / 60.0, input);
        Assert.isFalse(car.isGrounded, "Car at 2.0m height must be airborne");

        // Touchdown occurs on road surface (Z = 0.06)
        car.pos.z = 0.06;
        car.verticalVelocity = -10.0;
        car.forwardSpeed = 20.0;
        car.syncToOimoBody();
        var speedBeforeLanding = car.forwardSpeed;

        car.update(1.0 / 60.0, input);
        Assert.isTrue(car.isGrounded, "Car should land on ground contact");
        // 30% of 10 m/s downward velocity should translate into forward speed (+3.0 m/s)
        Assert.isTrue(car.forwardSpeed > speedBeforeLanding + 2.0, "Landing buffer must convert vertical downward velocity into forward boost");
    }

    public function testHeadingDirectionVectorsConsistency() {
        var carFwd = new h3d.Vector();
        var carRight = new h3d.Vector();

        // Yaw = 0 (Facing +Y forward, +X right)
        car.yaw = 0.0;
        car.getForwardVector(carFwd);
        car.getRightVector(carRight);
        Assert.floatEquals(0.0, carFwd.x, 0.001);
        Assert.floatEquals(1.0, carFwd.y, 0.001);
        Assert.floatEquals(1.0, carRight.x, 0.001);
        Assert.floatEquals(0.0, carRight.y, 0.001);

        // TrafficCar heading consistency
        var dummyMesh = new entities.TrafficCarMesh(0xFFFFFF);
        var tc = new entities.TrafficSystem.TrafficCar(dummyMesh, 0, false, 17.0);
        tc.yaw = 1.5707963; // Facing +Y in standard angle (pi/2)
        var tcFwd = new h3d.Vector();
        var tcRight = new h3d.Vector();
        tc.getForwardVector(tcFwd);
        tc.getRightVector(tcRight);
        Assert.floatEquals(0.0, tcFwd.x, 0.001);
        Assert.floatEquals(1.0, tcFwd.y, 0.001);
        Assert.floatEquals(1.0, tcRight.x, 0.001);
        Assert.floatEquals(0.0, tcRight.y, 0.001);
    }

    public function testCarMeshPublicConstantsAndWheelTransform() {
        Assert.floatEquals(0.36, entities.CarMesh.TIRE_RADIUS, 0.001);
        Assert.floatEquals(0.30, entities.CarMesh.TIRE_WIDTH, 0.001);
        Assert.floatEquals(1.88, entities.CarMesh.CHASSIS_WIDTH, 0.001);
        Assert.floatEquals(4.30, entities.CarMesh.CHASSIS_LENGTH, 0.001);

        var mesh = new entities.CarMesh();
        mesh.updateWheelTransform(0, 0.10, 1.5, 0.35);
        Assert.floatEquals(entities.CarMesh.TIRE_RADIUS + 0.10 * 0.45, mesh.wheels[0].z, 0.001);
    }

    public function testStandstillStabilizationNoWobble() {
        car.resetState(0.0, 0.0, 0.0, 0.0);
        car.forwardSpeed = 0.05;
        car.lateralVelocity = 0.05;
        input.throttle = 0.0;
        input.brake = 0.0;
        input.steer = 0.0;

        for (i in 0...60) {
            car.update(1.0 / 60.0, input);
        }

        Assert.floatEquals(0.0, car.forwardSpeed, 0.01);
        Assert.floatEquals(0.0, car.lateralVelocity, 0.01);
        var angVel = car.chassisBody.getAngularVelocity();
        Assert.floatEquals(0.0, angVel.z, 0.01);
    }
}

