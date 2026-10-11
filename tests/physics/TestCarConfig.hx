package tests.physics;

import utest.Test;
import utest.Assert;
import physics.CarConfig;

/**
 * Unit test suite validating CarConfig default values, ranges, and JSON serialization.
 */
class TestCarConfig extends Test {
    public function testDefaultConfigValues() {
        var cfg = CarConfig.getDefault();

        // Mass and speeds
        Assert.isTrue(cfg.mass > 500.0 && cfg.mass < 3000.0);
        Assert.isTrue(cfg.baseTopSpeed > 40.0);
        Assert.isTrue(cfg.boostTopSpeed > cfg.baseTopSpeed);
        Assert.isTrue(cfg.baseAcceleration > 10.0);
        Assert.isTrue(cfg.boostAcceleration > cfg.baseAcceleration);

        // Suspension
        Assert.isTrue(cfg.suspension.restLength > 0.1 && cfg.suspension.restLength < 1.0);
        Assert.isTrue(cfg.suspension.springRate > 1000.0);
        Assert.isTrue(cfg.suspension.antiRollStiffness > 100.0);
        Assert.isTrue(cfg.suspension.bodyRollScale > 0.0);

        // Tires
        Assert.isTrue(cfg.tires.tireSlipBias >= -1.0 && cfg.tires.tireSlipBias <= 1.0);
        Assert.isTrue(cfg.tires.groundFriction > 0.5 && cfg.tires.groundFriction <= 2.0);
        Assert.isTrue(cfg.tires.wheelspinAmount >= 0.0);

        // Drift
        Assert.isTrue(cfg.drift.lateralStiffnessScale >= 0.2 && cfg.drift.lateralStiffnessScale <= 0.6);
        Assert.isTrue(cfg.drift.driftTriggerAngle > 0.05 && cfg.drift.driftTriggerAngle < 1.0);
        Assert.isTrue(cfg.drift.minDriftSpeed > 5.0);

        // Drivetrain
        Assert.isTrue(cfg.drivetrain.gearRatios.length >= 4);
        Assert.isTrue(cfg.drivetrain.redlineRPM > cfg.drivetrain.idleRPM);
    }

    public function testJsonSerializationRoundtrip() {
        var cfg = CarConfig.getDefault();
        cfg.tires.tireSlipBias = -0.45; // Test custom rear bias
        cfg.drift.driftTriggerAngle = 0.32;

        var jsonStr = CarConfig.toJson(cfg);
        Assert.isTrue(jsonStr.length > 50);

        var restored = CarConfig.fromJson(jsonStr);
        Assert.notNull(restored);
        Assert.floatEquals(cfg.mass, restored.mass, 0.001);
        Assert.floatEquals(-0.45, restored.tires.tireSlipBias, 0.001);
        Assert.floatEquals(0.32, restored.drift.driftTriggerAngle, 0.001);
        Assert.floatEquals(cfg.boostTopSpeed, restored.boostTopSpeed, 0.001);
    }
}

