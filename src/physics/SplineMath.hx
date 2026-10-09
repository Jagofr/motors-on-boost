package physics;

import h3d.Vector;

/**
 * Result data structure describing the orthogonal projection of a point onto a track segment.
 */
typedef SegmentProjection = {
    /** The closest 3D coordinate point located along the segment centerline. */
    var centerPoint:Vector;

    /** Squared euclidean distance from the query point to the closest segment point. */
    var distSq:Float;

    /** Interpolated track elevation (Z coordinate) at the projection point. */
    var z:Float;

    /** Normalized unit direction vector X component along the segment heading. */
    var segDirX:Float;

    /** Normalized unit direction vector Y component along the segment heading. */
    var segDirY:Float;
}

/**
 * Mathematical utilities for cubic Catmull-Rom spline curves and track segment projections.
 * Provides continuous interpolation for smooth racetrack geometry and collision projection.
 */
class SplineMath {
    /**
     * Evaluates standard cubic Catmull-Rom spline interpolation between control nodes p1 and p2.
     * Uses adjacent control nodes p0 and p3 to establish smooth tangent continuity.
     *
     * @param p0 Position value of the preceding control point.
     * @param p1 Position value of the starting segment control point.
     * @param p2 Position value of the ending segment control point.
     * @param p3 Position value of the subsequent control point.
     * @param t Normalized interpolation parameter along the segment in the range [0.0, 1.0].
     * @return Interpolated coordinate scalar along the spline curve.
     */
    public static inline function catmullRom(p0:Float, p1:Float, p2:Float, p3:Float, t:Float):Float {
        var t2 = t * t;
        var t3 = t2 * t;
        return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3);
    }

    /**
     * Projects an arbitrary 3D position onto a finite 3D line segment spanned between nodes `a` and `b`.
     * Calculates the nearest point on the segment, squared distance, and segment tangent orientation.
     *
     * @param p Query coordinate in world space.
     * @param a Segment starting node vector.
     * @param b Segment ending node vector.
     * @return Projection record containing closest point, squared distance, Z elevation, and heading vector.
     */
    public static function projectOntoSegment(p:Vector, a:Vector, b:Vector):SegmentProjection {
        var abX = b.x - a.x;
        var abY = b.y - a.y;
        var abLenSq = abX * abX + abY * abY;

        var apX = p.x - a.x;
        var apY = p.y - a.y;

        // Calculate scalar projection parameter t clamped to finite segment boundaries [0, 1]
        var t = 0.0;
        if (abLenSq > 0.0001) {
            t = (apX * abX + apY * abY) / abLenSq;
            if (t < 0.0) t = 0.0;
            if (t > 1.0) t = 1.0;
        }

        // Interpolate nearest position on the 3D line segment
        var closestX = a.x + t * abX;
        var closestY = a.y + t * abY;
        var closestZ = a.z + t * (b.z - a.z);

        var dx = p.x - closestX;
        var dy = p.y - closestY;

        // Compute normalized 2D horizontal heading along the segment
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
     * Identifies the closest adjacent track spline segment along a closed circular waypoint loop.
     *
     * @param p Query coordinate in world space.
     * @param waypoints Array of loop waypoints ordered chronologically around the closed track.
     * @return Best matching segment projection record with minimum squared distance.
     */
    public static function getClosestSegment(p:Vector, waypoints:Array<Vector>):SegmentProjection {
        var count = waypoints.length;
        var bestDistSq = 1e12;
        var bestIdx = 0;

        // Step 1: Broad-phase sweep to discover closest individual waypoint node
        for (i in 0...count) {
            var wp = waypoints[i];
            var d2 = (wp.x - p.x) * (wp.x - p.x) + (wp.y - p.y) * (wp.y - p.y);
            if (d2 < bestDistSq) {
                bestDistSq = d2;
                bestIdx = i;
            }
        }

        // Step 2: Narrow-phase test against the two adjoining line segments (prev-current vs current-next)
        var prevIdx = (bestIdx - 1 + count) % count;
        var nextIdx = (bestIdx + 1) % count;

        var projA = projectOntoSegment(p, waypoints[prevIdx], waypoints[bestIdx]);
        var projB = projectOntoSegment(p, waypoints[bestIdx], waypoints[nextIdx]);

        // Select the segment with lowest perpendicular squared distance
        return (projA.distSq < projB.distSq) ? projA : projB;
    }
}