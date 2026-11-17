package tests.physics;

import utest.Test;
import utest.Assert;
import math.Vec3;
import oimo.dynamics.World;
import input.InputController;
import input.InputKey;
import input.GamepadDevice;
import graphics.SceneGraph.Camera3D;
import ui.components.TouchControlsHUD;
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

    public function getGroundNormal(x:Float, y:Float, out:Vec3):Void {
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

    public function enforceBoundaries(pos:Vec3, forwardSpeed:Float, lateralVelocity:Float):{ hitWall:Bool, speedMult:Float, latMult:Float } {
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

    /**
     * Core anti-inversion regression contract:
     * Ensures EVERY supported input modality (Keyboard WASD, Keyboard Arrows,
     * Gamepad Analog Stick, Gamepad D-Pad, and Virtual Touch Stick) obeys:
     *   - Turn Left  => steer < 0, car.yaw < 0, car.pos.x < 0, camera screen ndc.x < 0
     *   - Turn Right => steer > 0, car.yaw > 0, car.pos.x > 0, camera screen ndc.x > 0
     */
    public function testCoreAllInputDevicesSteeringDirectionNeverInverted() {
        var ground = new MockGroundProvider("flat", 1.0);
        var fixedDt = 1.0 / 60.0;
        var cam = new Camera3D();
        cam.pos.set(0.0, -10.0, 4.0, 1.0);
        cam.target.set(0.0, 20.0, 1.0, 1.0);
        cam.up.set(0.0, 0.0, 1.0, 0.0);
        cam.updateMatrices(16.0 / 9.0);

        function projectScreenNdcX(worldPos:Vec3):Float {
            var p = new Vec3(worldPos.x, worldPos.y, worldPos.z, 1.0).transformed(cam.unjitteredViewProjMat);
            return p.x / p.w;
        }

        function runDriveCase(label:String, expectedDir:Int, applyFn:InputController->Void):Void {
            InputKey.clearAll();
            GamepadDevice.applyExternalSnapshot(false, [], [], []);
            var ctrl = new InputController();
            car.resetState(0.0, 0.0, 0.0, 0.0);
            for (_ in 0...65) {
                applyFn(ctrl);
                ctrl.update(fixedDt);
                car.update(fixedDt, ctrl, null, ground);
            }
            InputKey.clearAll();
            GamepadDevice.applyExternalSnapshot(false, [], [], []);
            var ndcX = projectScreenNdcX(car.pos);
            if (expectedDir < 0) {
                Assert.isTrue(ctrl.steer < -0.2, label + " must emit negative steer (< -0.2) for Left, got " + ctrl.steer);
                Assert.isTrue(car.yaw < -0.15, label + " must rotate car yaw negative for Left, got " + car.yaw);
                Assert.isTrue(car.pos.x < -1.0, label + " must move car toward -X (Left), got x=" + car.pos.x);
                Assert.isTrue(ndcX < -0.04, label + " must move car to Screen Left (ndcX < -0.04), got ndcX=" + ndcX);
            } else {
                Assert.isTrue(ctrl.steer > 0.2, label + " must emit positive steer (> 0.2) for Right, got " + ctrl.steer);
                Assert.isTrue(car.yaw > 0.15, label + " must rotate car yaw positive for Right, got " + car.yaw);
                Assert.isTrue(car.pos.x > 1.0, label + " must move car toward +X (Right), got x=" + car.pos.x);
                Assert.isTrue(ndcX > 0.04, label + " must move car to Screen Right (ndcX > 0.04), got ndcX=" + ndcX);
            }
            var arcDist = Math.sqrt(car.pos.x * car.pos.x + car.pos.y * car.pos.y);
            Assert.isTrue(car.pos.y > 1.0 && arcDist > 1.8, label + " must travel forward along turning arc, got pos=" + car.pos.toString());
        }

        // 1. Keyboard WASD
        runDriveCase("Keyboard WASD Left (A)", -1, function(_) {
            InputKey.setKeyState(InputKey.W, true);
            InputKey.setKeyState(InputKey.A, true);
        });
        runDriveCase("Keyboard WASD Right (D)", 1, function(_) {
            InputKey.setKeyState(InputKey.W, true);
            InputKey.setKeyState(InputKey.D, true);
        });

        // 2. Keyboard Arrow Keys
        runDriveCase("Keyboard Arrow Left", -1, function(_) {
            InputKey.setKeyState(InputKey.UP, true);
            InputKey.setKeyState(InputKey.LEFT, true);
        });
        runDriveCase("Keyboard Arrow Right", 1, function(_) {
            InputKey.setKeyState(InputKey.UP, true);
            InputKey.setKeyState(InputKey.RIGHT, true);
        });

        // 3. Gamepad Analog Left Stick + Right Trigger Throttle
        function makePadButtons(?dpadIdx:Int = -1):Array<Bool> {
            var b = [for (_ in 0...17) false];
            if (dpadIdx >= 0) b[dpadIdx] = true;
            b[7] = true; // RT
            return b;
        }
        function makePadValues():Array<Float> {
            var v = [for (_ in 0...17) 0.0];
            v[7] = 1.0; // RT analog 100%
            return v;
        }
        runDriveCase("Gamepad Analog Left", -1, function(_) {
            GamepadDevice.applyExternalSnapshot(true, [-0.85, 0.0, 0.0, 0.0], makePadButtons(), makePadValues());
        });
        runDriveCase("Gamepad Analog Right", 1, function(_) {
            GamepadDevice.applyExternalSnapshot(true, [0.85, 0.0, 0.0, 0.0], makePadButtons(), makePadValues());
        });

        // 4. Gamepad D-Pad
        runDriveCase("Gamepad D-Pad Left", -1, function(_) {
            GamepadDevice.applyExternalSnapshot(true, [0.0, 0.0, 0.0, 0.0], makePadButtons(14), makePadValues());
        });
        runDriveCase("Gamepad D-Pad Right", 1, function(_) {
            GamepadDevice.applyExternalSnapshot(true, [0.0, 0.0, 0.0, 0.0], makePadButtons(15), makePadValues());
        });

        // 5. Mobile / Virtual Analog Touch Stick via TouchControlsHUD widget (Gas + Stick multi-touch)
        function runVirtualAnalogStickCase(label:String, expectedDir:Int, frac:Float):Void {
            InputKey.clearAll();
            GamepadDevice.applyExternalSnapshot(false, [], [], []);
            var ctrl = new InputController();
            var hud = new TouchControlsHUD(ctrl, null);
            hud.layout(1280, 720);
            car.resetState(0.0, 0.0, 0.0, 0.0);

            hud.handlePointerDown(1, hud.gasX, hud.gasY);
            hud.handlePointerDown(2, hud.stickBaseX, hud.stickBaseY);
            hud.handlePointerMove(2, hud.stickBaseX + expectedDir * frac * hud.stickMaxTravel, hud.stickBaseY);
            if (expectedDir < 0) {
                Assert.isTrue(hud.stickKnobX < hud.stickBaseX, label + " virtual knob must move Left");
            } else {
                Assert.isTrue(hud.stickKnobX > hud.stickBaseX, label + " virtual knob must move Right");
            }
            for (_ in 0...65) {
                ctrl.isTouchActive = true;
                ctrl.update(fixedDt);
                car.update(fixedDt, ctrl, null, ground);
            }
            hud.handlePointerUp(2);
            hud.handlePointerUp(1);
            var ndcX = projectScreenNdcX(car.pos);
            if (expectedDir < 0) {
                Assert.isTrue(ctrl.steer < -0.1, label + " steer must be negative, got " + ctrl.steer);
                Assert.isTrue(car.yaw < -0.08, label + " yaw must be negative, got " + car.yaw);
                Assert.isTrue(car.pos.x < -0.5, label + " must steer toward -X (Left), got x=" + car.pos.x);
                Assert.isTrue(ndcX < -0.02, label + " must steer Screen Left, got ndcX=" + ndcX);
            } else {
                Assert.isTrue(ctrl.steer > 0.1, label + " steer must be positive, got " + ctrl.steer);
                Assert.isTrue(car.yaw > 0.08, label + " yaw must be positive, got " + car.yaw);
                Assert.isTrue(car.pos.x > 0.5, label + " must steer toward +X (Right), got x=" + car.pos.x);
                Assert.isTrue(ndcX > 0.02, label + " must steer Screen Right, got ndcX=" + ndcX);
            }
            var arcDist = Math.sqrt(car.pos.x * car.pos.x + car.pos.y * car.pos.y);
            Assert.isTrue(car.pos.y > 1.0 && arcDist > 1.8, label + " must travel forward along turning arc, got pos=" + car.pos.toString());
        }

        runVirtualAnalogStickCase("Virtual Analog Stick Partial Left (45%)", -1, 0.45);
        runVirtualAnalogStickCase("Virtual Analog Stick Partial Right (45%)", 1, 0.45);
        runVirtualAnalogStickCase("Virtual Analog Stick Full Left (100%)", -1, 1.0);
        runVirtualAnalogStickCase("Virtual Analog Stick Full Right (100%)", 1, 1.0);

        // Also assert zero inversion across all 3 car presets (Race AWD, Hatch FWD, Coupe RWD)
        for (presetId in [CarConfig.ID_RACE_AWD, CarConfig.ID_HATCH_FWD, CarConfig.ID_COUPE_RWD]) {
            car.setConfig(CarConfig.getPresetConfig(presetId));
            runDriveCase(presetId + " Left", -1, function(_) {
                InputKey.setKeyState(InputKey.W, true);
                InputKey.setKeyState(InputKey.A, true);
            });
            runDriveCase(presetId + " Right", 1, function(_) {
                InputKey.setKeyState(InputKey.W, true);
                InputKey.setKeyState(InputKey.D, true);
            });
        }
        car.setConfig(CarConfig.getDefault());
    }

    public function testTurningRadiusTighterOnCompactFwdHatchThanAwdRaceCar() {
        var ground = new MockGroundProvider("flat", 1.0);
        var fixedDt = 1.0 / 60.0;

        function measureYawAtCorner(presetId:String):Float {
            InputKey.clearAll();
            GamepadDevice.applyExternalSnapshot(false, [], [], []);
            var ctrl = new InputController();
            car.setConfig(CarConfig.getPresetConfig(presetId));
            car.resetState(0.0, 0.0, 0.0, 0.0);
            // Accelerate slightly then hold full right cornering
            for (i in 0...95) {
                InputKey.setKeyState(InputKey.W, true);
                InputKey.setKeyState(InputKey.D, i >= 20);
                ctrl.update(fixedDt);
                car.update(fixedDt, ctrl, null, ground);
            }
            InputKey.clearAll();
            return car.yaw;
        }

        var awdYaw = measureYawAtCorner(CarConfig.ID_RACE_AWD);
        var fwdYaw = measureYawAtCorner(CarConfig.ID_HATCH_FWD);
        var rwdYaw = measureYawAtCorner(CarConfig.ID_COUPE_RWD);

        Assert.isTrue(fwdYaw > awdYaw + 0.05, "Compact FWD Hatch (" + fwdYaw + ") must turn tighter than AWD Race Car (" + awdYaw + ")");
        Assert.isTrue(rwdYaw > awdYaw + 0.03, "Low RWD Coupe (" + rwdYaw + ") must rotate sharper than AWD Race Car (" + awdYaw + ")");
        car.setConfig(CarConfig.getDefault());
    }
}
