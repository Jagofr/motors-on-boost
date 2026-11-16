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

    public function testAnalogGamepadAndTouchSteeringSignsAndDeadzone() {
        var pad = hxd.Pad.createDummy();
        @:privateAccess input.pad = pad;
        input.exclusiveDevice = ExclusiveDevice.GamepadOnly;
        @:privateAccess pad.connected = true;

        // Inside deadzone must remain zero
        @:privateAccess pad.rawXAxis = -0.05;
        input.update(1.0 / 60.0);
        Assert.floatEquals(0.0, input.steer, 0.0001);

        // Analog stick pushed Left (-0.5) must produce positive steer (> 0)
        @:privateAccess pad.rawXAxis = -0.5;
        input.update(1.0 / 60.0);
        var leftHalf = input.steer;
        Assert.isTrue(leftHalf > 0.15 && leftHalf < 0.7, "Analog partial left stick expected in (0.15, 0.7), got " + leftHalf);

        // Analog stick pushed Right (+0.5) must produce exact opposite negative steer (< 0)
        @:privateAccess pad.rawXAxis = 0.5;
        input.update(1.0 / 60.0);
        var rightHalf = input.steer;
        Assert.floatEquals(-leftHalf, rightHalf, 0.001);

        // Full left / full right analog stick must reach +1.0 and -1.0 cleanly
        @:privateAccess pad.rawXAxis = -1.0;
        input.update(1.0 / 60.0);
        Assert.floatEquals(1.0, input.steer, 0.001);

        @:privateAccess pad.rawXAxis = 1.0;
        input.update(1.0 / 60.0);
        Assert.floatEquals(-1.0, input.steer, 0.001);

        // Releasing analog stick resets steer back to 0 cleanly
        @:privateAccess pad.rawXAxis = 0.0;
        input.update(1.0 / 60.0);
        Assert.floatEquals(0.0, input.steer, 0.001);

        // Virtual touch stick sign consistency and sensitivity non-compounding (1.20x base * 0.5 = 0.60)
        input.exclusiveDevice = ExclusiveDevice.Both;
        input.steerSensitivity = 0.5;
        input.touchSteer = -1.0;
        for (_ in 0...15) input.update(1.0 / 60.0);
        Assert.floatEquals(0.6, input.steer, 0.01);

        input.touchSteer = 1.0;
        for (_ in 0...15) input.update(1.0 / 60.0);
        Assert.floatEquals(-0.6, input.steer, 0.01);
    }
}
