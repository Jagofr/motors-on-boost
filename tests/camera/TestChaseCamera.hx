package tests.camera;

import utest.Test;
import utest.Assert;
import graphics.SceneGraph.Camera3D;
import input.InputController;
import physics.CarPhysics;
import camera.ChaseCamera;
import tests.physics.TestCarPhysics.MockGroundProvider;

/**
 * Unit test suite verifying ChaseCamera velocity-aligned spring lag, speed/boost FOV expansion,
 * lateral-G banking limits, terrain clearance floor protection, and trauma decay.
 */
class TestChaseCamera extends Test {
    var cam:Camera3D;
    var chase:ChaseCamera;
    var car:CarPhysics;
    var input:InputController;
    var dt:Float = 1.0 / 60.0;

    public function setup() {
        cam = new Camera3D();
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

    public function testProjectionJitterAndSoAPacking() {
        cam.pos.set(0.0, -10.0, 2.0, 1.0);
        cam.target.set(0.0, 0.0, 1.0, 1.0);
        cam.up.set(0.0, 0.0, 1.0, 0.0);

        var jx = 0.0025;
        var jy = -0.0040;
        cam.updateMatrices(16.0 / 9.0, jx, jy);

        var worldPt = new math.Vec3(0.0, 0.0, 1.0, 1.0);
        var jClip = worldPt.transformed(cam.viewProjMat);
        var uClip = worldPt.transformed(cam.unjitteredViewProjMat);
        Assert.floatEquals(uClip.x / uClip.w + jx, jClip.x / jClip.w, 0.0001);
        Assert.floatEquals(uClip.y / uClip.w + jy, jClip.y / jClip.w, 0.0001);

        var soa = new math.SoABuffer(4);
        var curMat = new math.Mat4();
        curMat.m[12] = 5.0;
        var prevMat = new math.Mat4();
        prevMat.m[12] = 2.5;
        soa.pushInstance(curMat, 1.0, 0.5, 0.25, 1.0, 0.0, 0.4, 0.0, 0.0, prevMat);
        var bytesLen = soa.packToBytes();
        Assert.equals(math.SoABuffer.INSTANCE_STRIDE_BYTES, bytesLen);
        Assert.floatEquals(5.0, soa.stagingBytes.getFloat(48), 0.0001);
        Assert.floatEquals(2.5, soa.stagingBytes.getFloat(64 + 48), 0.0001);
    }
}
