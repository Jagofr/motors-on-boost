package tests.world;

import utest.Test;
import utest.Assert;
import h3d.Vector;
import world.SandboxMap;

/**
 * Unit test suite validating open sandbox terrain elevations, rolling moguls,
 * apex hill peak, launch ramp geometry, analytical normal gradients, and invisible boundary walls.
 */
class TestSandboxMap extends Test {
    public function testSandboxConstants() {
        Assert.equals(200.0, SandboxMap.HALF_SPAN);
        Assert.equals(195.0, SandboxMap.WALL_LIMIT);
        Assert.equals(12.5, SandboxMap.HILL_APEX_Z);
        Assert.equals(3.8, SandboxMap.RAMP_CREST_Z);
    }

    public function testCenterSkidpadIsFlat() {
        var map = new SandboxMap(null);

        // Center origin
        Assert.floatEquals(0.0, map.getGroundElevation(0.0, 0.0), 0.001);

        // Within 35m skidpad radius
        Assert.floatEquals(0.0, map.getGroundElevation(15.0, 10.0), 0.001);
        Assert.floatEquals(0.0, map.getGroundElevation(-20.0, -20.0), 0.001);
        Assert.floatEquals(0.0, map.getGroundElevation(0.0, 30.0), 0.001);
    }

    public function testTerrainFeaturesElevation() {
        var map = new SandboxMap(null);

        // 1. Apex Mountain Peak at X: -95, Y: +95
        var apexZ = map.getGroundElevation(-95.0, 95.0);
        Assert.isTrue(apexZ >= 12.0, "Apex mountain should reach ~12.5m elevation");

        // 2. Rolling Moguls in X: 80, Y: 0
        var mogulZ = map.getGroundElevation(80.0, 0.0);
        Assert.isTrue(Math.abs(mogulZ) > 0.1, "Moguls should have non-zero wave displacement");

        // 3. Launch Ramp at X: 0, Y: 120 (crest apex)
        var rampZ = map.getGroundElevation(0.0, 120.0);
        Assert.floatEquals(3.8, rampZ, 0.05);

        // Beyond ramp drop-off crest
        var afterRampZ = map.getGroundElevation(0.0, 130.0);
        Assert.floatEquals(0.0, afterRampZ, 0.01);

        // 4. Banked High-Speed Bowl at center (-100, -100) offset 70m
        var bowlZ = map.getGroundElevation(-100.0, -170.0);
        Assert.isTrue(bowlZ >= 4.5, "Outer rim of bowl should be banked to ~5m");
    }

    public function testAnalyticalGroundNormals() {
        var map = new SandboxMap(null);
        var norm = new Vector();

        // Skidpad flat normal should point purely along +Z
        map.getGroundNormal(0.0, 0.0, norm);
        Assert.floatEquals(0.0, norm.x, 0.001);
        Assert.floatEquals(0.0, norm.y, 0.001);
        Assert.floatEquals(1.0, norm.z, 0.001);

        // Normal magnitude on hill slope should be unit-length
        map.getGroundNormal(-85.0, 85.0, norm);
        var len = Math.sqrt(norm.x * norm.x + norm.y * norm.y + norm.z * norm.z);
        Assert.floatEquals(1.0, len, 0.001);
        Assert.isTrue(norm.z > 0.0, "Normal should face upward");
    }

    public function testInvisibleWallBoundaries() {
        var map = new SandboxMap(null);

        // Inside boundary
        var pos = new Vector(50.0, 50.0, 0.0);
        var res = map.enforceBoundaries(pos, 25.0, 0.0);
        Assert.isFalse(res.hitWall);
        Assert.floatEquals(50.0, pos.x, 0.001);
        Assert.floatEquals(50.0, pos.y, 0.001);

        // Penetrating East boundary (X > 195m)
        var eastPos = new Vector(210.0, 0.0, 0.0);
        var eastRes = map.enforceBoundaries(eastPos, 30.0, 5.0);
        Assert.isTrue(eastRes.hitWall);
        Assert.floatEquals(195.0, eastPos.x, 0.001);
        Assert.isTrue(eastRes.speedMult < 1.0);

        // Penetrating South boundary (Y < -195m)
        var southPos = new Vector(0.0, -210.0, 0.0);
        var southRes = map.enforceBoundaries(southPos, 30.0, 0.0);
        Assert.isTrue(southRes.hitWall);
        Assert.floatEquals(-195.0, southPos.y, 0.001);
        Assert.isTrue(southRes.speedMult < 0.0, "Longitudinal bounce reflection should reverse forward speed");
    }

    public function testFloodlightTowersAndObstacles() {
        var map = new SandboxMap(null);
        Assert.isTrue(map.floodlights.length >= 12, "4 floodlight towers should contain mast, housing, and luminaires");
        Assert.isTrue(map.obstacles.length >= 8, "Slalom course and boundary markers should be instantiated");
    }
}
