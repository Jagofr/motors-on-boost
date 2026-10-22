package tests.world;

import utest.Test;
import utest.Assert;
import h3d.Vector;
import world.Track;
import physics.SplineMath;

/**
 * Unit test suite validating track geometric constants, lane boundaries,
 * and loop waypoint continuity.
 */
class TestTrack extends Test {
    public function testTrackConstants() {
        Assert.equals(20.0, Track.ROAD_WIDTH);
        Assert.equals(10.0, Track.HALF_WIDTH);
        Assert.equals(4.0, Track.BED_EXTRA_WIDTH);
        Assert.floatEquals(0.65, Track.RAIL_HEIGHT, 0.001);
    }

    public function testWaypointLoopContinuity() {
        var rawNodes = [
            new Vector(0,    0,    0),
            new Vector(0,    85,   0),
            new Vector(30,   170,  1.5),
            new Vector(90,   240,  3.0),
            new Vector(170,  260,  3.0),
            new Vector(250,  215,  1.5),
            new Vector(280,  135,  0),
            new Vector(255,  45,  -1.0),
            new Vector(175, -25,  -1.0),
            new Vector(110,  10,   0),
            new Vector(60,  -40,   0),
            new Vector(10,  -60,   0)
        ];

        Assert.equals(12, rawNodes.length);

        // Verify start and finish loop proximity
        var start = rawNodes[0];
        var end = rawNodes[rawNodes.length - 1];
        var dx = end.x - start.x;
        var dy = end.y - start.y;
        var loopGapDist = Math.sqrt(dx * dx + dy * dy);
        Assert.isTrue(loopGapDist < 100.0, "Start and end keypoints should form a reasonable loop transition");

        // Verify segment projections along the loop
        var midpoint = new Vector(0, 40, 0);
        var proj = SplineMath.getClosestSegment(midpoint, rawNodes);
        Assert.notNull(proj);
        Assert.floatEquals(0.0, proj.centerPoint.x, 0.1);
        Assert.isTrue(proj.distSq < 1.0);
    }

    public function testTrackStreetLightsAndGroundProvider() {
        var track = new Track(null);
        Assert.isTrue(track.streetLights.length >= 16);

        // Ground elevation at origin
        var z = track.getGroundElevation(0, 0);
        Assert.floatEquals(Track.ROAD_LIFT, z, 0.01);

        // Normal vector at origin
        var n = new Vector();
        track.getGroundNormal(0, 0, n);
        Assert.isTrue(n.z > 0.9);

        // Boundary enforcement inside track
        var insidePos = new Vector(0, 10, 0);
        var resInside = track.enforceBoundaries(insidePos, 20.0, 0.0);
        Assert.isFalse(resInside.hitWall);

        // Boundary enforcement outside track (breached Armco rail at lateral > 10m)
        var outsidePos = new Vector(15.0, 10, 0);
        var resOutside = track.enforceBoundaries(outsidePos, 20.0, 0.0);
        Assert.isTrue(resOutside.hitWall);
        Assert.floatEquals(0.94, resOutside.speedMult, 0.001);
    }
}

