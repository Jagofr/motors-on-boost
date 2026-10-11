package tests.input;

import utest.Test;
import utest.Assert;
import hxd.Key;
import input.InputController;
import input.InputController.ExclusiveDevice;

/**
 * Unit test suite validating input binding resets, multi-touch registers,
 * and steering sensitivity scaling.
 */
class TestInputController extends Test {
    var input:InputController;

    public function setup() {
        input = new InputController();
    }

    public function testDefaultBindings() {
        Assert.equals(Key.W, input.bindings.keyGas);
        Assert.equals(Key.S, input.bindings.keyBrake);
        Assert.equals(Key.A, input.bindings.keyLeft);
        Assert.equals(Key.D, input.bindings.keyRight);
        Assert.equals(Key.SPACE, input.bindings.keyHandbrake);
        Assert.equals(Key.SHIFT, input.bindings.keyBoost);
    }

    public function testSensitivityProperty() {
        Assert.floatEquals(1.0, input.steerSensitivity, 0.001);
        input.steerSensitivity = 0.5;
        Assert.floatEquals(0.5, input.steerSensitivity, 0.001);
    }

    public function testTouchRegistersDirectAssignment() {
        // Test simultaneous multi-touch chord: Throttle + Boost + Left Steer
        input.touchThrottle = 1.0;
        input.touchBoost = true;
        input.touchSteer = -0.75;
        input.isTouchActive = true;

        Assert.floatEquals(1.0, input.touchThrottle, 0.001);
        Assert.isTrue(input.touchBoost);
        Assert.floatEquals(-0.75, input.touchSteer, 0.001);
        Assert.isTrue(input.isTouchActive);

        // Clear touch inputs
        input.touchThrottle = 0.0;
        input.touchBoost = false;
        input.touchSteer = 0.0;
        Assert.floatEquals(0.0, input.touchThrottle, 0.001);
        Assert.isFalse(input.touchBoost);
    }

    public function testKeyNameLookup() {
        Assert.equals("W", InputController.getKeyName(Key.W));
        Assert.equals("A", InputController.getKeyName(Key.A));
        Assert.equals("SPACE", InputController.getKeyName(Key.SPACE));
        Assert.equals("L-SHIFT", InputController.getKeyName(Key.SHIFT));
    }

    public function testExclusiveDeviceModes() {
        input.exclusiveDevice = ExclusiveDevice.KeyboardOnly;
        Assert.equals(ExclusiveDevice.KeyboardOnly, input.exclusiveDevice);

        input.exclusiveDevice = ExclusiveDevice.GamepadOnly;
        Assert.equals(ExclusiveDevice.GamepadOnly, input.exclusiveDevice);

        input.exclusiveDevice = ExclusiveDevice.Both;
        Assert.equals(ExclusiveDevice.Both, input.exclusiveDevice);
    }
}
