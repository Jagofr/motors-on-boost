package tests.physics;

import utest.Test;
import utest.Assert;
import physics.CarConfig;

/**
 * Unit test suite validating vehicle configuration defaults, geometric alignment with CarMesh,
 * defensive parameter clamping, and JSON serialization round-trips.
 */
class TestCarConfig extends Test {
    public function testStaticGeometryConstants() {
        Assert.floatEquals(0.36, CarConfig.TIRE_RADIUS, 0.0001);
        Assert.floatEquals(0.30, CarConfig.TIRE_WIDTH, 0.0001);
        Assert.floatEquals(1.88, CarConfig.CHASSIS_WIDTH, 0.0001);
        Assert.floatEquals(4.30, CarConfig.CHASSIS_LENGTH, 0.0001);
        Assert.floatEquals(0.48, CarConfig.COG_HEIGHT, 0.0001);
        Assert.floatEquals(2.70, CarConfig.WHEELBASE, 0.0001);
        Assert.floatEquals(1.96, CarConfig.TRACK_WIDTH, 0.0001);
    }

    public function testDefaultProfileValidity() {
        var cfg = CarConfig.getDefault();
        Assert.isTrue(cfg.chassis.massKg > 800.0);
        Assert.isTrue(cfg.suspension.minLength < cfg.suspension.restLength);
        Assert.isTrue(cfg.suspension.restLength < cfg.suspension.unloadedLength);
        Assert.isTrue(cfg.suspension.bumpDamping > 0.0);
        Assert.isTrue(cfg.suspension.reboundDamping >= cfg.suspension.bumpDamping);
        Assert.isTrue(cfg.suspension.antiRollStiffness > 0.0);

        Assert.isTrue(cfg.drivetrain.idleRPM < cfg.drivetrain.shiftDownRPM);
        Assert.isTrue(cfg.drivetrain.shiftDownRPM < cfg.drivetrain.shiftUpRPM);
        Assert.isTrue(cfg.drivetrain.shiftUpRPM < cfg.drivetrain.redlineRPM);
        Assert.equals(6, cfg.drivetrain.gearRatios.length);

        Assert.isTrue(cfg.tires.pacejkaD > 0.5);
        Assert.isTrue(cfg.tires.relaxationLength > 0.05);
        Assert.isTrue(cfg.tires.stictionSpeed > 0.05);
        Assert.isTrue(cfg.boost.maxFuel > 0.0);
    }

    public function testClampSanitizesInvalidBounds() {
        var cfg = CarConfig.getDefault();
        cfg.chassis.massKg = -50.0;
        cfg.suspension.unloadedLength = 0.05;
        cfg.suspension.restLength = 0.90;
        cfg.tires.relaxationLength = 0.0;
        cfg.drivetrain.redlineRPM = 200.0;
        cfg.drivetrain.gearRatios = [];

        var clamped = CarConfig.clamp(cfg);
        Assert.isTrue(clamped.chassis.massKg >= 400.0);
        Assert.isTrue(clamped.suspension.unloadedLength > clamped.suspension.restLength);
        Assert.isTrue(clamped.suspension.restLength > clamped.suspension.minLength);
        Assert.isTrue(clamped.tires.relaxationLength >= 0.05);
        Assert.isTrue(clamped.drivetrain.redlineRPM > clamped.drivetrain.idleRPM);
        Assert.isTrue(clamped.drivetrain.gearRatios.length >= 1);
    }

    public function testJsonRoundTripAndMalformedFallback() {
        var cfg = CarConfig.getDefault();
        cfg.chassis.massKg = 1620.0;
        cfg.tires.maxSteerAngle = 0.49;

        var json = CarConfig.toJson(cfg);
        var parsed = CarConfig.fromJson(json);
        Assert.floatEquals(1620.0, parsed.chassis.massKg, 0.01);
        Assert.floatEquals(0.49, parsed.tires.maxSteerAngle, 0.001);

        var fallbackNull = CarConfig.fromJson(null);
        Assert.floatEquals(1450.0, fallbackNull.chassis.massKg, 0.01);

        var fallbackCorrupt = CarConfig.fromJson("{ broken json !!!");
        Assert.floatEquals(1450.0, fallbackCorrupt.chassis.massKg, 0.01);
    }

    public function testThreeCarPresetsAndPaintPalette() {
        Assert.equals(3, CarConfig.VEHICLE_PRESETS.length);
        Assert.isTrue(CarConfig.PAINT_PALETTE.length >= 6);

        var awd = CarConfig.getPresetConfig(CarConfig.ID_RACE_AWD);
        var fwd = CarConfig.getPresetConfig(CarConfig.ID_HATCH_FWD);
        var rwd = CarConfig.getPresetConfig(CarConfig.ID_COUPE_RWD);

        Assert.floatEquals(0.35, awd.drivetrain.frontDriveSplit, 0.001);
        Assert.floatEquals(1.0, fwd.drivetrain.frontDriveSplit, 0.001);
        Assert.floatEquals(0.0, rwd.drivetrain.frontDriveSplit, 0.001);

        Assert.isTrue(fwd.chassis.wheelbase < awd.chassis.wheelbase, "Sports Hatch FWD must have shorter wheelbase than AWD Race Car");
        Assert.isTrue(fwd.tires.maxSteerAngle > awd.tires.maxSteerAngle, "Sports Hatch FWD must have sharper steering lock");
        Assert.isTrue(rwd.chassis.cogHeight < awd.chassis.cogHeight, "Low Sports Coupe RWD must have lower CoG");
    }
}
