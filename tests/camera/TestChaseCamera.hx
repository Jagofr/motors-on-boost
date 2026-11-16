package tests.camera;

import utest.Test;
import utest.Assert;
import h3d.Camera;
import input.InputController;
import physics.CarPhysics;
import camera.ChaseCamera;
import tests.physics.TestCarPhysics.MockGroundProvider;

/**
 * Unit test suite verifying ChaseCamera velocity-aligned spring lag, speed/boost FOV expansion,
 * lateral-G banking limits, terrain clearance floor protection, and trauma decay.
 */
class TestChaseCamera extends Test {
    var cam:Camera;
    var chase:ChaseCamera;
    var car:CarPhysics;
    var input:InputController;
    var dt:Float = 1.0 / 60.0;

    public function setup() {
        cam = new Camera();
        car = new CarPhysics(0.0, 0.0, 0.0);
        chase = new ChaseCamera(cam, 0.0, -ChaseCamera.BASE_DISTANCE, ChaseCamera.BASE_HEIGHT);
        input = new InputController();
    }

    public function testSnapBehindPlacesCameraDirectlyBehindHeading() {
        car.resetState(10.0, 20.0, 1.0, 0.0);
        chase.snapBehind(car);

        Assert.floatEquals(10.0, cam.pos.x, 0.05);
        Assert.floatEquals(20.0 - ChaseCamera.BASE_DISTANCE, cam.pos.y, 0.05);
        Assert.floatEquals(1.0 + ChaseCamera.BASE_HEIGHT, cam.pos.z, 0.05);
        Assert.isTrue(cam.target.y > car.pos.y);
    }

    public function testDynamicFollowAndBoostFovExpansion() {
        var ground = new MockGroundProvider("flat", 1.0);
        car.resetState(0.0, 0.0, 0.0, 0.0);
        chase.snapBehind(car);

        // Accelerate forward and hold right steer
        for (i in 0...150) {
            input.throttle = 1.0;
            input.steer = i > 45 ? 0.65 : 0.0;
            input.boost = true;
            car.update(dt, input, null, ground);
            chase.update(dt, car, car.isBoosting);
        }

        // Camera should smoothly follow behind the vehicle along +Y/+X path and expand FOV
        Assert.isTrue(cam.pos.y > 10.0, "Camera should follow car forward down track");
        Assert.isTrue(cam.fovY > ChaseCamera.BASE_FOV + 4.0, "FOV should expand dynamically with speed & boost");
        Assert.isTrue(Math.abs(cam.up.x) <= ChaseCamera.MAX_BANK_RAD + 0.02, "Camera bank must stay subtly bounded");
    }

    public function testTraumaSofteningClampingAndDecay() {
        Assert.floatEquals(0.0, chase.trauma, 0.001);

        chase.addTrauma(0.35);
        Assert.floatEquals(0.175, chase.trauma, 0.001);

        chase.addTrauma(10.0);
        Assert.floatEquals(1.0, chase.trauma, 0.001);

        var ground = new MockGroundProvider("flat", 1.0);
        car.resetState(0.0, 0.0, 0.0, 0.0);
        for (_ in 0...120) {
            car.update(dt, input, null, ground);
            chase.update(dt, car, false);
        }
        Assert.floatEquals(0.0, chase.trauma, 0.001);
    }

    public function testTerrainFloorClearanceGuardPreventsUndergroundClipping() {
        var rampGround = new MockGroundProvider("ramp", 1.0);
        rampGround.slopeRadians = 0.25;
        rampGround.rampStartY = 0.0;

        car.resetState(0.0, 20.0, rampGround.getGroundElevation(0.0, 20.0), 0.0);
        car.groundProvider = rampGround;

        // Place camera deliberately underground before updating
        cam.pos.z = -5.0;
        for (_ in 0...20) {
            chase.update(dt, car, false);
        }

        var floorAtCam = rampGround.getGroundElevation(cam.pos.x, cam.pos.y);
        Assert.isTrue(cam.pos.z >= floorAtCam + 0.4, "Chase camera must never clip below rising terrain");
    }
}
