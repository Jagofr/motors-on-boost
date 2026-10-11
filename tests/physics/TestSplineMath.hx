package tests.physics;

import utest.Test;
import utest.Assert;
import h3d.Vector;
import physics.SplineMath;

/**
 * Unit test suite validating Catmull-Rom interpolation and segment projections.
 */
class TestSplineMath extends Test {
    public function testCatmullRomEndpoints() {
        // At t = 0, should equal p1
        var at0 = SplineMath.catmullRom(0.0, 10.0, 20.0, 30.0, 0.0);
        Assert.floatEquals(10.0, at0, 0.001);

        // At t = 1, should equal p2
        var at1 = SplineMath.catmullRom(0.0, 10.0, 20.0, 30.0, 1.0);
        Assert.floatEquals(20.0, at1, 0.001);

        // At t = 0.5 for linear points, should equal midpoint
        var atHalf = SplineMath.catmullRom(0.0, 10.0, 20.0, 30.0, 0.5);
        Assert.floatEquals(15.0, atHalf, 0.001);
    }

    public function testProjectOntoSegmentCollinear() {
        var a = new Vector(0, 0, 0);
        var b = new Vector(10, 0, 0);
        var p = new Vector(5, 2, 0); // 2 units above midpoint

        var proj = SplineMath.projectOntoSegment(p, a, b);
        Assert.floatEquals(5.0, proj.centerPoint.x, 0.001);
        Assert.floatEquals(0.0, proj.centerPoint.y, 0.001);
        Assert.floatEquals(4.0, proj.distSq, 0.001); // 2^2 = 4
        Assert.floatEquals(1.0, proj.segDirX, 0.001);
        Assert.floatEquals(0.0, proj.segDirY, 0.001);
    }

    public function testProjectOntoSegmentClamping() {
        var a = new Vector(0, 0, 0);
        var b = new Vector(10, 0, 0);
        var beforeA = new Vector(-5, 0, 0);
        var afterB = new Vector(15, 0, 0);

        var projBefore = SplineMath.projectOntoSegment(beforeA, a, b);
        Assert.floatEquals(0.0, projBefore.centerPoint.x, 0.001);

        var projAfter = SplineMath.projectOntoSegment(afterB, a, b);
        Assert.floatEquals(10.0, projAfter.centerPoint.x, 0.001);
    }

    public function testGetClosestSegment() {
        var waypoints = [
            new Vector(0, 0, 0),
            new Vector(100, 0, 0),
            new Vector(100, 100, 0),
            new Vector(0, 100, 0)
        ];

        var query = new Vector(50, 5, 0); // Near first segment (0,0)->(100,0)
        var proj = SplineMath.getClosestSegment(query, waypoints);

        Assert.floatEquals(50.0, proj.centerPoint.x, 0.1);
        Assert.floatEquals(0.0, proj.centerPoint.y, 0.1);
        Assert.floatEquals(25.0, proj.distSq, 0.1); // 5^2 = 25
    }
}

