package world;

import h3d.Vector;

/**
 * Universal interface for 3D world maps and driving surfaces.
 * Provides high-speed 4-wheel elevation raycasting, slope normals for chassis attitude,
 * and perimeter boundary constraint enforcement.
 */
interface IGroundProvider {
    /**
     * Computes the ground elevation in meters at world coordinate (x, y).
     *
     * @param x World X coordinate in meters.
     * @param y World Y coordinate in meters.
     * @return Ground contact elevation Z in meters.
     */
    public function getGroundElevation(x:Float, y:Float):Float;

    /**
     * Computes the ground surface normal gradient vector at world coordinate (x, y).
     *
     * @param x World X coordinate in meters.
     * @param y World Y coordinate in meters.
     * @param outNormal Scratch vector populated with unit-length normal (nx, ny, nz).
     */
    public function getGroundNormal(x:Float, y:Float, outNormal:Vector):Void;

    /**
     * Enforces perimeter boundaries (e.g. Armco guardrails on circuit, invisible walls on sandbox).
     * Repositions position in-place if boundary breached, and returns collision impulse multipliers.
     *
     * @param pos In-out world position vector.
     * @param forwardSpeed Current vehicle forward velocity in m/s.
     * @param lateralVelocity Current vehicle lateral velocity in m/s.
     * @return Object containing collision flag and velocity multipliers.
     */
    public function enforceBoundaries(pos:Vector, forwardSpeed:Float, lateralVelocity:Float):{ hitWall:Bool, speedMult:Float, latMult:Float };
}

