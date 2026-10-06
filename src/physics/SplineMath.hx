package physics;

import h3d.Vector;

typedef SegmentProjection = {
    var centerPoint:Vector;
    var distSq:Float;
    var z:Float;
    var segDirX:Float;
    var segDirY:Float;
}

class SplineMath {
    /**
     * Standard Catmull-Rom cubic interpolation between p1 and p2 using control points p0 and p3.
     */
    public static inline function catmullRom(p0:Float, p1:Float, p2:Float, p3:Float, t:Float):Float {
        var t2 = t * t;
        var t3 = t2 * t;
        return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3);
    }

    /**
     * Projects a 2D/3D point onto the line segment connecting nodes `a` and `b`.
     */
    public static function projectOntoSegment(p:Vector, a:Vector, b:Vector):SegmentProjection {
        var abX = b.x - a.x;
        var abY = b.y - a.y;
        var abLenSq = abX * abX + abY * abY;

        var apX = p.x - a.x;
        var apY = p.y - a.y;

        var t = 0.0;
        if (abLenSq > 0.0001) {
            t = (apX * abX + apY * abY) / abLenSq;
            if (t < 0.0) t = 0.0;
            if (t > 1.0) t = 1.0;
        }

        var closestX = a.x + t * abX;
        var closestY = a.y + t * abY;
        var closestZ = a.z + t * (b.z - a.z);

        var dx = p.x - closestX;
        var dy = p.y - closestY;

        var len = Math.sqrt(abLenSq);
        var dirX = len > 0.0001 ? abX / len : 0.0;
        var dirY = len > 0.0001 ? abY / len : 1.0;

        return {
            centerPoint: new Vector(closestX, closestY, closestZ),
            distSq: dx * dx + dy * dy,
            z: closestZ,
            segDirX: dirX,
            segDirY: dirY
        };
    }

    /**
     * Finds the nearest adjacent segment along a closed waypoint loop.
     */
    public static function getClosestSegment(p:Vector, waypoints:Array<Vector>):SegmentProjection {
        var count = waypoints.length;
        var bestDistSq = 1e12;
        var bestIdx = 0;

        for (i in 0...count) {
            var wp = waypoints[i];
            var d2 = (wp.x - p.x) * (wp.x - p.x) + (wp.y - p.y) * (wp.y - p.y);
            if (d2 < bestDistSq) {
                bestDistSq = d2;
                bestIdx = i;
            }
        }

        var prevIdx = (bestIdx - 1 + count) % count;
        var nextIdx = (bestIdx + 1) % count;

        var projA = projectOntoSegment(p, waypoints[prevIdx], waypoints[bestIdx]);
        var projB = projectOntoSegment(p, waypoints[bestIdx], waypoints[nextIdx]);

        return (projA.distSq < projB.distSq) ? projA : projB;
    }
}