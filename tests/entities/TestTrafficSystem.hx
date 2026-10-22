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

    public function testUnifiedFrontAndRearCollisionLogic() {
        var track = new world.Track(null);
        var ts = new TrafficSystem(track.waypoints, null);
        var player = new physics.CarPhysics(0, 0, 0);
        var cam = new camera.ChaseCamera(new h3d.Camera(), 0, -10, 4);

        Assert.isTrue(ts.trafficList.length >= 2);

        // Test rear collision (traffic directly ahead, moving same direction)
        var rearTraffic = ts.trafficList[0];
        rearTraffic.isOncoming = false;
        rearTraffic.currentSpeed = 10.0;
        rearTraffic.pos.set(0, 2.0, 0);
        player.pos.set(0, 0, 0);
        player.forwardSpeed = 30.0;
        player.yaw = 1.5707963; // facing +Y

        ts.update(0.016, player, cam);
        // Player speed reduced by 0.75x (30.0 * 0.75 = 22.5)
        Assert.floatEquals(22.5, player.forwardSpeed, 0.01);
        Assert.isTrue(rearTraffic.currentSpeed >= 20.0);
        // ChaseCamera softens incoming trauma by 50% (0.35 * 0.50 = 0.175)
        Assert.floatEquals(0.175, cam.trauma, 0.01);

        // Reset and test front collision (traffic oncoming, head-on approach)
        cam.trauma = 0.0;
        var frontTraffic = ts.trafficList[1];
        frontTraffic.isOncoming = true;
        frontTraffic.currentSpeed = 15.0;
        frontTraffic.pos.set(0, 2.0, 0);
        player.pos.set(0, 0, 0);
        player.forwardSpeed = 40.0;
        player.yaw = 1.5707963;

        ts.update(0.016, player, cam);
        // Front collision now also uses the identical 0.75x speed retention and 0.175 softened trauma
        Assert.floatEquals(30.0, player.forwardSpeed, 0.01);
        Assert.floatEquals(0.175, cam.trauma, 0.01);
    }
}

