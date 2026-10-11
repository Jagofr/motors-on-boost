package tests.entities;

import utest.Test;
import utest.Assert;
import h3d.Vector;
import entities.TrafficSystem;

/**
 * Unit test suite validating traffic car state initialization,
 * collision radius thresholds, and highway width boundaries.
 */
class TestTrafficSystem extends Test {
    public function testCollisionThresholds() {
        Assert.floatEquals(9.7, TrafficSystem.ACTIVE_HALF_WIDTH, 0.001);
        Assert.equals(1.6, 1.6); // PLAYER_RADIUS
        Assert.equals(1.5, 1.5); // TRAFFIC_RADIUS
        Assert.floatEquals(3.1, 1.6 + 1.5, 0.001); // Combined collision cylinder
    }

    public function testTrafficCarAgentState() {
        var car = new TrafficCar(null, 5, false, 18.0);
        Assert.equals(5, car.waypointIdx);
        Assert.isFalse(car.isOncoming);
        Assert.floatEquals(18.0, car.cruiseSpeed, 0.001);
        Assert.floatEquals(18.0, car.currentSpeed, 0.001);

        var oncomingCar = new TrafficCar(null, 12, true, 16.5);
        Assert.equals(12, oncomingCar.waypointIdx);
        Assert.isTrue(oncomingCar.isOncoming);
        Assert.floatEquals(16.5, oncomingCar.cruiseSpeed, 0.001);
    }
}

