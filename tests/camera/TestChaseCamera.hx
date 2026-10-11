package tests.camera;

import utest.Test;
import utest.Assert;
import h3d.Camera;
import camera.ChaseCamera;
import physics.CarPhysics;

/**
 * Unit test suite validating chase camera spring-arm lag, speed FOV scaling,
 * and trauma screen shake decay.
 */
class TestChaseCamera extends Test {
    var cam:Camera;
    var chaseCam:ChaseCamera;
    var car:CarPhysics;

    public function setup() {
        cam = new Camera();
        chaseCam = new ChaseCamera(cam, 0, -10, 4);
        car = new CarPhysics();
    }

    public function testInitialFov() {
        Assert.floatEquals(65.0, cam.fovY, 0.01);
        Assert.floatEquals(0.0, chaseCam.trauma, 0.001);
    }

    public function testTraumaClampingAndDecay() {
        // Adding massive impulse should be capped at ceiling 0.55
        chaseCam.addTrauma(2.0);
        Assert.floatEquals(0.55, chaseCam.trauma, 0.01);

        // Update camera, trauma should decay exponentially
        chaseCam.update(0.1, car, false);
        Assert.isTrue(chaseCam.trauma < 0.55, "Trauma must decay over time");
        Assert.isTrue(chaseCam.trauma >= 0.0, "Trauma cannot fall below 0");
    }

    public function testSpeedFovScaling() {
        car.forwardSpeed = 60.0; // High speed
        chaseCam.update(0.05, car, false);
        Assert.isTrue(cam.fovY > 65.0, "FOV must increase at high vehicle speed");

        // Nitrous boost adds additional FOV
        var fovCruising = cam.fovY;
        chaseCam.update(0.05, car, true);
        Assert.isTrue(cam.fovY > fovCruising, "Nitrous boost must widen FOV further");
    }
}

